class CreateLostFoundSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :lost_found_settings do |t|
      t.integer :hold_days, null: false, default: 14
      t.integer :pickup_days, null: false, default: 7

      t.timestamps
    end
  end
end
