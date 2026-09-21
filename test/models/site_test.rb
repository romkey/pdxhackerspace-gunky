require "test_helper"

class SiteTest < ActiveSupport::TestCase
  setup do
    @original_gunky = ENV["GUNKY_URL"]
    @original_lost_found = ENV["LOST_FOUND_URL"]
    ENV["GUNKY_URL"] = "http://gunky.test"
    ENV["LOST_FOUND_URL"] = "http://lostfound.test"
  end

  teardown do
    ENV["GUNKY_URL"] = @original_gunky
    ENV["LOST_FOUND_URL"] = @original_lost_found
  end

  test "for_host returns lost_found only for configured host" do
    assert_equal Site::LOST_FOUND, Site.for_host("lostfound.test")
    assert_equal Site::GUNKY, Site.for_host("gunky.test")
    assert_equal Site::GUNKY, Site.for_host("localhost")
    assert_equal Site::GUNKY, Site.for_host("")
  end

  test "for_request matches lost+found host when URL includes a port" do
    ENV["LOST_FOUND_URL"] = "http://lostfound.localhost:3000"

    assert_equal Site::LOST_FOUND, Site.for_request("lostfound.localhost", 3000)
    assert_equal Site::GUNKY, Site.for_request("lostfound.localhost")
    assert_equal "lostfound.localhost:3000", Site.request_host_key("lostfound.localhost", 3000)
  end

  test "gunky_url and lost_found_url read from environment" do
    assert_equal "http://gunky.test", Site.gunky_url
    assert_equal "http://lostfound.test", Site.lost_found_url
  end
end
