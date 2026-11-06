class Post < ApplicationRecord
  # Association scopes (post.comments) aren't Ractor-safe in this Rails branch yet,
  # so comments are queried directly with Comment.where(post_id: ...) instead of has_many.
  before_destroy do
    Comment.where(post_id: id).delete_all
    Tagging.where(post_id: id).delete_all
  end
  before_save :update_derived_fields

  validates :title, presence: true
  validates :body, presence: true

  scope :recent, -> { order(id: :desc) }
  scope :published, -> { where.not(published_at: nil).where(published_at: ..Time.current) }

  # Front matter, stored as a JSON object in the metadata column.
  def settings
    @settings ||= metadata.present? ? JSON.parse(metadata, symbolize_names: true) : {}
  end

  def featured? = settings[:featured] == true
  def series = settings[:series]

  def rendered
    @rendered ||= Blog::Markdown.render(body)
  end

  def stats
    @stats ||= Blog::TextStats.new(body)
  end

  def excerpt(length = 240)
    plain = Blog::Markdown.plain_text(body)
    plain.length > length ? plain[0, length].sub(/\s+\S*\z/, "") + "…" : plain
  end

  def author
    @author ||= Author.find_by(id: author_id) if author_id
  end
  attr_writer :author

  def tags
    @tags ||= Tag.where(id: Tagging.where(post_id: id).select(:tag_id)).order(:name).to_a
  end
  attr_writer :tags

  # Posts sharing the most tags with this one.
  def related(limit = 5)
    tag_ids = Tagging.where(post_id: id).pluck(:tag_id)
    return [] if tag_ids.empty?

    ranked = Tagging.where(tag_id: tag_ids).where.not(post_id: id)
                    .group(:post_id).order(count_all: :desc, post_id: :desc).limit(limit).count
    posts = Post.where(id: ranked.keys).index_by(&:id)
    ranked.filter_map { |post_id, shared| [ posts[post_id], shared ] if posts[post_id] }
  end

  # Neighbouring posts by id, for "previous / next" links.
  def previous = Post.where(id: ...id).order(id: :desc).first
  def next = Post.where(id: (id + 1)..).order(:id).first

  private
    def update_derived_fields
      self.slug ||= title.to_s.parameterize.first(60)
      self.words_count = Blog::TextStats.new(body.to_s).words
    end
end
