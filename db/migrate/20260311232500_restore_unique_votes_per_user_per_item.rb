class RestoreUniqueVotesPerUserPerItem < ActiveRecord::Migration[8.1]
  def up
    deduplicate_votes!
    remove_index :votes, name: "index_votes_on_item_id_and_slack_user_id"
    add_index :votes, [ :item_id, :slack_user_id ], name: "index_votes_on_item_id_and_slack_user_id", unique: true
  end

  def down
    remove_index :votes, name: "index_votes_on_item_id_and_slack_user_id"
    add_index :votes, [ :item_id, :slack_user_id ], name: "index_votes_on_item_id_and_slack_user_id"
  end

  private

  def deduplicate_votes!
    execute <<~SQL
      DELETE FROM votes
      WHERE id IN (
        SELECT id
        FROM (
          SELECT
            id,
            ROW_NUMBER() OVER (
              PARTITION BY item_id, slack_user_id
              ORDER BY updated_at DESC, id DESC
            ) AS row_num
          FROM votes
        ) ranked
        WHERE ranked.row_num > 1
      )
    SQL
  end
end
