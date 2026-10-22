# This file is used by Rack-based servers to start the application.

require_relative "config/environment"

# Propshaft memoizes lazily; warm it before ractorize! freezes the app.
assets = Rails.application.assets
assets.prefix
assets.resolver

Rails.application.ractorize!

run Rails.app
