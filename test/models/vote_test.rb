require "test_helper"

class VoteTest < ActiveSupport::TestCase
  test "valid vote" do
    vote = Vote.new(item: items(:expired_no_votes), slack_user_id: "U999", slack_username: "tester", choice: :mine)
    assert vote.valid?
  end

  test "invalid without slack_user_id" do
    vote = Vote.new(item: items(:expired_no_votes), slack_username: "tester", choice: :mine)
    assert_not vote.valid?
    assert_includes vote.errors[:slack_user_id], "can't be blank"
  end

  test "invalid without slack_username" do
    vote = Vote.new(item: items(:expired_no_votes), slack_user_id: "U999", choice: :mine)
    assert_not vote.valid?
    assert_includes vote.errors[:slack_username], "can't be blank"
  end

  test "invalid without choice" do
    vote = Vote.new(item: items(:expired_no_votes), slack_user_id: "U999", slack_username: "tester")
    assert_not vote.valid?
  end

  test "allows multiple votes per user per item" do
    vote = Vote.new(item: items(:pending_item), slack_user_id: "U001", slack_username: "alice_dupe", choice: :kill)
    assert vote.valid?
  end

  test "same user can vote on different items" do
    vote = Vote.new(item: items(:expired_no_votes), slack_user_id: "U001", slack_username: "alice", choice: :foster)
    assert vote.valid?
  end

  test "choice enum values" do
    assert_equal({ "mine" => 0, "foster" => 1, "kill" => 2 }, Vote.choices)
  end

  test "belongs to item" do
    vote = votes(:alice_mine)
    assert_equal items(:pending_item), vote.item
  end
end
