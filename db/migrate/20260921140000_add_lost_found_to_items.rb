class AddLostFoundToItems < ActiveRecord::Migration[8.1]
  def change
    change_table :items, bulk: true do |t|
      t.integer :lost_found_state, null: false, default: 0
      t.datetime :lost_found_posted_at
      t.datetime :lost_found_claimed_at
      t.datetime :lost_found_picked_up_at
      t.datetime :lost_found_promoted_at
      t.date :lost_found_hold_until
      t.date :lost_found_pickup_deadline
      t.string :lost_found_claimed_by
      t.string :lost_found_claimed_by_slack_user_id
      t.string :lost_found_slack_channel_id
      t.string :lost_found_slack_message_ts
    end

    add_index :items, :lost_found_state
    add_index :items, :lost_found_hold_until
    add_index :items, :lost_found_pickup_deadline
  end
end
