class AddDuplicateCheckedAtToItems < ActiveRecord::Migration[8.1]
  def change
    add_column :items, :duplicate_checked_at, :datetime
  end
end
