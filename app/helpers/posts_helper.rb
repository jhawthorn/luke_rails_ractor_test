module PostsHelper
  def reading_ease_label(score)
    case score
    when 90.. then "very easy"
    when 70...90 then "easy"
    when 50...70 then "fairly difficult"
    when 30...50 then "difficult"
    else "very difficult"
    end
  end

  def toc(headings)
    return "" if headings.empty?
    items = headings.map do |h|
      tag.li(link_to(h.text, "##{h.anchor}"), class: "toc-#{h.level}")
    end
    tag.nav(tag.ol(safe_join(items)), class: "toc")
  end
end
