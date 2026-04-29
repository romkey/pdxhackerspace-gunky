require "test_helper"

class OllamaServiceTest < ActiveSupport::TestCase
  test "describe_image sends api key when configured" do
    settings = AgentSetting.new(
      ollama_url: "http://ollama.example.test",
      ollama_model: "llava",
      prompt: "Describe this",
      api_key: "secret-key"
    )
    http = FakeHttp.new

    with_fake_http(http) do
      description = OllamaService.new(settings).describe_image(FakeBlob.new("fake image"))

      assert_equal "A red toolbox.", description
      assert_equal "Bearer secret-key", http.last_request["Authorization"]
      assert_equal "/v1/chat/completions", http.last_request.path
    end
  end

  test "describe_image omits authorization when api key is blank" do
    settings = AgentSetting.new(
      ollama_url: "http://ollama.example.test",
      ollama_model: "llava",
      prompt: "Describe this",
      api_key: ""
    )
    http = FakeHttp.new

    with_fake_http(http) do
      OllamaService.new(settings).describe_image(FakeBlob.new("fake image"))

      assert_nil http.last_request["Authorization"]
    end
  end

  test "describe_image sends openai-compatible vision payload" do
    settings = AgentSetting.new(
      ollama_url: "http://ollama.example.test",
      ollama_model: "llava",
      prompt: "Describe this",
      api_key: ""
    )
    http = FakeHttp.new

    with_fake_http(http) do
      OllamaService.new(settings).describe_image(FakeBlob.new("fake image"))

      payload = JSON.parse(http.last_request.body)
      assert_equal "llava", payload["model"]
      assert_equal false, payload["stream"]
      assert_equal "user", payload.dig("messages", 0, "role")
      assert_equal "text", payload.dig("messages", 0, "content", 0, "type")
      assert_equal "Describe this", payload.dig("messages", 0, "content", 0, "text")
      assert_equal "image_url", payload.dig("messages", 0, "content", 1, "type")
      assert_match %r{\Adata:image/jpeg;base64,}, payload.dig("messages", 0, "content", 1, "image_url", "url")
    end
  end

  test "describe_image appends chat completions path to v1 base url" do
    settings = AgentSetting.new(
      ollama_url: "http://ollama.example.test/v1",
      ollama_model: "llava",
      prompt: "Describe this"
    )
    http = FakeHttp.new

    with_fake_http(http) do
      OllamaService.new(settings).describe_image(FakeBlob.new("fake image"))

      assert_equal "/v1/chat/completions", http.last_request.path
    end
  end

  test "describe_image preserves existing chat completions path" do
    settings = AgentSetting.new(
      ollama_url: "http://ollama.example.test/openai/v1/chat/completions",
      ollama_model: "llava",
      prompt: "Describe this"
    )
    http = FakeHttp.new

    with_fake_http(http) do
      OllamaService.new(settings).describe_image(FakeBlob.new("fake image"))

      assert_equal "/openai/v1/chat/completions", http.last_request.path
    end
  end

  private

  FakeBlob = Data.define(:download)

  class FakeHttp
    attr_reader :last_request

    attr_accessor :use_ssl, :open_timeout, :read_timeout

    def request(request)
      @last_request = request
      Net::HTTPOK.new("1.1", "200", "OK").tap do |response|
        response.instance_variable_set(:@read, true)
        response.instance_variable_set(:@body, { choices: [ { message: { content: "A red toolbox." } } ] }.to_json)
      end
    end
  end

  def with_fake_http(http)
    original = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) { |_host, _port| http }
    yield
  ensure
    Net::HTTP.define_singleton_method(:new, original)
  end
end
