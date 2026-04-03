class PrintSetting < ApplicationRecord
  ALLOWED_PAPER_WIDTHS = [ 58, 80 ].freeze
  # Safe subset of CUPS queue names (lp -d); avoids shell metacharacters.
  CUPS_QUEUE_FORMAT = /\A[\w.@+-]+\z/

  validates :paper_width_mm, inclusion: { in: ALLOWED_PAPER_WIDTHS }
  validates :cups_queue,
            format: { with: CUPS_QUEUE_FORMAT, message: "may only contain letters, digits, and . _ @ + -" },
            allow_blank: true

  def self.instance
    first_or_create!
  end
end
