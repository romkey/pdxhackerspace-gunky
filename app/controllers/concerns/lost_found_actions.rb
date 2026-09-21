module LostFoundActions
  extend ActiveSupport::Concern

  private

  def claim_lost_found_item!(item, name:, slack_user_id:)
    return false unless item.lost_found_unclaimed?

    pickup_days = LostFoundSetting.instance.pickup_days
    item.claim_lost_found!(name: name, slack_user_id: slack_user_id, pickup_days: pickup_days)
    refresh_lost_found_slack_message(item)
    true
  end

  def release_lost_found_item!(item)
    return false unless item.lost_found_claimed?

    item.release_lost_found_claim!
    refresh_lost_found_slack_message(item)
    true
  end

  def mark_lost_found_picked_up!(item)
    return false unless item.lost_found_claimed?

    item.mark_lost_found_picked_up!
    refresh_lost_found_slack_message(item)
    true
  end

  def promote_lost_found_item!(item)
    return false unless item.lost_found_unclaimed? || item.lost_found_claimed?

    item.promote_from_lost_found!
    refresh_lost_found_slack_message(item)
    PostToSlackJob.perform_later(item.id) if ENV["SLACK_BOT_TOKEN"].present?
    true
  end

  def refresh_lost_found_slack_message(item)
    return unless item.posted_to_lost_found_slack?

    SlackService.new.update_lost_found_item_message(item)
  rescue => e
    Rails.logger.error(
      "Failed to refresh lost+found Slack message for item #{item.id}: #{e.class}: #{e.message}"
    )
  end
end
