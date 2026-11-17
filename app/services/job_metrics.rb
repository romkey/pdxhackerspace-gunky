# Per-job-class execution counts, failures, and durations for /metrics.
#
# Sidekiq runs in a different process (usually a different container) from
# the web server that answers scrapes, so the numbers live in one Redis hash
# instead of process memory. Every field is a monotonically increasing counter
# (or a last-seen timestamp), and the field count is bounded by
# job classes x (queues + buckets + error classes), so the hash stays small.
#
# Counts are per attempt: a job that fails twice and then succeeds records two
# failures and one success. That includes ActiveJob retry_on/discard_on, which
# swallow the error before Sidekiq sees it (see ApplicationJob#around_perform).
class JobMetrics
  KEY = "gunky:metrics:jobs".freeze
  SEPARATOR = "|".freeze
  FAILURE_KEY = :gunky_job_metrics_failure
  # Seconds. Covers quick Slack posts through slow AI vision calls.
  DURATION_BUCKETS = [ 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10, 30, 60, 120, 300 ].freeze

  Snapshot = Struct.new(:executions, :failures, :durations, :last_success, :last_failure, keyword_init: true)
  Duration = Struct.new(:sum, :count, :buckets, keyword_init: true)

  class << self
    def record(job_class:, queue:, duration:, error_class: nil, now: Time.now)
      status = error_class ? "failure" : "success"
      with_redis do |conn|
        conn.pipelined do |p|
          p.call("HINCRBY", KEY, field("executions", job_class, queue, status), 1)
          p.call("HINCRBYFLOAT", KEY, field("duration_sum", job_class), duration.to_f)
          p.call("HINCRBY", KEY, field("duration_count", job_class), 1)
          DURATION_BUCKETS.each do |le|
            p.call("HINCRBY", KEY, field("duration_bucket", job_class, le), 1) if duration <= le
          end
          p.call("HINCRBY", KEY, field("failures", job_class, error_class), 1) if error_class
          p.call("HSET", KEY, field("last_#{status}", job_class), now.to_f)
        end
      end
    rescue StandardError => e
      # Metrics must never break job execution.
      Rails.logger.warn("JobMetrics.record failed: #{e.class}: #{e.message}")
      nil
    end

    def snapshot
      raw = with_redis { |conn| conn.call("HGETALL", KEY) }
      raw = raw.each_slice(2).to_h if raw.is_a?(Array)
      parse(raw || {})
    end

    def reset!
      with_redis { |conn| conn.call("DEL", KEY) }
    end

    # ActiveJob's retry_on/discard_on handle errors before they reach Sidekiq.
    # ApplicationJob notes them here so the middleware still counts a failure.
    def note_failure(error)
      Thread.current[FAILURE_KEY] = error.class.name
    end

    def take_failure
      Thread.current[FAILURE_KEY].tap { Thread.current[FAILURE_KEY] = nil }
    end

    def job_class_for(job)
      (job["wrapped"] || job["class"]).to_s
    end

    def with_redis(&block)
      Sidekiq.redis(&block)
    end

    private

    def field(*parts)
      parts.map(&:to_s).join(SEPARATOR)
    end

    def parse(raw)
      snap = Snapshot.new(executions: Hash.new(0), failures: Hash.new(0), durations: {}, last_success: {}, last_failure: {})

      raw.each do |key, value|
        kind, job, *rest = key.to_s.split(SEPARATOR)
        next if job.blank?

        case kind
        when "executions"
          queue, status = rest
          snap.executions[[ job, queue, status ]] += value.to_i
        when "failures"
          snap.failures[[ job, rest.first ]] += value.to_i
        when "duration_sum"
          duration_for(snap, job).sum = value.to_f
        when "duration_count"
          duration_for(snap, job).count = value.to_i
        when "duration_bucket"
          duration_for(snap, job).buckets[rest.first.to_f] = value.to_i
        when "last_success"
          snap.last_success[job] = value.to_f
        when "last_failure"
          snap.last_failure[job] = value.to_f
        end
      end

      snap
    end

    def duration_for(snap, job)
      snap.durations[job] ||= Duration.new(sum: 0.0, count: 0, buckets: {})
    end
  end

  # Registered in config/initializers/sidekiq.rb.
  class ServerMiddleware
    include Sidekiq::ServerMiddleware

    # Sidekiq::Shutdown is not a StandardError: a job interrupted by shutdown
    # is re-queued rather than finished, so it is not counted either way.
    def call(_job_instance, job, queue)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      JobMetrics.take_failure
      result = yield
      record(job, queue, started, JobMetrics.take_failure)
      result
    rescue StandardError => e
      JobMetrics.take_failure
      record(job, queue, started, e.class.name)
      raise
    end

    private

    def record(job, queue, started, error_class = nil)
      JobMetrics.record(
        job_class: JobMetrics.job_class_for(job),
        queue: queue,
        duration: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started,
        error_class: error_class
      )
    end
  end
end
