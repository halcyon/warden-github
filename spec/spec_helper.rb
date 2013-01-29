require 'warden/github'
require 'app'
require 'rack/test'
require 'webrat'
require 'addressable/uri'
require 'pp'

Webrat.configure do |config|
  config.mode = :rack
  config.application_port = 4567
end

RSpec.configure do |config|
  config.include(Rack::Test::Methods)
  config.include(Webrat::Methods)
  config.include(Webrat::Matchers)

  config.before(:each) do
  end

  def app
    Example.app
  end
end
