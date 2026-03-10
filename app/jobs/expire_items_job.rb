class ExpireItemsJob < ApplicationJob
  queue_as :default

  def perform
    expired_count = 0

    Item.expired_without_votes.find_each do |item|
      item.update!(disposition: :kill)
      SlackService.new.update_item_message(item) if item.posted_to_slack?
      expired_count += 1
    rescue => e
      Rails.logger.error("Failed to expire item #{item.id}: #{e.message}")
    end

    Rails.logger.info("ExpireItemsJob: auto-killed #{expired_count} items with no votes")
  end
end
