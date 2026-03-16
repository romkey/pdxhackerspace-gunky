class CreateSlackMemberCaches < ActiveRecord::Migration[8.1]
  def change
    create_table :slack_member_caches do |t|
      t.string :slack_user_id, null: false
      t.string :display_name
      t.string :real_name

      t.timestamps
    end

    add_index :slack_member_caches, :slack_user_id, unique: true
  end
end
