class ItemsController < ApplicationController
  include Pagy::Method

  before_action :set_item, only: [ :show, :edit, :update, :destroy, :resolve, :describe ]

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
      if @item.photo.attached? && @item.description.blank?
        if AgentSetting.enabled?
          Rails.logger.info("Enqueuing DescribeItemJob for item #{@item.id}")
          DescribeItemJob.perform_later(@item.id)
        else
          Rails.logger.info("AI agent disabled, skipping DescribeItemJob for item #{@item.id}")
        end
      end
      redirect_to @item, notice: "Item was successfully created."
    else
      @locations = Location.sorted
      render :new, status: :unprocessable_entity
    end
  end

  def preview_description
    photo = params[:photo]
    if photo.blank?
      render json: { error: "Photo is required." }, status: :unprocessable_entity
      return
    end

    io = photo.respond_to?(:tempfile) ? photo.tempfile : photo
    io.rewind if io.respond_to?(:rewind)

    blob = ActiveStorage::Blob.create_and_upload!(
      io: io,
      filename: photo.respond_to?(:original_filename) ? photo.original_filename : "upload.jpg",
      content_type: photo.respond_to?(:content_type) ? photo.content_type : nil
    )

    ai_description = nil
    if AgentSetting.enabled?
      ai_description = OllamaService.new.describe_image(blob)
    end

    render json: { signed_id: blob.signed_id, description: ai_description }
  rescue OllamaService::Error => e
    blob&.purge_later
    render json: { error: e.message }, status: :unprocessable_entity
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

  def describe
    unless @item.photo.attached?
      redirect_to @item, alert: "No photo attached to describe."
      return
    end

    unless AgentSetting.enabled?
      redirect_to @item, alert: "AI agent is not enabled. Enable it in Settings > AI Agent."
      return
    end

    DescribeItemJob.perform_later(@item.id, force: true)
    redirect_to @item, notice: "AI description requested. It will update shortly."
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
