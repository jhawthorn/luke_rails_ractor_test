# The data behind the sidebar on every HTML page. Building it takes half a
# dozen aggregate queries, so it lives in Rails.cache (a file store) for a few
# seconds at a time.
class Sidebar < Data.define(:tags, :archive, :authors, :recent_comments, :totals, :built_at)
  TTL = 5 # seconds

  def self.fetch
    Rails.cache.fetch("sidebar/v1", expires_in: TTL, race_condition_ttl: 2.seconds) { build }
  end

  def self.build
    counts = Tagging.group(:tag_id).count
    tags = Tag.where(id: counts.keys).pluck(:id, :name, :slug)
              .map { |id, name, slug| { name:, slug:, count: counts[id] } }
              .max_by(20) { it[:count] }.sort_by { it[:name] }

    archive = Post.published.pluck(:published_at).group_by { it.beginning_of_month.to_date }
                  .map { |month, dates| [ month, dates.size ] }.sort.reverse.first(12)

    by_author = Post.published.group(:author_id).sum(:words_count)
    authors = Author.where(id: by_author.keys).pluck(:id, :name, :handle)
                    .map { |id, name, handle| { name:, handle:, words: by_author[id] } }
                    .max_by(5) { it[:words] }

    recent_comments = Comment.order(id: :desc).limit(5).pluck(:post_id, :author, :body, :created_at)
                             .map { |post_id, author, body, at| { post_id:, author:, body: body.truncate(80), at: } }

    totals = { posts: Post.published.count, comments: Comment.count, words: Post.sum(:words_count),
               views: PageView.count }

    new(tags:, archive:, authors:, recent_comments:, totals:, built_at: Time.current)
  end
end
