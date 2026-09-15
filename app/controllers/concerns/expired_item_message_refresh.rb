# Winner pickup and forfeit can happen from either the Slack buttons or the web
# UI. Both paths have to rewrite the completed-item message, otherwise Slack
# keeps offering buttons for a vote that no longer needs action and pressing one
# silently does nothing.
module ExpiredItemMessageRefresh
  extend ActiveSupport::Concern

  private

  # Failures here must not fail the caller: the vote change is already
  # committed, and Slack shows an error banner for any non-2xx interaction
  # response.
  def refresh_expired_item_message(item)
    return unless item.posted_to_slack?

    SlackService.new.update_expired_item_message(item)
  rescue => e
    Rails.logger.error(
      "Failed to refresh expired Slack message for item #{item.id}: #{e.class}: #{e.message}"
    )
  end
end
