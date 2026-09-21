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
    original_post = SlackService.instance_method(:post_item)
    original_update = SlackService.instance_method(:update_lost_found_item_message)
    SlackService.define_method(:post_item) { |i| posted_ids << i.id }
    SlackService.define_method(:update_lost_found_item_message) { |_| nil }

    ENV["SLACK_BOT_TOKEN"] = "xoxb-test"
    PromoteLostFoundItemsJob.perform_now
    ENV.delete("SLACK_BOT_TOKEN")

    item.reload
    assert item.lost_found_promoted?
    assert_equal 7.days.from_now.to_date, item.expiration_date
    assert_includes posted_ids, item.id
  ensure
    SlackService.define_method(:post_item, original_post)
    SlackService.define_method(:update_lost_found_item_message, original_update)
  end

  test "promotes claimed items past pickup deadline" do
    item = items(:lost_found_claimed_overdue_item)

    post_called = false
    original_post = SlackService.instance_method(:post_item)
    original_update = SlackService.instance_method(:update_lost_found_item_message)
    SlackService.define_method(:post_item) { |i| post_called = (i.id == item.id) }
    SlackService.define_method(:update_lost_found_item_message) { |_| nil }

    ENV["SLACK_BOT_TOKEN"] = "xoxb-test"
    PromoteLostFoundItemsJob.perform_now
    ENV.delete("SLACK_BOT_TOKEN")

    item.reload
    assert item.lost_found_promoted?
    assert post_called
  ensure
    SlackService.define_method(:post_item, original_post)
    SlackService.define_method(:update_lost_found_item_message, original_update)
  end

  test "does not promote picked up items" do
    item = items(:lost_found_picked_up_item)

    PromoteLostFoundItemsJob.perform_now

    assert item.reload.lost_found_picked_up?
  end
end
