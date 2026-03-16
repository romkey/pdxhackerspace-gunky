class SlackMemberCache < ApplicationRecord
  validates :slack_user_id, presence: true, uniqueness: true

  scope :recent, -> { order(updated_at: :desc) }

  def preferred_name
    display_name.presence || real_name.presence || slack_user_id
  end
end
