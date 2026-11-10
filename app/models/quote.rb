# A random quote for the home page, read from content/quotes.txt on every call
# (a small file read per request, on purpose).
class Quote < Data.define(:text, :who)
  PATH = Rails.root.join("content", "quotes.txt").to_s.freeze

  def self.all
    File.foreach(PATH, chomp: true).filter_map do |line|
      next if line.empty? || line.start_with?("#")
      text, who = line.split(" -- ", 2)
      new(text:, who: who || "Anonymous")
    end
  end

  def self.random(rng: Random) = all.sample(random: rng)
end
