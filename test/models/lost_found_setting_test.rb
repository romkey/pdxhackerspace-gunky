require "test_helper"

class LostFoundSettingTest < ActiveSupport::TestCase
  test "validates hold and pickup day ranges" do
    setting = lost_found_settings(:default)

    setting.hold_days = 0
    assert_not setting.valid?

    setting.hold_days = 14
    setting.pickup_days = 100
    assert_not setting.valid?

    setting.pickup_days = 7
    assert setting.valid?
  end

  test "instance returns singleton row" do
    assert_equal lost_found_settings(:default), LostFoundSetting.instance
  end
end
