require "test_helper"

class CheckDuplicatesJobTest < ActiveJob::TestCase
  setup do
    @original_flag = ENV["DUPLICATE_HINTS_ENABLED"]
    ENV["DUPLICATE_HINTS_ENABLED"] = "true"
    @earlier = Item.create!(description: "Cordless power drill, DeWalt, with two batteries", created_at: 3.days.ago)
    @item = Item.create!(
      description: "Cordless power drill with batteries",
      slack_channel_id: "C0123456789",
      slack_message_ts: "1700000000.000100"
    )
    @hint_calls = []
  end

  teardown do
    ENV["DUPLICATE_HINTS_ENABLED"] = @original_flag
  end

  test "does nothing until the item is posted" do
    @item.update!(slack_message_ts: nil, slack_channel_id: nil)

    with_recorded_hints { CheckDuplicatesJob.perform_now(@item.id) }

    assert_empty @hint_calls
    assert_nil @item.reload.duplicate_checked_at
  end

  test "waits for the AI description when a photo is being described" do
    attach_photo(@item)

    with_overridden_class_method(AgentSetting, :enabled?, -> { true }) do
      with_recorded_hints { CheckDuplicatesJob.perform_now(@item.id) }
    end

    assert_empty @hint_calls
    assert_nil @item.reload.duplicate_checked_at
  end

  test "fallback run ignores the AI wait" do
    attach_photo(@item)

    with_overridden_class_method(AgentSetting, :enabled?, -> { true }) do
      with_recorded_hints { CheckDuplicatesJob.perform_now(@item.id, ignore_ai_wait: true) }
    end

    assert_equal 1, @hint_calls.size
  end

  test "replies once in the poll's thread when something matches" do
    with_recorded_hints { CheckDuplicatesJob.perform_now(@item.id) }

    assert_equal 1, @hint_calls.size
    call = @hint_calls.first
    assert_equal "C0123456789", call[:channel]
    assert_equal "1700000000.000100", call[:thread_ts]
    assert_includes call[:matches], @earlier
    assert_not_nil @item.reload.duplicate_checked_at
  end

  test "running twice replies only once" do
    with_recorded_hints do
      CheckDuplicatesJob.perform_now(@item.id)
      CheckDuplicatesJob.perform_now(@item.id)
    end

    assert_equal 1, @hint_calls.size
  end

  test "marks the item checked when nothing matches" do
    item = Item.create!(description: "Antique brass sextant", slack_channel_id: "C1", slack_message_ts: "1.2")

    with_recorded_hints { CheckDuplicatesJob.perform_now(item.id) }

    assert_empty @hint_calls
    assert_not_nil item.reload.duplicate_checked_at
  end

  test "releases the claim and raises when Slack fails" do
    failing = ->(*) { raise Slack::Web::Api::Errors::SlackError, "ratelimited" }

    with_overridden_instance_method(SlackService, :post_duplicate_hint, failing) do
      assert_raises(Slack::Web::Api::Errors::SlackError) { CheckDuplicatesJob.perform_now(@item.id) }
    end

    assert_nil @item.reload.duplicate_checked_at
  end

  test "only logs when the flag is unset" do
    ENV["DUPLICATE_HINTS_ENABLED"] = nil

    with_recorded_hints { CheckDuplicatesJob.perform_now(@item.id) }

    assert_empty @hint_calls
    assert_not_nil @item.reload.duplicate_checked_at
  end

  test "lost+found items reply in the lost+found thread and match only lost+found items" do
    lost_earlier = Item.create!(
      description: "Blue insulated water bottle with stickers",
      lost_found_state: :lost_found_unclaimed,
      created_at: 2.days.ago
    )
    gunky_earlier = Item.create!(description: "Blue insulated water bottle with stickers", created_at: 2.days.ago)
    item = Item.create!(
      description: "Insulated blue water bottle, stickers",
      lost_found_state: :lost_found_unclaimed,
      lost_found_slack_channel_id: "CLOST",
      lost_found_slack_message_ts: "1700000000.000200"
    )

    with_recorded_hints { CheckDuplicatesJob.perform_now(item.id) }

    assert_equal 1, @hint_calls.size
    call = @hint_calls.first
    assert_equal "CLOST", call[:channel]
    assert_equal "1700000000.000200", call[:thread_ts]
    assert_includes call[:matches], lost_earlier
    assert_not_includes call[:matches], gunky_earlier
  end

  test "promoted items that were already checked do not reply again" do
    @item.update!(duplicate_checked_at: 1.day.ago, lost_found_state: :lost_found_promoted)

    with_recorded_hints { CheckDuplicatesJob.perform_now(@item.id) }

    assert_empty @hint_calls
  end

  private

  def with_recorded_hints(&block)
    calls = @hint_calls
    recorder = lambda do |matches, channel:, thread_ts:|
      calls << { matches: matches, channel: channel, thread_ts: thread_ts }
    end
    with_overridden_instance_method(SlackService, :post_duplicate_hint, recorder, &block)
  end

  def attach_photo(item)
    item.photo.attach(
      io: StringIO.new(Vips::Image.black(10, 10).jpegsave_buffer),
      filename: "photo.jpg",
      content_type: "image/jpeg"
    )
  end
end
