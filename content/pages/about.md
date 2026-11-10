---
title: About this blog
author: The maintainers
---
# About this blog

This is a **benchmark application**. Every page runs a realistic mix of work:

- several SQL queries, including aggregates and joins
- Markdown rendering with a hand-written parser and Prism-based highlighting
- reads and writes against a file-based cache store
- a small file read and a database write on some requests

## Why

To see how fast Rails can go when every request is handled by its own Ractor.

| Page | Queries | Writes |
|:-----|--------:|-------:|
| Home | ~8 | 0 |
| Post | ~10 | 2 |
| Search | ~4 | 0 |

```ruby
Ractor.new { Rails.application.call(env) }
```
