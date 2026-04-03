class CreatePrintSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :print_settings do |t|
      t.string :thermal_printer_name
      t.integer :paper_width_mm, null: false, default: 80

      t.timestamps
    end
  end
end
