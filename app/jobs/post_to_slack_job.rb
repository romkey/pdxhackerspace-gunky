class PostToSlackJob < ApplicationJob
  queue_as :default

  CRITICAL_SLACK_ERRORS = %w[channel_not_found not_authed not_in_channel].freeze

  def perform(item_id)
    item = Item.find_by(id: item_id)
    unless item
      Rails.logger.warn("PostToSlackJob skipped: item #{item_id} not found")
      return
    end

    if item.in_lost_found?
      Rails.logger.info("PostToSlackJob posting lost+found item #{item_id} to Slack")
      SlackService.new.post_lost_found_item(item)
    else
      Rails.logger.info("PostToSlackJob posting gunky item #{item_id} to Slack")
      SlackService.new.post_item(item)
    end
  rescue Slack::Web::Api::Errors::SlackError => e
    error_code = slack_error_code(e)
    Rails.logger.error("Failed to post item #{item_id} to Slack (#{error_code}): #{e.message}")
    raise if CRITICAL_SLACK_ERRORS.include?(error_code)
  end

  private

  def slack_error_code(error)
    error.response&.dig("error").presence || error.message.to_s
  end
end
