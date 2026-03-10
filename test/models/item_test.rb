require "test_helper"

class ItemTest < ActiveSupport::TestCase
  test "valid item with description" do
    item = Item.new(description: "A thing")
    assert item.valid?
  end

  test "invalid without description or photo" do
    item = Item.new(description: nil)
    assert_not item.valid?
    assert_includes item.errors[:description], "is required when no photo is provided"
  end

  test "sets default expiration date on create" do
    item = Item.create!(description: "Test item")
    assert_equal 7.days.from_now.to_date, item.expiration_date
  end

  test "does not override explicit expiration date" do
    date = 3.days.from_now.to_date
    item = Item.create!(description: "Test item", expiration_date: date)
    assert_equal date, item.expiration_date
  end

  test "defaults to pending disposition" do
    item = Item.create!(description: "Test item")
    assert item.pending?
  end

  test "disposition enum values" do
    assert_equal({ "pending" => 0, "mine" => 1, "foster" => 2, "kill" => 3 }, Item.dispositions)
  end

  test "expired? returns true when past expiration" do
    assert items(:expired_no_votes).expired?
  end

  test "expired? returns false when not yet expired" do
    assert_not items(:pending_item).expired?
  end

  test "expired? returns false when expiration_date is nil" do
    item = Item.new(description: "No date", expiration_date: nil)
    assert_not item.expired?
  end

  test "posted_to_slack? returns true with slack_message_ts" do
    assert items(:claimed_item).posted_to_slack?
  end

  test "posted_to_slack? returns false without slack_message_ts" do
    assert_not items(:pending_item).posted_to_slack?
  end

  test "vote_summary groups votes by choice" do
    summary = items(:pending_item).vote_summary
    assert_equal 1, summary["mine"]
    assert_equal 1, summary["foster"]
  end

  test "expired_without_votes scope finds expired pending items with no votes" do
    results = Item.expired_without_votes
    assert_includes results, items(:expired_no_votes)
    assert_not_includes results, items(:pending_item)
    assert_not_includes results, items(:claimed_item)
  end

  test "expired_without_votes excludes items with votes" do
    items(:expired_no_votes).votes.create!(slack_user_id: "U999", slack_username: "tester", choice: :kill)
    results = Item.expired_without_votes
    assert_not_includes results, items(:expired_no_votes)
  end

  test "expired_with_votes scope finds expired pending items that have votes" do
    items(:expired_no_votes).votes.create!(slack_user_id: "U999", slack_username: "tester", choice: :mine)
    results = Item.expired_with_votes
    assert_includes results, items(:expired_no_votes)
  end

  test "destroying item destroys associated votes" do
    item = items(:pending_item)
    assert_difference "Vote.count", -2 do
      item.destroy
    end
  end
end
