class CreateItems < ActiveRecord::Migration[8.1]
  def change
    create_table :items do |t|
      t.text :description, null: false
      t.string :location
      t.date :expiration_date
      t.integer :disposition, null: false, default: 0
      t.string :claimed_by
      t.string :slack_message_ts
      t.string :slack_channel_id

      t.timestamps
    end

    add_index :items, :disposition
    add_index :items, :expiration_date
  end
end
