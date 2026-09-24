class Location < ApplicationRecord
  validates :name, presence: true, uniqueness: true
  validates :default_lost_found, inclusion: { in: [ true, false ] }

  before_save :clear_other_default_lost_found, if: :default_lost_found?

  scope :sorted, -> { order(:name) }

  def self.default_lost_found_location
    find_by(default_lost_found: true)
  end

  private

  def clear_other_default_lost_found
    self.class.where(default_lost_found: true).where.not(id: id).update_all(
      default_lost_found: false,
      updated_at: Time.current
    )
  end
end
