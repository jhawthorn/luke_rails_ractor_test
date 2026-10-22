class Comment < ApplicationRecord
  # No belongs_to: loading an association isn't Ractor-safe in this Rails branch yet,
  # so the post is referenced by post_id and the counter cache is kept by hand.
  validates :post_id, presence: true
  validates :author, presence: true
  validates :body, presence: true

  # Keeps posts.comments_count current so the index needs no count query.
  after_create { Post.increment_counter(:comments_count, post_id) }
  after_destroy { Post.decrement_counter(:comments_count, post_id) }
end
