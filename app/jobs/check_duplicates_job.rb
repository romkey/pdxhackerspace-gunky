class CheckDuplicatesJob < ApplicationJob
  queue_as :default

  AI_DESCRIPTION_FALLBACK_WAIT = 10.minutes

  def self.enabled?
    ENV["DUPLICATE_HINTS_ENABLED"].present?
  end

  def perform(item_id, ignore_ai_wait: false)
    item = Item.find_by(id: item_id)
    return unless item

    channel, thread_ts = thread_target(item)
    return if thread_ts.blank?
    return if !ignore_ai_wait && awaiting_ai_description?(item)
    return unless claim(item)

    begin
      check(item, channel: channel, thread_ts: thread_ts)
    rescue
      release(item)
      raise
    end
  end

  private

  def thread_target(item)
    if item.in_lost_found? && item.posted_to_lost_found_slack?
      [ item.lost_found_slack_channel_id, item.lost_found_slack_message_ts ]
    elsif !item.in_lost_found? && item.posted_to_slack?
      [ item.slack_channel_id, item.slack_message_ts ]
    end
  end

  def awaiting_ai_description?(item)
    item.photo.attached? && item.ai_description.blank? && AgentSetting.enabled?
  end

  # Conditional UPDATE so two concurrent runs cannot both reply.
  def claim(item)
    Item.where(id: item.id, duplicate_checked_at: nil).update_all(duplicate_checked_at: Time.current).positive?
  end

  def release(item)
    Item.where(id: item.id).update_all(duplicate_checked_at: nil)
  end

  def check(item, channel:, thread_ts:)
    matches = DuplicateFinder.new(item).matches
    return if matches.empty?

    unless self.class.enabled?
      Rails.logger.info("CheckDuplicatesJob: would reply to item #{item.id} with #{describe(matches)}")
      return
    end

    Rails.logger.info("CheckDuplicatesJob: replying to item #{item.id} with #{describe(matches)}")
    SlackService.new.post_duplicate_hint(matches.map(&:item), channel: channel, thread_ts: thread_ts)
  end

  def describe(matches)
    matches.map do |match|
      "##{match.item.id} (rank #{match.rank.round(3)}, shared: #{match.shared_lexemes.join(' ')})"
    end.join(", ")
  end
end
