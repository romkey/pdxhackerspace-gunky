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

  # Slack side effects cannot roll back with the DB transaction. Post the Gunky
  # poll first, persist promotion only after that succeeds, then rewrite the
  # lost+found message. Delete any orphan Gunky post if persistence fails.
  def promote_item!(item)
    slack = SlackService.new
    gunky_response = post_gunky_poll(slack, item)

    ActiveRecord::Base.transaction do
      item.promote_from_lost_found!
      persist_gunky_poll!(item, gunky_response)
    end

    refresh_lost_found_message(slack, item)
  rescue => e
    delete_orphan_gunky_poll(slack, gunky_response)
    raise e
  end

  def post_gunky_poll(slack, item)
    return nil unless ENV["SLACK_BOT_TOKEN"].present?

    slack.chat_post_item(item)
  end

  def persist_gunky_poll!(item, gunky_response)
    return if gunky_response.blank?

    item.update!(
      slack_message_ts: gunky_response["ts"],
      slack_channel_id: gunky_response["channel"]
    )
  end

  def refresh_lost_found_message(slack, item)
    slack.update_lost_found_item_message(item)
  rescue => e
    Rails.logger.error(
      "PromoteLostFoundItemsJob: promoted item #{item.id} but failed to refresh lost+found Slack message: " \
      "#{e.class}: #{e.message}"
    )
  end

  def delete_orphan_gunky_poll(slack, gunky_response)
    return if gunky_response.blank?

    slack.delete_message(channel: gunky_response["channel"], ts: gunky_response["ts"])
  rescue => e
    Rails.logger.warn(
      "PromoteLostFoundItemsJob: failed to delete orphan Gunky Slack message " \
      "(channel=#{gunky_response['channel']}, ts=#{gunky_response['ts']}): #{e.class}: #{e.message}"
    )
  end
end
