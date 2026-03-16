module Settings
  class SlackMemberCachesController < ApplicationController
    def index
      @cache_entries = SlackMemberCache.recent
    end

    def destroy
      cache_entry = SlackMemberCache.find(params[:id])
      cache_entry.destroy!
      redirect_to settings_slack_member_caches_path, notice: "Cache entry deleted."
    end

    def refresh_items
      updated_count = 0
      failed_count = 0
      slack_service = SlackService.new

      posted_items.find_each do |item|
        slack_service.update_item_message(item)
        updated_count += 1
      rescue => e
        failed_count += 1
        Rails.logger.error("Slack cache refresh failed for item #{item.id}: #{e.class}: #{e.message}")
      end

      message = "Refreshed #{updated_count} Slack item message#{'s' unless updated_count == 1}."
      message += " #{failed_count} failed." if failed_count.positive?
      redirect_to settings_slack_member_caches_path, notice: message
    end

    private

    def posted_items
      Item.where.not(slack_message_ts: [ nil, "" ]).where.not(slack_channel_id: [ nil, "" ])
    end
  end
end
