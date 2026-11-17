# Prometheus scrape endpoint. Requires `Authorization: Bearer <GUNKY_METRICS_TOKEN>`;
# answers 404 when no token is configured so the endpoint does not exist by default.
#
# Inherits from ActionController::Base directly (not ApplicationController) so
# scrapes skip the browser-version gate, site scoping, and admin session.
class MetricsController < ActionController::Base
  include ActionController::HttpAuthentication::Token::ControllerMethods

  TOKEN_ENV = "GUNKY_METRICS_TOKEN".freeze

  before_action :require_metrics_token

  def show
    response.headers["Cache-Control"] = "no-store"
    render plain: MetricsCollector.new.render, content_type: MetricsExposition::CONTENT_TYPE
  end

  def self.token_configured?
    ENV[TOKEN_ENV].present?
  end

  def self.token_matches?(token)
    configured = ENV[TOKEN_ENV].to_s
    return false if configured.blank? || token.blank?

    ActiveSupport::SecurityUtils.secure_compare(
      Digest::SHA256.hexdigest(token),
      Digest::SHA256.hexdigest(configured)
    )
  end

  private

  def require_metrics_token
    return head(:not_found) unless self.class.token_configured?

    authenticate_or_request_with_http_token("Gunky metrics") do |token, _options|
      self.class.token_matches?(token)
    end
  end
end
