require "test_helper"

class JobMetricsTest < ActiveSupport::TestCase
  class FlakyJob < ApplicationJob
    class Flake < StandardError; end

    retry_on Flake, wait: 1.second, attempts: 3

    def perform
      raise Flake, "try again"
    end
  end
  test "record and snapshot round-trip executions, failures, and durations" do
    with_fake_job_metrics_redis do
      JobMetrics.record(job_class: "PostToSlackJob", queue: "default", duration: 0.2, now: Time.at(100))
      JobMetrics.record(job_class: "PostToSlackJob", queue: "default", duration: 3.0, now: Time.at(200))
      JobMetrics.record(job_class: "PostToSlackJob", queue: "default", duration: 0.04,
        error_class: "Slack::Web::Api::Errors::SlackError", now: Time.at(300))

      snap = JobMetrics.snapshot

      assert_equal 2, snap.executions[[ "PostToSlackJob", "default", "success" ]]
      assert_equal 1, snap.executions[[ "PostToSlackJob", "default", "failure" ]]
      assert_equal 1, snap.failures[[ "PostToSlackJob", "Slack::Web::Api::Errors::SlackError" ]]

      duration = snap.durations["PostToSlackJob"]
      assert_in_delta 3.24, duration.sum, 0.0001
      assert_equal 3, duration.count
      assert_equal 1, duration.buckets[0.05]
      assert_equal 2, duration.buckets[0.25]
      assert_equal 2, duration.buckets[2.5]
      assert_equal 3, duration.buckets[5.0]
      assert_equal 3, duration.buckets[300.0]

      assert_equal 200.0, snap.last_success["PostToSlackJob"]
      assert_equal 300.0, snap.last_failure["PostToSlackJob"]
    end
  end

  test "record swallows Redis errors" do
    failing = ->(&_blk) { raise RedisClient::CannotConnectError, "down" }
    with_overridden_class_method(JobMetrics, :with_redis, failing) do
      assert_nil JobMetrics.record(job_class: "X", queue: "default", duration: 1)
    end
  end

  test "job_class_for unwraps ActiveJob" do
    assert_equal "DescribeItemJob", JobMetrics.job_class_for(
      "class" => "Sidekiq::ActiveJob::Wrapper", "wrapped" => "DescribeItemJob"
    )
    assert_equal "PlainWorker", JobMetrics.job_class_for("class" => "PlainWorker")
  end

  test "server middleware records success and failure, re-raising errors" do
    middleware = JobMetrics::ServerMiddleware.new
    job = { "class" => "Sidekiq::ActiveJob::Wrapper", "wrapped" => "ExpireItemsJob" }

    with_fake_job_metrics_redis do
      assert_equal :done, middleware.call(nil, job, "default") { :done }
      assert_raises(ArgumentError) do
        middleware.call(nil, job, "default") { raise ArgumentError, "boom" }
      end

      snap = JobMetrics.snapshot
      assert_equal 1, snap.executions[[ "ExpireItemsJob", "default", "success" ]]
      assert_equal 1, snap.executions[[ "ExpireItemsJob", "default", "failure" ]]
      assert_equal 1, snap.failures[[ "ExpireItemsJob", "ArgumentError" ]]
      assert_equal 2, snap.durations["ExpireItemsJob"].count
    end
  end

  test "server middleware does not count shutdown interruptions" do
    middleware = JobMetrics::ServerMiddleware.new

    with_fake_job_metrics_redis do |redis|
      assert_raises(Sidekiq::Shutdown) do
        middleware.call(nil, { "class" => "SlowJob" }, "default") { raise Sidekiq::Shutdown }
      end
      assert_empty redis.hashes[JobMetrics::KEY]
    end
  end

  test "server middleware counts ActiveJob retry_on errors as failures" do
    middleware = JobMetrics::ServerMiddleware.new
    job = { "class" => "Sidekiq::ActiveJob::Wrapper", "wrapped" => FlakyJob.name }

    with_fake_job_metrics_redis do
      middleware.call(nil, job, "default") { FlakyJob.perform_now }
      middleware.call(nil, job, "default") { :ok }

      snap = JobMetrics.snapshot
      assert_equal 1, snap.executions[[ FlakyJob.name, "default", "failure" ]]
      assert_equal 1, snap.executions[[ FlakyJob.name, "default", "success" ]]
      assert_equal 1, snap.failures[[ FlakyJob.name, FlakyJob::Flake.name ]]
    end
  end
end
