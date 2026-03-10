module Settings
  class LocationsController < ApplicationController
    before_action :set_location, only: [ :edit, :update, :destroy ]

    def index
      @locations = Location.sorted
      @location = Location.new
    end

    def create
      @location = Location.new(location_params)

      if @location.save
        redirect_to settings_locations_path, notice: "Location added."
      else
        @locations = Location.sorted
        render :index, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @location.update(location_params)
        redirect_to settings_locations_path, notice: "Location updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @location.destroy
      redirect_to settings_locations_path, notice: "Location deleted."
    end

    private

    def set_location
      @location = Location.find(params[:id])
    end

    def location_params
      params.require(:location).permit(:name)
    end
  end
end
