class AuthorsController < ApplicationController
  def index
    @authors = Author.order(:name).to_a
    rows = Post.published.group(:author_id).pluck(:author_id, Arel.sql("COUNT(*)"), Arel.sql("SUM(words_count)"),
                                                  Arel.sql("SUM(comments_count)"), Arel.sql("MAX(published_at)"))
    @totals = rows.to_h { |id, posts, words, comments, last| [ id, { posts:, words:, comments:, last: } ] }
  end

  def show
    @author = Author.find_by!(handle: params.expect(:id))
    posts = Post.published.where(author_id: @author.id).recent.to_a
    @posts = decorate(posts.first(10))
    stats = posts.map(&:stats)
    @summary = {
      posts: posts.size,
      words: stats.sum(&:words),
      reading_minutes: stats.sum(&:reading_minutes),
      reading_ease: stats.empty? ? 0 : (stats.sum(&:reading_ease) / stats.size).round(1),
      comments: posts.sum(&:comments_count)
    }
    @top_terms = stats.flat_map(&:word_list)
                      .reject { it.size < 5 || Blog::TextStats::STOP_WORDS.include?(it) }
                      .tally.max_by(12) { |word, n| [ n, word ] }
    @activity = posts.group_by { it.published_at.strftime("%Y-%m") }.transform_values(&:size).sort.last(12)
    @tags = Tag.by_post(posts.map(&:id)).values.flatten.map(&:name).tally.max_by(8) { |name, n| [ n, name ] }
  end
end
