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
      next unless action["action_id"]&.start_with?("vote_")

      choice = action["action_id"].delete_prefix("vote_")
      item_id = action["value"].to_i
      user = payload["user"]

      item = Item.find_by(id: item_id)
      next unless item&.pending?

      vote = item.votes.find_or_initialize_by(slack_user_id: user["id"])
      vote.update!(
        slack_username: user["username"].presence || user["name"].presence || user["id"],
        choice: choice
      )

      SlackService.new.update_item_message(item)
    end
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
