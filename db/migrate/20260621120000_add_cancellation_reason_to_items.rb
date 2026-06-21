class AddCancellationReasonToItems < ActiveRecord::Migration[8.1]
  def change
    add_column :items, :cancellation_reason, :text
  end
end
