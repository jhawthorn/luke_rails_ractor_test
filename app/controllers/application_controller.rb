class ApplicationController < ActionController::Base
  PER_PAGE = 20

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :sidebar
  before_action { @started_us = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond) }

  private
    def page
      @page ||= [ params[:page].to_i, 1 ].max
    end

    # Loads one page of `scope` into @pagination; returns its records.
    def paginate(scope, per: PER_PAGE)
      total = scope.count
      @pagination = Pagination.new(page:, per:, total:)
      scope.offset(@pagination.offset).limit(per).to_a
    end

    # Rendered on every HTML page. Rebuilt at most every Sidebar::TTL from the
    # database and otherwise read back from the file cache store.
    def sidebar
      @sidebar ||= Sidebar.fetch
    end

    # Writes one page_views row and bumps the post's counter: two small writes
    # (three statements, with the transaction around the create) per post page.
    def record_view(post_id = nil)
      PageView.create!(post_id:, path: request.path, user_agent: request.user_agent.to_s.first(200),
                       remote_ip: request.remote_ip, created_at: Time.current,
                       duration_us: Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond) - @started_us)
      Post.update_counters(post_id, views_count: 1) if post_id
    end

    # Authors and tags for a list of posts, two queries in total.
    def decorate(posts)
      authors = Author.index_for(posts.map(&:author_id))
      tags = Tag.by_post(posts.map(&:id))
      posts.each do |post|
        post.author = authors[post.author_id]
        post.tags = tags.fetch(post.id, [])
      end
    end
end
