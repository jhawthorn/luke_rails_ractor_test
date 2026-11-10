# frozen_string_literal: true

require "set"

module Blog
  # Readability numbers for a Markdown document: word and sentence counts,
  # reading time, the Flesch reading-ease score and the most frequent terms.
  class TextStats
    WORDS_PER_MINUTE = 230
    STOP_WORDS = Set.new(%w[
      a an and are as at be but by for from has have i if in into is it its of on or so
      that the their then there these this to was we were what when which will with you
      your can each one own not no our more than just also all any only very
    ]).freeze

    attr_reader :text

    def initialize(markdown)
      @text = Markdown.plain_text(markdown)
    end

    def word_list = @word_list ||= text.downcase.scan(/[a-z][a-z']*/)
    def words = word_list.size
    def sentences = [ text.scan(/[^.!?]+[.!?]+/).size, 1 ].max
    def reading_minutes = [ (words / WORDS_PER_MINUTE.to_f).ceil, 1 ].max

    def syllables
      @syllables ||= word_list.sum do |word|
        count = word.sub(/(?:[^laeiouy]es|ed|[^laeiouy]e)\z/, "").scan(/[aeiouy]{1,2}/).size
        count.clamp(1, 8)
      end
    end

    # 206.835 - 1.015 (words / sentences) - 84.6 (syllables / words)
    def reading_ease
      return 100.0 if words.zero?
      (206.835 - 1.015 * (words.to_f / sentences) - 84.6 * (syllables.to_f / words)).round(1)
    end

    def top_terms(limit = 8)
      word_list.reject { it.size < 4 || STOP_WORDS.include?(it) }
               .tally.max_by(limit) { |word, n| [ n, word ] }
    end
  end
end
