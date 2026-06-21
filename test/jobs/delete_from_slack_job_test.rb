require "test_helper"

class DeleteFromSlackJobTest < ActiveJob::TestCase
  test "calls SlackService delete_message" do
    called_with = nil

    SlackService.define_method(:delete_message) { |**kwargs| called_with = kwargs }
    DeleteFromSlackJob.perform_now("C123", "111.222")
    assert_equal({ channel: "C123", ts: "111.222" }, called_with)
  ensure
    SlackService.remove_method(:delete_message)
    load Rails.root.join("app/services/slack_service.rb")
  end

  test "does nothing when channel or ts is blank" do
    called = false
    SlackService.define_method(:delete_message) { |_| called = true }

    DeleteFromSlackJob.perform_now("", "111.222")
    DeleteFromSlackJob.perform_now("C123", "")
    assert_not called
  ensure
    SlackService.remove_method(:delete_message)
    load Rails.root.join("app/services/slack_service.rb")
  end

  test "logs and swallows non-critical Slack errors" do
    SlackService.define_method(:delete_message) do |_|
      raise Slack::Web::Api::Errors::SlackError.new("message_not_found", response: { "ok" => false, "error" => "message_not_found" })
    end

    assert_nothing_raised do
      DeleteFromSlackJob.perform_now("C123", "111.222")
    end
  ensure
    SlackService.remove_method(:delete_message)
    load Rails.root.join("app/services/slack_service.rb")
  end

  test "re-raises channel_not_found error" do
    SlackService.define_method(:delete_message) do |_|
      raise Slack::Web::Api::Errors::SlackError.new("channel_not_found", response: { "ok" => false, "error" => "channel_not_found" })
    end

    assert_raises Slack::Web::Api::Errors::SlackError do
      DeleteFromSlackJob.perform_now("C123", "111.222")
    end
  ensure
    SlackService.remove_method(:delete_message)
    load Rails.root.join("app/services/slack_service.rb")
  end
end
