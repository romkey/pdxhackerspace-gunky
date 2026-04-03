# frozen_string_literal: true

require "open3"

# Submits a PDF to a CUPS queue using lp(1).
class LpPrintService
  PrintResult = Struct.new(:ok, :error_message, keyword_init: true) do
    def success?
      ok
    end
  end

  def initialize(printer:, paper_width_mm:)
    @printer = printer.to_s.strip
    @paper_width_mm = paper_width_mm
  end

  def print_items(items)
    list = Array(items)
    return PrintResult.new(ok: false, error_message: "No items to print.") if list.empty?

    pdf_bytes = ReceiptPdfBuilder.render(items: list, paper_width_mm: @paper_width_mm)
    return PrintResult.new(ok: false, error_message: "Empty PDF.") if pdf_bytes.blank?

    if Rails.env.test?
      Rails.logger.info("[LpPrintService] test: would lp -d #{@printer} (#{pdf_bytes.bytesize} bytes)")
      return PrintResult.new(ok: true)
    end

    tmp = Tempfile.new([ "gunky-receipt", ".pdf" ])
    tmp.binmode
    tmp.write(pdf_bytes)
    tmp.flush

    stdout, stderr, status = Open3.capture3("lp", "-d", @printer, tmp.path)
    tmp.close!

    if status.success?
      PrintResult.new(ok: true)
    else
      msg = [ stderr, stdout ].map(&:to_s).reject { |s| s.strip.empty? }.join(" ").presence || "lp exited #{status.exitstatus}"
      PrintResult.new(ok: false, error_message: msg)
    end
  rescue Errno::ENOENT
    PrintResult.new(ok: false, error_message: "lp command not found. Install a CUPS client (e.g. cups-client on Debian).")
  end
end
