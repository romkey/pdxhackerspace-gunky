require "net/http"
require "json"
require "base64"

class OllamaService
  class Error < StandardError; end

  def initialize(settings = nil)
    @settings = settings || AgentSetting.instance
  end

  def describe_image(image_blob)
    image_data = Base64.strict_encode64(image_blob.download)

    uri = endpoint_uri
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
    http.open_timeout = 10
    http.read_timeout = 120

    request = Net::HTTP::Post.new(uri.path, "Content-Type" => "application/json")
    request["Authorization"] = "Bearer #{@settings.api_key}" if @settings.api_key.present?
    request.body = payload.to_json

    response = http.request(request)

    raise Error, "AI endpoint returned #{response.code}: #{response.body.truncate(200)}" unless response.is_a?(Net::HTTPSuccess)

    parsed = JSON.parse(response.body)
    response_text(parsed)&.strip.presence ||
      raise(Error, "AI endpoint returned empty response")
  end

  private

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
