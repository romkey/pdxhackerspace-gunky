# Builds a Prometheus text exposition (format 0.0.4).
#
# Metrics are computed fresh on every scrape from the database, Redis, and
# Sidekiq, so there is no long-lived client registry: each scrape builds one of
# these, adds families and samples, and renders it.
class MetricsExposition
  CONTENT_TYPE = "text/plain; version=0.0.4; charset=utf-8".freeze
  TYPES = %w[counter gauge histogram summary untyped].freeze
  NAME_FORMAT = /\A[a-zA-Z_:][a-zA-Z0-9_:]*\z/
  LABEL_FORMAT = /\A[a-zA-Z_][a-zA-Z0-9_]*\z/

  Family = Struct.new(:name, :type, :help, :samples)

  def initialize
    @families = {}
  end

  # Declares a metric family (idempotent) and yields it so samples can be added.
  def family(name, type:, help:)
    name = name.to_s
    raise ArgumentError, "invalid metric name: #{name}" unless name.match?(NAME_FORMAT)
    raise ArgumentError, "invalid metric type: #{type}" unless TYPES.include?(type.to_s)

    fam = (@families[name] ||= Family.new(name, type.to_s, help, []))
    yield SampleWriter.new(fam) if block_given?
    fam
  end

  def gauge(name, help, value = nil, labels = {}, &block)
    family(name, type: :gauge, help: help) do |f|
      f.sample(value, labels) unless value.nil?
      block&.call(f)
    end
  end

  def counter(name, help, value = nil, labels = {}, &block)
    family(name, type: :counter, help: help) do |f|
      f.sample(value, labels) unless value.nil?
      block&.call(f)
    end
  end

  def families
    @families.values
  end

  def render
    out = +""
    @families.each_value do |fam|
      out << "# HELP #{fam.name} #{escape_help(fam.help)}\n"
      out << "# TYPE #{fam.name} #{fam.type}\n"
      fam.samples.each do |suffix, labels, value|
        out << fam.name << suffix << format_labels(labels) << " " << format_value(value) << "\n"
      end
    end
    out
  end

  class SampleWriter
    def initialize(family)
      @family = family
    end

    # Labels may be passed as a hash or as keywords: sample(3, state: "open").
    def sample(value, labels = nil, suffix: "", **keyword_labels)
      return if value.nil?

      labels = (labels || {}).merge(keyword_labels)

      labels.each_key do |key|
        raise ArgumentError, "invalid label name: #{key}" unless key.to_s.match?(LABEL_FORMAT)
      end
      @family.samples << [ suffix, labels, value ]
    end
  end

  private

  def format_labels(labels)
    return "" if labels.empty?

    "{" + labels.map { |k, v| %(#{k}="#{escape_label(v)}") }.join(",") + "}"
  end

  def format_value(value)
    case value
    when true then "1"
    when false then "0"
    when Integer then value.to_s
    when Float
      if value.nan? then "NaN"
      elsif value.infinite? then value.positive? ? "+Inf" : "-Inf"
      elsif value == value.floor && value.abs < 1e15 then value.to_i.to_s
      else value.to_s
      end
    when Time, ActiveSupport::TimeWithZone, DateTime then format_value(value.to_f)
    else format_value(Float(value))
    end
  end

  LABEL_ESCAPES = { "\\" => "\\\\", "\"" => "\\\"", "\n" => "\\n" }.freeze
  HELP_ESCAPES = { "\\" => "\\\\", "\n" => "\\n" }.freeze

  def escape_label(value)
    value.to_s.gsub(/[\\"\n]/, LABEL_ESCAPES)
  end

  def escape_help(text)
    text.to_s.gsub(/[\\\n]/, HELP_ESCAPES)
  end
end
