require "test_helper"

class MetricsCollectorTest < ActiveSupport::TestCase
  DB_SECTIONS = %i[app items users activity_log settings storage database web].freeze

  def render(sections)
    MetricsCollector.new(sections: sections).render
  end

  test "item and vote metrics reflect the database" do
    body = render(%i[items])

    assert_equal Item.pending.not_lost_found.count,
      metric_value(body, 'gunky_items{disposition="pending",lost_found_state="not_lost_found"}')
    assert_equal Item.lost_found_unclaimed.count,
      metric_value(body, 'gunky_items{disposition="pending",lost_found_state="lost_found_unclaimed"}')
    assert_equal 1, metric_value(body, 'gunky_votes{choice="mine"}')
    assert_equal 1, metric_value(body, 'gunky_votes{choice="foster"}')
    assert_equal Item.gunky_stats[:trashed], metric_value(body, 'gunky_item_outcomes{outcome="trashed"}')
    assert_equal Item.lost_found_to_move.count, metric_value(body, "gunky_lost_found_to_move")
    assert_equal Item.lost_found_pickup_elapsed.count, metric_value(body, "gunky_lost_found_pickup_overdue")
    assert_equal Location.count, metric_value(body, "gunky_locations")
    assert_equal Item.where(created_at: 30.days.ago..).count, metric_value(body, 'gunky_items_created{window="30d"}')
    assert_equal 1, metric_value(body, 'gunky_metrics_collector_up{collector="items"}')
  end

  test "items expiring today are overdue only after ExpireItemsJob's daily run" do
    Item.update_all(expiration_date: 1.year.from_now.to_date)
    items(:pending_item).update_columns(expiration_date: Date.new(2026, 3, 10))

    travel_to Time.zone.local(2026, 3, 10, 5, 59) do
      assert_equal 0, metric_value(render(%i[items]), "gunky_items_expiration_overdue")
    end
    travel_to Time.zone.local(2026, 3, 10, 6, 0) do
      assert_equal 1, metric_value(render(%i[items]), "gunky_items_expiration_overdue")
    end
    travel_to Time.zone.local(2026, 3, 11, 1, 0) do
      assert_equal 1, metric_value(render(%i[items]), "gunky_items_expiration_overdue")
    end
  end

  test "active items by location buckets unknown names as other" do
    Item.update_all(location: "Somewhere unlisted")
    items(:pending_item).update_columns(location: "Workshop")
    items(:expired_no_votes).update_columns(location: nil)

    body = render(%i[items])

    assert_equal 1, metric_value(body, 'gunky_active_items_by_location{location="Workshop"}')
    assert_equal 1, metric_value(body, 'gunky_active_items_by_location{location="none"}')
    assert_operator metric_value(body, 'gunky_active_items_by_location{location="other"}'), :>, 0
    assert_not_includes body, "Somewhere unlisted"
  end

  test "user metrics count distinct Slack users" do
    body = render(%i[users])

    assert_equal 2, metric_value(body, 'gunky_users{role="voter"}')
    assert_equal 3, metric_value(body, 'gunky_users{role="lost_found_claimant"}')
    assert_equal 3, metric_value(body, 'gunky_users{role="all"}')
    assert_operator metric_value(body, 'gunky_active_users{window="30d"}'), :>=, 2
    assert_equal SlackMemberCache.count, metric_value(body, "gunky_slack_member_cache_entries")
  end

  test "activity log counters and last failure timestamps" do
    failed_at = 5.minutes.ago.change(usec: 0)
    LogEntry.create!(category: "ai", action: "describe_image", message: "AI failed", succeeded: false, created_at: failed_at)

    body = render(%i[activity_log])

    assert_equal 1, metric_value(body, 'gunky_activity_log_entries_total{category="ai",action="describe_image",succeeded="true"}')
    assert_equal 1, metric_value(body, 'gunky_activity_log_entries_total{category="ai",action="describe_image",succeeded="false"}')
    assert_in_delta failed_at.to_f, metric_value(body, 'gunky_activity_log_last_failure_timestamp_seconds{category="ai"}'), 1
    assert_includes body, "# TYPE gunky_activity_log_entries_total counter"
  end

  test "settings report configured integrations" do
    previous = ENV["SLACK_BOT_TOKEN"]
    ENV["SLACK_BOT_TOKEN"] = "xoxb-test"
    AgentSetting.instance.update!(enabled: true)

    body = render(%i[settings])

    assert_equal 1, metric_value(body, 'gunky_feature_enabled{feature="slack"}')
    assert_equal 1, metric_value(body, 'gunky_feature_enabled{feature="ai_agent"}')
    assert_equal LostFoundSetting.instance.hold_days, metric_value(body, "gunky_lost_found_hold_days")
  ensure
    if previous.nil?
      ENV.delete("SLACK_BOT_TOKEN")
    else
      ENV["SLACK_BOT_TOKEN"] = previous
    end
  end

  test "app, storage, database and web sections succeed" do
    body = render(DB_SECTIONS)

    DB_SECTIONS.each do |section|
      assert_equal 1, metric_value(body, %(gunky_metrics_collector_up{collector="#{section}"})), "#{section} failed"
    end
    assert_match(/^gunky_build_info\{version="#{Regexp.escape(Gunky::VERSION)}",/, body)
    assert_operator metric_value(body, "gunky_database_size_bytes"), :>, 0
    assert_equal Item.count, metric_value(body, 'gunky_database_table_rows{table="items"}')
    assert_operator metric_value(body, 'gunky_database_pool{state="size"}'), :>, 0
    assert_operator metric_value(body, "gunky_metrics_scrape_duration_seconds"), :>=, 0
  end

  test "a failing section is reported without breaking the others" do
    failing = ->(*) { raise RedisClient::CannotConnectError, "redis down" }
    with_overridden_instance_method(MetricsCollector, :collect_redis, failing) do
      body = render(%i[app redis])

      assert_equal 0, metric_value(body, 'gunky_metrics_collector_up{collector="redis"}')
      assert_equal 1, metric_value(body, 'gunky_metrics_collector_up{collector="app"}')
      assert_equal 1, metric_value(body, "gunky_up")
    end
  end

  test "job execution histogram comes from JobMetrics" do
    with_fake_job_metrics_redis do
      JobMetrics.record(job_class: "DescribeItemJob", queue: "default", duration: 4.0)
      JobMetrics.record(job_class: "DescribeItemJob", queue: "default", duration: 0.3, error_class: "Net::ReadTimeout")

      body = render(%i[jobs])

      assert_equal 1, metric_value(body, 'gunky_job_executions_total{job_class="DescribeItemJob",queue="default",status="success"}')
      assert_equal 1, metric_value(body, 'gunky_job_failures_total{job_class="DescribeItemJob",error_class="Net::ReadTimeout"}')
      assert_equal 0, metric_value(body, 'gunky_job_duration_seconds_bucket{job_class="DescribeItemJob",le="0.25"}')
      assert_equal 1, metric_value(body, 'gunky_job_duration_seconds_bucket{job_class="DescribeItemJob",le="0.5"}')
      assert_equal 2, metric_value(body, 'gunky_job_duration_seconds_bucket{job_class="DescribeItemJob",le="5"}')
      assert_equal 2, metric_value(body, 'gunky_job_duration_seconds_bucket{job_class="DescribeItemJob",le="+Inf"}')
      assert_in_delta 4.3, metric_value(body, 'gunky_job_duration_seconds_sum{job_class="DescribeItemJob"}'), 0.0001
      assert_equal 2, metric_value(body, 'gunky_job_duration_seconds_count{job_class="DescribeItemJob"}')
      assert_includes body, "# TYPE gunky_job_duration_seconds histogram"
    end
  end

  FakeStats = Struct.new(:processed, :failed, :enqueued, :scheduled_size, :retry_size, :dead_size,
    :workers_size, :processes_size, keyword_init: true)
  FakeQueue = Struct.new(:name, :size, :latency)
  FakeSetJob = Struct.new(:display_class, :error_class) do
    def [](key) = key == "error_class" ? error_class : nil
  end
  FakeCronJob = Struct.new(:name, :klass, :status, :last_enqueue_time)

  test "sidekiq section reports stats, queues, servers, sets and cron jobs" do
    stats = FakeStats.new(processed: 120, failed: 4, enqueued: 3, scheduled_size: 2, retry_size: 2,
      dead_size: 1, workers_size: 1, processes_size: 1)
    process = {
      "hostname" => "worker-1", "pid" => 42, "tag" => "gunky", "queues" => %w[default],
      "concurrency" => 5, "busy" => 1, "rss" => 2048, "beat" => 1_700_000_000.0,
      "started_at" => 1_699_000_000.0, "quiet" => "false"
    }
    retries = [ FakeSetJob.new("PostToSlackJob", "Slack::Web::Api::Errors::SlackError") ] * 2
    dead = [ FakeSetJob.new("DescribeItemJob", "Net::ReadTimeout") ]
    cron = [ FakeCronJob.new("expire_items", "ExpireItemsJob", "enabled", Time.at(1_700_000_100)) ]

    with_overridden_class_method(Sidekiq::Stats, :new, ->(*) { stats }) do
      with_overridden_class_method(Sidekiq::Queue, :all, ->(*) { [ FakeQueue.new("default", 3, 12.5) ] }) do
        with_overridden_class_method(Sidekiq::ProcessSet, :new, ->(*) { [ process ] }) do
          with_overridden_class_method(Sidekiq::RetrySet, :new, ->(*) { retries }) do
            with_overridden_class_method(Sidekiq::DeadSet, :new, ->(*) { dead }) do
              with_overridden_class_method(Sidekiq::Cron::Job, :all, ->(*) { cron }) do
                body = render(%i[sidekiq])

                assert_equal 1, metric_value(body, 'gunky_metrics_collector_up{collector="sidekiq"}')
                assert_equal 120, metric_value(body, "gunky_sidekiq_jobs_processed_total")
                assert_equal 4, metric_value(body, "gunky_sidekiq_jobs_failed_total")
                assert_equal 1, metric_value(body, 'gunky_sidekiq_jobs{set="dead"}')
                assert_equal 1, metric_value(body, "gunky_sidekiq_processes")
                assert_equal 12.5, metric_value(body, 'gunky_sidekiq_queue_latency_seconds{queue="default"}')

                server = 'hostname="worker-1",pid="42",tag="gunky",queues="default"'
                assert_equal 5, metric_value(body, "gunky_sidekiq_process_concurrency{#{server}}")
                assert_equal 2048 * 1024, metric_value(body, "gunky_sidekiq_process_resident_memory_bytes{#{server}}")
                assert_equal 0, metric_value(body, "gunky_sidekiq_process_quiet{#{server}}")

                assert_equal 2, metric_value(body,
                  'gunky_sidekiq_set_jobs_by_class{set="retry",job_class="PostToSlackJob",error_class="Slack::Web::Api::Errors::SlackError"}')
                assert_equal 1, metric_value(body,
                  'gunky_sidekiq_set_jobs_by_class{set="dead",job_class="DescribeItemJob",error_class="Net::ReadTimeout"}')

                cron_labels = 'job="expire_items",job_class="ExpireItemsJob"'
                assert_equal 1, metric_value(body, "gunky_cron_job_enabled{#{cron_labels}}")
                assert_equal 1_700_000_100, metric_value(body, "gunky_cron_job_last_enqueue_timestamp_seconds{#{cron_labels}}")
              end
            end
          end
        end
      end
    end
  end

  test "redis section reads server info" do
    info = { "redis_version" => "8.0.0", "used_memory" => "1048576", "connected_clients" => "3", "uptime_in_seconds" => "60" }
    with_overridden_instance_method(Sidekiq::Config, :redis_info, ->(*) { info }) do
      body = render(%i[redis])

      assert_equal 1, metric_value(body, 'gunky_redis_info{version="8.0.0"}')
      assert_equal 1_048_576, metric_value(body, "gunky_redis_used_memory_bytes")
      assert_equal 3, metric_value(body, "gunky_redis_connected_clients")
    end
  end
end
