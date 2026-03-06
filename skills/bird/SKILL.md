---
name: bird
description: X/Twitter CLI for reading, searching, and posting via browser cookies. Use when the user asks about tweets, X/Twitter content, or wants to post/reply on X.
homepage: https://bird.fast
---

# bird

Use `bird` to read/search X and post tweets/replies.

## Authentication

Requires `AUTH_TOKEN` and `CT0` environment variables (X session cookies).
Run `bird check` to verify credentials before any operation.

## Quick start

- `bird whoami` — show authenticated account
- `bird check` — verify credential availability
- `bird read <url-or-id>` — read a tweet
- `bird thread <url-or-id>` — full conversation thread
- `bird search "query" -n 5` — search tweets
- `bird mentions -n 10` — recent mentions
- `bird home -n 10` — home timeline
- `bird user-tweets <handle> -n 5` — tweets from a user
- `bird about <username>` — account info and location
- `bird news` — trending topics

## Posting (ALWAYS confirm with user first)

- `bird tweet "text"` — post a new tweet
- `bird reply <id-or-url> "text"` — reply to a tweet
- `bird --media <path> tweet "text"` — tweet with image (up to 4)

## Reading with JSON output

Add `--json` to any read command for structured output:
- `bird read <url> --json`
- `bird search "query" -n 5 --json`

## Tips

- Use `--plain` flag for clean output without emoji/color
- Use `--quote-depth 0` to skip quoted tweet expansion
- Tweet IDs and URLs are interchangeable in all commands
- `bird <tweet-id-or-url>` is a shorthand for `bird read`
