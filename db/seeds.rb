# Seed enough data to make the pages worth benchmarking.
# Run with: bin/rails db:seed   (set POSTS / COMMENTS to change the volume)
return if Post.count > 10

posts_count    = ENV.fetch("POSTS", 200).to_i
comments_count = ENV.fetch("COMMENTS", 25).to_i
authors = %w[ alice bob carol dave erin frank grace heidi ]
paragraph = "Ractors give Ruby real parallelism. Each one has its own GVL, so request handling can use every core. "

now = Time.current
posts = Array.new(posts_count) do |i|
  { title: "Post #{i + 1}: notes on parallel Ruby",
    body: (paragraph * (3 + i % 5)).strip,
    created_at: now - (posts_count - i).hours, updated_at: now }
end
Post.insert_all(posts)

comments = Post.pluck(:id).flat_map do |post_id|
  Array.new(comments_count) do |j|
    { post_id: post_id, author: authors[j % authors.size],
      body: "Comment #{j + 1}. #{paragraph}", created_at: now - j.minutes, updated_at: now }
  end
end
Comment.insert_all(comments)
# insert_all skips counter caches, so set them directly.
Post.update_all(comments_count: comments_count)

puts "Seeded #{Post.count} posts and #{Comment.count} comments"
