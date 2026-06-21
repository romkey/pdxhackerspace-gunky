class DeleteFromSlackJob < ApplicationJob
  queue_as :default

  def perform(slack_channel_id, slack_message_ts)
    return if slack_channel_id.blank? || slack_message_ts.blank?

    SlackService.new.delete_message(channel: slack_channel_id, ts: slack_message_ts)
  rescue Slack::Web::Api::Errors::SlackError => e
    Rails.logger.error(
      "Failed to delete Slack message #{slack_message_ts} in #{slack_channel_id}: #{e.message}"
    )
    raise if e.message == "channel_not_found" || e.message == "not_authed"
  end
end
