module ApplicationHelper
  def nav_link(label, path)
    css = current_page?(path) ? "active" : nil
    link_to label, path, class: css
  end

  def byline(post)
    parts = []
    parts << link_to(post.author.name, author_path(post.author)) if post.author
    parts << tag.time(l(post.published_at.to_date, format: :long), datetime: post.published_at.iso8601) if post.published_at
    parts << pluralize(post.stats.reading_minutes, "minute") + " read"
    safe_join(parts, " · ")
  end

  def tag_chips(tags)
    safe_join(tags.map { link_to(it.name, tag_path(it), class: "chip") }, " ")
  end

  def avatar(author, size: 32)
    tag.span(author.initials, class: "avatar", title: author.name,
             style: "background: #{author.avatar_color}; width: #{size}px; height: #{size}px; line-height: #{size}px")
  end

  # A horizontal bar for simple inline charts.
  def bar(value, max, label: nil)
    width = max.to_f.positive? ? (value * 100.0 / max).round(1) : 0
    tag.div(class: "bar") do
      tag.span("", class: "fill", style: "width: #{width}%") + tag.span(label || number_with_delimiter(value), class: "value")
    end
  end
end
