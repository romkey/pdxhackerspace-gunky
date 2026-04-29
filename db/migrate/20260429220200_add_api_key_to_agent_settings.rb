class AddApiKeyToAgentSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :agent_settings, :api_key, :string
  end
end
