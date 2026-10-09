class AddLostFoundMovedAtToItems < ActiveRecord::Migration[8.1]
  def change
    add_column :items, :lost_found_moved_at, :datetime
  end
end
