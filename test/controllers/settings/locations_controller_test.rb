require "test_helper"

module Settings
  class LocationsControllerTest < ActionDispatch::IntegrationTest
    test "index lists locations and default badge" do
      locations(:shelf).update!(default_lost_found: true)

      get settings_locations_path

      assert_response :success
      assert_select "td", text: "Lost shelf"
      assert_select "span.badge", text: "Default"
    end

    test "update can set default lost+found location" do
      location = locations(:lobby)
      locations(:shelf).update!(default_lost_found: true)

      patch settings_location_path(location), params: {
        location: { name: location.name, default_lost_found: "1" }
      }

      assert_redirected_to settings_locations_path
      assert location.reload.default_lost_found?
      assert_not locations(:shelf).reload.default_lost_found?
    end
  end
end
