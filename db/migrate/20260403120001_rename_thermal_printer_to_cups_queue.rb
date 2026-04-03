class RenameThermalPrinterToCupsQueue < ActiveRecord::Migration[8.1]
  def change
    rename_column :print_settings, :thermal_printer_name, :cups_queue
  end
end
