require "test_helper"

class LostFoundHelperTest < ActionView::TestCase
  include LostFoundHelper

  test "lost_found_state_label returns readable labels" do
    assert_equal "Unclaimed", lost_found_state_label(items(:lost_found_unclaimed_item))
    assert_equal "Awaiting pickup", lost_found_state_label(items(:lost_found_claimed_item))
    assert_equal "Picked up", lost_found_state_label(items(:lost_found_picked_up_item))
    assert_equal "Promoted to Gunky", lost_found_state_label(items(:lost_found_promoted_item))
  end

  test "lost_found_pickup_deadline_line shows overdue text" do
    item = items(:lost_found_claimed_overdue_item)

    assert_includes lost_found_pickup_deadline_line(item), "overdue"
  end
end
