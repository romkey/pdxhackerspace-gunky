require "test_helper"

class ExpireItemsJobTest < ActiveJob::TestCase
  test "auto-kills expired items without votes" do
    expired_item = items(:expired_no_votes)
    assert expired_item.pending?
    assert expired_item.expired?

    ExpireItemsJob.perform_now

    expired_item.reload
    assert expired_item.kill?
  end

  test "does not kill expired items that have votes" do
    expired_item = items(:expired_no_votes)
    expired_item.votes.create!(slack_user_id: "U999", slack_username: "voter", choice: :mine)

    ExpireItemsJob.perform_now

    expired_item.reload
    assert expired_item.pending?
  end

  test "does not kill non-expired pending items" do
    pending_item = items(:pending_item)

    ExpireItemsJob.perform_now

    pending_item.reload
    assert pending_item.pending?
  end

  test "does not affect already-resolved items" do
    claimed = items(:claimed_item)

    ExpireItemsJob.perform_now

    claimed.reload
    assert claimed.mine?
  end

  test "updates slack message for posted items" do
    expired_item = items(:expired_no_votes)
    expired_item.update!(slack_message_ts: "123.456", slack_channel_id: "C999")

    update_called = false
    original_method = SlackService.instance_method(:update_item_message)
    SlackService.define_method(:update_item_message) { |_| update_called = true }

    ExpireItemsJob.perform_now

    assert update_called
  ensure
    SlackService.define_method(:update_item_message, original_method)
  end

  test "continues processing when one item fails" do
    second = Item.create!(description: "Also expired", expiration_date: 2.days.ago, disposition: :pending)

    ExpireItemsJob.perform_now

    assert items(:expired_no_votes).reload.kill?
    assert second.reload.kill?
  end
end
