module ItemsHelper
  DISPOSITION_BADGES = {
    "pending" => "bg-secondary",
    "mine"    => "bg-primary",
    "foster"  => "bg-info",
    "kill"    => "bg-danger"
  }.freeze

  VOTE_BADGES = {
    "mine"   => "bg-primary",
    "foster" => "bg-info",
    "kill"   => "bg-danger"
  }.freeze

  def disposition_badge_class(disposition)
    DISPOSITION_BADGES[disposition] || "bg-secondary"
  end

  def vote_badge_class(choice)
    VOTE_BADGES[choice] || "bg-secondary"
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
    when "pending"
      if item.votes.any?
        %i[mine foster kill].each do |choice|
          names = item.voter_usernames_for(choice)
          next if names.empty?

          lines << "#{choice.to_s.capitalize}: #{names.join(', ')}"
        end
      else
        lines << "No votes recorded."
      end
    end

    lines
  end
end
