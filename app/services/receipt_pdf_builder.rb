# frozen_string_literal: true

require "stringio"
require "prawn"

# Builds a multi-page PDF (one page per item) for CUPS / lp(1).
#
# Each page is sized to the receipt content (not a fixed very tall page). A
# narrow page that is much taller than the printer driver's default media (e.g.
# Letter) causes CUPS to scale the whole page down to fit the height, which
# shrinks the width and leaves large side margins on thermal rolls.
class ReceiptPdfBuilder
  include ItemsHelper

  # Top, right, bottom, left (PDF points)
  MARGINS = [ 8, 6, 8, 6 ].freeze
  # Scratch canvas for measuring content height (must exceed any single receipt).
  MEASURE_PAGE_HEIGHT = 50_000.0
  MIN_PAGE_HEIGHT_PT = 120

  def self.render(items:, paper_width_mm:)
    new(items, paper_width_mm).render
  end

  def initialize(items, paper_width_mm)
    @items = Array(items)
    @paper_width_mm = paper_width_mm
  end

  def render
    page_w = (@paper_width_mm * 72.0 / 25.4).round(2)
    heights = @items.map { |item| measure_receipt_page_height(page_w, item) }

    Prawn::Document.new(skip_page_creation: true, margin: MARGINS.dup) do |pdf|
      @items.each_with_index do |item, i|
        pdf.start_new_page(size: [ page_w, heights[i] ])
        render_receipt(pdf, item)
      end
    end.render
  end

  private

  def measure_receipt_page_height(page_w, item)
    dummy = Prawn::Document.new(page_size: [ page_w, MEASURE_PAGE_HEIGHT ], margin: MARGINS.dup)
    render_receipt(dummy, item)
    content_h = dummy.bounds.top - dummy.cursor
    [ (MARGINS[0] + content_h + MARGINS[2] + 4).ceil, MIN_PAGE_HEIGHT_PT ].max
  end

  def render_receipt(pdf, item)
    max_img_px = @paper_width_mm >= 80 ? 576 : 384
    usable_w = pdf.bounds.width

    pdf.font_size(18) do
      pdf.text item.display_description.to_s, align: :center, style: :bold
    end
    pdf.move_down 8

    embed_photo(pdf, item, usable_w, max_img_px)

    pdf.move_down 10
    pdf.font_size(10) do
      pdf.text "Location: #{item.location.presence || 'Not specified'}"
      pdf.move_down 4
      pdf.text "Winners / disposition", style: :bold
      receipt_disposition_lines(item).each do |line|
        pdf.text line.to_s
      end
    end

    pdf.move_down 12
    pdf.stroke_horizontal_rule
    pdf.move_down 8
    pdf.font_size(11) do
      deadline = item.pickup_deadline_date&.strftime("%B %d, %Y") || "N/A (no expiration date)"
      pdf.text "Pickup / action deadline: #{deadline}", style: :bold, align: :center
      pdf.text "(One week after item end date)", size: 8, align: :center
    end
  end

  def embed_photo(pdf, item, max_w_pts, max_px)
    if item.photo.attached?
      data = item.photo.variant(resize_to_limit: [ max_px, max_px ]).processed.download
      io = StringIO.new(data)
      io.rewind
      pdf.image io, position: :center, fit: [ max_w_pts, max_w_pts ]
    else
      pdf.text "No photo", align: :center, color: "666666"
    end
  rescue StandardError => e
    Rails.logger.warn("Receipt PDF photo skip: #{e.message}")
    pdf.text "(Photo unavailable)", align: :center, color: "666666"
  end
end
