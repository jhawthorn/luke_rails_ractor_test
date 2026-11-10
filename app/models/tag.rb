class Tag < ApplicationRecord
  validates :name, :slug, presence: true

  def to_param = slug

  # [[Tag, posts_count], ...] for the most used tags.
  def self.cloud(limit = 30)
    counts = Tagging.group(:tag_id).order(count_all: :desc).limit(limit).count
    tags = where(id: counts.keys).index_by(&:id)
    counts.filter_map { |id, n| [ tags[id], n ] if tags[id] }.sort_by { |t, _| t.name }
  end

  # { post_id => [Tag, ...] } for the given posts, in one query.
  def self.by_post(post_ids)
    rows = Tagging.where(post_id: post_ids).pluck(:post_id, :tag_id)
    tags = where(id: rows.map(&:last).uniq).index_by(&:id)
    rows.group_by(&:first).transform_values { |pairs| pairs.map { tags[it.last] }.sort_by(&:name) }
  end
end
