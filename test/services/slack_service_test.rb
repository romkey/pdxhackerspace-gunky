require "test_helper"

class SlackServiceTest < ActiveSupport::TestCase
  setup do
    @item = items(:pending_item)
    @posted_item = items(:claimed_item)
  end

  test "post_item updates item with slack metadata" do
    service = SlackService.new
    client = FakeSlackClient.new(ts: "111.222", channel: "C999")
    service.instance_variable_set(:@client, client)

    ENV["SLACK_CHANNEL_ID"] = "C999"
    service.post_item(@item)
    ENV.delete("SLACK_CHANNEL_ID")

    @item.reload
    assert_equal "111.222", @item.slack_message_ts
    assert_equal "C999", @item.slack_channel_id
    assert_equal 1, client.post_calls.size
  end

  test "update_item_message calls chat_update for posted item" do
    service = SlackService.new
    client = FakeSlackClient.new
    service.instance_variable_set(:@client, client)

    service.update_item_message(@posted_item)
    assert_equal 1, client.update_calls.size
  end

  test "update_item_message does nothing for unposted item" do
    service = SlackService.new
    client = FakeSlackClient.new
    service.instance_variable_set(:@client, client)

    service.update_item_message(@item)
    assert_equal 0, client.update_calls.size
  end

  test "build_item_blocks includes header and section" do
    service = SlackService.new
    blocks = service.send(:build_item_blocks, @item)
    types = blocks.map { |b| b[:type] }
    assert_includes types, "header"
    assert_includes types, "section"
  end

  test "build_item_blocks includes action buttons for pending item" do
    service = SlackService.new
    blocks = service.send(:build_item_blocks, @item)
    actions_block = blocks.find { |b| b[:type] == "actions" }
    assert_not_nil actions_block
    action_ids = actions_block[:elements].map { |e| e[:action_id] }
    assert_equal %w[vote_mine vote_foster vote_kill], action_ids
  end

  test "build_item_blocks omits action buttons for resolved item" do
    service = SlackService.new
    blocks = service.send(:build_item_blocks, @posted_item)
    actions_block = blocks.find { |b| b[:type] == "actions" }
    assert_nil actions_block
  end

  test "build_item_blocks includes vote context when votes exist" do
    service = SlackService.new
    blocks = service.send(:build_item_blocks, @item)
    context_block = blocks.find { |b| b[:type] == "context" }
    assert_not_nil context_block
  end

  test "build_item_blocks includes claimed_by field when present" do
    service = SlackService.new
    blocks = service.send(:build_item_blocks, @posted_item)
    section = blocks.find { |b| b[:type] == "section" }
    claimed_field = section[:fields].find { |f| f[:text].include?("Claimed by") }
    assert_not_nil claimed_field
    assert_includes claimed_field[:text], "alice"
  end

  class FakeSlackClient
    attr_reader :post_calls, :update_calls

    def initialize(ts: "0.0", channel: "C000")
      @ts = ts
      @channel = channel
      @post_calls = []
      @update_calls = []
    end

    def chat_postMessage(**kwargs)
      @post_calls << kwargs
      { "ts" => @ts, "channel" => @channel }
    end

    def chat_update(**kwargs)
      @update_calls << kwargs
      {}
    end
  end
end
