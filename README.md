# Rails Ractor Test

### Servers

The app boots under either server, selected with `RAILS_SERVER`:

| `RAILS_SERVER` | Server    | Concurrency unit        | Bundle            |
| -------------- | --------- | ----------------------- | ----------------- |
| `cougar`       | cougar    | N Ractors, one process  | `Gemfile`         |
| `unicorn`      | unicorn   | N forked worker procs   | `Gemfile.unicorn` |

Both bundles share `Gemfile.common`, so the two targets differ only in the
server gem. Install the unicorn one once:

  BUNDLE_GEMFILE=Gemfile.unicorn bundle install

`bin/server` boots either one with a matching configuration (same port, same
bind address, same number of request-serving units, `RAILS_ENV=production`):

  RAILS_SERVER=cougar  WORKERS=10 PORT=3030 bin/server
  RAILS_SERVER=unicorn WORKERS=10 PORT=3030 bin/server

Knobs: `WORKERS` (Ractors or worker processes, default 10), `PORT` (3030),
`BIND` (127.0.0.1), `RUBY_OPTS` (`--yjit`), `RAILS_LOG_TO_STDOUT`. Extra
arguments are passed through to the server. Unicorn's own settings live in
`config/unicorn.rb`.

Note that `RAILS_SERVER` also drives two things in the app config: only cougar
gets `Rails.application.ractorize!` (`config.ru`) and the Ractor-shareable
logger (`config/environments/production.rb`); a forking server would inherit
that logger's consumer thread as a dead port and hang on its first flush.

### Running on Unicorn

Unicorn with 10 workers. Note that you will run out of connections when load testing this way, because
the client closes and open a new TCP connection for each request because of the way Unicorn behaves (it
sends the `Connection: close` HTTP header. Use unicorn with nginx for real benchmarking.

  RAILS_SERVER=unicorn WORKERS=10 bin/server

### Running on Unicorn with nginx as proxy

Unicorn with 10 workers, nginx with 2 workers. Nginx listens on PORT, unicorn on a UDS:

  RAILS_SERVER=unicorn-nginx WORKERS=10 bin/server

### Running on Cougar

Cougar with ractors:

  RAILS_SERVER=cougar WORKERS=10 bin/server

### Load Testing / Benchmarking

  RAILS_SERVER=cougar WORKERS=10 bin/server

### Sending requests

Send requests with 10 connections for 30s straight.

  oha -c 10 -z 30s http://localhost:3030/

`/` is the home page (recent posts, featured posts, sidebar), not the posts
index. To spread the load over every page, build a URL mix from the database
and let oha pick from it:

  scripts/make_urls.sh http://localhost:3030 > urls.txt
  oha -c 10 -z 30s --urls-from-file urls.txt

### What a request does

The blog has authors, tags, posts with Markdown bodies, rated comments and a
page_views table. Seed it with `RESEED=1 bin/rails db:seed` (300 posts and
about 4500 comments by default; set `POSTS` and `COMMENTS` to change that).

| Page | Work |
| ---- | ---- |
| `/`, `/posts`, `/tags/:slug` | listing queries, post cards in a fragment cache (file store) |
| `/posts/:id` | Markdown render (`lib/blog/markdown.rb`), Prism-based Ruby highlighting, readability stats, related posts, a `page_views` insert and a counter update |
| `/authors`, `/authors/:handle` | aggregate queries, top terms over all of the author's posts |
| `/search?q=` | LIKE queries, ranking and snippets in Ruby |
| `/stats` | percentiles, histograms, group-by queries, `Dir.glob` + `File.size` |
| `/pages/:name` | reads and renders `content/pages/*.md` from disk every time |
| `/feed` | Atom via Builder |
| `/posts.json`, `/posts.csv`, `/api/...` | jbuilder, CSV, `JSON.generate` with a SHA256 ETag |

Every HTML page also renders a sidebar from `Rails.cache` (5 s TTL) and reads
a random line from `content/quotes.txt`.

Set `YJIT=0` to boot without YJIT. `load_defaults` enables it even when ruby
was started without `--yjit`.

### Starting cougar directly

  RAILS_MAX_THREADS=16 RUBY_MAX_CPU=10 RAILS_LOG_TO_STDOUT=true RAILS_ENV=production ruby --yjit -r bundler/setup -S cougar -p 3030 -w 10

  oha -c 10 -z 30s http://localhost:3030/

### Profiling with samply

  RAILS_MAX_THREADS=16 RUBY_MAX_CPU=12 RAILS_LOG_TO_STDOUT=true RAILS_ENV=production samply record --save-only ruby --yjit --yjit-perf -r bundler/setup -S cougar -p 3030 -w 10
  samply load profile.json.gz
