require "sidekiq/web"
require "sidekiq/cron/web"

Rails.application.routes.draw do
  mount Sidekiq::Web => "/sidekiq"

  resources :items do
    member do
      patch :resolve
    end
  end

  post "slack/interactions", to: "slack_interactions#create"

  get "up" => "rails/health#show", as: :rails_health_check

  root "items#index"
end
