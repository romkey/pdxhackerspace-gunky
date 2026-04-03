class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  def default_url_options
    host = ENV["APP_HOST"]
    return {} if host.blank?

    { host:, protocol: ENV.fetch("APP_PROTOCOL", "http") }
  end
end
