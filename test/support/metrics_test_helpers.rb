module MetricsTestHelpers
  # Value of one series in a Prometheus text exposition, e.g.
  #   metric_value(body, 'gunky_votes{choice="mine"}')
  def metric_value(body, series)
    line = body.each_line.find { |l| l.start_with?("#{series} ") }
    assert line, "expected series #{series} in metrics output"
    Float(line.split(" ", 2).last.strip.sub("+Inf", "Infinity"))
  end

  def with_fake_job_metrics_redis(redis = FakeHashRedis.new, &block)
    with_overridden_class_method(JobMetrics, :with_redis, ->(&blk) { blk.call(redis) }) { block.call(redis) }
  end
end
