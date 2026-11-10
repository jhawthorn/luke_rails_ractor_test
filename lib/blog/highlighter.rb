# frozen_string_literal: true

require "prism"
require "set"
require "strscan"
require "cgi/escape"

module Blog
  # Syntax highlighting for fenced code blocks. Ruby is tokenized with Prism;
  # other languages go through a small keyword/regex scanner.
  module Highlighter
    # Prism token types mapped onto the CSS classes in the layout.
    RUBY_CLASSES = {
      COMMENT: "c", EMBDOC_BEGIN: "c", EMBDOC_LINE: "c", EMBDOC_END: "c",
      CONSTANT: "t", INSTANCE_VARIABLE: "v", CLASS_VARIABLE: "v", GLOBAL_VARIABLE: "v",
      INTEGER: "n", FLOAT: "n", RATIONAL_NUMBER: "n", IMAGINARY_NUMBER: "n",
      STRING_BEGIN: "s", STRING_CONTENT: "s", STRING_END: "s", CHARACTER_LITERAL: "s",
      HEREDOC_START: "s", HEREDOC_END: "s", REGEXP_BEGIN: "r", REGEXP_END: "r",
      SYMBOL_BEGIN: "y", LABEL: "y", LABEL_END: "y",
      METHOD_NAME: "f", EMBEXPR_BEGIN: "o", EMBEXPR_END: "o"
    }.freeze

    KEYWORDS = {
      "sql" => %w[select from where and or not in is null order by group having limit offset join left
                  inner outer on as insert into values update set delete create table index primary key
                  references distinct count sum avg min max case when then else end with union desc asc],
      "javascript" => %w[const let var function return if else for while of in new class extends import
                         export from default async await try catch finally throw this null undefined true false typeof],
      "shell" => %w[if then else fi for do done while case esac in function export local return echo cd],
      "yaml" => %w[true false null yes no],
      "json" => %w[true false null]
    }.transform_values { Set.new(it).freeze }.freeze
    ALIASES = { "js" => "javascript", "sh" => "shell", "bash" => "shell", "console" => "shell", "yml" => "yaml" }.freeze
    COMMENTS = { "sql" => /--[^\n]*/, "javascript" => %r{//[^\n]*}, "shell" => /#[^\n]*/, "yaml" => /#[^\n]*/ }.freeze

    module_function

    def block(code, lang)
      lang = ALIASES.fetch(lang.downcase, lang.downcase)
      body =
        case lang
        when "ruby", "rb" then ruby(code)
        when *KEYWORDS.keys then generic(code, lang)
        else escape(code)
        end
      label = lang.empty? ? "" : %( data-lang="#{escape(lang)}")
      %(<pre class="code"#{label}><code>#{body}</code></pre>\n)
    end

    def ruby(code)
      result = Prism.lex(code)
      return escape(code) if result.failure?

      bytes = code.b
      out = +""
      pos = 0
      prev_type = nil
      result.value.each do |token, _state|
        type = token.type
        break if type == :EOF

        start = token.location.start_offset
        stop = token.location.end_offset
        next if start < pos # heredoc bodies are reported out of order

        out << escape(utf8(bytes.byteslice(pos, start - pos))) if start > pos
        text = escape(utf8(bytes.byteslice(start, stop - start)))
        css = RUBY_CLASSES[type] || (type.start_with?("KEYWORD_") ? "k" : nil)
        css ||= "f" if type == :IDENTIFIER && prev_type == :KEYWORD_DEF
        out << (css ? %(<span class="#{css}">#{text}</span>) : text)
        pos = stop
        prev_type = type
      end
      out << escape(utf8(bytes.byteslice(pos..))) if pos < bytes.bytesize
      out
    end

    def generic(code, lang)
      keywords = KEYWORDS.fetch(lang)
      comment = COMMENTS[lang]
      s = StringScanner.new(code)
      out = +""
      until s.eos?
        if comment && s.scan(comment)
          out << span("c", s[0])
        elsif s.scan(/"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'/)
          out << span(lang == "json" && s.check(/\s*:/) ? "y" : "s", s[0])
        elsif s.scan(/\b\d+(\.\d+)?\b/)
          out << span("n", s[0])
        elsif s.scan(/[A-Za-z_$][\w$]*/)
          word = s[0]
          out << (keywords.include?(word.downcase) ? span("k", word) : escape(word))
        elsif lang == "yaml" && s.scan(/^\s*[\w-]+(?=:)/)
          out << span("y", s[0])
        else
          out << escape(s.getch)
        end
      end
      out
    end

    def span(css, text) = %(<span class="#{css}">#{escape(text)}</span>)
    def escape(text) = CGI.escapeHTML(text)
    def utf8(bytes) = bytes.force_encoding(Encoding::UTF_8)
  end
end
