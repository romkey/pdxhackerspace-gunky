module Settings
  class LostFoundController < ApplicationController
    def show
      @lost_found_setting = LostFoundSetting.instance
    end

    def update
      @lost_found_setting = LostFoundSetting.instance

      if @lost_found_setting.update(lost_found_setting_params)
        redirect_to settings_lost_found_path, notice: "Lost+Found settings updated."
      else
        render :show, status: :unprocessable_entity
      end
    end

    private

    def lost_found_setting_params
      params.require(:lost_found_setting).permit(:hold_days, :pickup_days)
    end
  end
end
