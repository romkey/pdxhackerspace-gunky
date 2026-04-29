module Settings
  class AgentController < ApplicationController
    def show
      @agent_setting = AgentSetting.instance
    end

    def update
      @agent_setting = AgentSetting.instance

      if @agent_setting.update(agent_setting_params)
        redirect_to settings_agent_path, notice: "Agent settings updated."
      else
        render :show, status: :unprocessable_entity
      end
    end

    private

    def agent_setting_params
      permitted = params.require(:agent_setting).permit(:ollama_url, :ollama_model, :prompt, :enabled, :api_key, :clear_api_key)
      if ActiveModel::Type::Boolean.new.cast(permitted.delete(:clear_api_key))
        permitted[:api_key] = nil
      elsif permitted[:api_key].blank?
        permitted.delete(:api_key)
      end
      permitted
    end
  end
end
