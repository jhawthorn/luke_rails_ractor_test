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

Unicorn with 10 workers:

  RAILS_SERVER=unicorn WORKERS=10 bin/server

### Running on Cougar

Cougar with ractors:

  RAILS_SERVER=cougar WORKERS=10 bin/server

### Load Testing / Benchmarking

  RAILS_SERVER=cougar WORKERS=10 bin/server


### Sending requests

Send requests with 10 connections for 30s straight.

  oha -c 10 -z 30s http://127.0.0.1:3030/

### Starting cougar directly

  RAILS_MAX_THREADS=16 RUBY_MAX_CPU=10 RAILS_LOG_TO_STDOUT=true RAILS_ENV=production ruby --yjit -r bundler/setup -S cougar -p 3030 -w 10

  oha -c 10 -z 30s http://localhost:3030/

### Profiling with samply

  RAILS_MAX_THREADS=16 RUBY_MAX_CPU=12 RAILS_LOG_TO_STDOUT=true RAILS_ENV=production samply record --save-only ruby --yjit --yjit-perf -r bundler/setup -S cougar -p 3030 -w 10
  samply load profile.json.gz
