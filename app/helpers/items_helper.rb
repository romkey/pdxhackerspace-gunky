module ItemsHelper
  INDEX_FILTER_TABS = [
    [ "Pending", "pending" ],
    [ "Want", "mine" ],
    [ "Keep", "foster" ],
    [ "Trash", "kill" ],
    [ "Owned", "owned" ]
  ].freeze

  DISPOSITION_LABELS = {
    "pending" => "Pending",
    "mine" => "Want",
    "foster" => "Keep",
    "kill" => "Trash",
    "cancelled" => "Cancelled"
  }.freeze

  DISPOSITION_BADGES = {
    "pending" => "bg-secondary",
    "mine"    => "bg-primary",
    "foster"  => "bg-info",
    "kill"    => "bg-danger",
    "cancelled" => "bg-dark"
  }.freeze

  VOTE_BADGES = {
    "mine"   => "bg-primary",
    "foster" => "bg-info",
    "kill"   => "bg-danger"
  }.freeze

  VOTE_LABELS = {
    "mine" => "I want this",
    "foster" => "Keep it for the space",
    "kill" => "Trash it"
  }.freeze

  def disposition_badge_class(disposition)
    DISPOSITION_BADGES[disposition] || "bg-secondary"
  end

  def disposition_label(disposition)
    DISPOSITION_LABELS[disposition.to_s] || disposition.to_s.capitalize
  end

  def item_disposition_label(item)
    return "Owned" if item.owned?

    disposition_label(item.disposition)
  end

  def index_filter_tabs
    INDEX_FILTER_TABS
  end

  def index_tab_active?(filter)
    params[:disposition].to_s == filter.to_s
  end

  def vote_badge_class(choice)
    VOTE_BADGES[choice] || "bg-secondary"
  end

  def vote_choice_label(choice)
    VOTE_LABELS[choice.to_s] || choice.to_s.capitalize
  end

  def pending_vote_counts_line(item)
    return unless item.pending?

    summary = item.vote_summary
    want = summary["mine"] || 0
    keep = summary["foster"] || 0
    trash = summary["kill"] || 0
    "Want: #{want} · Keep: #{keep} · Trash: #{trash}"
  end

  # Lines for thermal receipt (plain text; ERB-escaped in template).
  def receipt_disposition_lines(item)
    lines = []
    lines << "Disposition: #{item.disposition.capitalize}"

    case item.disposition
    when "mine"
      lines << "Claimed by: #{item.claimed_by}" if item.claimed_by.present?
      if item.mine_voters.any?
        names = item.mine_voters.map { |w| w[:slack_username] }.join(", ")
        lines << "Mine winners (queue): #{names}"
      end
    when "foster"
      names = item.foster_voter_usernames
      lines << "Foster interest: #{names.join(', ')}" if names.any?
    when "kill"
      names = item.kill_voter_usernames
      lines << "Kill votes: #{names.join(', ')}" if names.any?
    when "cancelled"
      if item.claimed_by.present?
        lines << "Kept by owner: #{item.claimed_by}"
      elsif item.normalized_cancellation_reason.present?
        lines << "Cancellation reason: #{item.normalized_cancellation_reason}"
      end
      lines << "No further giveaway actions."
    when "pending"
      if item.votes.any?
        %i[mine foster kill].each do |choice|
          names = item.voter_usernames_for(choice)
          next if names.empty?

          lines << "#{vote_choice_label(choice)}: #{names.join(', ')}"
        end
      else
        lines << "No votes recorded."
      end
    end

    lines
  end
end
