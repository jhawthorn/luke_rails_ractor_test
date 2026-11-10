require "csv"

# CSV export of a list of posts, with their authors and tags.
class PostsExport
  HEADERS = %w[ id title author tags words reading_minutes reading_ease comments views published_at url ].freeze

  def initialize(posts)
    @posts = posts
  end

  def to_csv
    CSV.generate(headers: HEADERS, write_headers: true) do |csv|
      @posts.each do |post|
        stats = post.stats
        csv << [ post.id, post.title, post.author&.name, post.tags.map(&:name).join(";"), stats.words,
                 stats.reading_minutes, stats.reading_ease, post.comments_count, post.views_count,
                 post.published_at&.iso8601, "/posts/#{post.to_param}" ]
      end
    end
  end
end
