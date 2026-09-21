require "test_helper"

class SlackInteractionsLostFoundTest < ActionDispatch::IntegrationTest
  setup do
    @item = items(:lost_found_unclaimed_item)
    ENV["SLACK_SIGNING_SECRET"] = nil
  end

  teardown do
    ENV["SLACK_SIGNING_SECRET"] = nil
  end

  test "lost_found_claim marks item claimed and refreshes slack message" do
    update_called = false
    original = SlackService.instance_method(:update_lost_found_item_message)
    SlackService.define_method(:update_lost_found_item_message) do |item|
      update_called = true
      assert_equal @item.id, item.id
    end

    original_resolve = SlackMemberCacheService.instance_method(:resolve_name)
    SlackMemberCacheService.define_method(:resolve_name) do |_id, fallback_username:|
      "Resolved #{fallback_username}"
    end

    payload = build_payload(action_id: "lost_found_claim", item_id: @item.id, user_id: "U999", username: "pat")

    post slack_interactions_path, params: { payload: payload.to_json }

    assert_response :ok
    @item.reload
    assert @item.lost_found_claimed?
    assert_equal "Resolved pat", @item.lost_found_claimed_by
    assert_equal "U999", @item.lost_found_claimed_by_slack_user_id
    assert update_called
  ensure
    SlackService.define_method(:update_lost_found_item_message, original)
    SlackMemberCacheService.define_method(:resolve_name, original_resolve)
  end

  test "second lost_found_claim gets ephemeral already claimed notice" do
    item = items(:lost_found_claimed_item)
    ephemeral = []
    original = SlackService.instance_method(:post_ephemeral)
    SlackService.define_method(:post_ephemeral) { |**kwargs| ephemeral << kwargs }

    payload = build_payload(action_id: "lost_found_claim", item_id: item.id, user_id: "U999", username: "mallory")
      .merge(channel: { id: "C0987654321" })

    post slack_interactions_path, params: { payload: payload.to_json }

    assert_response :ok
    assert_equal 1, ephemeral.size
    assert_includes ephemeral.first[:text], "Already claimed"
    assert item.reload.lost_found_claimed?
  ensure
    SlackService.define_method(:post_ephemeral, original)
  end

  test "lost_found_picked_up marks item picked up for authorized claimer" do
    item = items(:lost_found_claimed_item)
    update_called = false
    original = SlackService.instance_method(:update_lost_found_item_message)
    SlackService.define_method(:update_lost_found_item_message) { |_| update_called = true }

    payload = build_payload(
      action_id: "lost_found_picked_up:U001",
      item_id: item.id,
      user_id: "U001",
      username: "alice"
    )

    post slack_interactions_path, params: { payload: payload.to_json }

    assert_response :ok
    assert item.reload.lost_found_picked_up?
    assert update_called
  ensure
    SlackService.define_method(:update_lost_found_item_message, original)
  end

  test "lost_found_picked_up from wrong user sends ephemeral notice" do
    item = items(:lost_found_claimed_item)
    ephemeral = []
    original = SlackService.instance_method(:post_ephemeral)
    SlackService.define_method(:post_ephemeral) { |**kwargs| ephemeral << kwargs }

    payload = build_payload(
      action_id: "lost_found_picked_up:U001",
      item_id: item.id,
      user_id: "U999",
      username: "mallory"
    ).merge(channel: { id: "C0987654321" })

    post slack_interactions_path, params: { payload: payload.to_json }

    assert_response :ok
    assert item.reload.lost_found_claimed?
    assert_equal 1, ephemeral.size
    assert_includes ephemeral.first[:text], "<@U001>"
  ensure
    SlackService.define_method(:post_ephemeral, original)
  end

  test "ignores vote on in-phase lost+found item" do
    payload = build_payload(action_id: "vote_mine", item_id: @item.id, user_id: "U999", username: "newuser")

    assert_no_difference "Vote.count" do
      post slack_interactions_path, params: { payload: payload.to_json }
    end
    assert_response :ok
  end

  private

  def build_payload(action_id:, item_id:, user_id:, username:)
    {
      type: "block_actions",
      user: { id: user_id, username: username },
      actions: [ { action_id: action_id, value: item_id.to_s } ]
    }
  end
end
