require "test_helper"

class SlackMemberCacheServiceTest < ActiveSupport::TestCase
  test "resolve_name returns cached preferred name without API call" do
    client = FakeSlackLookupClient.new
    service = SlackMemberCacheService.new(client: client)

    resolved = service.resolve_name("U001", fallback_username: "alice")

    assert_equal "Alice Display", resolved
    assert_equal 0, client.calls
  end

  test "resolve_name fetches from Slack API on cache miss and stores result" do
    client = FakeSlackLookupClient.new(
      user_payload: {
        "profile" => {
          "display_name" => "Dave Display",
          "real_name" => "Dave Real"
        }
      }
    )
    service = SlackMemberCacheService.new(client: client)

    resolved = service.resolve_name("U999", fallback_username: "dave")
    cache_entry = SlackMemberCache.find_by(slack_user_id: "U999")

    assert_equal "Dave Display", resolved
    assert_equal 1, client.calls
    assert_not_nil cache_entry
    assert_equal "Dave Display", cache_entry.display_name
    assert_equal "Dave Real", cache_entry.real_name
  end

  class FakeSlackLookupClient
    attr_reader :calls

    def initialize(user_payload: nil)
      @user_payload = user_payload
      @calls = 0
    end

    def users_info(user:)
      @calls += 1
      { "user" => @user_payload || { "profile" => { "display_name" => "Name for #{user}" } } }
    end
  end
end
