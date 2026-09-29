require "test_helper"

class LostFoundHelperTest < ActionView::TestCase
  include LostFoundHelper

  test "lost_found_state_label returns readable labels" do
    assert_equal "Unclaimed", lost_found_state_label(items(:lost_found_unclaimed_item))
    assert_equal "Awaiting pickup", lost_found_state_label(items(:lost_found_claimed_item))
    assert_equal "Picked up", lost_found_state_label(items(:lost_found_picked_up_item))
    assert_equal "Promoted to Gunky", lost_found_state_label(items(:lost_found_promoted_item))
  end

  test "lost_found_filter_tabs include awaiting pickup and picked up" do
    labels = lost_found_filter_tabs.map(&:first)
    filters = lost_found_filter_tabs.map(&:last)

    assert_includes labels, "Awaiting pickup"
    assert_includes labels, "Picked up"
    assert_includes filters, "awaiting_pickup"
    assert_includes filters, "picked_up"
    assert_not_includes filters, "claimed"
  end

  test "lost_found_pickup_deadline_line shows overdue text" do
    item = items(:lost_found_claimed_overdue_item)

    assert_includes lost_found_pickup_deadline_line(item), "overdue"
  end
end
