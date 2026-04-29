class AddDisposedAtToItems < ActiveRecord::Migration[8.1]
  def change
    add_column :items, :disposed_at, :datetime
    add_index :items, :disposed_at
  end
end
