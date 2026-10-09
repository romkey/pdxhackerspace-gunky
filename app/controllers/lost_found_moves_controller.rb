class LostFoundMovesController < ApplicationController
  def index
    @items = Item.lost_found_to_move.order(lost_found_promoted_at: :asc, created_at: :asc)
  end

  def dismiss
    item = Item.lost_found_to_move.find_by(id: params[:id])
    unless item
      redirect_to lost_found_moves_path, alert: "That item is not waiting to be moved."
      return
    end

    item.mark_lost_found_moved!
    redirect_to lost_found_moves_path, notice: "Marked \"#{item.display_description}\" as moved to Gunky."
  end

  def dismiss_selected
    items = Item.lost_found_to_move.where(id: Array(params[:item_ids]))
    if items.none?
      redirect_to lost_found_moves_path, alert: "Select at least one item to dismiss."
      return
    end

    count = items.update_all(lost_found_moved_at: Time.current, updated_at: Time.current)
    redirect_to lost_found_moves_path, notice: "Marked #{helpers.pluralize(count, 'item')} as moved to Gunky."
  end
end
