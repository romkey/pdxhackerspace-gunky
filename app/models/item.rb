class Item < ApplicationRecord
  has_many :votes, dependent: :destroy
  has_one_attached :photo

  enum :disposition, { pending: 0, mine: 1, foster: 2, kill: 3 }

  validate :description_or_photo_present

  def display_description
    description.presence || ai_description.presence || "Awaiting AI description..."
  end

  before_create :set_default_expiration

  scope :expired_without_votes, -> {
    pending
      .where(expiration_date: ...Date.current)
      .left_joins(:votes)
      .where(votes: { id: nil })
  }

  scope :expired_with_votes, -> {
    pending
      .where(expiration_date: ...Date.current)
      .joins(:votes)
      .distinct
  }

  def vote_summary
    votes.group(:choice).count
  end

  def mine_voter_usernames
    unique_voter_usernames_for(:mine)
  end

  def mine_voter_user_ids
    unique_voter_user_ids_for(:mine)
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

  def posted_to_slack?
    slack_message_ts.present?
  end

  private

  def unique_voter_usernames_for(choice)
    seen_user_ids = {}
    votes.public_send(choice).order(:updated_at, :id).each_with_object([]) do |vote, usernames|
      next if seen_user_ids[vote.slack_user_id]

      seen_user_ids[vote.slack_user_id] = true
      usernames << vote.slack_username
    end
  end

  def unique_voter_user_ids_for(choice)
    seen_user_ids = {}
    votes.public_send(choice).order(:updated_at, :id).each_with_object([]) do |vote, user_ids|
      next if seen_user_ids[vote.slack_user_id]

      seen_user_ids[vote.slack_user_id] = true
      user_ids << vote.slack_user_id
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
