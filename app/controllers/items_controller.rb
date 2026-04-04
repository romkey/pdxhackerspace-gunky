class ItemsController < ApplicationController
  include Pagy::Method

  before_action :set_item, only: [ :show, :edit, :update, :destroy, :resolve, :describe, :winner_forfeit, :winner_picked_up, :print, :print_browser ]

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
      if params[:create_and_add_another].present?
        redirect_to new_item_path, notice: "Item was successfully created. Add the next one."
      else
        redirect_to @item, notice: "Item was successfully created."
      end
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

  def print
    setting = PrintSetting.instance
    if setting.cups_queue.blank?
      redirect_to @item, alert: "Set the CUPS printer queue in Settings → Thermal printer."
      return
    end

    result = LpPrintService.new(printer: setting.cups_queue, paper_width_mm: setting.paper_width_mm).print_items([ @item ])
    if result.success?
      redirect_to @item, notice: "Receipt queued on #{setting.cups_queue}."
    else
      redirect_to @item, alert: "Print failed: #{result.error_message}"
    end
  end

  def print_browser
    render layout: "print_browser"
  end

  def print_completed_browser
    @browser_print_items = Item.where.not(disposition: :pending).order(:expiration_date, :id)
    render :print_completed_browser, layout: "print_browser"
  end

  def print_completed
    setting = PrintSetting.instance
    if setting.cups_queue.blank?
      redirect_to items_path, alert: "Set the CUPS printer queue in Settings → Thermal printer."
      return
    end

    items = Item.where.not(disposition: :pending).order(:expiration_date, :id)
    if items.empty?
      redirect_to items_path, alert: "No completed items to print."
      return
    end

    result = LpPrintService.new(printer: setting.cups_queue, paper_width_mm: setting.paper_width_mm).print_items(items)
    if result.success?
      redirect_to items_path, notice: "Queued #{items.size} receipt(s) on #{setting.cups_queue}."
    else
      redirect_to items_path, alert: "Print failed: #{result.error_message}"
    end
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

  def winner_forfeit
    winner = winner_vote_for(@item)
    unless winner
      redirect_to items_path, alert: "Winner vote not found."
      return
    end

    winner.destroy!
    @item.resolve_from_votes!
    SlackService.new.replace_expired_item_message(@item) if @item.posted_to_slack?

    redirect_to items_path, notice: "Removed #{winner.slack_username} from Mine winners."
  end

  def winner_picked_up
    winner = winner_vote_for(@item)
    unless winner
      redirect_to items_path, alert: "Winner vote not found."
      return
    end

    @item.update!(disposition: :mine, claimed_by: winner.slack_username)
    redirect_to items_path, notice: "Marked #{winner.slack_username} as picked up."
  end

  private

  def set_item
    @item = Item.find(params[:id])
  end

  def item_params
    params.require(:item).permit(:description, :location, :photo, :expiration_date)
  end

  def winner_vote_for(item)
    item.votes.find_by(slack_user_id: params[:slack_user_id].to_s, choice: :mine)
  end
end
