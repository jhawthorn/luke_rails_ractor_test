# frozen_string_literal: true

require "strscan"
require "cgi/escape"

module Blog
  # A small Markdown renderer covering what the seeded posts use: headings,
  # paragraphs, nested lists, block quotes, fenced code (highlighted by
  # Blog::Highlighter), tables, rules, and the usual inline markup.
  #
  # Written here rather than taken from a gem: kramdown and rouge keep
  # mutable class-level state (option defaults, lexer registries, procs) that
  # worker Ractors can't read. Everything below keeps its state per instance,
  # so it runs in any Ractor.
  class Markdown
    Heading = Data.define(:level, :text, :anchor)
    Result = Data.define(:html, :toc)

    LIST_ITEM = /\A(\s*)([-*+]|\d+\.)\s+(.*)\z/
    TABLE_SEPARATOR = /\A\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*\z/
    BLOCK_START = /\A(\#{1,6}\s|```|>|\s*([-*+]|\d+\.)\s|\||(-{3,}|\*{3,})\s*\z)/
    SAFE_URL = %r{\A(https?://|/|#|mailto:)}

    def self.render(source) = new(source).render

    # The text of a document without its markup, for excerpts and search.
    def self.plain_text(source)
      source.gsub(/^```.*?^```\s*$/m, " ")
            .gsub(/!?\[([^\]]*)\]\([^)]*\)/, '\1')
            .gsub(/[*_~`#>|]+/, "")
            .gsub(/^\s*([-+]|\d+\.)\s+/, "")
            .squeeze(" \n").strip
    end

    def initialize(source)
      @lines = source.to_s.lines(chomp: true)
      @toc = []
      @anchors = Hash.new(0)
    end

    def render
      Result.new(html: blocks(@lines), toc: @toc.freeze)
    end

    private
      def blocks(lines)
        out = +""
        i = 0
        while i < lines.size
          line = lines[i]
          case line
          when /\A\s*\z/
            i += 1
          when /\A(\#{1,6})\s+(.*?)\s*#*\z/
            out << heading($1.size, $2)
            i += 1
          when /\A```\s*([\w+-]*)\s*\z/
            lang = $1
            code, i = take_until(lines, i + 1) { it.start_with?("```") }
            out << Highlighter.block(code.join("\n"), lang)
            i += 1
          when /\A>/
            quoted, i = take_while(lines, i) { it.start_with?(">") }
            out << +"<blockquote>" << blocks(quoted.map { it.sub(/\A>\s?/, "") }) << "</blockquote>\n"
          when LIST_ITEM
            items, i = take_while(lines, i) { it.match?(LIST_ITEM) || it.match?(/\A\s{2,}\S/) }
            out << list(items)
          when /\A\|/
            if lines[i + 1]&.match?(TABLE_SEPARATOR)
              rows, i = take_while(lines, i) { it.start_with?("|") }
              out << table(rows)
            else
              out << paragraph([ line ])
              i += 1
            end
          when /\A(-{3,}|\*{3,})\s*\z/
            out << "<hr>\n"
            i += 1
          else
            para, i = take_while(lines, i) { !it.strip.empty? && !it.match?(BLOCK_START) }
            if para.empty?
              para = [ line ]
              i += 1
            end
            out << paragraph(para)
          end
        end
        out
      end

      def take_while(lines, i)
        start = i
        i += 1 while i < lines.size && yield(lines[i])
        [ lines[start...i], i ]
      end

      def take_until(lines, i, &block)
        take_while(lines, i) { !block.call(it) }
      end

      def heading(level, text)
        anchor = text.downcase.gsub(/[^a-z0-9\s-]/, "").strip.gsub(/\s+/, "-")
        anchor = "section" if anchor.empty?
        n = (@anchors[anchor] += 1)
        anchor = "#{anchor}-#{n}" if n > 1
        @toc << Heading.new(level:, text: Markdown.plain_text(text), anchor:) if level.between?(2, 3)
        %(<h#{level} id="#{anchor}">#{inline(text)}</h#{level}>\n)
      end

      def paragraph(lines)
        +"<p>" << inline(lines.map(&:strip).join(" ")) << "</p>\n"
      end

      # Nested lists, from the indentation of each item.
      def list(lines)
        items = []
        lines.each do |line|
          if (m = LIST_ITEM.match(line))
            items << { indent: m[1].size, ordered: m[2].end_with?("."), text: +m[3] }
          elsif items.any?
            items.last[:text] << " " << line.strip
          end
        end
        nest(items, 0, items.first[:indent])[0]
      end

      def nest(items, i, indent)
        tag = items[i][:ordered] ? "ol" : "ul"
        out = +"<#{tag}>\n"
        while i < items.size && items[i][:indent] >= indent
          item = items[i]
          out << "<li>" << task(item[:text])
          i += 1
          if i < items.size && items[i][:indent] > item[:indent]
            inner, i = nest(items, i, items[i][:indent])
            out << "\n" << inner
          end
          out << "</li>\n"
        end
        [ out << "</#{tag}>\n", i ]
      end

      def task(text)
        case text
        when /\A\[ \]\s+(.*)/ then %(<input type="checkbox" disabled> ) + inline($1)
        when /\A\[x\]\s+(.*)/i then %(<input type="checkbox" checked disabled> ) + inline($1)
        else inline(text)
        end
      end

      def table(rows)
        cells = rows.map { |row| row.strip.delete_prefix("|").delete_suffix("|").split("|").map(&:strip) }
        header, separator, *body = cells
        aligns = separator.map do |s|
          if s.start_with?(":") && s.end_with?(":") then "center"
          elsif s.end_with?(":") then "right"
          elsif s.start_with?(":") then "left"
          end
        end
        cell = ->(tag, text, col) do
          style = aligns[col] ? %( style="text-align: #{aligns[col]}") : ""
          "<#{tag}#{style}>#{inline(text)}</#{tag}>"
        end
        out = +"<table>\n<thead><tr>"
        header.each_with_index { |text, col| out << cell.(:th, text, col) }
        out << "</tr></thead>\n<tbody>\n"
        body.each do |row|
          out << "<tr>"
          header.size.times { |col| out << cell.(:td, row[col].to_s, col) }
          out << "</tr>\n"
        end
        out << "</tbody>\n</table>\n"
      end

      def inline(text)
        s = StringScanner.new(text)
        out = +""
        until s.eos?
          if s.scan(/`([^`]+)`/)
            out << "<code>" << escape(s[1]) << "</code>"
          elsif s.scan(/\*\*(?=\S)(.+?)(?<=\S)\*\*/)
            out << "<strong>" << inline(s[1]) << "</strong>"
          elsif s.scan(/\*(?=\S)(.+?)(?<=\S)\*/) || s.scan(/(?<!\w)_(?=\S)(.+?)(?<=\S)_(?!\w)/)
            out << "<em>" << inline(s[1]) << "</em>"
          elsif s.scan(/~~(?=\S)(.+?)(?<=\S)~~/)
            out << "<del>" << inline(s[1]) << "</del>"
          elsif s.scan(/!\[([^\]]*)\]\(([^)\s]+)\)/)
            out << %(<img src="#{url(s[2])}" alt="#{escape(s[1])}" loading="lazy">)
          elsif s.scan(/\[([^\]]+)\]\(([^)\s]+)\)/)
            out << %(<a href="#{url(s[2])}">#{inline(s[1])}</a>)
          elsif s.scan(%r{https?://[^\s<>()]+[^\s<>().,;:!?]})
            out << %(<a href="#{url(s[0])}">#{escape(s[0])}</a>)
          else
            out << escape(s.scan(/[^`*_~!\[h]+/) || s.getch)
          end
        end
        out
      end

      def url(href)
        href.match?(SAFE_URL) ? escape(href) : "#"
      end

      def escape(text) = CGI.escapeHTML(text)
  end
end
