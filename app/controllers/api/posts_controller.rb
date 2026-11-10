module Api
  class PostsController < ActionController::API
    def index
      posts = Post.published.recent.limit(25).to_a
      authors = Author.index_for(posts.map(&:author_id))
      tags = Tag.by_post(posts.map(&:id))
      payload = posts.map do |post|
        { id: post.id, title: post.title, slug: post.slug, excerpt: post.excerpt(160),
          author: authors[post.author_id]&.then { { name: it.name, handle: it.handle } },
          tags: tags.fetch(post.id, []).map(&:name), words: post.words_count,
          comments: post.comments_count, views: post.views_count, settings: post.settings,
          published_at: post.published_at }
      end
      body = JSON.generate({ posts: payload, count: payload.size })
      response.headers["ETag"] = %("#{Digest::SHA256.hexdigest(body)[0, 32]}")
      render json: body
    end

    def show
      post = Post.find(params.expect(:id))
      render json: { id: post.id, title: post.title, html: post.rendered.html,
                     toc: post.rendered.toc.map(&:to_h), stats: { words: post.stats.words,
                     reading_ease: post.stats.reading_ease, top_terms: post.stats.top_terms.to_h } }
    end
  end
end
