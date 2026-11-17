require "sidekiq/api"

# Gathers everything exposed at /metrics. See README "Prometheus metrics".
#
# Each section is collected independently: if Redis is down, the database
# metrics are still served, and gunky_metrics_collector_up{collector="sidekiq"}
# drops to 0 so the outage itself is alertable.
class MetricsCollector
  PREFIX = "gunky".freeze
  SECTIONS = %i[app items users activity_log settings storage database web sidekiq jobs redis].freeze
  RECENT_WINDOWS = { "24h" => 24.hours, "7d" => 7.days, "30d" => 30.days }.freeze
  # Retry/dead sets are walked to group by job class; stop counting past this.
  MAX_SET_SCAN = 5_000
  EXPIRE_ITEMS_DEFAULT_RUN_TIME = [ 6, 0 ].freeze

  def initialize(sections: SECTIONS)
    @sections = sections
    @out = MetricsExposition.new
  end

  def render
    collect
    @out.render
  end

  def collect
    scrape_started = monotonic_now

    up = @out.gauge(m(:metrics_collector_up), "Whether the named metrics collector succeeded on this scrape (1) or raised (0).")
    took = @out.gauge(m(:metrics_collector_duration_seconds), "Seconds spent in each metrics collector on this scrape.")

    @sections.each do |section|
      started = monotonic_now
      ok = begin
        send(:"collect_#{section}")
        true
      rescue StandardError => e
        Rails.logger.warn("MetricsCollector #{section} failed: #{e.class}: #{e.message}")
        false
      end
      up.samples << [ "", { collector: section.to_s }, ok ]
      took.samples << [ "", { collector: section.to_s }, monotonic_now - started ]
    end

    @out.gauge(m(:metrics_scrape_duration_seconds), "Seconds taken to build this /metrics response.", monotonic_now - scrape_started)
    @out
  end

  private

  def m(name)
    "#{PREFIX}_#{name}"
  end

  def monotonic_now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def epoch(time)
    time&.to_f
  end

  # --- application -------------------------------------------------------

  def collect_app
    @out.gauge(m(:build_info), "Build and runtime information; always 1.", 1, {
      version: Gunky::VERSION,
      ruby_version: RUBY_VERSION,
      rails_version: Rails.version,
      sidekiq_version: Sidekiq::VERSION,
      environment: Rails.env.to_s
    })
    @out.gauge(m(:up), "Always 1 when the web process can answer a scrape.", 1)
    @out.gauge(m(:time_seconds), "Current wall-clock time on the web server (for clock-skew checks).", Time.now.to_f)
  end

  # --- items -------------------------------------------------------------

  def collect_items
    @out.gauge(m(:items), "Items by Gunky disposition and Lost+Found state.") do |f|
      Item.group(:disposition, :lost_found_state).count.each do |(disposition, lf_state), count|
        f.sample(count, disposition: enum_name(Item.dispositions, disposition), lost_found_state: enum_name(Item.lost_found_states, lf_state))
      end
    end

    @out.gauge(m(:item_outcomes), "Resolved Gunky giveaway outcomes (same numbers as the Winners page).") do |f|
      Item.gunky_stats.each { |outcome, count| f.sample(count, outcome: outcome.to_s) }
    end

    @out.gauge(m(:items_with_photo), "Items that have a photo attached.", Item.joins(:photo_attachment).count)
    @out.gauge(m(:items_with_ai_description), "Items with a non-blank AI-generated description.", Item.where.not(ai_description: [ nil, "" ]).count)
    @out.gauge(m(:items_posted_to_slack), "Items with a Gunky poll message in Slack.", Item.where.not(slack_message_ts: nil).count)
    @out.gauge(m(:items_lost_found_posted_to_slack), "Items with a Lost+Found message in Slack.", Item.where.not(lost_found_slack_message_ts: nil).count)

    @out.gauge(m(:items_expiration_overdue), "Pending Gunky items ExpireItemsJob should already have resolved (expiration date passed, or today after its daily run).",
      Item.gunky_visible.pending.where(expiration_date: ..expiration_overdue_cutoff).count)
    @out.gauge(m(:items_killed_not_disposed), "Items voted to trash that have not been marked disposed.", Item.killed_not_disposed.count)
    @out.gauge(m(:items_awaiting_pickup), "Gunky items with at least one winner who has not picked up.", Item.awaiting_pickup.count)

    @out.gauge(m(:lost_found_to_move), "Promoted Lost+Found items still waiting to be moved to the Gunky area.", Item.lost_found_to_move.count)
    @out.gauge(m(:lost_found_hold_elapsed), "Unclaimed Lost+Found items past their hold date (awaiting promotion).", Item.lost_found_hold_elapsed.count)
    @out.gauge(m(:lost_found_pickup_overdue), "Claimed Lost+Found items past their pickup deadline.", Item.lost_found_pickup_elapsed.count)

    @out.gauge(m(:items_created), "Items created within the trailing window.") do |f|
      RECENT_WINDOWS.each { |window, span| f.sample(Item.where(created_at: span.ago..).count, window: window) }
    end
    @out.gauge(m(:item_last_created_timestamp_seconds), "Unix time the newest item was created.", epoch(Item.maximum(:created_at)))

    @out.gauge(m(:active_items_by_location), "Pending Gunky items plus active Lost+Found items, by location.") do |f|
      known = Location.pluck(:name).to_set
      counts = Hash.new(0)
      active = Item.gunky_visible.pending.or(Item.lost_found_active)
      active.group(:location).count.each do |name, count|
        label = if name.blank? then "none"
        elsif known.include?(name) then name
        else "other"
        end
        counts[label] += count
      end
      counts.each { |label, count| f.sample(count, location: label) }
    end
    @out.gauge(m(:locations), "Configured locations.", Location.count)

    @out.gauge(m(:votes), "Votes by choice.") do |f|
      Vote.group(:choice).count.each { |choice, count| f.sample(count, choice: enum_name(Vote.choices, choice)) }
    end
    @out.gauge(m(:votes_awaiting_pickup), "Winning 'mine' votes on Gunky items not yet picked up.",
      Vote.mine.where(picked_up_at: nil).where(item_id: Item.gunky_visible.mine.select(:id)).count)
  end

  # ExpireItemsJob resolves items expiring today at its daily run (06:00 by
  # default), so today's items only count as overdue once that time passes.
  def expiration_overdue_cutoff(now = Time.current)
    hour, minute = expire_items_run_time
    now >= now.change(hour: hour, min: minute) ? now.to_date : now.to_date - 1
  end

  def expire_items_run_time
    schedule = YAML.load_file(Rails.root.join("config", "sidekiq_schedule.yml"))
    minute, hour = schedule.dig("expire_items", "cron").to_s.split
    return EXPIRE_ITEMS_DEFAULT_RUN_TIME unless hour&.match?(/\A\d+\z/) && minute&.match?(/\A\d+\z/)

    [ hour.to_i, minute.to_i ]
  rescue StandardError
    EXPIRE_ITEMS_DEFAULT_RUN_TIME
  end

  # --- users -------------------------------------------------------------

  # There are no accounts: users are Slack members who voted or claimed.
  def collect_users
    voters = Vote.distinct.pluck(:slack_user_id)
    claimants = Item.where.not(lost_found_claimed_by_slack_user_id: [ nil, "" ]).distinct.pluck(:lost_found_claimed_by_slack_user_id)
    winners = Vote.mine.where(item_id: Item.gunky_visible.mine.select(:id)).distinct.pluck(:slack_user_id)

    @out.gauge(m(:users), "Distinct Slack users by role (all = voted or claimed a Lost+Found item).") do |f|
      f.sample(voters.size, role: "voter")
      f.sample(winners.size, role: "winner")
      f.sample(claimants.size, role: "lost_found_claimant")
      f.sample((voters | claimants).size, role: "all")
    end

    @out.gauge(m(:active_users), "Distinct Slack users who voted or claimed a Lost+Found item within the trailing window.") do |f|
      RECENT_WINDOWS.each do |window, span|
        recent_voters = Vote.where(created_at: span.ago..).distinct.pluck(:slack_user_id)
        recent_claimants = Item.where(lost_found_claimed_at: span.ago..)
          .where.not(lost_found_claimed_by_slack_user_id: [ nil, "" ])
          .distinct.pluck(:lost_found_claimed_by_slack_user_id)
        f.sample((recent_voters | recent_claimants).size, window: window)
      end
    end

    @out.gauge(m(:votes_cast), "Votes cast within the trailing window.") do |f|
      RECENT_WINDOWS.each { |window, span| f.sample(Vote.where(created_at: span.ago..).count, window: window) }
    end

    @out.gauge(m(:slack_member_cache_entries), "Slack members in the local name cache.", SlackMemberCache.count)
    @out.gauge(m(:slack_member_cache_oldest_timestamp_seconds), "Unix time of the least recently refreshed Slack member cache entry.",
      epoch(SlackMemberCache.minimum(:updated_at)))
  end

  # --- activity log --------------------------------------------------------

  # Activity log entries are never pruned, so these are true counters.
  def collect_activity_log
    @out.counter(m(:activity_log_entries_total), "Activity log entries (uploads, Slack API calls, AI requests) by outcome.") do |f|
      LogEntry.group(:category, :action, :succeeded).count.each do |(category, action, succeeded), count|
        f.sample(count, category: category, action: action, succeeded: succeeded.to_s)
      end
    end

    @out.gauge(m(:activity_log_last_failure_timestamp_seconds), "Unix time of the most recent failed activity per category.") do |f|
      LogEntry.where(succeeded: false).group(:category).maximum(:created_at).each do |category, time|
        f.sample(epoch(time), category: category)
      end
    end

    @out.gauge(m(:activity_log_last_success_timestamp_seconds), "Unix time of the most recent successful activity per category.") do |f|
      LogEntry.where(succeeded: true).group(:category).maximum(:created_at).each do |category, time|
        f.sample(epoch(time), category: category)
      end
    end
  end

  # --- settings / features ------------------------------------------------

  def collect_settings
    agent = AgentSetting.first
    printer = PrintSetting.first
    lost_found = LostFoundSetting.first

    @out.gauge(m(:feature_enabled), "Whether an optional integration is configured (1) or not (0).") do |f|
      f.sample(ENV["SLACK_BOT_TOKEN"].present?, feature: "slack")
      f.sample(ENV["SLACK_SIGNING_SECRET"].present?, feature: "slack_interactions")
      f.sample(agent&.enabled? || false, feature: "ai_agent")
      f.sample(printer&.cups_queue.present? || false, feature: "receipt_printer")
      f.sample(ENV["DUPLICATE_HINTS_ENABLED"].present?, feature: "duplicate_hints")
      f.sample(AdminAuthentication.admin_password_configured?, feature: "admin_auth")
      f.sample((ENV["SENTRY_DSN"].presence || ENV["SENTRY_ENDPOINT"].presence).present?, feature: "sentry")
    end

    @out.gauge(m(:lost_found_hold_days), "Configured Lost+Found hold period in days.",
      lost_found&.hold_days || LostFoundSetting.column_defaults["hold_days"])
    @out.gauge(m(:lost_found_pickup_days), "Configured Lost+Found pickup window in days.",
      lost_found&.pickup_days || LostFoundSetting.column_defaults["pickup_days"])
  end

  # --- storage / database --------------------------------------------------

  def collect_storage
    @out.gauge(m(:active_storage_blobs), "Active Storage blobs (photos and variants).", ActiveStorage::Blob.count)
    @out.gauge(m(:active_storage_bytes), "Total bytes across Active Storage blobs.", ActiveStorage::Blob.sum(:byte_size))
  end

  def collect_database
    conn = ActiveRecord::Base.connection
    @out.gauge(m(:database_size_bytes), "Size of the primary PostgreSQL database.",
      conn.select_value("SELECT pg_database_size(current_database())").to_i)

    @out.gauge(m(:database_table_rows), "Row counts for application tables.") do |f|
      { "items" => Item, "votes" => Vote, "log_entries" => LogEntry, "locations" => Location,
        "slack_member_caches" => SlackMemberCache }.each do |table, model|
        f.sample(model.count, table: table)
      end
    end

    stat = ActiveRecord::Base.connection_pool.stat
    @out.gauge(m(:database_pool), "ActiveRecord connection pool of the web process answering this scrape.") do |f|
      %i[size connections busy idle waiting dead].each do |key|
        f.sample(stat[key], state: key.to_s) if stat.key?(key)
      end
    end
  end

  # --- web process -----------------------------------------------------------

  # Puma runs in single mode (no forked workers), so the process answering the
  # scrape is the whole web server.
  def collect_web
    if defined?(::Puma) && ::Puma.respond_to?(:stats_hash)
      stats = begin
        ::Puma.stats_hash
      rescue StandardError
        nil # Not running under a Puma launcher (console, tests).
      end
      if stats
        @out.gauge(m(:puma_threads), "Puma thread pool.") do |f|
          f.sample(stats[:running], state: "running")
          f.sample(stats[:max_threads], state: "max")
          f.sample(stats[:pool_capacity], state: "capacity")
          f.sample(stats[:busy_threads], state: "busy") if stats.key?(:busy_threads)
        end
        @out.gauge(m(:puma_backlog), "Requests waiting for a Puma thread.", stats[:backlog])
        @out.counter(m(:puma_requests_total), "Requests handled by Puma since boot.", stats[:requests_count]) if stats.key?(:requests_count)
      end
    end

    gc = GC.stat
    @out.counter(m(:ruby_gc_runs_total), "Ruby GC runs in the web process.") do |f|
      f.sample(gc[:minor_gc_count], kind: "minor")
      f.sample(gc[:major_gc_count], kind: "major")
    end
    @out.gauge(m(:ruby_heap_live_slots), "Live Ruby heap slots in the web process.", gc[:heap_live_slots])
    @out.gauge(m(:web_process_start_time_seconds), "Unix time the web process booted.", Gunky::BOOTED_AT.to_f)
    rss = resident_memory_bytes
    @out.gauge(m(:web_process_resident_memory_bytes), "Resident memory of the web process.", rss) if rss
  end

  def resident_memory_bytes
    statm = "/proc/self/statm"
    return unless File.readable?(statm)

    File.read(statm).split[1].to_i * 4096
  end

  # --- sidekiq (servers, queues, retries) ----------------------------------

  def collect_sidekiq
    stats = Sidekiq::Stats.new
    @out.counter(m(:sidekiq_jobs_processed_total), "Jobs Sidekiq has processed since its stats were last reset.", stats.processed)
    @out.counter(m(:sidekiq_jobs_failed_total), "Job attempts that raised, since Sidekiq stats were last reset.", stats.failed)
    @out.gauge(m(:sidekiq_jobs), "Jobs currently held by Sidekiq, by set.") do |f|
      f.sample(stats.enqueued, set: "enqueued")
      f.sample(stats.scheduled_size, set: "scheduled")
      f.sample(stats.retry_size, set: "retry")
      f.sample(stats.dead_size, set: "dead")
      f.sample(stats.workers_size, set: "busy")
    end
    @out.gauge(m(:sidekiq_processes), "Sidekiq server processes with a recent heartbeat.", stats.processes_size)

    queue_size = @out.gauge(m(:sidekiq_queue_size), "Jobs waiting in each Sidekiq queue.")
    queue_latency = @out.gauge(m(:sidekiq_queue_latency_seconds), "Age of the oldest job in each Sidekiq queue.")
    Sidekiq::Queue.all.each do |queue|
      queue_size.samples << [ "", { queue: queue.name }, queue.size ]
      queue_latency.samples << [ "", { queue: queue.name }, queue.latency.to_f ]
    end

    collect_sidekiq_processes
    collect_sidekiq_sets
    collect_sidekiq_cron
  end

  def collect_sidekiq_processes
    concurrency = @out.gauge(m(:sidekiq_process_concurrency), "Worker threads per Sidekiq server.")
    busy = @out.gauge(m(:sidekiq_process_busy), "Busy worker threads per Sidekiq server.")
    rss = @out.gauge(m(:sidekiq_process_resident_memory_bytes), "Resident memory per Sidekiq server.")
    beat = @out.gauge(m(:sidekiq_process_last_heartbeat_timestamp_seconds), "Unix time of each Sidekiq server's last heartbeat.")
    started = @out.gauge(m(:sidekiq_process_start_time_seconds), "Unix time each Sidekiq server started.")
    quiet = @out.gauge(m(:sidekiq_process_quiet), "Whether each Sidekiq server is quiet (finishing work, accepting none).")

    Sidekiq::ProcessSet.new.each do |process|
      labels = {
        hostname: process["hostname"].to_s,
        pid: process["pid"].to_s,
        tag: process["tag"].to_s,
        queues: Array(process["queues"]).sort.join(",")
      }
      concurrency.samples << [ "", labels, process["concurrency"].to_i ]
      busy.samples << [ "", labels, process["busy"].to_i ]
      rss.samples << [ "", labels, process["rss"].to_i * 1024 ] if process["rss"]
      beat.samples << [ "", labels, process["beat"].to_f ] if process["beat"]
      started.samples << [ "", labels, process["started_at"].to_f ] if process["started_at"]
      quiet.samples << [ "", labels, process["quiet"].to_s == "true" ]
    end
  end

  def collect_sidekiq_sets
    @out.gauge(m(:sidekiq_set_jobs_by_class), "Jobs in the Sidekiq retry and dead sets, by job class (capped scan).") do |f|
      { "retry" => Sidekiq::RetrySet.new, "dead" => Sidekiq::DeadSet.new }.each do |set_name, set|
        tally = Hash.new(0)
        set.each_with_index do |job, i|
          break if i >= MAX_SET_SCAN

          tally[[ job.display_class.to_s, job["error_class"].to_s ]] += 1
        end
        tally.each do |(job_class, error_class), count|
          f.sample(count, set: set_name, job_class: job_class, error_class: error_class)
        end
      end
    end
  end

  def collect_sidekiq_cron
    enabled = @out.gauge(m(:cron_job_enabled), "Whether each scheduled (cron) job is enabled.")
    last = @out.gauge(m(:cron_job_last_enqueue_timestamp_seconds), "Unix time each scheduled job was last enqueued.")

    Sidekiq::Cron::Job.all.each do |job|
      labels = { job: job.name.to_s, job_class: job.klass.to_s }
      enabled.samples << [ "", labels, job.status == "enabled" ]
      last.samples << [ "", labels, job.last_enqueue_time.to_f ] if job.last_enqueue_time
    end
  end

  # --- job executions (recorded by JobMetrics::ServerMiddleware) ------------

  def collect_jobs
    snap = JobMetrics.snapshot

    @out.counter(m(:job_executions_total), "Job attempts finished by Sidekiq workers, by job class, queue and status.") do |f|
      snap.executions.each do |(job, queue, status), count|
        f.sample(count, job_class: job, queue: queue.to_s, status: status.to_s)
      end
    end

    @out.counter(m(:job_failures_total), "Failed job attempts by job class and exception class.") do |f|
      snap.failures.each do |(job, error_class), count|
        f.sample(count, job_class: job, error_class: error_class.to_s)
      end
    end

    @out.family(m(:job_duration_seconds), type: :histogram, help: "Wall-clock duration of job attempts.") do |f|
      snap.durations.sort.each do |job, duration|
        JobMetrics::DURATION_BUCKETS.each do |le|
          f.sample(duration.buckets.fetch(le.to_f, 0), { job_class: job, le: le.to_s }, suffix: "_bucket")
        end
        f.sample(duration.count, { job_class: job, le: "+Inf" }, suffix: "_bucket")
        f.sample(duration.sum, { job_class: job }, suffix: "_sum")
        f.sample(duration.count, { job_class: job }, suffix: "_count")
      end
    end

    @out.gauge(m(:job_last_success_timestamp_seconds), "Unix time each job class last succeeded.") do |f|
      snap.last_success.each { |job, time| f.sample(time, job_class: job) }
    end
    @out.gauge(m(:job_last_failure_timestamp_seconds), "Unix time each job class last failed.") do |f|
      snap.last_failure.each { |job, time| f.sample(time, job_class: job) }
    end
  end

  # --- redis ---------------------------------------------------------------

  def collect_redis
    info = Sidekiq.default_configuration.redis_info
    @out.gauge(m(:redis_info), "Redis server information; always 1.", 1, { version: info["redis_version"].to_s })
    @out.gauge(m(:redis_used_memory_bytes), "Memory used by Redis.", info["used_memory"].to_i)
    @out.gauge(m(:redis_connected_clients), "Clients connected to Redis.", info["connected_clients"].to_i)
    @out.gauge(m(:redis_uptime_seconds), "Seconds since Redis started.", info["uptime_in_seconds"].to_i)
  end

  def enum_name(mapping, value)
    return value.to_s if mapping.key?(value.to_s)

    mapping.key(value).to_s.presence || value.to_s
  end
end
