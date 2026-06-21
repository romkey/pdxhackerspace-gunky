require "test_helper"

class ItemPhotoVariantTest < ActiveSupport::TestCase
  test "photo variant processes with ruby-vips" do
    jpeg = Vips::Image.black(40, 30).jpegsave_buffer

    item = Item.create!(description: "Variant regression")
    item.photo.attach(
      io: StringIO.new(jpeg),
      filename: "sample.jpg",
      content_type: "image/jpeg"
    )

    processed = item.photo.variant(resize_to_fill: [ 400, 300 ]).processed

    assert_operator processed.download.size, :>, 0
  end
end
