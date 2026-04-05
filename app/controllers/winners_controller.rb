class WinnersController < ApplicationController
  def index
    vote_scope = Vote.mine.where(picked_up_at: nil).joins(:item).where(items: { disposition: Item.dispositions[:mine] })
    votes = vote_scope.includes(:item).order(:slack_username, "items.id")

    grouped = votes.group_by(&:slack_user_id)
    name_by_user = SlackMemberCache.where(slack_user_id: grouped.keys).index_by(&:slack_user_id).transform_values(&:preferred_name)

    @winner_rows = grouped.map do |slack_user_id, user_votes|
      display = name_by_user[slack_user_id] || user_votes.first.slack_username
      items_list = user_votes.map(&:item).uniq.sort_by { |i| i.display_description.to_s.downcase }
      {
        slack_user_id: slack_user_id,
        slack_username: display,
        items: items_list
      }
    end.sort_by { |r| r[:slack_username].to_s.downcase }
  end
end
