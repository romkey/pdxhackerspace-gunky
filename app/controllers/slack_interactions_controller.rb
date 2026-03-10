class SlackInteractionsController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :verify_slack_signature

  def create
    payload = JSON.parse(params[:payload])

    case payload["type"]
    when "block_actions"
      handle_block_actions(payload)
    end

    head :ok
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
        slack_username: user["username"] || user["name"],
        choice: choice
      )

      SlackService.new.update_item_message(item)
    end
  end

  def verify_slack_signature
    signing_secret = ENV["SLACK_SIGNING_SECRET"]
    return if signing_secret.blank?

    timestamp = request.headers["X-Slack-Request-Timestamp"]
    if Time.now.to_i - timestamp.to_i > 300
      head :unauthorized
      return
    end

    body = request.body.read
    request.body.rewind

    sig_basestring = "v0:#{timestamp}:#{body}"
    my_signature = "v0=#{OpenSSL::HMAC.hexdigest('SHA256', signing_secret, sig_basestring)}"

    unless ActiveSupport::SecurityUtils.secure_compare(my_signature, request.headers["X-Slack-Signature"].to_s)
      head :unauthorized
    end
  end
end
