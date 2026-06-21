class SlackService
  def initialize
    @client = Slack::Web::Client.new
  end

  def post_item(item)
    summary_text = item.display_description.to_s
    blocks = build_item_blocks(item)
    payload = {
      channel: ENV.fetch("SLACK_CHANNEL_ID"),
      text: "New item: #{summary_text.truncate(100)}",
      blocks: blocks
    }
    log_payload("chat_postMessage", payload)
    response = @client.chat_postMessage(**payload)

    item.update!(
      slack_message_ts: response["ts"],
      slack_channel_id: response["channel"]
    )

    response
  end

  def update_item_message(item)
    return unless item.pending?
    return unless item.posted_to_slack?

    summary_text = item.display_description.to_s
    blocks = build_item_blocks(item)
    payload = {
      channel: item.slack_channel_id,
      ts: item.slack_message_ts,
      text: "Item: #{summary_text.truncate(100)}",
      blocks: blocks
    }
    log_payload("chat_update", payload)
    @client.chat_update(**payload)
  end

  def cancel_item_message(item)
    return unless item.cancelled?
    return unless item.posted_to_slack?

    summary_text = item.display_description.to_s
    blocks = build_item_blocks(item)
    payload = {
      channel: item.slack_channel_id,
      ts: item.slack_message_ts,
      text: "Item unavailable: #{summary_text.truncate(100)}",
      blocks: blocks
    }
    log_payload("chat_update_cancelled", payload)
    @client.chat_update(**payload)
  end

  def replace_expired_item_message(item)
    if item.posted_to_slack?
      begin
        delete_item_message(item)
      rescue => e
        Rails.logger.warn(
          "SlackService replace_expired_item_message delete failed for item #{item.id}: #{e.class}: #{e.message}"
        )
      end
    end

    post_expired_item_message(item)
  end

  def delete_item_message(item)
    return unless item.posted_to_slack?

    delete_message(channel: item.slack_channel_id, ts: item.slack_message_ts)
  end

  def delete_message(channel:, ts:)
    return if channel.blank? || ts.blank?

    payload = { channel: channel, ts: ts }
    log_payload("chat_delete", payload)
    @client.chat_delete(**payload)
  end

  private

  def cancelled_item_message(item)
    if item.claimed_by.present?
      return ":no_entry_sign: Unavailable - owned by #{item.claimed_by}. Giveaway halted."
    end

    message = ":no_entry_sign: Giveaway cancelled."
    reason = item.normalized_cancellation_reason
    message += " Reason: #{reason}" if reason.present?
    message
  end

  # Slack header plain_text must be <= 150 characters.
  def expired_item_header_plain_text(item)
    "\"#{item.display_description}\" has completed".truncate(150, omission: "…")
  end

  def post_expired_item_message(item)
    channel = item.slack_channel_id.presence || ENV.fetch("SLACK_CHANNEL_ID")
    text = expired_item_text(item)
    want_image = item.photo.attached?

    response =
      begin
        chat_post_expired(channel, text, expired_item_blocks(item, include_image: want_image))
      rescue Slack::Web::Api::Errors::SlackError => e
        raise unless want_image && slack_error_may_be_image_block?(e)

        Rails.logger.warn(
          "SlackService post_expired_item_message retry without image for item #{item.id}: #{e.class}: #{e.message}"
        )
        chat_post_expired(channel, text, expired_item_blocks(item, include_image: false))
      end

    item.update!(
      slack_message_ts: response["ts"],
      slack_channel_id: response["channel"]
    )
  end

  def chat_post_expired(channel, text, blocks)
    payload = { channel: channel, text: text, blocks: blocks }
    log_payload("chat_postMessage_expired", payload)
    @client.chat_postMessage(**payload)
  end

  def slack_error_may_be_image_block?(error)
    msg = "#{error.class} #{error.message}".downcase
    msg.include?("invalid_blocks") ||
      msg.include?("image") ||
      msg.include?("download") ||
      msg.include?("must_be")
  end

  def expired_item_text(item)
    mine_mentions = mentions_for(item.mine_voter_user_ids_pending_pickup)
    foster_mentions = mentions_for(item.foster_voter_user_ids)
    item_label = item.display_description.to_s.truncate(100)
    link_suffix = expired_item_link_suffix(item)

    if mine_mentions.present?
      "\"#{item_label}\" has completed. #{mine_mentions} please pick this up within one week. If you cannot, let the next person know it's theirs. Please enjoy each item equally#{link_suffix}"
    elsif item.mine? && item.votes.mine.exists? && item.votes.mine.where(picked_up_at: nil).none?
      "\"#{item_label}\" has completed. All mine winners have picked up.#{link_suffix}"
    elsif foster_mentions.present?
      "\"#{item_label}\" has completed. #{foster_mentions} what do you think the space should do with it?#{link_suffix}"
    else
      "\"#{item_label}\" has completed. Please trash it.#{link_suffix}"
    end
  end

  def expired_item_blocks(item, include_image: true)
    blocks = [
      {
        type: "header",
        text: { type: "plain_text", text: expired_item_header_plain_text(item), emoji: true }
      },
      {
        type: "section",
        text: { type: "mrkdwn", text: expired_item_text(item) }
      }
    ]

    if include_image && item.photo.attached?
      blocks << {
        type: "image",
        image_url: Rails.application.routes.url_helpers.rails_blob_url(item.photo, **app_url_options),
        alt_text: item.display_description.to_s.truncate(50)
      }
    end

    item.mine_voters_pending_pickup.each do |winner|
      user_id = winner[:slack_user_id]
      username = winner[:slack_username]

      blocks << {
        type: "section",
        text: { type: "mrkdwn", text: "*Actions for:* <@#{user_id}> (#{username})" }
      }

      blocks << {
        type: "actions",
        block_id: "expired_actions_#{item.id}_#{user_id}",
        elements: [
          {
            type: "button",
            text: { type: "plain_text", text: "Forfeit" },
            action_id: "expired_forfeit:#{user_id}",
            value: item.id.to_s,
            style: "danger"
          },
          {
            type: "button",
            text: { type: "plain_text", text: "Picked up" },
            action_id: "expired_picked_up:#{user_id}",
            value: item.id.to_s,
            style: "primary"
          }
        ]
      }
    end

    internal_url = item_internal_url(item)
    if internal_url.present?
      link_text = item_internal_link_markdown(item)
      blocks << {
        type: "context",
        elements: [ { type: "mrkdwn", text: link_text } ]
      }
    end

    blocks
  end

  def mentions_for(user_ids)
    user_ids.map { |user_id| "<@#{user_id}>" }.join(" ")
  end

  def item_internal_url(item)
    base = ENV["APP_INTERNAL_URL"].to_s.strip
    return nil if base.blank?

    "#{base.chomp('/')}/items/#{item.id}"
  end

  def item_internal_link_markdown(item)
    url = item_internal_url(item)
    return nil if url.blank?

    "<#{url}|View on Gunky> (only usable from CTRLH's network)"
  end

  def expired_item_link_suffix(item)
    internal_url = item_internal_url(item)
    return "" if internal_url.blank?

    " View item: #{internal_url}"
  end

  def log_payload(action, payload)
    Rails.logger.info(
      "SlackService #{action} payload: #{sanitized_payload_for_log(payload).to_json}"
    )
  end

  def sanitized_payload_for_log(payload)
    deep_transform(payload) do |key, value|
      next value unless key == "image_url" && value.is_a?(String)
      redact_image_url(value)
    end
  end

  def redact_image_url(value)
    uri = URI.parse(value)
    safe_url = +"#{uri.scheme}://#{uri.host}"
    safe_url << ":#{uri.port}" if uri.port && ![ 80, 443 ].include?(uri.port)
    safe_url << uri.path.to_s
    safe_url << "?[REDACTED_QUERY]" if uri.query.present?
    safe_url << "#[REDACTED_FRAGMENT]" if uri.fragment.present?
    safe_url
  rescue URI::InvalidURIError
    "[REDACTED_IMAGE_URL]"
  end

  def deep_transform(value, key = nil, &block)
    case value
    when Hash
      value.each_with_object({}) do |(k, v), memo|
        normalized_key = k.to_s
        memo[k] = deep_transform(v, normalized_key, &block)
      end
    when Array
      value.map { |entry| deep_transform(entry, key, &block) }
    else
      block.call(key, value)
    end
  end

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
      photo_url = Rails.application.routes.url_helpers.rails_blob_url(item.photo, **app_url_options)
      blocks << {
        type: "image",
        image_url: photo_url,
        alt_text: summary_text.truncate(50)
      }
    end

    vote_parts = []
    mine_voters = item.mine_voter_usernames
    foster_voters = item.foster_voter_usernames
    vote_parts << "I want this: #{mine_voters.join(', ')}" if mine_voters.any?
    vote_parts << "Keep it for the space: #{foster_voters.join(', ')}" if foster_voters.any?
    vote_parts << "Trash it: #{item.kill_vote_count}" if item.kill_vote_count.positive?

    if vote_parts.any?
      blocks << {
        type: "context",
        elements: [ { type: "mrkdwn", text: "Votes: #{vote_parts.join(' | ')}" } ]
      }
    end

    if item.cancelled?
      blocks << {
        type: "context",
        elements: [ { type: "mrkdwn", text: cancelled_item_message(item) } ]
      }
    end

    link_text = item_internal_link_markdown(item)
    if link_text.present?
      blocks << {
        type: "context",
        elements: [ { type: "mrkdwn", text: link_text } ]
      }
    end

    if item.pending?
      blocks << {
        type: "actions",
        block_id: "vote_#{item.id}",
        elements: [
          { type: "button", text: { type: "plain_text", text: "I want this" }, action_id: "vote_mine", value: item.id.to_s, style: "primary" },
          { type: "button", text: { type: "plain_text", text: "Keep it for the space" }, action_id: "vote_foster", value: item.id.to_s },
          { type: "button", text: { type: "plain_text", text: "Trash it" }, action_id: "vote_kill", value: item.id.to_s, style: "danger" },
          { type: "button", text: { type: "plain_text", text: "I own this" }, action_id: "keep_item", value: item.id.to_s }
        ]
      }
    end

    blocks
  end

  def app_url_options
    app_host = ENV.fetch("APP_HOST", "localhost:3000").to_s.strip
    parsed = parse_app_host(app_host)

    {
      host: parsed[:host],
      protocol: ENV["APP_PROTOCOL"].presence || parsed[:protocol] || default_protocol
    }
  end

  def parse_app_host(app_host)
    return { host: app_host, protocol: nil } unless app_host.match?(/\Ahttps?:\/\//i)

    uri = URI.parse(app_host)
    host = +"#{uri.host}"
    host << ":#{uri.port}" if uri.port && ![ 80, 443 ].include?(uri.port)

    { host: host, protocol: uri.scheme }
  rescue URI::InvalidURIError
    { host: app_host, protocol: nil }
  end

  def default_protocol
    Rails.env.production? ? "https" : "http"
  end
end
