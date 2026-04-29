class KilledController < ApplicationController
  def index
    @pending_disposal_items = Item.killed_not_disposed.order(created_at: :desc)
    @disposed_items = Item.killed_disposed.order(disposed_at: :desc, created_at: :desc)
  end
end
