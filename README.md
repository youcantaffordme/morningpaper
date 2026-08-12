# Morning Paper for KOReader

A Kindle/KOReader-first personal newspaper plugin.

## v0.2.0
Morning Paper now tries to turn current RSS/Atom headlines into a **real readable paper**, not just a list of feed snippets.

For each story it:
1. pulls the current feed entry,
2. filters obviously stale dated entries,
3. follows the article link,
4. attempts to extract the publicly available article body,
5. strips page chrome/navigation/ads where possible,
6. falls back to the publisher's RSS excerpt when full text cannot be extracted,
7. keeps the original source and article link visible.

It does **not** bypass subscriptions, logins, or paywalls.

## Default sections
- Front Page
- World
- U.S.
- Business & Markets
- Technology & AI
- Science
- Culture

## Default source pack
- BBC News — Top Stories
- BBC News — World
- The Guardian — U.S. News
- BBC News — Business
- The Guardian — Business
- Federal Reserve — Press Releases
- U.S. Bureau of Labor Statistics — Latest Numbers
- Ars Technica
- BBC News — Technology
- BBC News — Science & Environment
- The Guardian — Culture

The legacy WSJ Markets RSS entry remains in `sources.lua` but is **disabled by default** because it was observed returning stale 2025 items during August 2026 testing. Morning Paper will not pretend stale feed entries are current news.

## Install / update from the KOReader App Store
If you installed Morning Paper from the community App Store, update/reinstall it there and restart KOReader completely.

Manual install:
1. Download this repository as a ZIP.
2. Extract it and rename the folder to **morningpaper.koplugin** if necessary.
3. Copy the folder to `/mnt/us/koreader/plugins/`.
4. Restart KOReader completely.

## Use
Open the KOReader tools menu → **Morning Paper** → **Refresh today's paper**.

Generated issues are stored in:
`/mnt/us/documents/Morning Paper/`

At the top of each generated issue, Morning Paper reports how many stories were included and how many were successfully upgraded from feed excerpts to full article bodies.

Each story is labeled either:
- **Full article** — Morning Paper successfully extracted the public article body, or
- **Feed excerpt** — the publisher limited access, the page could not be parsed reliably, or the feed itself is the best available source.

## Customize
Edit `sources.lua` to change source limits, freshness windows, sections, or enable/disable feeds.

Useful fields:
- `limit` — maximum stories considered from the feed
- `max_age_hours` — ignore older dated stories
- `full_text` — attempt article-page extraction
- `min_fulltext_chars` — minimum extracted body size before it counts as a full article
- `enabled` — turn a source on/off

## Current limitations
- Article extraction is best-effort because publisher HTML changes over time.
- Sites that require JavaScript, block automated readers, or require a subscription may fall back to excerpts.
- Refreshing takes longer than v0.1 because the Kindle now visits article pages one by one.
- No source editor UI yet; edit `sources.lua` for now.
- No automatic scheduled morning refresh yet.

## Next
- on-device source toggles/editor
- better duplicate-story clustering
- California/local source pack
- archive cleanup
- scheduled morning refresh
- optional AI-generated front-page brief built on top of the underlying journalism
- optional authenticated support for publications a user personally subscribes to, where technically and contractually permitted
