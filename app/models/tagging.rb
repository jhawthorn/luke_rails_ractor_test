class Tagging < ApplicationRecord
  validates :post_id, :tag_id, presence: true
end
