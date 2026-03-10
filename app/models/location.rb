class Location < ApplicationRecord
  validates :name, presence: true, uniqueness: true

  scope :sorted, -> { order(:name) }
end
