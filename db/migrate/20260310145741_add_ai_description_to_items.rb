class AddAiDescriptionToItems < ActiveRecord::Migration[8.1]
  def change
    add_column :items, :ai_description, :text
  end
end
