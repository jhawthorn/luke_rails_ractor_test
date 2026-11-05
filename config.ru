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

  # Rails, Rack and gems often store a value in a constant or class ivar and
  # #freeze it later. Workers may only read such values once they are flagged
  # shareable, and freezing no longer flags a value that was stored earlier.
  # Ractor.shareable? flags a fully frozen graph as shareable without freezing
  # anything, so ask it about every class-level value now.
  ObjectSpace.each_object(Module) do |mod|
    mod.instance_variables.each { |ivar| Ractor.shareable?(mod.instance_variable_get(ivar)) }
    mod.constants(false).each do |name|
      next if mod.autoload?(name, false)
      Ractor.shareable?(mod.const_get(name, false))
    rescue NameError, LoadError
    end
  end
end

run Rails.app
