require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module RailsRactorTest
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.2

    # load_defaults 8.2 switches to Herb; stay on Erubi.
    config.action_view.erb_implementation = :erubi

    # Which web server this process is booting under; set by bin/server.
    # Drives the Ractor-only bits of the config: the shareable logger in
    # config/environments/production.rb and ractorize! in config.ru.
    config.x.server = ENV.fetch("RAILS_SERVER", "cougar").to_sym

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
