require "test_helper"

class SlackServiceLostFoundTest < ActiveSupport::TestCase
  setup do
    @item = items(:lost_found_unclaimed_item)
  end

  test "post_lost_found_item updates lost+found slack metadata" do
    service = SlackService.new
    client = FakeSlackClient.new(ts: "555.666", channel: "CLF")
    service.instance_variable_set(:@client, client)

    ENV["SLACK_LOST_FOUND_CHANNEL_ID"] = "CLF"
    service.post_lost_found_item(@item)
    ENV.delete("SLACK_LOST_FOUND_CHANNEL_ID")

    @item.reload
    assert_equal "555.666", @item.lost_found_slack_message_ts
    assert_equal "CLF", @item.lost_found_slack_channel_id
    assert @item.lost_found_posted_at.present?
    assert_equal 1, client.post_calls.size
    assert_equal "CLF", client.post_calls.first[:channel]
  end

  test "build_lost_found_blocks includes claim button for unclaimed item" do
    service = SlackService.new
    blocks = service.send(:build_lost_found_blocks, @item)

    action_blocks = blocks.select { |b| b[:type] == "actions" }
    assert_equal 1, action_blocks.size
    assert_equal "lost_found_claim", action_blocks.first[:elements].first[:action_id]
  end

  test "build_lost_found_blocks omits pickup button for web-claimed item" do
    item = items(:lost_found_claimed_item)
    item.update!(lost_found_claimed_by_slack_user_id: nil)

    service = SlackService.new
    blocks = service.send(:build_lost_found_blocks, item)

    action_blocks = blocks.select { |b| b[:type] == "actions" }
    assert_empty action_blocks

    context_text = blocks.find { |b| b[:type] == "context" }[:elements].first[:text]
    assert_includes context_text, "Claimed by alice"
    assert_not_includes context_text, "<@web>"
  end

  test "build_lost_found_blocks includes pickup button for claimed item" do
    item = items(:lost_found_claimed_item)
    service = SlackService.new
    blocks = service.send(:build_lost_found_blocks, item)

    action_blocks = blocks.select { |b| b[:type] == "actions" }
    assert_equal 1, action_blocks.size
    assert_equal "lost_found_picked_up:U001", action_blocks.first[:elements].first[:action_id]
  end

  test "build_item_blocks notes previously lost+found for promoted items" do
    item = items(:lost_found_promoted_item)
    service = SlackService.new
    blocks = service.send(:build_item_blocks, item)

    context_blocks = blocks.select { |b| b[:type] == "context" }
    texts = context_blocks.flat_map { |b| b[:elements].map { |e| e[:text] } }
    assert texts.any? { |t| t.include?("Previously in lost+found") }
  end

  class FakeSlackClient
    attr_reader :post_calls

    def initialize(ts: "0.0", channel: "C000")
      @ts = ts
      @channel = channel
      @post_calls = []
    end

    def chat_postMessage(**kwargs)
      @post_calls << kwargs
      { "ts" => @ts, "channel" => @channel }
    end

    def chat_update(**kwargs)
      {}
    end
  end
end
