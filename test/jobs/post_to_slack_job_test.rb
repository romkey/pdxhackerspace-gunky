require "test_helper"

class PostToSlackJobTest < ActiveJob::TestCase
  test "calls SlackService for the item" do
    item = items(:pending_item)
    called_with = nil

    SlackService.define_method(:post_item) { |i| called_with = i }
    PostToSlackJob.perform_now(item.id)
    assert_equal item, called_with
  ensure
    SlackService.remove_method(:post_item)
    load Rails.root.join("app/services/slack_service.rb")
  end

  test "does nothing when item does not exist" do
    assert_nothing_raised do
      PostToSlackJob.perform_now(0)
    end
  end

  test "logs and swallows non-critical Slack errors" do
    item = items(:pending_item)

    SlackService.define_method(:post_item) do |_|
      raise Slack::Web::Api::Errors::SlackError.new("some_error", response: { "ok" => false, "error" => "some_error" })
    end

    assert_nothing_raised do
      PostToSlackJob.perform_now(item.id)
    end
  ensure
    SlackService.remove_method(:post_item)
    load Rails.root.join("app/services/slack_service.rb")
  end

  test "re-raises channel_not_found error" do
    item = items(:pending_item)

    SlackService.define_method(:post_item) do |_|
      raise Slack::Web::Api::Errors::SlackError.new("channel_not_found", response: { "ok" => false, "error" => "channel_not_found" })
    end

    assert_raises Slack::Web::Api::Errors::SlackError do
      PostToSlackJob.perform_now(item.id)
    end
  ensure
    SlackService.remove_method(:post_item)
    load Rails.root.join("app/services/slack_service.rb")
  end

  test "re-raises not_authed error" do
    item = items(:pending_item)

    SlackService.define_method(:post_item) do |_|
      raise Slack::Web::Api::Errors::SlackError.new("not_authed", response: { "ok" => false, "error" => "not_authed" })
    end

    assert_raises Slack::Web::Api::Errors::SlackError do
      PostToSlackJob.perform_now(item.id)
    end
  ensure
    SlackService.remove_method(:post_item)
    load Rails.root.join("app/services/slack_service.rb")
  end
end
