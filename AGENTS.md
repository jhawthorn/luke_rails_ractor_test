Rails App Testing with Ractors
==============================

Overview
--------

I'm testing a Rails app with Ractors to benchmark it and fix issues.

Ruby version
------------

ruby version: chruby ruby_ctl
ruby srcdir: /Users/luke/workspace/ruby-dev/ruby2
ruby builddir: /Users/luke/workspace/ruby-dev/ruby2-build

Servers
-------

`RAILS_SERVER=cougar` (default) runs the Ractor server from `Gemfile`;
`RAILS_SERVER=unicorn` runs unicorn from `Gemfile.unicorn`. Shared deps are in
`Gemfile.common`. Launch either with `bin/server`; see README.md.

Unicorn comes from `k0kubun/unicorn` branch `ruby-3-4`, not from rubygems:
every released unicorn (up to 6.1.0) depends on kgio, whose `kgio_tryaccept`
SIGBUSes on Ruby 4. Unicorn master dropped kgio and handles Rack 3 headers;
that branch is master plus the generated `unicorn_http.c` and `version.rb`.

Ractor-safe gems
----------------

Checked in plain Ruby Ractors. These work: csv, json, zlib, digest, openssl,
prism, strscan, set, cgi/escape, uri, bigdecimal. These do not: kramdown and
rouge (mutable class-level state, procs), msgpack (DefaultFactory), nokogiri
and loofah (C extensions), ripper, ERB#result_with_hash (TOPLEVEL_BINDING),
addressable (UnicodeNormalize constants). That is why Markdown and
highlighting are in `lib/blog/`.

App code under Ractors: no association loading (query by foreign key), no
collection rendering (render partials in a loop), no `simple_format`, and
every constant must be shareable (use `# frozen_string_literal: true`).

Database data
-------------

Never write rows with SQL (INSERT, UPDATE, DELETE) against the database,
whether through the `sqlite3` CLI, `bin/rails dbconsole` or raw `execute`
calls. All benchmark data comes from `db/seeds.rb`, so it can be rebuilt the
same way every time: change the seeds file and reseed instead. Read-only
queries for checking the data are fine.

Back up `storage/production.sqlite3` (with `sqlite3 ... ".backup FILE"`)
before reseeding or resetting it.
