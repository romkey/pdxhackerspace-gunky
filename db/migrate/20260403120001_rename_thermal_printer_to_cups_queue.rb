class RenameThermalPrinterToCupsQueue < ActiveRecord::Migration[8.1]
  def up
    return unless column_exists?(:print_settings, :thermal_printer_name)

    rename_column :print_settings, :thermal_printer_name, :cups_queue
  end

  def down
    return unless column_exists?(:print_settings, :cups_queue)
    return if column_exists?(:print_settings, :thermal_printer_name)

    rename_column :print_settings, :cups_queue, :thermal_printer_name
  end
end
