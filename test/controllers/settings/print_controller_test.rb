require "test_helper"

class Settings::PrintControllerTest < ActionDispatch::IntegrationTest
  test "show returns success" do
    get settings_print_path
    assert_response :success
  end

  test "update persists paper width" do
    patch settings_print_path, params: { print_setting: { paper_width_mm: 58, thermal_printer_name: "Test printer" } }
    assert_redirected_to settings_print_path
    assert_equal 58, PrintSetting.instance.paper_width_mm
    assert_equal "Test printer", PrintSetting.instance.thermal_printer_name
  end
end
