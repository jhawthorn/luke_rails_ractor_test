class StatsController < ApplicationController
  def index
    @stats = SiteStats.new
  end
end
