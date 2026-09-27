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

    enqueue_duplicate_check(item)
  rescue Slack::Web::Api::Errors::SlackError => e
    error_code = slack_error_code(e)
    Rails.logger.error("Failed to post item #{item_id} to Slack (#{error_code}): #{e.message}")
    raise if CRITICAL_SLACK_ERRORS.include?(error_code)
  end

  private

  # The delayed run covers an AI description that never arrives.
  def enqueue_duplicate_check(item)
    CheckDuplicatesJob.perform_later(item.id)
    CheckDuplicatesJob.set(wait: CheckDuplicatesJob::AI_DESCRIPTION_FALLBACK_WAIT)
                      .perform_later(item.id, ignore_ai_wait: true)
  end

  def slack_error_code(error)
    error.response&.dig("error").presence || error.message.to_s
  end
end
