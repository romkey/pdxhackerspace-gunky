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

  test "resolves expired items with mine votes to mine and first mine voter" do
    expired_item = items(:expired_no_votes)
    expired_item.votes.create!(slack_user_id: "U999", slack_username: "first_voter", choice: :mine)
    expired_item.votes.create!(slack_user_id: "U888", slack_username: "second_voter", choice: :mine)

    ExpireItemsJob.perform_now

    expired_item.reload
    assert expired_item.mine?
    assert_equal "first_voter", expired_item.claimed_by
  end

  test "resolves expired items with foster votes to foster even if kill has more votes" do
    expired_item = items(:expired_no_votes)
    expired_item.votes.create!(slack_user_id: "U001", slack_username: "alice", choice: :foster)
    expired_item.votes.create!(slack_user_id: "U002", slack_username: "bob", choice: :kill)
    expired_item.votes.create!(slack_user_id: "U003", slack_username: "carol", choice: :kill)

    ExpireItemsJob.perform_now

    expired_item.reload
    assert expired_item.foster?
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
    original_method = SlackService.instance_method(:replace_expired_item_message)
    SlackService.define_method(:replace_expired_item_message) { |_| update_called = true }

    ExpireItemsJob.perform_now

    assert update_called
  ensure
    SlackService.define_method(:replace_expired_item_message, original_method)
  end

  test "continues processing when one item fails" do
    second = Item.create!(description: "Also expired", expiration_date: 2.days.ago, disposition: :pending)

    ExpireItemsJob.perform_now

    assert items(:expired_no_votes).reload.kill?
    assert second.reload.kill?
  end
end
