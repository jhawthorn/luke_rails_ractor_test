class FeedsController < ApplicationController
  def show
    @posts = decorate(Post.published.recent.limit(20).to_a)
    respond_to do |format|
      format.atom
    end
  end
end
