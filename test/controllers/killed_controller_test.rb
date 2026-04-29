require "test_helper"

class KilledControllerTest < ActionDispatch::IntegrationTest
  test "index returns success" do
    get killed_path
    assert_response :success
  end

  test "index separates killed items by disposal status" do
    get killed_path

    assert_response :success
    assert_select "h2", text: "Awaiting disposal"
    assert_select "h2", text: "Disposed of"
    assert_select "form[action='#{dispose_item_path(items(:killed_item))}']"
    assert_select "a[href='#{item_path(items(:killed_item))}']", text: items(:killed_item).description
    assert_select "a[href='#{item_path(items(:disposed_killed_item))}']", text: items(:disposed_killed_item).description
  end
end
