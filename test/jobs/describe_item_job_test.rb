require "test_helper"

class DescribeItemJobTest < ActiveJob::TestCase
  setup do
    @item = Item.create!(description: "Label printer")
    @item.photo.attach(
      io: StringIO.new(Vips::Image.black(10, 10).jpegsave_buffer),
      filename: "photo.jpg",
      content_type: "image/jpeg"
    )
  end

  test "stores the AI description and enqueues the duplicate check" do
    with_described_image("A Brother label printer") do
      DescribeItemJob.perform_now(@item.id)
    end

    assert_equal "A Brother label printer", @item.reload.ai_description
    assert_enqueued_with(job: CheckDuplicatesJob, args: [ @item.id ])
  end

  test "does not enqueue the duplicate check when AI is disabled" do
    AgentSetting.instance.update!(enabled: false)

    DescribeItemJob.perform_now(@item.id)

    assert_no_enqueued_jobs(only: CheckDuplicatesJob)
  end

  test "broadcasts AI failure to the item page after retries are exhausted" do
    broadcasts = []
    capture_broadcast = proc do |*_args, **kwargs|
      broadcasts << kwargs
    end
    failing = proc { |_photo| raise OllamaService::Error, "AI endpoint read timed out" }

    with_overridden_instance_method(Item, :broadcast_replace_to, capture_broadcast) do
      with_overridden_instance_method(OllamaService, :describe_image, failing) do
        AgentSetting.instance.update!(enabled: true)
        assert_performed_jobs 3, only: DescribeItemJob do
          DescribeItemJob.perform_later(@item.id)
        end
      end
    end

    assert_equal 1, broadcasts.length
    assert_equal @item.id, broadcasts.first[:locals][:item].id
    assert_match(/timed out/, broadcasts.first[:locals][:ai_error])
  end

  private

  def with_described_image(text, &block)
    AgentSetting.instance.update!(enabled: true)
    with_overridden_instance_method(OllamaService, :describe_image, ->(_photo) { text }, &block)
  end
end
