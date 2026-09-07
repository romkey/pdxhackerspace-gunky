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
    assert_equal({ "pending" => 0, "mine" => 1, "foster" => 2, "kill" => 3, "cancelled" => 4 }, Item.dispositions)
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

  test "completed? is false for pending and true for resolved" do
    assert_not items(:pending_item).completed?
    assert items(:claimed_item).completed?
  end

  test "pickup_deadline_date is one week after expiration" do
    item = items(:claimed_item)
    assert_equal item.expiration_date + 7.days, item.pickup_deadline_date
  end

  test "pickup_deadline_date is nil when expiration is nil" do
    item = Item.create!(description: "No expiry", disposition: :kill)
    item.update_column(:expiration_date, nil)
    assert_nil item.reload.pickup_deadline_date
  end

  test "disposed? reflects disposed_at" do
    assert_not items(:killed_item).disposed?
    assert items(:disposed_killed_item).disposed?
  end

  test "killed disposal scopes separate disposed items" do
    assert_includes Item.killed_not_disposed, items(:killed_item)
    assert_not_includes Item.killed_not_disposed, items(:disposed_killed_item)
    assert_includes Item.killed_disposed, items(:disposed_killed_item)
    assert_not_includes Item.killed_disposed, items(:killed_item)
  end

  test "owned scope includes cancelled items with claimed_by" do
    assert_includes Item.owned, items(:owned_item)
    assert_not_includes Item.owned, items(:cancelled_item)
  end

  test "giveaway_cancelled scope includes cancelled items without claimed_by" do
    assert_includes Item.giveaway_cancelled, items(:cancelled_item)
    assert_not_includes Item.giveaway_cancelled, items(:owned_item)
  end

  test "owned? and giveaway_cancelled? reflect claimed_by" do
    assert items(:owned_item).owned?
    assert_not items(:owned_item).giveaway_cancelled?

    assert items(:cancelled_item).giveaway_cancelled?
    assert_not items(:cancelled_item).owned?
  end

  test "normalized_cancellation_reason strips blank values" do
    item = items(:cancelled_item)
    assert_equal "Already have two", item.normalized_cancellation_reason

    item.update!(cancellation_reason: "   ")
    assert_nil item.normalized_cancellation_reason
  end

  test "disown! returns owned item to pending and clears owner fields" do
    item = items(:owned_item)

    item.disown!
    item.reload

    assert item.pending?
    assert_nil item.claimed_by
    assert_nil item.cancellation_reason
  end

  test "picked_up scope covers mine items whose every winner collected" do
    all_collected = Item.create!(description: "All collected", disposition: :mine)
    all_collected.votes.create!(slack_user_id: "U1", slack_username: "a", choice: :mine, picked_up_at: Time.current)
    all_collected.votes.create!(slack_user_id: "U2", slack_username: "b", choice: :mine, picked_up_at: Time.current)

    partly = Item.create!(description: "Partly collected", disposition: :mine)
    partly.votes.create!(slack_user_id: "U1", slack_username: "a", choice: :mine, picked_up_at: Time.current)
    partly.votes.create!(slack_user_id: "U2", slack_username: "b", choice: :mine)

    none = Item.create!(description: "None collected", disposition: :mine)
    none.votes.create!(slack_user_id: "U1", slack_username: "a", choice: :mine)

    no_votes = Item.create!(description: "No mine votes", disposition: :mine)

    picked = Item.picked_up
    assert_includes picked, all_collected
    assert_not_includes picked, partly
    assert_not_includes picked, none
    assert_not_includes picked, no_votes

    awaiting = Item.awaiting_pickup
    assert_includes awaiting, partly
    assert_includes awaiting, none
    assert_not_includes awaiting, all_collected
    assert_not_includes awaiting, no_votes
  end

  test "picked_up? and awaiting_pickup? mirror the scopes" do
    item = Item.create!(description: "Toolbox", disposition: :mine)
    vote = item.votes.create!(slack_user_id: "U1", slack_username: "a", choice: :mine)

    assert item.awaiting_pickup?
    assert_not item.picked_up?

    vote.update!(picked_up_at: Time.current)
    item.reload

    assert item.picked_up?
    assert_not item.awaiting_pickup?
  end

  test "pickup predicates are false for items that are not mine" do
    item = Item.create!(description: "Trashed", disposition: :kill)
    item.votes.create!(slack_user_id: "U1", slack_username: "a", choice: :mine, picked_up_at: Time.current)

    assert_not item.picked_up?
    assert_not item.awaiting_pickup?
  end

  test "mine_voters_picked_up carries pickup and claim timestamps" do
    item = Item.create!(description: "Plane", disposition: :mine)
    collected_at = 2.days.ago
    item.votes.create!(slack_user_id: "U1", slack_username: "a", choice: :mine, picked_up_at: collected_at)
    item.votes.create!(slack_user_id: "U2", slack_username: "b", choice: :mine)

    collected = item.mine_voters_picked_up
    assert_equal [ "U1" ], collected.map { |w| w[:slack_user_id] }
    assert_in_delta collected_at, collected.first[:picked_up_at], 1.second
    assert collected.first[:claimed_at].present?

    assert_equal [ "U2" ], item.mine_voters_pending_pickup.map { |w| w[:slack_user_id] }
  end

  test "last_picked_up_at reports the most recent collection" do
    item = Item.create!(description: "Plane", disposition: :mine)
    item.votes.create!(slack_user_id: "U1", slack_username: "a", choice: :mine, picked_up_at: 3.days.ago)
    latest = 1.hour.ago
    item.votes.create!(slack_user_id: "U2", slack_username: "b", choice: :mine, picked_up_at: latest)

    assert_in_delta latest, item.last_picked_up_at, 1.second
  end

  test "gunky_stats counts completed dispositions" do
    stats = Item.gunky_stats

    assert_equal Item.gunky_completed.count, stats[:total]
    assert_equal Item.mine.count, stats[:new_homes]
    assert_equal Item.foster.count, stats[:kept_for_space]
    assert_equal Item.kill.count, stats[:trashed]
    assert_equal Item.owned.count, stats[:owners_found]
    assert_equal Item.giveaway_cancelled.count, stats[:cancelled]
    assert_equal Item.picked_up.count, stats[:picked_up]
    assert_equal Item.awaiting_pickup.count, stats[:awaiting_pickup]
  end

  test "dispose! records disposal time" do
    item = items(:killed_item)

    assert_changes -> { item.reload.disposed_at }, from: nil do
      item.dispose!
    end
  end

  test "vote_summary groups votes by choice" do
    summary = items(:pending_item).vote_summary
    assert_equal 1, summary["mine"]
    assert_equal 1, summary["foster"]
  end

  test "mine_voter_usernames returns unique usernames in vote order" do
    item = items(:pending_item)
    item.votes.create!(slack_user_id: "U010", slack_username: "claire", choice: :mine)
    item.votes.create!(slack_user_id: "U009", slack_username: "zoe", choice: :mine)

    assert_equal [ "Alice Display", "claire", "zoe" ], item.mine_voter_usernames
  end

  test "mine_voters_pending_pickup excludes votes with picked_up_at" do
    item = items(:pending_item)
    item.votes.create!(slack_user_id: "U010", slack_username: "claire", choice: :mine)
    picked = item.votes.create!(slack_user_id: "U011", slack_username: "done", choice: :mine, picked_up_at: Time.current)

    pending = item.mine_voters_pending_pickup
    assert_equal 2, pending.size
    assert_not_includes pending.map { |w| w[:slack_user_id] }, picked.slack_user_id
  end

  test "foster_voter_usernames returns unique usernames in vote order" do
    item = items(:pending_item)
    item.votes.create!(slack_user_id: "U010", slack_username: "claire", choice: :foster)
    item.votes.create!(slack_user_id: "U011", slack_username: "dave", choice: :foster)

    assert_equal [ "bob", "claire", "dave" ], item.foster_voter_usernames
  end

  test "resolve_from_votes! assigns to first mine voter" do
    item = items(:expired_no_votes)
    item.votes.create!(slack_user_id: "U020", slack_username: "first", choice: :mine)
    item.votes.create!(slack_user_id: "U021", slack_username: "second", choice: :mine)

    item.resolve_from_votes!
    item.reload

    assert item.mine?
    assert_equal "first", item.claimed_by
  end

  test "resolve_from_votes! prefers foster when no mine votes and foster exists" do
    item = items(:expired_no_votes)
    item.votes.create!(slack_user_id: "U020", slack_username: "first", choice: :kill)
    item.votes.create!(slack_user_id: "U021", slack_username: "second", choice: :kill)
    item.votes.create!(slack_user_id: "U022", slack_username: "third", choice: :foster)

    item.resolve_from_votes!
    item.reload

    assert item.foster?
    assert_nil item.claimed_by
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

  test "expired scopes include items expiring today" do
    item = Item.create!(description: "Expires today", expiration_date: Date.current, disposition: :pending)

    assert_includes Item.expired_without_votes, item

    item.votes.create!(slack_user_id: "U777", slack_username: "today_voter", choice: :mine)
    assert_includes Item.expired_with_votes, item
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
