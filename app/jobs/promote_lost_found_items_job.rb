class PromoteLostFoundItemsJob < ApplicationJob
  queue_as :default

  def perform
    hold_elapsed_count = 0
    pickup_elapsed_count = 0

    Item.lost_found_hold_elapsed.find_each do |item|
      promote_item!(item)
      hold_elapsed_count += 1
    rescue => e
      Rails.logger.error("Failed to promote unclaimed lost+found item #{item.id}: #{e.message}")
    end

    Item.lost_found_pickup_elapsed.find_each do |item|
      promote_item!(item)
      pickup_elapsed_count += 1
    rescue => e
      Rails.logger.error("Failed to promote overdue claimed lost+found item #{item.id}: #{e.message}")
    end

    Rails.logger.info(
      "PromoteLostFoundItemsJob: promoted #{hold_elapsed_count} unclaimed items, " \
      "#{pickup_elapsed_count} overdue claimed items"
    )
  end

  private

  def promote_item!(item)
    item.promote_from_lost_found!
    SlackService.new.update_lost_found_item_message(item)
    SlackService.new.post_item(item) if ENV["SLACK_BOT_TOKEN"].present?
  end
end
