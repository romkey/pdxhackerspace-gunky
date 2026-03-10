class CreateAgentSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_settings do |t|
      t.string :ollama_url, null: false, default: "http://localhost:11434"
      t.string :ollama_model, null: false, default: "llava"
      t.text :prompt, null: false, default: "Describe this object in one or two sentences. What is it and what condition is it in?"
      t.boolean :enabled, null: false, default: false

      t.timestamps
    end
  end
end
