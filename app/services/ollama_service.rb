require "net/http"
require "json"
require "base64"

class OllamaService
  class Error < StandardError; end

  OPEN_TIMEOUT_SECONDS = ENV.fetch("OLLAMA_OPEN_TIMEOUT_SECONDS", 5).to_i
  READ_TIMEOUT_SECONDS = ENV.fetch("OLLAMA_READ_TIMEOUT_SECONDS", 30).to_i

  def initialize(settings = nil)
    @settings = settings || AgentSetting.instance
  end

  def describe_image(image_blob)
    uri = endpoint_uri
    Rails.logger.info(
      "OllamaService: describing image via #{uri} model=#{@settings.ollama_model} " \
      "(timeouts: open=#{OPEN_TIMEOUT_SECONDS}s read=#{READ_TIMEOUT_SECONDS}s)"
    )

    image_data = Base64.strict_encode64(image_blob.download)

    payload = {
      model: @settings.ollama_model,
      messages: [
        {
          role: "user",
          content: [
            { type: "text", text: @settings.prompt.presence || "Describe this photo" },
            { type: "image_url", image_url: { url: "data:image/jpeg;base64,#{image_data}" } }
          ]
        }
      ],
      stream: false
    }

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = OPEN_TIMEOUT_SECONDS
    http.read_timeout = READ_TIMEOUT_SECONDS

    request = Net::HTTP::Post.new(uri.path, "Content-Type" => "application/json")
    request["Authorization"] = "Bearer #{@settings.api_key}" if @settings.api_key.present?
    request.body = payload.to_json

    response = request_with_diagnostics(http, request, uri)

    unless response.is_a?(Net::HTTPSuccess)
      Rails.logger.error(
        "OllamaService: HTTP #{response.code} from #{uri}: #{response.body.to_s.truncate(500)}"
      )
      raise Error, "AI endpoint returned HTTP #{response.code}: #{response.body.to_s.truncate(200)}"
    end

    parsed = parse_response_json(response.body, uri)
    response_text(parsed)&.strip.presence ||
      raise(Error, "AI endpoint returned empty description text")
  end

  private

  def request_with_diagnostics(http, request, uri)
    http.request(request)
  rescue Net::OpenTimeout => e
    raise Error,
          "AI endpoint connection timed out after #{OPEN_TIMEOUT_SECONDS}s " \
          "(#{uri.host}:#{uri.port}): #{e.message}"
  rescue Net::ReadTimeout => e
    raise Error,
          "AI endpoint read timed out after #{READ_TIMEOUT_SECONDS}s waiting for " \
          "#{@settings.ollama_model} at #{uri}: #{e.message}"
  rescue Errno::ECONNREFUSED => e
    raise Error, "AI endpoint refused connection at #{uri.host}:#{uri.port}: #{e.message}"
  rescue SocketError, Errno::EHOSTUNREACH, Errno::ENETUNREACH => e
    raise Error, "AI endpoint network error for #{uri}: #{e.message}"
  end

  def parse_response_json(body, uri)
    JSON.parse(body)
  rescue JSON::ParserError => e
    Rails.logger.error("OllamaService: invalid JSON from #{uri}: #{body.to_s.truncate(500)}")
    raise Error, "AI endpoint returned invalid JSON: #{e.message}"
  end

  def response_text(parsed)
    content = parsed.dig("choices", 0, "message", "content")
    return content if content.is_a?(String)

    content&.filter_map { |part| part["text"] if part["type"] == "text" }&.join
  end

  def endpoint_uri
    base = URI.parse(@settings.ollama_url.to_s)

    unless base.is_a?(URI::HTTP) && base.host.present?
      raise Error, "Invalid AI endpoint URL: must be http(s) with a host"
    end

    base.path = openai_chat_completions_path(base.path)
    base.query = nil
    base.fragment = nil
    base
  rescue URI::InvalidURIError
    raise Error, "Invalid AI endpoint URL"
  end

  def openai_chat_completions_path(base_path)
    normalized_path = base_path.to_s.chomp("/")
    normalized_path = "" if normalized_path == "/"

    if normalized_path.end_with?("/v1")
      "#{normalized_path}/chat/completions"
    elsif normalized_path.end_with?("/v1/chat/completions")
      normalized_path
    else
      "#{normalized_path}/v1/chat/completions"
    end
  end
end
