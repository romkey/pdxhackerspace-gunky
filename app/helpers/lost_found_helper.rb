module LostFoundHelper
  LOST_FOUND_FILTER_TABS = [
    [ "Unclaimed", "unclaimed" ],
    [ "Awaiting pickup", "awaiting_pickup" ],
    [ "Picked up", "picked_up" ],
    [ "Promoted to Gunky", "promoted" ]
  ].freeze

  LOST_FOUND_STATE_BADGES = {
    "lost_found_unclaimed" => "bg-secondary",
    "lost_found_claimed" => "bg-primary",
    "lost_found_picked_up" => "bg-success",
    "lost_found_promoted" => "bg-info"
  }.freeze

  LOST_FOUND_STATE_LABELS = {
    "lost_found_unclaimed" => "Unclaimed",
    "lost_found_claimed" => "Awaiting pickup",
    "lost_found_picked_up" => "Picked up",
    "lost_found_promoted" => "Promoted to Gunky"
  }.freeze

  def lost_found_filter_tabs
    LOST_FOUND_FILTER_TABS
  end

  def lost_found_nav_active?(filter)
    disposition = params[:disposition].to_s
    filter = filter.to_s
    return disposition.in?(%w[awaiting_pickup claimed]) if filter == "awaiting_pickup"

    disposition == filter
  end

  def lost_found_state_badge_class(item)
    LOST_FOUND_STATE_BADGES[item.lost_found_state] || "bg-secondary"
  end

  def lost_found_state_label(item)
    LOST_FOUND_STATE_LABELS[item.lost_found_state] || item.lost_found_state.humanize
  end

  def lost_found_hold_line(item)
    return unless item.lost_found_hold_until.present?

    "Unclaimed until #{item.lost_found_hold_until.strftime('%b %d, %Y')}"
  end

  def lost_found_pickup_deadline_line(item)
    deadline = item.lost_found_pickup_deadline
    return "No pickup deadline" if deadline.blank?

    if item.lost_found_pickup_overdue?
      days = (Date.current - deadline).to_i
      "Due #{deadline.strftime('%b %d, %Y')} - #{pluralize(days, 'day')} overdue"
    else
      "Pick up by #{deadline.strftime('%b %d, %Y')}"
    end
  end
end
