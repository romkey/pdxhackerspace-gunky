require "test_helper"

module Settings
  class LostFoundControllerTest < ActionDispatch::IntegrationTest
    test "show displays current settings" do
      get settings_lost_found_path

      assert_response :success
      assert_select "input[name='lost_found_setting[hold_days]'][value='14']"
      assert_select "input[name='lost_found_setting[pickup_days]'][value='7']"
    end

    test "update changes hold and pickup days" do
      patch settings_lost_found_path, params: {
        lost_found_setting: { hold_days: 21, pickup_days: 10 }
      }

      assert_redirected_to settings_lost_found_path
      setting = lost_found_settings(:default).reload
      assert_equal 21, setting.hold_days
      assert_equal 10, setting.pickup_days
    end
  end
end
