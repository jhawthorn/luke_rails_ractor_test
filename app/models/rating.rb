# Summary of the 1-5 star ratings left in a post's comments.
class Rating
  attr_reader :scores

  def initialize(scores)
    @scores = scores
  end

  def count = scores.size
  def any? = scores.any?

  # Kept as a BigDecimal so the mean rounds the way a person would expect.
  def average
    return nil if scores.empty?
    (BigDecimal(scores.sum) / scores.size).round(2)
  end

  # { 5 => 12, 4 => 3, ... } including the stars nobody gave.
  def distribution
    tally = scores.tally
    5.downto(1).to_h { [ it, tally.fetch(it, 0) ] }
  end

  def stars = average ? ("★" * average.round + "☆" * (5 - average.round)) : ""
end
