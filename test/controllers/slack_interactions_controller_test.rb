require "test_helper"
require "cgi"

class SlackInteractionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @item = items(:pending_item)
    ENV["SLACK_SIGNING_SECRET"] = nil
  end

  teardown do
    ENV["SLACK_SIGNING_SECRET"] = nil
  end

  test "creates a new vote from block action" do
    stub_slack_update do
      payload = build_payload(action_id: "vote_mine", item_id: @item.id, user_id: "U999", username: "newuser")

      assert_difference "Vote.count", 1 do
        post slack_interactions_path, params: { payload: payload.to_json }
      end

      assert_response :ok
      vote = Vote.last
      assert_equal "U999", vote.slack_user_id
      assert_equal "newuser", vote.slack_username
      assert vote.mine?
    end
  end

  test "replaces existing vote when user votes again" do
    stub_slack_update do
      payload = build_payload(action_id: "vote_kill", item_id: @item.id, user_id: "U001", username: "alice")

      assert_no_difference "Vote.count" do
        post slack_interactions_path, params: { payload: payload.to_json }
      end

      assert_response :ok
      vote = @item.votes.find_by!(slack_user_id: "U001")
      assert vote.kill?
      assert_equal "alice", vote.slack_username
    end
  end

  test "updates Slack message on every vote" do
    update_calls = 0
    original = SlackService.instance_method(:update_item_message)
    SlackService.define_method(:update_item_message) do |item|
      update_calls += 1
    end

    first_payload = build_payload(action_id: "vote_mine", item_id: @item.id, user_id: "U100", username: "one")
    second_payload = build_payload(action_id: "vote_foster", item_id: @item.id, user_id: "U101", username: "two")

    post slack_interactions_path, params: { payload: first_payload.to_json }
    post slack_interactions_path, params: { payload: second_payload.to_json }

    assert_equal 2, update_calls
  ensure
    SlackService.define_method(:update_item_message, original)
  end

  test "forfeit removes mine vote, re-resolves item, and reposts expired notice" do
    item = Item.create!(
      description: "Expired item",
      expiration_date: Date.current - 1.day,
      disposition: :mine,
      claimed_by: "alice",
      slack_channel_id: "C123",
      slack_message_ts: "111.222"
    )
    item.votes.create!(slack_user_id: "U001", slack_username: "alice", choice: :mine)
    item.votes.create!(slack_user_id: "U002", slack_username: "bob", choice: :foster)

    repost_called = false
    original = SlackService.instance_method(:replace_expired_item_message)
    SlackService.define_method(:replace_expired_item_message) { |_| repost_called = true }

    payload = build_payload(
      action_id: "expired_forfeit:U001",
      item_id: item.id,
      user_id: "U001",
      username: "alice"
    )

    post slack_interactions_path, params: { payload: payload.to_json }

    assert_response :ok
    assert repost_called
    assert_nil item.votes.find_by(slack_user_id: "U001", choice: :mine)
    assert item.reload.foster?
  ensure
    SlackService.define_method(:replace_expired_item_message, original)
  end

  test "forfeit from different user is ignored" do
    item = Item.create!(
      description: "Expired item",
      expiration_date: Date.current - 1.day,
      disposition: :mine,
      claimed_by: "alice",
      slack_channel_id: "C123",
      slack_message_ts: "111.222"
    )
    item.votes.create!(slack_user_id: "U001", slack_username: "alice", choice: :mine)

    payload = build_payload(
      action_id: "expired_forfeit:U001",
      item_id: item.id,
      user_id: "U999",
      username: "mallory"
    )

    post slack_interactions_path, params: { payload: payload.to_json }

    assert_response :ok
    assert item.votes.find_by(slack_user_id: "U001", choice: :mine).present?
    assert item.reload.mine?
  end

  test "ignores vote on non-pending item" do
    resolved_item = items(:claimed_item)
    payload = build_payload(action_id: "vote_mine", item_id: resolved_item.id, user_id: "U999", username: "newuser")

    assert_no_difference "Vote.count" do
      post slack_interactions_path, params: { payload: payload.to_json }
    end
    assert_response :ok
  end

  test "ignores vote on nonexistent item" do
    payload = build_payload(action_id: "vote_mine", item_id: 0, user_id: "U999", username: "newuser")

    assert_no_difference "Vote.count" do
      post slack_interactions_path, params: { payload: payload.to_json }
    end
    assert_response :ok
  end

  test "ignores non-vote actions" do
    payload = {
      type: "block_actions",
      user: { id: "U999", username: "newuser" },
      actions: [ { action_id: "something_else", value: @item.id.to_s } ]
    }

    assert_no_difference "Vote.count" do
      post slack_interactions_path, params: { payload: payload.to_json }
    end
    assert_response :ok
  end

  test "rejects request with invalid signature" do
    ENV["SLACK_SIGNING_SECRET"] = "test_secret"
    payload = build_payload(action_id: "vote_mine", item_id: @item.id, user_id: "U999", username: "newuser")

    post slack_interactions_path,
         params: { payload: payload.to_json },
         headers: {
           "X-Slack-Request-Timestamp" => Time.now.to_i.to_s,
           "X-Slack-Signature" => "v0=bad_signature"
         }

    assert_response :unauthorized
  end

  test "accepts request with valid signature" do
    ENV["SLACK_SIGNING_SECRET"] = "test_secret"
    payload = build_payload(action_id: "vote_mine", item_id: @item.id, user_id: "U123", username: "signeduser")
    encoded_payload = "payload=#{CGI.escape(payload.to_json)}"
    timestamp = Time.now.to_i.to_s
    signature = "v0=#{OpenSSL::HMAC.hexdigest('SHA256', ENV['SLACK_SIGNING_SECRET'], "v0:#{timestamp}:#{encoded_payload}")}"

    stub_slack_update do
      assert_difference "Vote.count", 1 do
        post slack_interactions_path,
             params: encoded_payload,
             headers: {
               "CONTENT_TYPE" => "application/x-www-form-urlencoded",
               "X-Slack-Request-Timestamp" => timestamp,
               "X-Slack-Signature" => signature
             }
      end
    end

    assert_response :ok
    assert_equal "U123", Vote.last.slack_user_id
  end

  test "rejects request with missing signature header" do
    ENV["SLACK_SIGNING_SECRET"] = "test_secret"
    payload = build_payload(action_id: "vote_mine", item_id: @item.id, user_id: "U999", username: "newuser")

    post slack_interactions_path,
         params: { payload: payload.to_json },
         headers: {
           "X-Slack-Request-Timestamp" => Time.now.to_i.to_s
         }

    assert_response :unauthorized
  end

  test "rejects request with stale timestamp" do
    ENV["SLACK_SIGNING_SECRET"] = "test_secret"
    payload = build_payload(action_id: "vote_mine", item_id: @item.id, user_id: "U999", username: "newuser")

    post slack_interactions_path,
         params: { payload: payload.to_json },
         headers: {
           "X-Slack-Request-Timestamp" => (Time.now.to_i - 600).to_s,
           "X-Slack-Signature" => "v0=anything"
         }

    assert_response :unauthorized
  end

  test "returns bad request when payload is missing" do
    post slack_interactions_path, params: {}

    assert_response :bad_request
  end

  test "skips signature check when signing secret is not configured" do
    ENV["SLACK_SIGNING_SECRET"] = nil

    stub_slack_update do
      payload = build_payload(action_id: "vote_foster", item_id: @item.id, user_id: "U888", username: "signer")

      assert_difference "Vote.count", 1 do
        post slack_interactions_path, params: { payload: payload.to_json }
      end

      assert_response :ok
    end
  end

  private

  def stub_slack_update(&block)
    original = SlackService.instance_method(:update_item_message)
    SlackService.define_method(:update_item_message) { |_| nil }
    yield
  ensure
    SlackService.define_method(:update_item_message, original)
  end

  def build_payload(action_id:, item_id:, user_id:, username:)
    {
      type: "block_actions",
      user: { id: user_id, username: username },
      actions: [ { action_id: action_id, value: item_id.to_s } ]
    }
  end
end
