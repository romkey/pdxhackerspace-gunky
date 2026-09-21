require "test_helper"

class PromoteLostFoundItemsJobTest < ActiveJob::TestCase
  test "promotes unclaimed items past hold date" do
    item = Item.create!(
      description: "Overdue for promotion",
      lost_found_state: :lost_found_unclaimed,
      lost_found_hold_until: 1.day.ago.to_date,
      expiration_date: 1.day.ago.to_date
    )

    posted_ids = []
    original_post = SlackService.instance_method(:chat_post_item)
    original_update = SlackService.instance_method(:update_lost_found_item_message)
    SlackService.define_method(:chat_post_item) { |i| posted_ids << i.id; { "ts" => "1.1", "channel" => "C1" } }
    SlackService.define_method(:update_lost_found_item_message) { |_| nil }

    ENV["SLACK_BOT_TOKEN"] = "xoxb-test"
    PromoteLostFoundItemsJob.perform_now
    ENV.delete("SLACK_BOT_TOKEN")

    item.reload
    assert item.lost_found_promoted?
    assert_equal 7.days.from_now.to_date, item.expiration_date
    assert_includes posted_ids, item.id
  ensure
    SlackService.define_method(:chat_post_item, original_post)
    SlackService.define_method(:update_lost_found_item_message, original_update)
  end

  test "promotes claimed items past pickup deadline" do
    item = items(:lost_found_claimed_overdue_item)

    post_called = false
    original_post = SlackService.instance_method(:chat_post_item)
    original_update = SlackService.instance_method(:update_lost_found_item_message)
    SlackService.define_method(:chat_post_item) { |i| post_called = (i.id == item.id); { "ts" => "2.2", "channel" => "C1" } }
    SlackService.define_method(:update_lost_found_item_message) { |_| nil }

    ENV["SLACK_BOT_TOKEN"] = "xoxb-test"
    PromoteLostFoundItemsJob.perform_now
    ENV.delete("SLACK_BOT_TOKEN")

    item.reload
    assert item.lost_found_promoted?
    assert post_called
  ensure
    SlackService.define_method(:chat_post_item, original_post)
    SlackService.define_method(:update_lost_found_item_message, original_update)
  end

  test "does not persist promotion when gunky slack post fails" do
    item = Item.create!(
      description: "Slack failure should roll back",
      lost_found_state: :lost_found_unclaimed,
      lost_found_hold_until: 1.day.ago.to_date,
      expiration_date: 1.day.ago.to_date
    )

    update_calls = 0
    original_post = SlackService.instance_method(:chat_post_item)
    original_update = SlackService.instance_method(:update_lost_found_item_message)
    SlackService.define_method(:chat_post_item) { |_| raise "slack down" }
    SlackService.define_method(:update_lost_found_item_message) { |_| update_calls += 1 }

    ENV["SLACK_BOT_TOKEN"] = "xoxb-test"
    PromoteLostFoundItemsJob.perform_now
    ENV.delete("SLACK_BOT_TOKEN")

    item.reload
    assert item.lost_found_unclaimed?
    assert_nil item.lost_found_promoted_at
    assert_equal 0, update_calls
  ensure
    SlackService.define_method(:chat_post_item, original_post)
    SlackService.define_method(:update_lost_found_item_message, original_update)
  end

  test "updates lost+found slack message only after gunky post and promotion succeed" do
    item = Item.create!(
      description: "Promotion order test",
      lost_found_state: :lost_found_unclaimed,
      lost_found_hold_until: 1.day.ago.to_date,
      expiration_date: 1.day.ago.to_date,
      lost_found_slack_channel_id: "CLF",
      lost_found_slack_message_ts: "111.222"
    )

    events = []
    original_post = SlackService.instance_method(:chat_post_item)
    original_update = SlackService.instance_method(:update_lost_found_item_message)
    SlackService.define_method(:chat_post_item) do |i|
      events << :gunky_post
      { "ts" => "999.888", "channel" => "CGUNKY" }
    end
    SlackService.define_method(:update_lost_found_item_message) do |i|
      events << :lost_found_update
      assert i.lost_found_promoted?, "lost+found message should update only after promotion"
    end

    ENV["SLACK_BOT_TOKEN"] = "xoxb-test"
    PromoteLostFoundItemsJob.new.send(:promote_item!, item)
    ENV.delete("SLACK_BOT_TOKEN")

    assert_equal [ :gunky_post, :lost_found_update ], events
  ensure
    SlackService.define_method(:chat_post_item, original_post)
    SlackService.define_method(:update_lost_found_item_message, original_update)
  end

  test "deletes orphan gunky post when promotion persistence fails" do
    item = Item.create!(
      description: "Orphan cleanup test",
      lost_found_state: :lost_found_unclaimed,
      lost_found_hold_until: 1.day.ago.to_date,
      expiration_date: 1.day.ago.to_date
    )

    deleted = []
    original_post = SlackService.instance_method(:chat_post_item)
    original_delete = SlackService.instance_method(:delete_message)
    original_promote = Item.instance_method(:promote_from_lost_found!)
    SlackService.define_method(:chat_post_item) { |_| { "ts" => "777.666", "channel" => "CGUNKY" } }
    SlackService.define_method(:delete_message) { |**kwargs| deleted << kwargs }
    Item.define_method(:promote_from_lost_found!) { raise "db failed" }

    ENV["SLACK_BOT_TOKEN"] = "xoxb-test"
    assert_raises(RuntimeError) do
      PromoteLostFoundItemsJob.new.send(:promote_item!, item)
    end
    ENV.delete("SLACK_BOT_TOKEN")

    item.reload
    assert item.lost_found_unclaimed?
    assert_equal [ { channel: "CGUNKY", ts: "777.666" } ], deleted
  ensure
    SlackService.define_method(:chat_post_item, original_post)
    SlackService.define_method(:delete_message, original_delete)
    Item.define_method(:promote_from_lost_found!, original_promote)
  end

  test "does not promote picked up items" do
    item = items(:lost_found_picked_up_item)

    PromoteLostFoundItemsJob.perform_now

    assert item.reload.lost_found_picked_up?
  end
end
