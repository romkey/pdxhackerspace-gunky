require "test_helper"

class ImageUploadNormalizerTest < ActiveSupport::TestCase
  setup do
    @jpeg_bytes = Vips::Image.black(40, 30).jpegsave_buffer
  end

  test "passes jpeg uploads through unchanged" do
    io = StringIO.new(@jpeg_bytes)

    result = ImageUploadNormalizer.normalize(
      io: io,
      filename: "photo.jpg",
      content_type: "image/jpeg"
    )

    assert_not result.converted
    assert_equal "photo.jpg", result.filename
    assert_equal "image/jpeg", result.content_type
    assert_equal @jpeg_bytes, result.io.read
  end

  test "converts heic uploads to jpeg" do
    io = StringIO.new(@jpeg_bytes)

    result = ImageUploadNormalizer.normalize(
      io: io,
      filename: "iphone.heic",
      content_type: "image/heic"
    )

    assert result.converted
    assert_equal "iphone.jpg", result.filename
    assert_equal "image/jpeg", result.content_type
    assert_operator result.io.size, :>, 0
  end

  test "detects heic by file extension when content type is missing" do
    io = StringIO.new(@jpeg_bytes)

    result = ImageUploadNormalizer.normalize(
      io: io,
      filename: "iphone.HEIC",
      content_type: ""
    )

    assert result.converted
    assert_equal "iphone.jpg", result.filename
    assert_equal "image/jpeg", result.content_type
  end
end
