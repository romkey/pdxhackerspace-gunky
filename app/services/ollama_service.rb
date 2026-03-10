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
      prompt: @settings.prompt,
      images: [ image_data ],
      stream: false
    }

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 10
    http.read_timeout = 120

    request = Net::HTTP::Post.new(uri.path, "Content-Type" => "application/json")
    request.body = payload.to_json

    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      raise Error, "Ollama returned #{response.code}: #{response.body.truncate(200)}"
    end

    parsed = JSON.parse(response.body)
    parsed["response"]&.strip.presence || raise(Error, "Ollama returned empty response")
  end

  private

  def endpoint_uri
    base = URI.parse(@settings.ollama_url.to_s)

    unless base.is_a?(URI::HTTP) && base.host.present?
      raise Error, "Invalid Ollama URL: must be http(s) with a host"
    end

    base.path = "/api/generate"
    base.query = nil
    base.fragment = nil
    base
  rescue URI::InvalidURIError
    raise Error, "Invalid Ollama URL"
  end
end
