module SiteScoped
  extend ActiveSupport::Concern

  included do
    helper_method :current_site, :lost_found_site?, :gunky_site?, :other_site_url, :site_name
  end

  private

  def current_site
    @current_site ||= Site.for_host(request.host)
  end

  def lost_found_site?
    current_site == Site::LOST_FOUND
  end

  def gunky_site?
    current_site == Site::GUNKY
  end

  def other_site_url
    lost_found_site? ? Site.gunky_url : Site.lost_found_url
  end

  def site_name
    lost_found_site? ? "Lost+Found" : "Gunky"
  end
end
