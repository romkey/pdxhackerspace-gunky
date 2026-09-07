class WinnersController < ApplicationController
  def index
    vote_scope = Vote.mine.where(picked_up_at: nil).joins(:item).where(items: { disposition: Item.dispositions[:mine] })
    votes = vote_scope.includes(:item).order(:slack_username, "items.id")

    grouped = votes.group_by(&:slack_user_id)
    name_by_user = SlackMemberCache.where(slack_user_id: grouped.keys).index_by(&:slack_user_id).transform_values(&:preferred_name)

    @winner_rows = grouped.map do |slack_user_id, user_votes|
      display = name_by_user[slack_user_id] || user_votes.first.slack_username
      # Sort the most overdue first: these are the pickups that need chasing.
      entries = user_votes.uniq(&:item_id).map { |vote| { item: vote.item, claimed_at: vote.created_at } }
      entries.sort_by! { |e| [ e[:item].pickup_deadline_date || Date::Infinity.new, e[:item].display_description.to_s.downcase ] }

      {
        slack_user_id: slack_user_id,
        slack_username: display,
        entries: entries,
        overdue_count: entries.count { |e| e[:item].pickup_deadline_date.present? && e[:item].pickup_deadline_date < Date.current }
      }
    end.sort_by { |r| [ -r[:overdue_count], r[:slack_username].to_s.downcase ] }
  end
end
