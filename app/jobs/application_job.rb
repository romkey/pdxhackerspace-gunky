class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError

  # retry_on/discard_on rescue errors inside ActiveJob, so Sidekiq sees the
  # attempt return normally. Note the error for JobMetrics::ServerMiddleware
  # so that attempt is still counted as a failure.
  around_perform do |_job, block|
    block.call
  rescue StandardError => e
    JobMetrics.note_failure(e)
    raise
  end
end
