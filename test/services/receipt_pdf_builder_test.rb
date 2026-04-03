require "test_helper"

class ReceiptPdfBuilderTest < ActiveSupport::TestCase
  test "render produces PDF for item" do
    pdf = ReceiptPdfBuilder.render(items: [ items(:pending_item) ], paper_width_mm: 80)
    assert pdf.start_with?("%PDF")
  end

  test "render produces multi-page PDF for multiple items" do
    pdf = ReceiptPdfBuilder.render(items: [ items(:pending_item), items(:claimed_item) ], paper_width_mm: 58)
    assert pdf.start_with?("%PDF")
    assert_operator pdf.bytesize, :>, 200
  end
end
