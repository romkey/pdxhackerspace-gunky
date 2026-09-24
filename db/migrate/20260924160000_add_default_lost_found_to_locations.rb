class AddDefaultLostFoundToLocations < ActiveRecord::Migration[8.1]
  def change
    add_column :locations, :default_lost_found, :boolean, default: false, null: false
    add_index :locations, :default_lost_found,
              unique: true,
              where: "default_lost_found = true",
              name: "index_locations_on_default_lost_found_unique"
  end
end
