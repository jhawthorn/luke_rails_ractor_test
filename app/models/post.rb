class Post < ApplicationRecord
  # Association scopes (post.comments) aren't Ractor-safe in this Rails branch yet,
  # so comments are queried directly with Comment.where(post_id: ...) instead of has_many.
  before_destroy { Comment.where(post_id: id).delete_all }

  validates :title, presence: true
  validates :body, presence: true

  scope :recent, -> { order(id: :desc) }
end
