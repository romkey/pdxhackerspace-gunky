require "test_helper"

class MetricsControllerTest < ActionDispatch::IntegrationTest
  TOKEN = "test-metrics-token".freeze

  setup do
    @previous_token = ENV["GUNKY_METRICS_TOKEN"]
    ENV["GUNKY_METRICS_TOKEN"] = TOKEN
  end

  teardown do
    if @previous_token.nil?
      ENV.delete("GUNKY_METRICS_TOKEN")
    else
      ENV["GUNKY_METRICS_TOKEN"] = @previous_token
    end
  end

  # Keep these tests independent of a running Redis.
  def stub_redis_sections(&block)
    with_overridden_instance_method(MetricsCollector, :collect_sidekiq, ->(*) { }) do
      with_overridden_instance_method(MetricsCollector, :collect_redis, ->(*) { }) do
        with_fake_job_metrics_redis(&block)
      end
    end
  end

  test "returns 404 when no token is configured" do
    ENV.delete("GUNKY_METRICS_TOKEN")

    get metrics_path, headers: { "Authorization" => "Bearer #{TOKEN}" }
    assert_response :not_found
  end

  test "requires a token" do
    get metrics_path
    assert_response :unauthorized
    assert_match(/\AToken realm=/, response.headers["WWW-Authenticate"])
  end

  test "rejects a wrong token" do
    get metrics_path, headers: { "Authorization" => "Bearer nope" }
    assert_response :unauthorized
  end

  test "ignores a token passed as a query parameter" do
    get metrics_path, params: { token: TOKEN }
    assert_response :unauthorized
  end

  test "serves Prometheus text with a valid bearer token" do
    stub_redis_sections do
      get metrics_path, headers: { "Authorization" => "Bearer #{TOKEN}" }
    end

    assert_response :success
    assert_equal MetricsExposition::CONTENT_TYPE, response.headers["Content-Type"]
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_includes response.body, "# TYPE gunky_items gauge"
    assert_equal 1, metric_value(response.body, "gunky_up")
    assert_equal 1, metric_value(response.body, 'gunky_metrics_collector_up{collector="items"}')
    assert_nil response.headers["Set-Cookie"]
  end

  test "token comparison" do
    assert MetricsController.token_matches?(TOKEN)
    assert_not MetricsController.token_matches?("#{TOKEN}x")
    assert_not MetricsController.token_matches?("")
    assert_not MetricsController.token_matches?(nil)
  end
end
