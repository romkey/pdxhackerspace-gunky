class ItemsController < ApplicationController
  include Pagy::Method

  before_action :set_item, only: [
    :show, :edit, :update, :destroy, :resolve, :describe, :dispose,
    :winner_forfeit, :winner_picked_up, :print, :print_browser,
    :cancel_giveaway, :claim_ownership
  ]

  def index
    items = filtered_items.order(created_at: :desc)
    @stats = Item.gunky_stats
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
        redirect_to item_path(@item), notice: "Item was successfully created."
      end
    else
      @locations = Location.sorted
      render :new, status: :unprocessable_entity
    end
  end

  def preview_photo
    blob = upload_preview_photo(params[:photo])
    return if performed?

    render json: { signed_id: blob.signed_id }
  end

  def preview_description
    blob = find_preview_blob(params[:signed_id])
    return if performed?

    ai_description = nil
    ai_error = nil
    if AgentSetting.enabled?
      begin
        ai_description = OllamaService.new.describe_image(blob)
        Rails.logger.info(
          "preview_description: AI description for blob #{blob.key}: #{ai_description.truncate(100)}"
        )
      rescue OllamaService::Error => e
        ai_error = e.message
        Rails.logger.error("preview_description: AI failed for blob #{blob.key}: #{ai_error}")
      end
    else
      Rails.logger.info("preview_description: AI agent disabled, skipping description for blob #{blob.key}")
    end

    render json: { signed_id: blob.signed_id, description: ai_description, ai_error: ai_error }
  end

  def edit
    @locations = Location.sorted
  end

  def update
    if @item.update(item_params)
      redirect_to item_path(@item), notice: "Item was successfully updated."
    else
      @locations = Location.sorted
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    enqueue_slack_delete(@item)
    @item.destroy
    redirect_to items_path, notice: "Item was successfully deleted."
  end

  def print
    setting = PrintSetting.instance
    if setting.cups_queue.blank?
      redirect_to item_path(@item), alert: "Set the CUPS printer queue in Settings → Thermal printer."
      return
    end

    result = LpPrintService.new(printer: setting.cups_queue, paper_width_mm: setting.paper_width_mm).print_items([ @item ])
    if result.success?
      redirect_to item_path(@item), notice: "Receipt queued on #{setting.cups_queue}."
    else
      redirect_to item_path(@item), alert: "Print failed: #{result.error_message}"
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
      redirect_to item_path(@item), alert: "No photo attached to describe."
      return
    end

    unless AgentSetting.enabled?
      redirect_to item_path(@item), alert: "AI agent is not enabled. Enable it in Settings > AI Agent."
      return
    end

    DescribeItemJob.perform_later(@item.id, force: true)
    redirect_to item_path(@item), notice: "AI description requested. It will update shortly."
  end

  def dispose
    unless @item.kill?
      redirect_back fallback_location: killed_path, alert: "Only killed items can be marked as disposed of."
      return
    end

    @item.dispose!
    redirect_back fallback_location: killed_path, notice: "Marked item as disposed of."
  end

  def resolve
    disposition = params[:disposition]
    claimed_by = params[:claimed_by]

    unless Item.dispositions.key?(disposition)
      redirect_to item_path(@item), alert: "Invalid disposition."
      return
    end

    @item.update!(disposition: disposition, claimed_by: claimed_by)
    redirect_to item_path(@item), notice: "Item resolved as #{disposition}."
  end

  def winner_forfeit
    winner = winner_vote_for(@item)
    unless winner
      redirect_back fallback_location: items_path, alert: "Winner vote not found."
      return
    end

    winner.destroy!
    @item.resolve_from_votes!

    redirect_back fallback_location: items_path, notice: "Removed #{winner.slack_username} from Mine winners."
  end

  def winner_picked_up
    winner = winner_vote_for(@item)
    unless winner
      redirect_back fallback_location: items_path, alert: "Winner vote not found."
      return
    end

    winner.update!(picked_up_at: Time.current)
    @item.update!(disposition: :mine, claimed_by: winner.slack_username)
    redirect_back fallback_location: items_path, notice: "Marked #{winner.slack_username} as picked up."
  end

  def cancel_giveaway
    unless @item.pending?
      redirect_back fallback_location: items_path, alert: "Only pending items can be cancelled."
      return
    end

    @item.update!(disposition: :cancelled, claimed_by: nil)
    SlackService.new.cancel_item_message(@item)
    redirect_back fallback_location: items_path, notice: "Giveaway cancelled."
  end

  def claim_ownership
    unless @item.pending?
      redirect_back fallback_location: items_path, alert: "Only pending items can be marked as owned."
      return
    end

    claimed_by = params[:claimed_by].to_s.strip
    if claimed_by.blank?
      redirect_back fallback_location: items_path, alert: "Owner name is required."
      return
    end

    @item.update!(disposition: :cancelled, claimed_by: claimed_by)
    SlackService.new.cancel_item_message(@item)
    redirect_back fallback_location: items_path, notice: "Marked as owned by #{claimed_by}."
  end

  private

  def filtered_items
    disposition = params[:disposition].to_s

    if disposition == "owned"
      Item.owned
    elsif disposition == "cancelled"
      Item.giveaway_cancelled
    elsif disposition.present? && Item.dispositions.key?(disposition)
      Item.where(disposition: disposition)
    else
      Item.all
    end
  end

  def set_item
    @item = Item.find(params[:id])
  end

  def item_params
    params.require(:item).permit(:description, :location, :photo, :expiration_date)
  end

  def winner_vote_for(item)
    item.votes.find_by(slack_user_id: params[:slack_user_id].to_s, choice: :mine)
  end

  def enqueue_slack_delete(item)
    return unless item.posted_to_slack?
    return unless ENV["SLACK_BOT_TOKEN"].present?

    DeleteFromSlackJob.perform_later(item.slack_channel_id, item.slack_message_ts)
  end

  def upload_preview_photo(photo)
    if photo.blank?
      render json: { error: "Photo is required." }, status: :unprocessable_entity
      return nil
    end

    io = photo.respond_to?(:tempfile) ? photo.tempfile : photo
    io.rewind if io.respond_to?(:rewind)

    blob = ActiveStorage::Blob.create_and_upload!(
      io: io,
      filename: photo.respond_to?(:original_filename) ? photo.original_filename : "upload.jpg",
      content_type: photo.respond_to?(:content_type) ? photo.content_type : nil
    )
    Rails.logger.info(
      "preview_photo: uploaded blob #{blob.key} " \
      "(#{blob.byte_size} bytes, #{blob.content_type})"
    )
    blob
  end

  def find_preview_blob(signed_id)
    if signed_id.blank?
      render json: { error: "signed_id is required." }, status: :unprocessable_entity
      return nil
    end

    blob = ActiveStorage::Blob.find_signed(signed_id)
    unless blob
      render json: { error: "Photo not found." }, status: :unprocessable_entity
      return nil
    end

    blob
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    render json: { error: "Photo reference is invalid." }, status: :unprocessable_entity
    nil
  end
end
