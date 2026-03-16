require "test_helper"

module Settings
  class SlackMemberCachesControllerTest < ActionDispatch::IntegrationTest
    test "index returns success" do
      get settings_slack_member_caches_path

      assert_response :success
      assert_select "h2", "Settings: Slack Member Cache"
    end

    test "destroy removes a cache entry" do
      cache_entry = SlackMemberCache.find_by!(slack_user_id: "U001")

      assert_difference "SlackMemberCache.count", -1 do
        delete settings_slack_member_cache_path(cache_entry)
      end

      assert_redirected_to settings_slack_member_caches_path
    end

    test "refresh_items updates all posted items in Slack" do
      update_calls = 0
      original = SlackService.instance_method(:update_item_message)
      SlackService.define_method(:update_item_message) do |_item|
        update_calls += 1
      end

      post refresh_items_settings_slack_member_caches_path

      assert_redirected_to settings_slack_member_caches_path
      assert_equal 1, update_calls
      assert_match(/Refreshed 1 Slack item message/, flash[:notice])
    ensure
      SlackService.define_method(:update_item_message, original)
    end
  end
end
