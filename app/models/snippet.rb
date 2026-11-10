# The part of a document around the first match of `pattern`, with every
# match wrapped in <mark>.
class Snippet
  RADIUS = 120

  def initialize(markdown, pattern)
    @text = Blog::Markdown.plain_text(markdown)
    @pattern = pattern
  end

  def to_html
    at = @text =~ @pattern || 0
    from = [ at - RADIUS, 0 ].max
    from = @text.index(" ", from)&.succ || from if from > 0
    piece = @text[from, RADIUS * 2]
    html = ERB::Util.html_escape(piece).to_str.gsub(@pattern) { "<mark>#{it}</mark>" }
    ((from > 0 ? "…" : "") + html + (from + piece.size < @text.size ? "…" : "")).html_safe
  end
end
