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
      params.require(:agent_setting).permit(:ollama_url, :ollama_model, :prompt, :enabled)
    end
  end
end
