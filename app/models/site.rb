class Site
  GUNKY = :gunky
  LOST_FOUND = :lost_found

  class << self
    def for_host(host)
      return LOST_FOUND if host.present? && host == lost_found_host

      GUNKY
    end

    def gunky_url
      normalize_url(ENV["GUNKY_URL"].presence || ENV["APP_INTERNAL_URL"].presence || default_local_url)
    end

    def lost_found_url
      normalize_url(ENV["LOST_FOUND_URL"].presence || default_lost_found_local_url)
    end

    def gunky_host
      host_from_url(gunky_url)
    end

    def lost_found_host
      host_from_url(lost_found_url)
    end

    private

    def default_local_url
      host = ENV.fetch("APP_HOST", "localhost:3000")
      protocol = ENV.fetch("APP_PROTOCOL", "http")
      "#{protocol}://#{host}"
    end

    def default_lost_found_local_url
      host = ENV.fetch("APP_HOST", "localhost:3000")
      protocol = ENV.fetch("APP_PROTOCOL", "http")
      "#{protocol}://lostfound.#{host}"
    end

    def normalize_url(url)
      url.to_s.chomp("/")
    end

    def host_from_url(url)
      return nil if url.blank?

      uri = URI.parse(url)
      host = uri.host.to_s
      host << ":#{uri.port}" if uri.port && ![ 80, 443 ].include?(uri.port)
      host
    rescue URI::InvalidURIError
      nil
    end
  end
end
