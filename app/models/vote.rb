class Vote < ApplicationRecord
  belongs_to :item

  enum :choice, { mine: 0, foster: 1, kill: 2 }

  validates :slack_user_id, presence: true, uniqueness: { scope: :item_id }
  validates :slack_username, presence: true
  validates :choice, presence: true
end
