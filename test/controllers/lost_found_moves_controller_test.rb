require "test_helper"

class LostFoundMovesControllerTest < ActionDispatch::IntegrationTest
  test "index lists promoted items that have not been moved" do
    get lost_found_moves_path

    assert_response :success
    assert_select "h1", text: "To move"
    assert_select "a[href='#{item_path(items(:lost_found_promoted_item))}']", text: "Old soldering iron"
    assert_select "a[href='#{item_path(items(:lost_found_promoted_moved_item))}']", count: 0
    assert_select "a[href='#{item_path(items(:lost_found_unclaimed_item))}']", count: 0
    assert_select "form[action='#{dismiss_lost_found_move_path(items(:lost_found_promoted_item))}']"
    assert_select "input[type=checkbox][name='item_ids[]'][value='#{items(:lost_found_promoted_item).id}']"
    assert_select "button", text: "Select"
  end

  test "index shows empty state when nothing needs moving" do
    Item.lost_found_to_move.update_all(lost_found_moved_at: Time.current)

    get lost_found_moves_path

    assert_response :success
    assert_select "h4", text: "Nothing to move"
    assert_select "button", text: "Select", count: 0
  end

  test "dismiss marks a single item as moved" do
    item = items(:lost_found_promoted_item)

    post dismiss_lost_found_move_path(item)

    assert_redirected_to lost_found_moves_path
    assert item.reload.lost_found_moved_at.present?
    assert_not_includes Item.lost_found_to_move, item
  end

  test "dismiss rejects items that are not waiting to be moved" do
    item = items(:lost_found_unclaimed_item)

    post dismiss_lost_found_move_path(item)

    assert_redirected_to lost_found_moves_path
    assert_equal "That item is not waiting to be moved.", flash[:alert]
    assert_nil item.reload.lost_found_moved_at
  end

  test "dismiss_selected marks only the checked promoted items as moved" do
    promoted = items(:lost_found_promoted_item)
    other = Item.create!(description: "Spare monitor", lost_found_state: :lost_found_promoted,
                         lost_found_promoted_at: 1.hour.ago)
    unclaimed = items(:lost_found_unclaimed_item)

    post dismiss_selected_lost_found_moves_path, params: { item_ids: [ promoted.id, unclaimed.id ] }

    assert_redirected_to lost_found_moves_path
    assert_equal "Marked 1 item as moved to Gunky.", flash[:notice]
    assert promoted.reload.lost_found_moved_at.present?
    assert_nil other.reload.lost_found_moved_at
    assert_nil unclaimed.reload.lost_found_moved_at
  end

  test "dismiss_selected with nothing checked shows an alert" do
    post dismiss_selected_lost_found_moves_path

    assert_redirected_to lost_found_moves_path
    assert_equal "Select at least one item to dismiss.", flash[:alert]
  end
end
