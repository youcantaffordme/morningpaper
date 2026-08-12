# Morning Paper for KOReader

A Kindle/KOReader-first personal newspaper plugin.

## v0.3.0
Morning Paper can now build itself before you wake up.

### New in v0.3
- **Automatic morning delivery** using KOReader's hardware wake scheduler when the device supports it.
- Configurable presets from **5:30 AM through 8:00 AM**; default is 6:30 AM.
- Automatic delivery is **opt-in** so installing the plugin does not unexpectedly wake other users' devices.
- The plugin attempts to bring Wi-Fi online, builds the dated issue silently, then turns Wi-Fi back off if it was originally off.
- Automatic delivery status shows the next scheduled wake and the last delivery result.
- Stories are now sorted **newest → oldest within each section** instead of trusting feed order.
- Publisher timestamps are intentionally preserved exactly as supplied. That means a GMT/UTC story can show an August 12 date while it is still August 11 in California.

## Enable automatic delivery
After updating and restarting KOReader:

**Tools → Morning Paper → Automatic delivery → Enable automatic delivery**

Then choose a delivery time. The default is **6:30 AM**.

For fully unattended Wi-Fi startup, KOReader's Wi-Fi action must allow Wi-Fi to turn on automatically. If it does not, the Auto-delivery status screen will report that the scheduled paper could not bring Wi-Fi online.

Hardware-wake behavior varies by device and firmware, so v0.3 should be treated as the first public hardware test of this feature.

## How the paper is built
For each story Morning Paper:
1. pulls the current RSS/Atom entry,
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

The legacy WSJ Markets RSS entry remains in `sources.lua` but is **disabled by default** because it was observed returning stale 2025 items during August 2026 testing.

## Install / update
If you installed Morning Paper from the KOReader community App Store, refresh the App Store, update/reinstall Morning Paper, and restart KOReader completely.

Manual install:
1. Download this repository as a ZIP.
2. Extract it and rename the folder to **morningpaper.koplugin** if necessary.
3. Copy that folder to `/mnt/us/koreader/plugins/`.
4. Restart KOReader completely.

Generated issues are stored in:
`/mnt/us/documents/Morning Paper/`

## Article labels
Each story is labeled either:
- **Full article** — Morning Paper successfully extracted the public article body, or
- **Feed excerpt** — the publisher limited access, the page could not be parsed reliably, or the feed itself is the best available source.

## Customize sources
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
- Scheduled hardware wake and unattended Wi-Fi behavior can vary across Kindle/e-reader models and needs real-device testing.
- No on-device source editor yet.
