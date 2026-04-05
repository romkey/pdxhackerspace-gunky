class AddPickedUpAtToVotes < ActiveRecord::Migration[8.1]
  def change
    add_column :votes, :picked_up_at, :datetime
  end
end
