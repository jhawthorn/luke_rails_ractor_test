class TagsController < ApplicationController
  def index
    @tags = Tag.cloud(100)
    @max = @tags.map(&:last).max || 1
  end

  def show
    @tag = Tag.find_by!(slug: params.expect(:id))
    scope = Post.published.recent.where(id: Tagging.where(tag_id: @tag.id).select(:post_id))
    @posts = decorate(paginate(scope))
    # Tags that appear on the same posts as this one, most frequent first.
    post_ids = Tagging.where(tag_id: @tag.id).pluck(:post_id)
    counts = Tagging.where(post_id: post_ids).where.not(tag_id: @tag.id).group(:tag_id).count
    names = Tag.where(id: counts.keys).pluck(:id, :name, :slug).to_h { |id, *rest| [ id, rest ] }
    @co_tags = counts.sort_by { |id, n| [ -n, names[id][0] ] }.first(10).map { |id, n| [ *names[id], n ] }
  end
end
