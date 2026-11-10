module Api
  class StatsController < ActionController::API
    def show
      render json: SiteStats.new
    end
  end
end
