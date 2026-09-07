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
    assert_select ".card-header .fw-semibold", text: "alice"
    assert_select ".card-header .fw-semibold", text: "bob"
    assert_select "a[href='#{item_path(desk)}']", text: "Alpha desk"
    assert_select "a[href='#{item_path(lamp)}']", text: "Zebra lamp"
    assert_select "form[action='#{winner_forfeit_item_path(desk, slack_user_id: "U200")}']"
    assert_select "form[action='#{winner_picked_up_item_path(desk, slack_user_id: "U200")}']"
  end

  test "index shows claimed, completed and due dates for each awaiting item" do
    item = Item.create!(
      description: "Vintage plane",
      disposition: :mine,
      claimed_by: "alice",
      expiration_date: Date.current - 10.days
    )
    item.votes.create!(slack_user_id: "U100", slack_username: "alice", choice: :mine)

    get winners_path

    assert_response :success
    body = response.body
    assert_includes body, "Claimed"
    assert_includes body, "Completed #{item.expiration_date.strftime('%b %d, %Y')}"
    assert_includes body, "Due #{item.pickup_deadline_date.strftime('%b %d, %Y')}"
  end

  test "index flags overdue pickups and counts them per winner" do
    overdue = Item.create!(
      description: "Overdue crate",
      disposition: :mine,
      claimed_by: "alice",
      expiration_date: Date.current - 30.days
    )
    overdue.votes.create!(slack_user_id: "U100", slack_username: "alice", choice: :mine)

    get winners_path

    assert_response :success
    assert_select ".card-header .badge.bg-danger", text: "1 item overdue"
    assert_includes response.body, "days overdue"
  end

  test "index does not flag a pickup that is still inside the deadline" do
    fresh = Item.create!(
      description: "Fresh crate",
      disposition: :mine,
      claimed_by: "alice",
      expiration_date: Date.current
    )
    fresh.votes.create!(slack_user_id: "U100", slack_username: "alice", choice: :mine)

    get winners_path

    assert_response :success
    assert_select ".card-header .badge.bg-danger", count: 0
    assert_not_includes response.body, "days overdue"
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
