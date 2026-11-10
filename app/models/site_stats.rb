# Aggregates for the stats page and the stats API, computed in Ruby from a
# handful of plucks.
class SiteStats
  def initialize(now: Time.current)
    @now = now
  end

  def words = @words ||= Post.published.pluck(:words_count).sort

  def percentiles
    [ 50, 90, 99 ].to_h { |p| [ "p#{p}", percentile(words, p) ] }
      .merge("min" => words.first, "max" => words.last, "mean" => mean(words).round(1))
  end

  # Word counts bucketed by 100.
  def histogram
    words.group_by { it / 100 * 100 }.transform_values(&:size).sort.to_h
  end

  def monthly
    Post.published.pluck(:published_at, :words_count, :comments_count)
        .group_by { |at, *| at.strftime("%Y-%m") }
        .transform_values { |rows| { posts: rows.size, words: rows.sum { it[1] }, comments: rows.sum { it[2] } } }
        .sort.last(12).to_h
  end

  def ratings
    scores = Comment.where.not(rating: nil).pluck(:rating)
    Rating.new(scores)
  end

  def most_viewed(limit = 10)
    Post.order(views_count: :desc, id: :asc).limit(limit).pluck(:id, :title, :views_count)
  end

  def views_by_hour = PageView.hourly(24, now: @now)

  def busiest_commenters
    Comment.group(:author).order(count_all: :desc).limit(8).count
  end

  # Database files on disk: one stat() per file.
  def storage
    Dir.glob(Rails.root.join("storage", "*.sqlite3*")).sort.to_h { [ File.basename(it), File.size(it) ] }
  end

  def as_json(*)
    { generated_at: @now.iso8601, words: percentiles, histogram:, monthly:,
      ratings: { average: ratings.average&.to_f, distribution: ratings.distribution },
      most_viewed: most_viewed.map { |id, title, views| { id:, title:, views: } },
      views_by_hour: views_by_hour.map { |at, n| [ at.iso8601, n ] }, storage: }
  end

  private
    def percentile(sorted, p)
      return 0 if sorted.empty?
      rank = (p / 100.0) * (sorted.size - 1)
      lower, upper = sorted[rank.floor], sorted[rank.ceil]
      (lower + (upper - lower) * (rank - rank.floor)).round
    end

    def mean(values) = values.empty? ? 0 : values.sum.fdiv(values.size)
end
