class ImageUploadNormalizer
  HEIC_CONTENT_TYPES = %w[
    image/heic
    image/heif
    image/heic-sequence
    image/heif-sequence
  ].freeze

  HEIC_EXTENSIONS = %w[.heic .heif].freeze

  Result = Struct.new(:io, :filename, :content_type, :converted, keyword_init: true)

  def self.normalize(io:, filename:, content_type: nil)
    new(io: io, filename: filename, content_type: content_type).normalize
  end

  def initialize(io:, filename:, content_type: nil)
    @io = io
    @filename = filename.to_s.presence || "upload.jpg"
    @content_type = content_type.to_s
  end

  def normalize
    unless convert?
      return Result.new(
        io: @io,
        filename: @filename,
        content_type: normalized_content_type,
        converted: false
      )
    end

    converted_io = convert_to_jpeg
    Result.new(
      io: converted_io,
      filename: jpeg_filename,
      content_type: "image/jpeg",
      converted: true
    )
  end

  private

  def convert?
    heic_content_type? || heic_extension?
  end

  def heic_content_type?
    type = @content_type.split(";").first.to_s.strip.downcase
    HEIC_CONTENT_TYPES.include?(type)
  end

  def heic_extension?
    HEIC_EXTENSIONS.include?(File.extname(@filename).downcase)
  end

  def normalized_content_type
    type = @content_type.split(";").first.to_s.strip.downcase
    type.presence || Marcel::MimeType.for(name: @filename)
  end

  def jpeg_filename
    base = File.basename(@filename, ".*")
    base = "upload" if base.blank?
    "#{base}.jpg"
  end

  def convert_to_jpeg
    @io.rewind if @io.respond_to?(:rewind)
    image = Vips::Image.new_from_buffer(@io.read, "")

    output = Tempfile.new([ "upload", ".jpg" ])
    output.binmode
    output.write(image.jpegsave_buffer(Q: 85, strip: true))
    output.rewind
    output
  end
end
