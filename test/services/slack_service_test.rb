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
    vote_text = context_block[:elements].first[:text]
    assert_includes vote_text, "Mine: Alice Display"
    assert_includes vote_text, "Foster: bob"
  end

  test "build_item_blocks includes claimed_by field when present" do
    service = SlackService.new
    blocks = service.send(:build_item_blocks, @posted_item)
    section = blocks.find { |b| b[:type] == "section" }
    claimed_field = section[:fields].find { |f| f[:text].include?("Claimed by") }
    assert_not_nil claimed_field
    assert_includes claimed_field[:text], "alice"
  end

  test "app_url_options uses APP_PROTOCOL with host-only APP_HOST" do
    service = SlackService.new
    ENV["APP_HOST"] = "gunky.example.org"
    ENV["APP_PROTOCOL"] = "https"

    options = service.send(:app_url_options)

    assert_equal "gunky.example.org", options[:host]
    assert_equal "https", options[:protocol]
  ensure
    ENV.delete("APP_HOST")
    ENV.delete("APP_PROTOCOL")
  end

  test "app_url_options supports full URL APP_HOST" do
    service = SlackService.new
    ENV["APP_HOST"] = "https://gunky.example.org:8443"
    ENV.delete("APP_PROTOCOL")

    options = service.send(:app_url_options)

    assert_equal "gunky.example.org:8443", options[:host]
    assert_equal "https", options[:protocol]
  ensure
    ENV.delete("APP_HOST")
    ENV.delete("APP_PROTOCOL")
  end

  test "build_item_blocks uses fallback text when description is blank" do
    item = Item.new(
      description: "",
      location: "Shelf A",
      expiration_date: Date.current + 7.days
    )
    item.photo.attach(
      io: StringIO.new("fake image bytes"),
      filename: "item.jpg",
      content_type: "image/jpeg"
    )
    item.save!

    service = SlackService.new
    blocks = service.send(:build_item_blocks, item)
    header_block = blocks.find { |b| b[:type] == "header" }
    image_block = blocks.find { |b| b[:type] == "image" }

    assert_not_nil header_block
    assert_not_empty header_block[:text][:text]
    assert_not_nil image_block
    assert_not_empty image_block[:alt_text]
  end

  test "replace_expired_item_message deletes original post and posts mine mentions" do
    item = Item.create!(
      description: "Vintage lamp",
      location: "Shelf B",
      expiration_date: Date.current - 1.day,
      disposition: :mine,
      slack_channel_id: "C123",
      slack_message_ts: "111.222"
    )
    item.votes.create!(slack_user_id: "U100", slack_username: "alice", choice: :mine)
    item.votes.create!(slack_user_id: "U200", slack_username: "bob", choice: :mine)

    service = SlackService.new
    client = FakeSlackClient.new(ts: "333.444", channel: "C123")
    service.instance_variable_set(:@client, client)
    ENV["APP_INTERNAL_URL"] = "https://internal.example"

    service.replace_expired_item_message(item)

    assert_equal 1, client.delete_calls.size
    assert_equal 1, client.post_calls.size
    posted_text = client.post_calls.first[:text]
    assert_includes posted_text, "<@U100>"
    assert_includes posted_text, "<@U200>"
    assert_includes posted_text, "pick this up within one week"
    assert_includes posted_text, "Please enjoy each item equally"
    assert_includes posted_text, "https://internal.example/items/#{item.id}"
    posted_blocks = client.post_calls.first[:blocks]
    assert_equal "header", posted_blocks.first[:type]
    winner_label_blocks = posted_blocks.select { |b| b[:type] == "section" && b[:text].present? && b[:text][:text].include?("Actions for:") }
    assert_equal 2, winner_label_blocks.size
    label_text = winner_label_blocks.map { |b| b[:text][:text] }.join(" ")
    assert_includes label_text, "<@U100>"
    assert_includes label_text, "<@U200>"
    actions_blocks = posted_blocks.select { |b| b[:type] == "actions" }
    assert_equal 2, actions_blocks.size
    action_ids = actions_blocks.flat_map { |b| b[:elements].map { |e| e[:action_id] } }
    assert_includes action_ids, "expired_forfeit:U100"
    assert_includes action_ids, "expired_picked_up:U100"
    assert_includes action_ids, "expired_forfeit:U200"
    assert_includes action_ids, "expired_picked_up:U200"
    context_block = posted_blocks.find { |b| b[:type] == "context" }
    assert_not_nil context_block
    assert_includes context_block[:elements].first[:text], "https://internal.example/items/#{item.id}"
  ensure
    ENV.delete("APP_INTERNAL_URL")
  end

  test "replace_expired_item_message posts foster mentions when no mine votes" do
    item = Item.create!(
      description: "Shop stool",
      location: "Workshop",
      expiration_date: Date.current - 1.day,
      disposition: :foster,
      slack_channel_id: "C123",
      slack_message_ts: "111.222"
    )
    item.votes.create!(slack_user_id: "U300", slack_username: "carol", choice: :foster)

    service = SlackService.new
    client = FakeSlackClient.new(ts: "333.444", channel: "C123")
    service.instance_variable_set(:@client, client)

    service.replace_expired_item_message(item)

    posted_text = client.post_calls.first[:text]
    assert_includes posted_text, "<@U300>"
    assert_includes posted_text, "what do you think the space should do with it?"
  end

  test "replace_expired_item_message posts trash message when no mine or foster votes" do
    item = Item.create!(
      description: "Broken fan",
      location: "Storage",
      expiration_date: Date.current - 1.day,
      disposition: :kill,
      slack_channel_id: "C123",
      slack_message_ts: "111.222"
    )
    item.votes.create!(slack_user_id: "U400", slack_username: "dave", choice: :kill)

    service = SlackService.new
    client = FakeSlackClient.new(ts: "333.444", channel: "C123")
    service.instance_variable_set(:@client, client)

    service.replace_expired_item_message(item)

    posted_text = client.post_calls.first[:text]
    assert_includes posted_text, "Please trash it."
    assert_includes posted_text, "has completed"
  end

  test "replace_expired_item_message includes photo block when item has photo" do
    item = Item.create!(
      description: "Rusty bike",
      location: "Hallway",
      expiration_date: Date.current - 1.day,
      disposition: :kill,
      slack_channel_id: "C123",
      slack_message_ts: "111.222"
    )
    item.photo.attach(
      io: StringIO.new("fake image bytes"),
      filename: "bike.jpg",
      content_type: "image/jpeg"
    )

    service = SlackService.new
    client = FakeSlackClient.new(ts: "333.444", channel: "C123")
    service.instance_variable_set(:@client, client)

    service.replace_expired_item_message(item)

    image_block = client.post_calls.first[:blocks].find { |b| b[:type] == "image" }
    assert_not_nil image_block
  end

  test "replace_expired_item_message still posts when delete fails" do
    item = Item.create!(
      description: "Heavy monitor",
      location: "Storage",
      expiration_date: Date.current - 1.day,
      disposition: :kill,
      slack_channel_id: "C123",
      slack_message_ts: "111.222"
    )

    service = SlackService.new
    client = FakeSlackClient.new(ts: "333.444", channel: "C123", delete_error: RuntimeError.new("already deleted"))
    service.instance_variable_set(:@client, client)

    service.replace_expired_item_message(item)

    assert_equal 1, client.delete_calls.size
    assert_equal 1, client.post_calls.size
    assert_equal "333.444", item.reload.slack_message_ts
  end

  class FakeSlackClient
    attr_reader :post_calls, :update_calls, :delete_calls

    def initialize(ts: "0.0", channel: "C000", delete_error: nil)
      @ts = ts
      @channel = channel
      @delete_error = delete_error
      @post_calls = []
      @update_calls = []
      @delete_calls = []
    end

    def chat_postMessage(**kwargs)
      @post_calls << kwargs
      { "ts" => @ts, "channel" => @channel }
    end

    def chat_update(**kwargs)
      @update_calls << kwargs
      {}
    end

    def chat_delete(**kwargs)
      @delete_calls << kwargs
      raise @delete_error if @delete_error

      {}
    end
  end
end
