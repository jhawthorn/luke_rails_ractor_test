#!/bin/bash
# Usage: scripts/make_urls.sh [BASE_URL] > urls.txt
#
# A weighted mix of the blog's pages for `oha --urls-from-file urls.txt`,
# picked from what is in storage/production.sqlite3. Roughly half the lines
# are post pages (the heaviest render, plus a page_views insert each); the
# rest spread over the listing, tag, author, search, stats, feed, static
# page and JSON API endpoints.
base=${1:-http://localhost:3030}
db=$(dirname "$0")/../storage/production.sqlite3
q() { sqlite3 "$db" "$1"; }

for id in $(q "select id from posts where published_at is not null order by id"); do
  echo "$base/posts/$id"
done
for i in $(seq 20); do echo "$base/"; done
for p in 1 2 3 4 5 6 7 8; do echo "$base/posts?page=$p"; echo "$base/api/posts?page=$p"; done
for slug in $(q "select slug from tags order by id"); do echo "$base/tags/$slug"; done
for handle in $(q "select handle from authors order by id"); do echo "$base/authors/$handle"; done
for term in ractor "ractor gc" sqlite yjit "frozen string" profiling keep-alive "method cache" benchmarks allocation; do
  echo "$base/search?q=${term// /+}"
done
for id in $(q "select id from posts where published_at is not null order by id limit 40"); do
  echo "$base/api/posts/$id"
done
for u in /tags /authors /stats /feed /pages/about /pages/colophon /posts.json /posts.csv /api/stats; do
  for i in 1 2 3; do echo "$base$u"; done
done
