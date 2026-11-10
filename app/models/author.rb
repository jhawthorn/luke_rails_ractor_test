class Author < ApplicationRecord
  # Posts are looked up with Post.where(author_id: ...) rather than has_many;
  # association loading isn't Ractor-safe in this Rails branch yet.
  validates :name, :handle, :email, presence: true
  validates :handle, format: { with: /\A[a-z0-9_]+\z/ }

  def to_param = handle

  def avatar_color
    # A stable color per author, derived from a digest of the email.
    "#" + Digest::MD5.hexdigest(email.downcase)[0, 6]
  end

  def initials = name.split.map { it[0] }.join.upcase

  # { author_id => Author } for the given ids, in one query.
  def self.index_for(ids) = where(id: ids.uniq).index_by(&:id)
end
