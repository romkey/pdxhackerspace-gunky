class PrintSetting < ApplicationRecord
  ALLOWED_PAPER_WIDTHS = [ 58, 80 ].freeze

  validates :paper_width_mm, inclusion: { in: ALLOWED_PAPER_WIDTHS }

  def self.instance
    first_or_create!
  end
end
