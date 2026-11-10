# Unicorn configuration for the RAILS_SERVER=unicorn benchmark target.
#
# This is the forking counterpart to the cougar (Ractor) setup: the same app,
# the same number of request-serving units, one request in flight per unit.
# Cougar runs N Ractors in one process; unicorn runs N single-threaded worker
# processes. WEB_CONCURRENCY here plays the role of cougar's -w.
#
#   RAILS_SERVER=unicorn bin/server
#   RAILS_SERVER=unicorn WEB_CONCURRENCY=10 PORT=3030 bin/server

app_root = File.expand_path("..", __dir__)

working_directory app_root

worker_processes Integer(ENV.fetch("WEB_CONCURRENCY", 10))

# Behind nginx (RAILS_SERVER=unicorn-nginx), listen on a Unix socket. Unicorn
# closes every connection after one response, so nginx opens one per request,
# and over TCP each of those would leave a port in TIME_WAIT. A Unix socket
# uses no ports and has no TIME_WAIT.
#
# Otherwise, the same address bin/server hands cougar's -b, so the load
# generator talks to both servers over the same stack.
if (socket = ENV["UNICORN_SOCKET"])
  listen socket, backlog: 1024
else
  listen "#{ENV.fetch("BIND", "localhost")}:#{ENV.fetch("PORT", 3030)}",
         backlog: 1024, tcp_nodelay: true
end

# Load the app in the master and fork workers from it. This matches cougar,
# which boots the app once and hands it to the Ractors, and keeps the fork
# children sharing as many pages as possible.
preload_app true

# Never wrap the app in rackup's default middleware (CommonLogger, Lint,
# ShowExceptions, ...). Cougar runs the bare Rails stack, so unicorn must too,
# otherwise the comparison measures Rack::Lint.
default_middleware false

timeout Integer(ENV.fetch("UNICORN_TIMEOUT", 30))
# Per-port, so a run on another port does not trip over a live master's pidfile.
pid File.join(app_root, "tmp/pids/unicorn-#{ENV.fetch("PORT", 3030)}.pid")

# Drop pooled connections before forking so no worker inherits a live socket
# or SQLite handle from the master, then make sure anything that did slip
# through is dropped on the child side too. Each worker reconnects lazily on
# its first checkout.
before_fork do |_server, _worker|
  defined?(ActiveRecord::Base) &&
    ActiveRecord::Base.connection_handler.clear_all_connections!
end

after_fork do |_server, _worker|
  defined?(ActiveRecord::Base) &&
    ActiveRecord::Base.connection_handler.clear_all_connections!
end
