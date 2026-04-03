module Settings
  class PrintController < ApplicationController
    def show
      @print_setting = PrintSetting.instance
    end

    def update
      @print_setting = PrintSetting.instance

      if @print_setting.update(print_setting_params)
        redirect_to settings_print_path, notice: "Thermal print settings updated."
      else
        render :show, status: :unprocessable_entity
      end
    end

    private

    def print_setting_params
      params.require(:print_setting).permit(:cups_queue, :paper_width_mm)
    end
  end
end
