#!/usr/bin/env bash
# Usage: scripts/profile_run.sh N [DIR] [URLS]
# Boots a fresh cougar under samply, runs oha for 30s (against / or, given a
# URLS file from scripts/make_urls.sh, a random pick of its lines each
# request), stops the server and
# leaves profile_runN_<stamp>.json.gz (+ .syms.json), oha_runN,
# cougar_runN.log and loadN in DIR (default: the app root). Refuses to start
# if the 1-minute load average is above MAX_LOAD (default 4).
set -u
n=$1
cd "$(dirname "$0")/.."
dir=${2:-.}
urls=${3:-}
mkdir -p "$dir"
export PATH=$HOME/.rubies/ruby_ctl/bin:$HOME/.gem/ruby/ruby_ctl/bin:$PATH
export GEM_HOME=$HOME/.gem/ruby/ruby_ctl
export GEM_PATH=$HOME/.gem/ruby/ruby_ctl:$HOME/.rubies/ruby_ctl/lib/ruby/gems/4.1.0+5
export RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 RAILS_SERVER=cougar
export RUBY_MAX_CPU=10 RAILS_LOG_TO_STDOUT=true
out="$dir/profile_run${n}_$(date +%Y%m%d-%H%M%S).json.gz"

# Other processes competing for CPU skew the numbers, so refuse to start
# when the 1-minute load average is above MAX_LOAD (default 4; an idle
# machine sits around 2-3). The load before and after is kept in loadN.
load1() { sysctl -n vm.loadavg | awk '{print $2}'; }
max_load=${MAX_LOAD:-4}
load=$(load1)
if awk -v l="$load" -v m="$max_load" 'BEGIN { exit !(l > m) }'; then
  echo "run $n: load average is $load (MAX_LOAD=$max_load); not starting" >&2
  echo "top CPU users:" >&2
  top -l 1 -o cpu -n 5 -stats pid,cpu,command 2>/dev/null | tail -6 >&2
  exit 1
fi
echo "before: $load" > "$dir/load${n}"

# Every post view inserts a page_views row and /stats aggregates them, so
# start each run from the same (empty) table; KEEP_VIEWS=1 skips this.
if [ -z "${KEEP_VIEWS:-}" ]; then
  sqlite3 storage/production.sqlite3 "delete from page_views; update posts set views_count = 0;"
fi

samply record --save-only --unstable-presymbolicate -o "$out" \
  ruby --yjit --yjit-perf -r bundler/setup -S cougar -b localhost -p 3030 -w 10 \
  > "$dir/cougar_run${n}.log" 2>&1 &
samply_pid=$!

for i in $(seq 1 120); do
  lsof -nP -iTCP:3030 -sTCP:LISTEN >/dev/null 2>&1 && break
  sleep 1
done
echo "run $n: listening after ${i}s"

if [ -n "$urls" ]; then
  oha -c 10 -z 30s --no-tui --urls-from-file "$urls" > "$dir/oha_run${n}" 2>&1
else
  oha -c 10 -z 30s --no-tui http://localhost:3030/ > "$dir/oha_run${n}" 2>&1
fi
echo "after: $(load1)" >> "$dir/load${n}"

pkill -INT -f "cougar -b localhost -p 3030"
wait "$samply_pid"
echo "run $n: saved $out"
grep -c "IsolationError" "$dir/cougar_run${n}.log" | sed 's/^/isolation errors: /'
grep -c '\[BUG\]' "$dir/cougar_run${n}.log" | sed 's/^/crashes: /'
