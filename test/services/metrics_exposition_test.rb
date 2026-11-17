require "test_helper"

class MetricsExpositionTest < ActiveSupport::TestCase
  test "renders help, type, and labelled samples" do
    out = MetricsExposition.new
    out.gauge("demo_items", "Items by state.") do |f|
      f.sample(3, state: "open")
      f.sample(1.5, state: "closed")
    end
    out.counter("demo_total", "A counter.", 7)

    assert_equal <<~TEXT, out.render
      # HELP demo_items Items by state.
      # TYPE demo_items gauge
      demo_items{state="open"} 3
      demo_items{state="closed"} 1.5
      # HELP demo_total A counter.
      # TYPE demo_total counter
      demo_total 7
    TEXT
  end

  test "escapes label values and help text" do
    out = MetricsExposition.new
    out.gauge("demo", "Line one\nback\\slash", 1, { name: %(say "hi"\\\nbye) })

    body = out.render
    assert_includes body, "# HELP demo Line one\\nback\\\\slash\n"
    assert_includes body, %(demo{name="say \\"hi\\"\\\\\\nbye"} 1\n)
  end

  test "formats booleans, special floats, and times" do
    out = MetricsExposition.new
    out.gauge("demo", "x") do |f|
      f.sample(true, v: "t")
      f.sample(false, v: "f")
      f.sample(Float::INFINITY, v: "inf")
      f.sample(Float::NAN, v: "nan")
      f.sample(2.0, v: "whole")
      f.sample(Time.at(1_700_000_000), v: "time")
    end

    body = out.render
    assert_includes body, %(demo{v="t"} 1\n)
    assert_includes body, %(demo{v="f"} 0\n)
    assert_includes body, %(demo{v="inf"} +Inf\n)
    assert_includes body, %(demo{v="nan"} NaN\n)
    assert_includes body, %(demo{v="whole"} 2\n)
    assert_includes body, %(demo{v="time"} 1700000000\n)
  end

  test "nil values are skipped" do
    out = MetricsExposition.new
    out.gauge("demo", "x", nil)
    out.gauge("demo2", "x") { |f| f.sample(nil, a: "b") }

    assert_equal "# HELP demo x\n# TYPE demo gauge\n# HELP demo2 x\n# TYPE demo2 gauge\n", out.render
  end

  test "histogram samples use suffixes" do
    out = MetricsExposition.new
    out.family("demo_seconds", type: :histogram, help: "h") do |f|
      f.sample(1, { le: "+Inf" }, suffix: "_bucket")
      f.sample(0.5, {}, suffix: "_sum")
      f.sample(1, {}, suffix: "_count")
    end

    body = out.render
    assert_includes body, "# TYPE demo_seconds histogram\n"
    assert_includes body, %(demo_seconds_bucket{le="+Inf"} 1\n)
    assert_includes body, "demo_seconds_sum 0.5\n"
    assert_includes body, "demo_seconds_count 1\n"
  end

  test "rejects invalid metric and label names" do
    out = MetricsExposition.new
    assert_raises(ArgumentError) { out.gauge("bad-name", "x", 1) }
    assert_raises(ArgumentError) { out.gauge("ok", "x", 1, { "bad-label" => "v" }) }
    assert_raises(ArgumentError) { out.family("ok2", type: :bogus, help: "x") }
  end
end
