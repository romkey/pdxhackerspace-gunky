class SlackMemberCacheService
  def initialize(client: nil)
    @lookup_token = lookup_token
    @injected_client = client.present?
    @client = client || Slack::Web::Client.new(token: @lookup_token)
  end

  def resolve_name(slack_user_id, fallback_username: nil)
    cache_entry = SlackMemberCache.find_by(slack_user_id: slack_user_id)
    if cache_entry.present? && (cache_entry.display_name.present? || cache_entry.real_name.present?)
      return cache_entry.preferred_name
    end

    refresh_name(slack_user_id, fallback_username: fallback_username)
  end

  def refresh_name(slack_user_id, fallback_username: nil)
    user = fetch_user(slack_user_id)
    display_name = user&.dig("profile", "display_name_normalized").presence ||
      user&.dig("profile", "display_name").presence
    real_name = user&.dig("profile", "real_name_normalized").presence ||
      user&.dig("profile", "real_name").presence ||
      user&.dig("real_name").presence
    real_name ||= fallback_username

    cache_entry = SlackMemberCache.find_or_initialize_by(slack_user_id: slack_user_id)
    cache_entry.display_name = display_name
    cache_entry.real_name = real_name
    cache_entry.save! if cache_entry.changed?

    cache_entry.preferred_name.presence || fallback_username.presence || slack_user_id
  rescue => e
    Rails.logger.warn(
      "SlackMemberCacheService lookup failed for user #{slack_user_id}: #{e.class}: #{e.message}"
    )
    fallback_username.presence || slack_user_id
  end

  private

  def fetch_user(slack_user_id)
    return nil if @lookup_token.blank? && !@injected_client

    @client.users_info(user: slack_user_id)["user"]
  end

  def lookup_token
    ENV["SLACK_USER_LOOKUP_TOKEN"].presence || ENV["SLACK_BOT_TOKEN"].presence
  end
end
