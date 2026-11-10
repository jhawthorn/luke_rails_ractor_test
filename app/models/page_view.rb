class PageView < ApplicationRecord
  # Views per hour over the last `hours` hours, oldest first, with empty hours as 0.
  def self.hourly(hours = 24, now: Time.current)
    since = (now - (hours - 1).hours).beginning_of_hour
    counts = where(created_at: since..).group("strftime('%Y-%m-%d %H:00', created_at)").count
    Array.new(hours) do |i|
      at = since + i.hours
      [ at, counts.fetch(at.utc.strftime("%Y-%m-%d %H:00"), 0) ]
    end
  end
end
