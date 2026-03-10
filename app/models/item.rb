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

  def expired?
    expiration_date.present? && expiration_date <= Date.current
  end

  def posted_to_slack?
    slack_message_ts.present?
  end

  private

  def set_default_expiration
    self.expiration_date ||= 7.days.from_now.to_date
  end

  def description_or_photo_present
    if description.blank? && !photo.attached?
      errors.add(:description, "is required when no photo is provided")
    end
  end
end
