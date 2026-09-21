class LostFoundSetting < ApplicationRecord
  HOLD_DAYS_RANGE = (1..365).freeze
  PICKUP_DAYS_RANGE = (1..90).freeze

  validates :hold_days, numericality: { only_integer: true, in: HOLD_DAYS_RANGE }
  validates :pickup_days, numericality: { only_integer: true, in: PICKUP_DAYS_RANGE }

  def self.instance
    first_or_create!
  end
end
