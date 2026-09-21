class Item < ApplicationRecord
  has_many :votes, dependent: :destroy
  has_one_attached :photo

  enum :disposition, { pending: 0, mine: 1, foster: 2, kill: 3, cancelled: 4 }
  enum :lost_found_state, {
    not_lost_found: 0,
    lost_found_unclaimed: 1,
    lost_found_claimed: 2,
    lost_found_picked_up: 3,
    lost_found_promoted: 4
  }

  validate :description_or_photo_present

  def display_description
    description.presence || ai_description.presence || "Awaiting AI description..."
  end

  before_create :set_default_expiration

  scope :gunky_visible, -> {
    where(lost_found_state: [ lost_found_states[:not_lost_found], lost_found_states[:lost_found_promoted] ])
  }

  scope :lost_found_visible, -> {
    where(lost_found_state: [
      lost_found_states[:lost_found_unclaimed],
      lost_found_states[:lost_found_claimed],
      lost_found_states[:lost_found_picked_up],
      lost_found_states[:lost_found_promoted]
    ])
  }

  scope :lost_found_active, -> {
    where(lost_found_state: [
      lost_found_states[:lost_found_unclaimed],
      lost_found_states[:lost_found_claimed],
      lost_found_states[:lost_found_picked_up]
    ])
  }

  scope :lost_found_hold_elapsed, -> {
    lost_found_unclaimed.where(lost_found_hold_until: ..Date.current)
  }

  scope :lost_found_pickup_elapsed, -> {
    lost_found_claimed.where(lost_found_pickup_deadline: ..Date.current)
  }

  scope :expired_without_votes, -> {
    gunky_visible.pending
      .where(expiration_date: ..Date.current)
      .left_joins(:votes)
      .where(votes: { id: nil })
  }

  scope :expired_with_votes, -> {
    gunky_visible.pending
      .where(expiration_date: ..Date.current)
      .joins(:votes)
      .distinct
  }

  scope :killed_not_disposed, -> { gunky_visible.kill.where(disposed_at: nil) }
  scope :killed_disposed, -> { gunky_visible.kill.where.not(disposed_at: nil) }
  scope :owned, -> { gunky_visible.cancelled.where.not(claimed_by: [ nil, "" ]) }
  scope :giveaway_cancelled, -> { gunky_visible.cancelled.where(claimed_by: [ nil, "" ]) }
  scope :gunky_completed, -> { gunky_visible.where.not(disposition: :pending) }

  # A "mine" item is awaiting pickup while any winner still has an outstanding
  # vote, and picked up once every winner has collected.
  scope :awaiting_pickup, -> {
    gunky_visible.mine.where(id: Vote.mine.where(picked_up_at: nil).select(:item_id))
  }
  scope :picked_up, -> {
    gunky_visible.mine.where(id: Vote.mine.select(:item_id))
        .where.not(id: Vote.mine.where(picked_up_at: nil).select(:item_id))
  }

  SEARCH_COLUMNS = %w[description ai_description location claimed_by cancellation_reason lost_found_claimed_by].freeze

  # Every whitespace-separated term must match somewhere: an item text column or
  # a voter's Slack name. A bare number (optionally "#42") also matches the id.
  def self.search(query)
    terms = query.to_s.split
    return all if terms.empty?

    terms.reduce(all) do |scope, term|
      pattern = "%#{sanitize_sql_like(term)}%"
      voted_item_ids = Vote.where(Vote.arel_table[:slack_username].matches(pattern)).select(:item_id)

      conditions = SEARCH_COLUMNS.map { |column| arel_table[column].matches(pattern) }
      conditions << arel_table[:id].in(voted_item_ids.arel)
      id = term.delete_prefix("#")
      conditions << arel_table[:id].eq(id.to_i) if id.match?(/\A\d{1,18}\z/)

      scope.where(conditions.reduce(:or))
    end
  end

  def self.gunky_stats
    {
      total: gunky_completed.count,
      new_homes: gunky_visible.mine.count,
      picked_up: picked_up.count,
      awaiting_pickup: awaiting_pickup.count,
      kept_for_space: gunky_visible.foster.count,
      trashed: gunky_visible.kill.count,
      owners_found: owned.count,
      cancelled: giveaway_cancelled.count
    }
  end

  def self.lost_found_stats
    {
      unclaimed: lost_found_unclaimed.count,
      awaiting_pickup: lost_found_claimed.count,
      picked_up: lost_found_picked_up.count,
      promoted: lost_found_promoted.count
    }
  end

  def in_lost_found?
    lost_found_unclaimed? || lost_found_claimed? || lost_found_picked_up?
  end

  def was_lost_found?
    !not_lost_found?
  end

  def lost_found_pickup_overdue?
    lost_found_claimed? &&
      lost_found_pickup_deadline.present? &&
      lost_found_pickup_deadline < Date.current
  end

  def posted_to_lost_found_slack?
    lost_found_slack_message_ts.present?
  end

  def start_lost_found!(hold_days:)
    hold_until = hold_days.days.from_now.to_date
    assign_attributes(
      lost_found_state: :lost_found_unclaimed,
      lost_found_hold_until: hold_until,
      expiration_date: hold_until
    )
    save! if persisted?
  end

  def claim_lost_found!(name:, slack_user_id: nil, pickup_days:)
    pickup_deadline = pickup_days.days.from_now.to_date
    update!(
      lost_found_state: :lost_found_claimed,
      lost_found_claimed_by: name,
      lost_found_claimed_by_slack_user_id: slack_user_id.presence,
      lost_found_claimed_at: Time.current,
      lost_found_pickup_deadline: pickup_deadline
    )
  end

  def release_lost_found_claim!
    update!(
      lost_found_state: :lost_found_unclaimed,
      lost_found_claimed_by: nil,
      lost_found_claimed_by_slack_user_id: nil,
      lost_found_claimed_at: nil,
      lost_found_pickup_deadline: nil
    )
  end

  def mark_lost_found_picked_up!
    update!(
      lost_found_state: :lost_found_picked_up,
      lost_found_picked_up_at: Time.current
    )
  end

  def promote_from_lost_found!
    update!(
      lost_found_state: :lost_found_promoted,
      lost_found_promoted_at: Time.current,
      expiration_date: 7.days.from_now.to_date
    )
  end

  def owned?
    cancelled? && claimed_by.present?
  end

  def giveaway_cancelled?
    cancelled? && claimed_by.blank?
  end

  def normalized_cancellation_reason
    cancellation_reason.to_s.strip.presence
  end

  def disown!
    update!(disposition: :pending, claimed_by: nil, cancellation_reason: nil)
  end

  def vote_summary
    votes.group(:choice).count
  end

  def mine_voter_usernames
    unique_voter_usernames_for(:mine)
  end

  def mine_voter_user_ids
    unique_voter_user_ids_for(:mine)
  end

  def mine_voters
    unique_mine_winner_hashes(votes.mine)
  end

  def mine_voters_pending_pickup
    unique_mine_winner_hashes(votes.mine.where(picked_up_at: nil))
  end

  def mine_voter_user_ids_pending_pickup
    mine_voters_pending_pickup.map { |w| w[:slack_user_id] }
  end

  def mine_voters_picked_up
    unique_mine_winner_hashes(votes.mine.where.not(picked_up_at: nil))
  end

  def awaiting_pickup?
    mine? && votes.mine.where(picked_up_at: nil).exists?
  end

  def picked_up?
    mine? && votes.mine.exists? && !votes.mine.where(picked_up_at: nil).exists?
  end

  # Most recent collection, which is when the item as a whole became picked up.
  def last_picked_up_at
    votes.mine.maximum(:picked_up_at)
  end

  def foster_voter_usernames
    unique_voter_usernames_for(:foster)
  end

  def foster_voter_user_ids
    unique_voter_user_ids_for(:foster)
  end

  def kill_voter_usernames
    unique_voter_usernames_for(:kill)
  end

  def voter_usernames_for(choice)
    unique_voter_usernames_for(choice)
  end

  def foster_vote_count
    votes.foster.count
  end

  def kill_vote_count
    votes.kill.count
  end

  def resolve_from_votes!
    mine_vote = votes.mine.order(:updated_at, :id).first
    if mine_vote
      update!(disposition: :mine, claimed_by: mine_vote.slack_username)
      return
    end

    disposition_to_set = foster_vote_count.positive? ? :foster : :kill
    update!(disposition: disposition_to_set, claimed_by: nil)
  end

  def expired?
    expiration_date.present? && expiration_date <= Date.current
  end

  def completed?
    !pending?
  end

  def disposed?
    disposed_at.present?
  end

  def dispose!
    update!(disposed_at: Time.current)
  end

  def pickup_deadline_date
    return nil if expiration_date.blank?

    expiration_date + 7.days
  end

  def posted_to_slack?
    slack_message_ts.present?
  end

  private

  def unique_voter_usernames_for(choice)
    unique_votes = unique_votes_for_choice(choice)
    names_by_id = cached_names_by_slack_user_id(unique_votes.map(&:slack_user_id))

    unique_votes.map do |vote|
      names_by_id[vote.slack_user_id] || vote.slack_username
    end
  end

  def unique_voter_user_ids_for(choice)
    unique_votes_for_choice(choice).map(&:slack_user_id)
  end

  def unique_votes_for_choice(choice)
    seen_user_ids = {}
    votes.public_send(choice).order(:updated_at, :id).each_with_object([]) do |vote, unique_votes|
      next if seen_user_ids[vote.slack_user_id]

      seen_user_ids[vote.slack_user_id] = true
      unique_votes << vote
    end
  end

  def cached_names_by_slack_user_id(slack_user_ids)
    return {} if slack_user_ids.empty?

    SlackMemberCache.where(slack_user_id: slack_user_ids).each_with_object({}) do |entry, names|
      names[entry.slack_user_id] = entry.preferred_name
    end
  end

  def unique_mine_winner_hashes(votes_scope)
    seen_user_ids = {}
    unique_votes = votes_scope.order(:updated_at, :id).each_with_object([]) do |vote, acc|
      next if seen_user_ids[vote.slack_user_id]

      seen_user_ids[vote.slack_user_id] = true
      acc << vote
    end
    names_by_id = cached_names_by_slack_user_id(unique_votes.map(&:slack_user_id))

    unique_votes.map do |vote|
      {
        slack_user_id: vote.slack_user_id,
        slack_username: names_by_id[vote.slack_user_id] || vote.slack_username,
        claimed_at: vote.created_at,
        picked_up_at: vote.picked_up_at
      }
    end
  end

  def set_default_expiration
    self.expiration_date ||= 7.days.from_now.to_date
  end

  def description_or_photo_present
    return if description.present?
    return if photo.attached?
    return if attachment_changes["photo"].present?

    errors.add(:description, "is required when no photo is provided")
  end
end
