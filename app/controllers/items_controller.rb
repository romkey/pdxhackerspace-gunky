class ItemsController < ApplicationController
  include Pagy::Method

  before_action :set_item, only: [ :show, :edit, :update, :destroy, :resolve ]

  def index
    items = Item.order(created_at: :desc)
    items = items.where(disposition: params[:disposition]) if params[:disposition].present?
    @pagy, @items = pagy(:offset, items)
  end

  def show
  end

  def new
    @item = Item.new
    @locations = Location.sorted
  end

  def create
    @item = Item.new(item_params)

    if @item.save
      PostToSlackJob.perform_later(@item.id) if ENV["SLACK_BOT_TOKEN"].present?
      DescribeItemJob.perform_later(@item.id) if @item.photo.attached? && @item.description.blank? && AgentSetting.enabled?
      redirect_to @item, notice: "Item was successfully created."
    else
      @locations = Location.sorted
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @locations = Location.sorted
  end

  def update
    if @item.update(item_params)
      redirect_to @item, notice: "Item was successfully updated."
    else
      @locations = Location.sorted
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @item.destroy
    redirect_to items_path, notice: "Item was successfully deleted."
  end

  def resolve
    disposition = params[:disposition]
    claimed_by = params[:claimed_by]

    unless Item.dispositions.key?(disposition)
      redirect_to @item, alert: "Invalid disposition."
      return
    end

    @item.update!(disposition: disposition, claimed_by: claimed_by)
    redirect_to @item, notice: "Item resolved as #{disposition}."
  end

  private

  def set_item
    @item = Item.find(params[:id])
  end

  def item_params
    params.require(:item).permit(:description, :location, :photo, :expiration_date)
  end
end
