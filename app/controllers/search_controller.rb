class SearchController < ApplicationController
  def index
    @query = params[:q].to_s.strip.first(100)
    @terms = @query.downcase.scan(/[\p{Alnum}']+/).uniq.first(5)
    return @results = [] if @terms.empty?

    scope = Post.published
    @terms.each do |term|
      pattern = "%#{Post.sanitize_sql_like(term)}%"
      scope = scope.where("title LIKE :p OR body LIKE :p", p: pattern)
    end
    candidates = scope.limit(200).to_a
    @total = candidates.size
    # Rank in Ruby: title hits count more than body hits, newer posts break ties.
    pattern = Regexp.union(@terms.map { Regexp.new("\\b#{Regexp.escape(it)}", Regexp::IGNORECASE) })
    ranked = candidates.map do |post|
      score = post.title.scan(pattern).size * 5 + Blog::Markdown.plain_text(post.body).scan(pattern).size
      [ score, post.published_at, post ]
    end.sort_by { |score, at, _| [ -score, -at.to_i ] }
    @results = decorate(ranked.first(20).map(&:last)).map do |post|
      { post:, score: ranked.find { it.last.equal?(post) }.first, snippet: Snippet.new(post.body, pattern) }
    end
  end
end
