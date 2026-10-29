# Rails Ractor Test

### Load Testing / Benchmarking

Example of using `oha` for http load testing:

Start server:

  RAILS_MAX_THREADS=16 RUBY_MAX_CPU=12 RAILS_LOG_TO_STDOUT=true RAILS_ENV=production ruby --yjit --yjit-perf -r bundler/setup -S cougar -p 3030 -w 12

  oha -c 12 -z 30s http://localhost:3030/


### Profiling with samply

  RAILS_MAX_THREADS=16 RUBY_MAX_CPU=12 RAILS_LOG_TO_STDOUT=true RAILS_ENV=production samply record --save-only ruby --yjit --yjit-perf -r bundler/setup -S cougar -p 3030 -w 12
