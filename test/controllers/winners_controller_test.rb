require "test_helper"

class WinnersControllerTest < ActionDispatch::IntegrationTest
  test "index returns success" do
    get winners_path
    assert_response :success
  end

  test "index lists winners alphabetically with item links and actions" do
    lamp = Item.create!(
      description: "Zebra lamp",
      disposition: :mine,
      claimed_by: "bob",
      expiration_date: Date.current - 1.day
    )
    desk = Item.create!(
      description: "Alpha desk",
      disposition: :mine,
      claimed_by: "alice",
      expiration_date: Date.current - 1.day
    )
    lamp.votes.create!(slack_user_id: "U100", slack_username: "bob", choice: :mine)
    desk.votes.create!(slack_user_id: "U100", slack_username: "bob", choice: :mine)
    desk.votes.create!(slack_user_id: "U200", slack_username: "alice", choice: :mine)

    get winners_path

    assert_response :success
    assert_select "h1", text: "Winners"
    assert_select ".card-header", text: "alice"
    assert_select ".card-header", text: "bob"
    assert_select "a[href='#{item_path(desk)}']", text: "Alpha desk"
    assert_select "a[href='#{item_path(lamp)}']", text: "Zebra lamp"
    assert_select "form[action='#{winner_forfeit_item_path(desk, slack_user_id: "U200")}']"
    assert_select "form[action='#{winner_picked_up_item_path(desk, slack_user_id: "U200")}']"
  end

  test "index omits items the user has already picked up" do
    item = Item.create!(
      description: "Toolbox",
      disposition: :mine,
      claimed_by: "alice",
      expiration_date: Date.current - 1.day
    )
    item.votes.create!(slack_user_id: "U111", slack_username: "alice", choice: :mine, picked_up_at: Time.current)

    get winners_path

    assert_response :success
    assert_select "a[href='#{item_path(item)}']", count: 0
  end
end
