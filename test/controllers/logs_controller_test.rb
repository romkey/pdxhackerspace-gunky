require "test_helper"

class LogsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @previous_password = ENV["GUNKY_ADMIN_PASSWORD"]
    ENV["GUNKY_ADMIN_PASSWORD"] = "secret-admin-password"
  end

  teardown do
    if @previous_password.nil?
      ENV.delete("GUNKY_ADMIN_PASSWORD")
    else
      ENV["GUNKY_ADMIN_PASSWORD"] = @previous_password
    end
  end

  test "index requires admin sign-in" do
    get logs_path
    assert_redirected_to admin_sign_in_path
  end

  test "index shows log entries for signed-in admin" do
    post admin_session_path, params: { password: "secret-admin-password" }
    get logs_path
    assert_response :success
    assert_includes response.body, "Uploaded preview photo item.jpg"
    assert_includes response.body, "Slack chat_postMessage"
  end

  test "index filters by category" do
    post admin_session_path, params: { password: "secret-admin-password" }
    get logs_path, params: { category: "upload" }
    assert_response :success
    assert_includes response.body, "Uploaded preview photo item.jpg"
    assert_not_includes response.body, "Slack chat_postMessage"
  end

  test "navbar shows log link when admin auth is configured" do
    get items_path
    assert_includes response.body, 'href="/logs"'
  end

  test "navbar hides log link when admin auth is not configured" do
    ENV.delete("GUNKY_ADMIN_PASSWORD")

    get items_path
    assert_not_includes response.body, 'href="/logs"'
  end
end
