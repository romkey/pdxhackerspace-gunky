require "test_helper"

module Settings
  class AgentControllerTest < ActionDispatch::IntegrationTest
    test "show returns success" do
      get settings_agent_path
      assert_response :success
    end

    test "update saves api key" do
      patch settings_agent_path, params: {
        agent_setting: {
          enabled: "1",
          ollama_url: "http://localhost:11434",
          ollama_model: "llava",
          prompt: "Describe it",
          api_key: "test-key"
        }
      }

      assert_redirected_to settings_agent_path
      assert_equal "test-key", AgentSetting.instance.api_key
    end

    test "update preserves api key when field is blank" do
      AgentSetting.instance.update!(api_key: "existing-key")

      patch settings_agent_path, params: {
        agent_setting: {
          enabled: "1",
          ollama_url: "http://localhost:11434",
          ollama_model: "llava",
          prompt: "Describe it",
          api_key: ""
        }
      }

      assert_redirected_to settings_agent_path
      assert_equal "existing-key", AgentSetting.instance.api_key
    end

    test "update clears api key when requested" do
      AgentSetting.instance.update!(api_key: "existing-key")

      patch settings_agent_path, params: {
        agent_setting: {
          enabled: "1",
          ollama_url: "http://localhost:11434",
          ollama_model: "llava",
          prompt: "Describe it",
          api_key: "",
          clear_api_key: "1"
        }
      }

      assert_redirected_to settings_agent_path
      assert_nil AgentSetting.instance.api_key
    end
  end
end
