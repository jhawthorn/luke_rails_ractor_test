# Gem state that has to be made Ractor-shareable before
# Rails.application.ractorize! hands the app over to the worker Ractors.
#
# Rails covers its own objects through the :before_ractorize load hooks; what is
# left is state belonging to gems that do not know about Ractors yet. A worker
# may not read an instance variable off a class the main Ractor created unless
# the value it holds is already shareable, so each one has to be frozen here
# while the main Ractor is still the only one running.
ActiveSupport.on_load(:before_ractorize) do
  # JbuilderTemplate#_render_partial reads this on every .json.jbuilder render.
  # It is a plain { handlers: [:jbuilder] } Hash and is only ever merged into a
  # caller-owned options Hash, never mutated in place.
  if defined?(::JbuilderTemplate)
    Ractor.make_shareable(::JbuilderTemplate.template_lookup_options)
  end

  # Builder (atom_feed, .builder templates) escapes text through lookup
  # tables held in constants (Builder::XChar::CP1252_DIFFERENCES and friends)
  # that are built at load time and never frozen. Action View only requires
  # it when the first .builder template compiles, so load it here.
  require "builder"
  begin
    [ ::Builder, ::Builder::XChar, *::Builder.constants.map { ::Builder.const_get(it) }.grep(Module) ].uniq.each do |mod|
      mod.constants(false).each do |name|
        value = mod.const_get(name)
        Ractor.make_shareable(value) unless value.is_a?(Module)
      end
    end
  end
end
