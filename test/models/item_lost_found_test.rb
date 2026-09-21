require "test_helper"

class ItemLostFoundTest < ActiveSupport::TestCase
  setup do
    @setting = lost_found_settings(:default)
  end

  test "start_lost_found sets unclaimed state and hold until date" do
    item = Item.new(description: "Test item")
    item.start_lost_found!(hold_days: 14)
    item.save!

    assert item.lost_found_unclaimed?
    assert_equal 14.days.from_now.to_date, item.lost_found_hold_until
    assert item.in_lost_found?
    assert item.was_lost_found?
  end

  test "claim_lost_found sets claimed state and pickup deadline" do
    item = items(:lost_found_unclaimed_item)
    item.claim_lost_found!(name: "Pat", slack_user_id: "U999", pickup_days: 7)

    assert item.lost_found_claimed?
    assert_equal "Pat", item.lost_found_claimed_by
    assert_equal "U999", item.lost_found_claimed_by_slack_user_id
    assert_equal 7.days.from_now.to_date, item.lost_found_pickup_deadline
  end

  test "release_lost_found_claim clears claim fields" do
    item = items(:lost_found_claimed_item)
    item.release_lost_found_claim!

    assert item.lost_found_unclaimed?
    assert_nil item.lost_found_claimed_by
    assert_nil item.lost_found_pickup_deadline
  end

  test "mark_lost_found_picked_up sets picked up state" do
    item = items(:lost_found_claimed_item)
    item.mark_lost_found_picked_up!

    assert item.lost_found_picked_up?
    assert item.lost_found_picked_up_at.present?
  end

  test "promote_from_lost_found resets expiration for gunky poll" do
    item = items(:lost_found_unclaimed_item)
    item.promote_from_lost_found!

    assert item.lost_found_promoted?
    assert item.lost_found_promoted_at.present?
    assert_equal 7.days.from_now.to_date, item.expiration_date
  end

  test "gunky_visible excludes in-phase lost+found items" do
    assert_includes Item.gunky_visible, items(:pending_item)
    assert_includes Item.gunky_visible, items(:lost_found_promoted_item)
    assert_not_includes Item.gunky_visible, items(:lost_found_unclaimed_item)
    assert_not_includes Item.gunky_visible, items(:lost_found_claimed_item)
  end

  test "lost_found_hold_elapsed finds overdue unclaimed items" do
    overdue = Item.create!(
      description: "Overdue unclaimed",
      lost_found_state: :lost_found_unclaimed,
      lost_found_hold_until: 1.day.ago.to_date,
      expiration_date: 1.day.ago.to_date
    )

    assert_includes Item.lost_found_hold_elapsed, overdue
    assert_not_includes Item.lost_found_hold_elapsed, items(:lost_found_unclaimed_item)
  end

  test "lost_found_pickup_elapsed finds overdue claimed items" do
    assert_includes Item.lost_found_pickup_elapsed, items(:lost_found_claimed_overdue_item)
    assert_not_includes Item.lost_found_pickup_elapsed, items(:lost_found_claimed_item)
    assert_not_includes Item.lost_found_pickup_elapsed, items(:lost_found_picked_up_item)
  end

  test "gunky_stats excludes in-phase lost+found items" do
    stats = Item.gunky_stats

    assert_equal Item.gunky_completed.count, stats[:total]
    assert_not_includes Item.gunky_visible.mine.pluck(:id), items(:lost_found_unclaimed_item).id
  end
end
