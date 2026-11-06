# Seed enough data to make the pages worth benchmarking.
# Run with: bin/rails db:seed   (set POSTS / COMMENTS to change the volume, RESEED=1 to start over)
#
# Everything is generated from a fixed Random seed, so every database built
# from this file has the same content and the benchmarks stay comparable.
if ENV["RESEED"]
  [ PageView, Tagging, Comment, Post, Tag, Author ].each(&:delete_all)
elsif Post.where.not(author_id: nil).count > 10
  return
end

rng = Random.new(42)
posts_count    = ENV.fetch("POSTS", 300).to_i
comments_count = ENV.fetch("COMMENTS", 20).to_i
now = Time.current.change(usec: 0)

author_names = [ "Alice Archer", "Bob Baker", "Carol Chen", "Dave Diaz", "Erin Evans", "Frank Fischer",
                 "Grace Gupta", "Heidi Hall", "Ivan Ito", "Judy Jones", "Ken Kim", "Lena Larsen" ]
authors = author_names.each_with_index.map do |name, i|
  handle = name.split.first.downcase
  { name:, handle:, email: "#{handle}@example.com", joined_on: Date.new(2019, 1, 1) + (i * 97),
    bio: "#{name.split.first} writes about #{%w[concurrency databases web performance tooling Ruby][i % 6]} " \
         "and has been programming for #{4 + i} years.", created_at: now, updated_at: now }
end
Author.insert_all(authors)
author_ids = Author.order(:id).pluck(:id)

tag_names = %w[ruby rails ractors performance concurrency gc yjit sqlite http testing profiling
               memory parsing prism benchmarks threads fibers io networking security caching json
               csv markdown tooling deployment linux macos debugging api]
Tag.insert_all(tag_names.map { { name: it, slug: it, created_at: now, updated_at: now } })
tag_ids = Tag.order(:id).pluck(:id)

sentences = [
  "Ractors give Ruby real parallelism, because each one runs under its own lock.",
  "Objects can only be shared between Ractors once they are deeply frozen.",
  "The garbage collector still has to stop every Ractor to mark the heap.",
  "Profiling with samply shows where the time goes, down to the C function.",
  "A request spends most of its time rendering templates and building strings.",
  "SQLite is fast enough here that the database is rarely the bottleneck.",
  "Moving state into Ractor-local storage avoids taking the VM lock on every call.",
  "Method caches are per class, so a cache miss in one Ractor can slow the others down.",
  "Throughput scales with the number of cores until the shared locks start to dominate.",
  "Every allocation counts when ten workers allocate in parallel.",
  "YJIT compiles hot methods to machine code and the compiled code is shared.",
  "Benchmarks are only useful when the machine is otherwise idle.",
  "Keep-alive connections let the load generator reuse one socket for many requests.",
  "Frozen string literals save allocations and make constants shareable.",
  "The logger runs in its own Ractor and receives messages from the workers."
].freeze
code_blocks = [
  [ "ruby", <<~RUBY ],
    class Counter
      def initialize = @count = 0

      def increment(by: 1)
        @count += by # not shared between Ractors
      end
    end

    workers = 4.times.map do |i|
      Ractor.new(i) { |n| Counter.new.tap { it.increment(by: n) } }
    end
    puts workers.map(&:value).inspect
  RUBY
  [ "ruby", <<~RUBY ],
    CONFIG = Ractor.make_shareable({ timeout: 5, retries: [1, 2, 4] })

    def fetch(url, attempts: CONFIG[:retries])
      attempts.each_with_index do |delay, i|
        return yield(url) rescue sleep(delay * 0.01)
      end
      nil
    end
  RUBY
  [ "sql", <<~SQL ],
    SELECT posts.id, posts.title, COUNT(comments.id) AS comments
    FROM posts
    LEFT JOIN comments ON comments.post_id = posts.id
    WHERE posts.published_at IS NOT NULL
    GROUP BY posts.id
    ORDER BY comments DESC
    LIMIT 10;
  SQL
  [ "javascript", <<~JS ],
    const results = await Promise.all(urls.map(async (url) => {
      const response = await fetch(url); // one request per URL
      return { url, status: response.status };
    }));
  JS
  [ "shell", <<~SH ],
    # Profile 30 seconds of traffic
    samply record --save-only -o profile.json.gz bin/server &
    oha -c 10 -z 30s http://localhost:3030/
  SH
  [ "yaml", <<~YAML ]
    production:
      adapter: sqlite3
      timeout: 5000 # milliseconds
      max_connections: 16
  YAML
].freeze

paragraph = ->(n) { Array.new(n) { sentences[rng.rand(sentences.size)] }.join(" ") }
body_for = lambda do |i|
  parts = [ paragraph.(3 + rng.rand(3)) ]
  (2 + rng.rand(3)).times do |s|
    parts << "## #{%w[Background Approach Results Measurements Caveats Notes Next\ steps][(i + s) % 7]}"
    parts << paragraph.(2 + rng.rand(4))
    case rng.rand(5)
    when 0
      lang, code = code_blocks[rng.rand(code_blocks.size)]
      parts << "```#{lang}\n#{code}```"
    when 1
      parts << Array.new(3 + rng.rand(3)) { "- #{sentences[rng.rand(sentences.size)]}" }.join("\n") +
               "\n  - a nested point with `inline code`"
    when 2
      rows = Array.new(4) { |w| "| #{2**w} | #{(600 * 2**w * (0.9**w)).round} | #{rng.rand(1..9)}.#{rng.rand(10)} ms |" }
      parts << "| Workers | req/s | p99 |\n|--------:|------:|:----|\n#{rows.join("\n")}"
    when 3
      parts << "> #{paragraph.(2)}\n> — *someone on the mailing list*"
    else
      parts << "1. Read the [docs](https://docs.ruby-lang.org/en/master/Ractor.html)\n" \
               "2. Try it with **#{rng.rand(2..16)} workers**\n3. [x] Measure\n4. [ ] Repeat"
    end
  end
  parts.join("\n\n") + "\n"
end

posts = Array.new(posts_count) do |i|
  body = body_for.(i)
  title = "#{%w[Notes Thoughts Lessons Experiments Questions][i % 5]} on #{tag_names[i % tag_names.size]}, part #{i / tag_names.size + 1}"
  published = now - (posts_count - i) * 7.hours
  metadata = { featured: (i % 17).zero?, series: (i % 4).zero? ? "Ractor diaries" : nil,
               license: %w[CC-BY-4.0 MIT All-rights-reserved][i % 3], summary: sentences[i % sentences.size] }.compact
  { title:, body:, slug: "#{title.parameterize}-#{i + 1}", author_id: author_ids[rng.rand(author_ids.size)],
    published_at: (i % 23).zero? ? nil : published, words_count: Blog::TextStats.new(body).words,
    metadata: metadata.to_json, views_count: 0, created_at: published, updated_at: published }
end
Post.insert_all(posts)
post_ids = Post.order(:id).pluck(:id)

taggings = post_ids.flat_map do |post_id|
  tag_ids.sample(2 + rng.rand(4), random: rng).map { { post_id:, tag_id: it } }
end
Tagging.insert_all(taggings)

commenters = %w[alice bob carol dave erin frank grace heidi ivan judy]
comments = post_ids.flat_map do |post_id|
  Array.new(rng.rand(comments_count / 2..comments_count)) do |j|
    { post_id:, author: commenters[rng.rand(commenters.size)], rating: rng.rand(6).nonzero?,
      body: "Comment #{j + 1}. #{paragraph.(1 + rng.rand(3))}", created_at: now - j.minutes, updated_at: now }
  end
end
comments.each_slice(5000) { Comment.insert_all(it) }
# insert_all skips counter caches, so set them from the data.
Comment.group(:post_id).count.each { |post_id, n| Post.where(id: post_id).update_all(comments_count: n) }

puts "Seeded #{Author.count} authors, #{Tag.count} tags, #{Post.count} posts, " \
     "#{Tagging.count} taggings and #{Comment.count} comments"
