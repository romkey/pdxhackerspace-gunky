require "sidekiq/web"
require "sidekiq/cron/web"

Rails.application.routes.draw do
  mount Sidekiq::Web => "/sidekiq"

  resources :winners, only: [ :index ]

  resources :items do
    collection do
      post :preview_description
      post :print_completed
      get :print_completed_browser
    end

    member do
      post :print
      get :print_browser
      patch :resolve
      post :describe
      post :winner_forfeit
      post :winner_picked_up
    end
  end

  namespace :settings do
    resources :locations, except: :show
    resource :agent, only: [ :show, :update ], controller: "agent"
    resource :print, only: [ :show, :update ], controller: "print"
    resources :slack_member_caches, only: [ :index, :destroy ] do
      collection do
        post :refresh_items
      end
    end
  end

  post "slack/interactions", to: "slack_interactions#create"

  get "up" => "rails/health#show", as: :rails_health_check

  root "items#index"
end
