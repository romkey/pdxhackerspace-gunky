require "test_helper"

class ItemsControllerLostFoundTest < ActionDispatch::IntegrationTest
  setup do
    @original_lost_found_url = ENV["LOST_FOUND_URL"]
    @original_gunky_url = ENV["GUNKY_URL"]
    @original_slack_token = ENV["SLACK_BOT_TOKEN"]
    ENV["LOST_FOUND_URL"] = "http://lostfound.test"
    ENV["GUNKY_URL"] = "http://www.example.com"
    ENV["SLACK_BOT_TOKEN"] = "xoxb-test"
    @lost_found_host = "lostfound.test"
    @gunky_host = "www.example.com"
  end

  teardown do
    ENV["LOST_FOUND_URL"] = @original_lost_found_url
    ENV["GUNKY_URL"] = @original_gunky_url
    ENV["SLACK_BOT_TOKEN"] = @original_slack_token
  end

  test "lost+found index shows only lost+found items" do
    host! @lost_found_host
    get items_path

    assert_response :success
    assert_select "h1", text: "Lost+Found"
    assert_select "h5.card-title", text: /Mystery backpack/
    assert_select "h5.card-title", text: /Old printer/, count: 0
  end

  test "gunky index excludes in-phase lost+found items" do
    host! @gunky_host
    get items_path

    assert_response :success
    assert_select "h5.card-title", text: /Old printer/
    assert_select "h5.card-title", text: /Mystery backpack/, count: 0
  end

  test "gunky index includes promoted lost+found items" do
    host! @gunky_host
    get items_path

    assert_response :success
    assert_select "h5.card-title", text: /Old soldering iron/
  end

  test "create on lost+found host starts lost+found phase" do
    host! @lost_found_host

    assert_enqueued_with(job: PostToSlackJob) do
      post items_path, params: { item: { description: "Found wallet", location: "Lobby" } }
    end

    item = Item.order(:id).last
    assert item.lost_found_unclaimed?
    assert_equal 14.days.from_now.to_date, item.lost_found_hold_until
    assert_redirected_to item_path(item)
  end

  test "create on gunky host stays not lost+found" do
    host! @gunky_host

    post items_path, params: { item: { description: "Giveaway widget", location: "Shelf" } }

    item = Item.order(:id).last
    assert item.not_lost_found?
  end

  test "new form on lost+found host shows hold note instead of expiration field" do
    host! @lost_found_host
    get new_item_path

    assert_response :success
    assert_select "input[name='item[expiration_date]']", count: 0
    assert_select ".form-label", text: "Hold period"
  end

  test "show works on both hosts" do
    item = items(:lost_found_unclaimed_item)

    host! @gunky_host
    get item_path(item)
    assert_response :success

    host! @lost_found_host
    get item_path(item)
    assert_response :success
  end

  test "lost_found_claim marks item claimed" do
    item = items(:lost_found_unclaimed_item)
    host! @lost_found_host

    post lost_found_claim_item_path(item), params: { claimed_by: "Pat Owner" }

    assert_redirected_to item_path(item)
    item.reload
    assert item.lost_found_claimed?
    assert_equal "Pat Owner", item.lost_found_claimed_by
  end

  test "lost_found_picked_up marks item picked up" do
    item = items(:lost_found_claimed_item)
    host! @lost_found_host

    post lost_found_picked_up_item_path(item)

    assert_redirected_to item_path(item)
    assert item.reload.lost_found_picked_up?
  end

  test "lost_found_promote promotes item to gunky" do
    item = items(:lost_found_unclaimed_item)
    host! @lost_found_host

    assert_enqueued_with(job: PostToSlackJob) do
      post lost_found_promote_item_path(item)
    end

    assert_redirected_to item_path(item)
    assert item.reload.lost_found_promoted?
  end

  test "lost+found index promoted filter tab" do
    host! @lost_found_host
    get items_path(disposition: "promoted")

    assert_response :success
    assert_select "h5.card-title", text: /Old soldering iron/
    assert_select "h5.card-title", text: /Mystery backpack/, count: 0
  end
end
