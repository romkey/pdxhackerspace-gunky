class ExpireItemsJob < ApplicationJob
  queue_as :default

  def perform
    auto_killed_count = 0
    resolved_with_votes_count = 0

    Item.expired_without_votes.find_each do |item|
      item.update!(disposition: :kill)
      SlackService.new.update_item_message(item) if item.posted_to_slack?
      auto_killed_count += 1
    rescue => e
      Rails.logger.error("Failed to expire item #{item.id}: #{e.message}")
    end

    Item.expired_with_votes.find_each do |item|
      item.resolve_from_votes!
      SlackService.new.update_item_message(item) if item.posted_to_slack?
      resolved_with_votes_count += 1
    rescue => e
      Rails.logger.error("Failed to resolve voted item #{item.id}: #{e.message}")
    end

    Rails.logger.info(
      "ExpireItemsJob: auto-killed #{auto_killed_count} items with no votes, resolved #{resolved_with_votes_count} items with votes"
    )
  end
end
