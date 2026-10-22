# This file is used by Rack-based servers to start the application.

require_relative "config/environment"

Rails.application.ractorize!

run Rails.app
