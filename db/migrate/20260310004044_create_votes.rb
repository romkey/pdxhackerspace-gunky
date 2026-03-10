class CreateVotes < ActiveRecord::Migration[8.1]
  def change
    create_table :votes do |t|
      t.references :item, null: false, foreign_key: true
      t.string :slack_user_id, null: false
      t.string :slack_username, null: false
      t.integer :choice, null: false

      t.timestamps
    end

    add_index :votes, [ :item_id, :slack_user_id ], unique: true
  end
end
