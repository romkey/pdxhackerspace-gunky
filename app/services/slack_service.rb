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

  private

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
