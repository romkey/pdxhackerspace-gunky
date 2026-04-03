require "test_helper"

class Settings::PrintControllerTest < ActionDispatch::IntegrationTest
  test "show returns success" do
    get settings_print_path
    assert_response :success
  end

  test "update persists paper width and CUPS queue" do
    patch settings_print_path, params: { print_setting: { paper_width_mm: 58, cups_queue: "TestPrinter" } }
    assert_redirected_to settings_print_path
    assert_equal 58, PrintSetting.instance.paper_width_mm
    assert_equal "TestPrinter", PrintSetting.instance.cups_queue
  end

  test "update rejects invalid cups queue name" do
    patch settings_print_path, params: { print_setting: { cups_queue: "bad queue", paper_width_mm: 80 } }
    assert_response :unprocessable_entity
  end
end
