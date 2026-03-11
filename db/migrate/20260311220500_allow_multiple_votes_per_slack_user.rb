class AllowMultipleVotesPerSlackUser < ActiveRecord::Migration[8.1]
  def change
    remove_index :votes, name: "index_votes_on_item_id_and_slack_user_id"
    add_index :votes, [ :item_id, :slack_user_id ], name: "index_votes_on_item_id_and_slack_user_id"
  end
end
