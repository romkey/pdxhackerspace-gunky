require "test_helper"

class LocationTest < ActiveSupport::TestCase
  test "only one location can be the default lost+found location" do
    first = locations(:lobby)
    second = locations(:shelf)

    first.update!(default_lost_found: true)
    assert first.reload.default_lost_found?

    second.update!(default_lost_found: true)
    assert second.reload.default_lost_found?
    assert_not first.reload.default_lost_found?
  end

  test "default_lost_found_location returns the flagged location" do
    locations(:workshop).update!(default_lost_found: true)

    assert_equal locations(:workshop), Location.default_lost_found_location
  end
end
