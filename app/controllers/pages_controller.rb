# Static pages written in Markdown under content/pages, read from disk and
# rendered on every request.
class PagesController < ApplicationController
  ROOT = Rails.root.join("content", "pages").to_s.freeze

  def show
    name = params.expect(:id)
    raise ActionController::RoutingError, "No page #{name}" unless name.match?(/\A[a-z0-9-]+\z/)

    path = File.join(ROOT, "#{name}.md")
    raise ActionController::RoutingError, "No page #{name}" unless File.file?(path)

    front, body = File.read(path).split(/^---\s*$/, 3).values_at(1, 2)
    @meta = front.to_s.scan(/^(\w+):\s*(.*)$/).to_h.transform_keys(&:to_sym)
    @page = Blog::Markdown.render(body || "")
    @updated_at = File.mtime(path)
  end
end
