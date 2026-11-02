# This file is used by Rack-based servers to start the application.

require_relative "config/environment"

# Only the Ractor server needs (and tolerates) a frozen, shareable app; the
# forking server wants the app left as it is. See bin/server.
if Rails.application.config.x.server == :cougar
  # Propshaft memoizes lazily; warm it before ractorize! freezes the app.
  assets = Rails.application.assets
  assets.prefix
  assets.resolver

  Rails.application.ractorize!
end

run Rails.app
