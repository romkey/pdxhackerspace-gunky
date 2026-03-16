class SlackInteractionsController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :verify_slack_signature

  def create
    raw_payload = params[:payload]
    if raw_payload.blank?
      Rails.logger.error("Slack callback rejected: missing payload parameter")
      head :bad_request
      return
    end

    payload = JSON.parse(raw_payload)

    case payload["type"]
    when "block_actions"
      handle_block_actions(payload)
    else
      Rails.logger.info("Slack callback ignored unsupported payload type: #{payload['type'].inspect}")
    end

    head :ok
  rescue JSON::ParserError => e
    Rails.logger.error(
      "Slack callback rejected: invalid JSON payload (error=#{e.message}, payload_prefix=#{raw_payload.to_s.truncate(200).inspect})"
    )
    head :bad_request
  end

  private

  def handle_block_actions(payload)
    payload["actions"].each do |action|
      action_id = action["action_id"].to_s
      case
      when action_id.start_with?("vote_")
        handle_vote_action(payload, action)
      when action_id.start_with?("expired_forfeit:")
        handle_expired_forfeit_action(payload, action)
      when action_id.start_with?("expired_picked_up:")
        handle_expired_picked_up_action(payload, action)
      end
    end
  end

  def handle_vote_action(payload, action)
    choice = action["action_id"].delete_prefix("vote_")
    item_id = action["value"].to_i
    user = payload["user"]

    item = Item.find_by(id: item_id)
    unless item&.pending?
      Rails.logger.info(
        "Slack vote ignored for non-pending item (item_id=#{item_id}, disposition=#{item&.disposition.inspect}, user_id=#{user['id']})"
      )
      return
    end

    resolved_name = SlackMemberCacheService.new.resolve_name(
      user["id"],
      fallback_username: user["username"].presence || user["name"].presence || user["id"]
    )

    vote = item.votes.find_or_initialize_by(slack_user_id: user["id"])
    vote.update!(
      slack_username: resolved_name,
      choice: choice
    )

    SlackService.new.update_item_message(item)
  end

  def handle_expired_forfeit_action(payload, action)
    item_id = action["value"].to_i
    target_user_id = action["action_id"].delete_prefix("expired_forfeit:")
    acting_user_id = payload.dig("user", "id").to_s
    return unless acting_user_id == target_user_id

    item = Item.find_by(id: item_id)
    return unless item

    mine_vote = item.votes.find_by(slack_user_id: target_user_id, choice: :mine)
    return unless mine_vote

    mine_vote.destroy!
    item.resolve_from_votes!

    SlackService.new.replace_expired_item_message(item) if item.posted_to_slack?
  end

  def handle_expired_picked_up_action(payload, action)
    item_id = action["value"].to_i
    target_user_id = action["action_id"].delete_prefix("expired_picked_up:")
    acting_user_id = payload.dig("user", "id").to_s
    return unless acting_user_id == target_user_id

    item = Item.find_by(id: item_id)
    return unless item

    Rails.logger.info("Expired item #{item.id}: #{acting_user_id} acknowledged pickup")
  end

  def verify_slack_signature
    signing_secret = ENV["SLACK_SIGNING_SECRET"].to_s.strip
    if signing_secret.blank?
      Rails.logger.warn("Slack signature verification skipped: SLACK_SIGNING_SECRET is not configured")
      return
    end

    timestamp = request.headers["X-Slack-Request-Timestamp"].to_s.strip
    signature = request.headers["X-Slack-Signature"].to_s.strip

    if timestamp.blank?
      log_signature_failure(
        reason: "missing_timestamp",
        expected_timestamp_window_seconds: 300,
        got_timestamp: timestamp,
        got_signature: signature
      )
      head :unauthorized
      return
    end

    timestamp_i = Integer(timestamp, exception: false)
    if timestamp_i.nil?
      log_signature_failure(
        reason: "invalid_timestamp",
        expected_timestamp_window_seconds: 300,
        got_timestamp: timestamp,
        got_signature: signature
      )
      head :unauthorized
      return
    end

    if (Time.now.to_i - timestamp_i).abs > 300
      log_signature_failure(
        reason: "stale_or_future_timestamp",
        expected_timestamp_window_seconds: 300,
        got_timestamp: timestamp_i,
        got_signature: signature
      )
      head :unauthorized
      return
    end

    body = request.raw_post.to_s

    sig_basestring = "v0:#{timestamp}:#{body}"
    expected_signature = "v0=#{OpenSSL::HMAC.hexdigest('SHA256', signing_secret, sig_basestring)}"

    unless secure_compare_signatures(expected_signature, signature)
      log_signature_failure(
        reason: "signature_mismatch",
        expected_signature: expected_signature,
        got_signature: signature,
        got_timestamp: timestamp_i,
        body_sha256: OpenSSL::Digest::SHA256.hexdigest(body)
      )
      head :unauthorized
    end
  end

  def secure_compare_signatures(expected_signature, actual_signature)
    return false if actual_signature.blank?
    return false unless expected_signature.bytesize == actual_signature.bytesize

    ActiveSupport::SecurityUtils.secure_compare(expected_signature, actual_signature)
  end

  def log_signature_failure(details)
    context = details.merge(
      path: request.path,
      request_method: request.method,
      request_id: request.request_id
    )
    Rails.logger.error("Slack signature verification failed: #{context.to_json}")
  end
end
