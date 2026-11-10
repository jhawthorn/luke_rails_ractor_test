class HomeController < ApplicationController
  def index
    recent = Post.published.recent.limit(60).to_a
    @featured = recent.select(&:featured?).first(3)
    @posts = decorate(recent.first(15))
    @series = recent.group_by(&:series).except(nil).transform_values { it.size }
    @quote = Quote.random
  end
end
