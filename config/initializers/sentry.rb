dsn = ENV["SENTRY_DSN"].to_s.strip
endpoint = ENV["SENTRY_ENDPOINT"].to_s.strip
sentry_dsn = dsn.presence || endpoint.presence

if sentry_dsn.present?
  Sentry.init do |config|
    config.dsn = sentry_dsn
    config.breadcrumbs_logger = [ :active_support_logger, :http_logger ]
    config.enabled_environments = %w[production]
  end
end
