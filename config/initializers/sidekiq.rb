Sidekiq.configure_server do |config|
  config.redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0") }

  schedule_file = Rails.root.join("config", "sidekiq_schedule.yml")
  if File.exist?(schedule_file)
    schedule = YAML.load_file(schedule_file)
    # Match wall-clock 6:00 to Rails' calendar (Date.current / expiration_date), not UTC-only cron.
    cron_tz = Time.zone.tzinfo.canonical_identifier
    schedule.each_value do |job|
      next unless job.is_a?(Hash)

      job["timezone"] = job["timezone"].presence || cron_tz
    end
    Sidekiq::Cron::Job.load_from_hash(schedule)
  end
end

# Per-job-class counts and durations for /metrics (see JobMetrics). Added after
# initialization because JobMetrics is an autoloaded app constant.
Rails.application.config.after_initialize do
  Sidekiq.configure_server do |config|
    config.server_middleware { |chain| chain.add JobMetrics::ServerMiddleware }
  end
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0") }
end
