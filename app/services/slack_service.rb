class SlackService
  def initialize
    @client = Slack::Web::Client.new
  end

  def post_item(item)
    summary_text = item.display_description.to_s
    blocks = build_item_blocks(item)
    response = @client.chat_postMessage(
      channel: ENV.fetch("SLACK_CHANNEL_ID"),
      text: "New item: #{summary_text.truncate(100)}",
      blocks: blocks
    )

    item.update!(
      slack_message_ts: response["ts"],
      slack_channel_id: response["channel"]
    )

    response
  end

  def update_item_message(item)
    return unless item.posted_to_slack?

    summary_text = item.display_description.to_s
    blocks = build_item_blocks(item)
    @client.chat_update(
      channel: item.slack_channel_id,
      ts: item.slack_message_ts,
      text: "Item: #{summary_text.truncate(100)}",
      blocks: blocks
    )
  end

  private

  def build_item_blocks(item)
    blocks = []
    summary_text = item.display_description.to_s

    blocks << {
      type: "header",
      text: { type: "plain_text", text: summary_text.truncate(150), emoji: true }
    }

    fields = []
    fields << { type: "mrkdwn", text: "*Location:*\n#{item.location.presence || 'Not specified'}" }
    fields << { type: "mrkdwn", text: "*Expires:*\n#{item.expiration_date&.strftime('%b %d, %Y') || 'N/A'}" }
    fields << { type: "mrkdwn", text: "*Status:*\n#{item.disposition.capitalize}" }

    if item.claimed_by.present?
      fields << { type: "mrkdwn", text: "*Claimed by:*\n#{item.claimed_by}" }
    end

    blocks << { type: "section", fields: fields }

    if item.photo.attached?
      photo_url = Rails.application.routes.url_helpers.rails_blob_url(item.photo, host: ENV.fetch("APP_HOST", "localhost:3000"))
      blocks << {
        type: "image",
        image_url: photo_url,
        alt_text: summary_text.truncate(50)
      }
    end

    vote_summary = item.vote_summary
    if vote_summary.any?
      vote_text = vote_summary.map { |choice, count| "#{choice.capitalize}: #{count}" }.join(" | ")
      blocks << {
        type: "context",
        elements: [ { type: "mrkdwn", text: "Votes: #{vote_text}" } ]
      }
    end

    if item.pending?
      blocks << {
        type: "actions",
        block_id: "vote_#{item.id}",
        elements: [
          { type: "button", text: { type: "plain_text", text: "Mine" }, action_id: "vote_mine", value: item.id.to_s, style: "primary" },
          { type: "button", text: { type: "plain_text", text: "Foster" }, action_id: "vote_foster", value: item.id.to_s },
          { type: "button", text: { type: "plain_text", text: "Kill" }, action_id: "vote_kill", value: item.id.to_s, style: "danger" }
        ]
      }
    end

    blocks
  end
end
