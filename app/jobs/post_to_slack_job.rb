class PostToSlackJob < ApplicationJob
  queue_as :default

  def perform(item_id)
    item = Item.find_by(id: item_id)
    return unless item

    SlackService.new.post_item(item)
  rescue Slack::Web::Api::Errors::SlackError => e
    Rails.logger.error("Failed to post item #{item_id} to Slack: #{e.message}")
    raise if e.message == "channel_not_found" || e.message == "not_authed"
  end
end
