# Morning Paper for KOReader

A Kindle/KOReader-first personal newspaper plugin.

## v0.4.0 — real daily EPUB editions with covers
Morning Paper now generates each daily issue as a **real EPUB** instead of a plain HTML document.

Every issue gets its own dynamically generated black-and-white newspaper cover containing:
- **MORNING PAPER** masthead,
- the issue date,
- the edition time,
- up to three leading headlines from that issue,
- story/full-article counts,
- a newspaper-style section footer.

The cover is embedded in EPUB metadata as the book cover, so KOReader can use it when displaying the issue in cover/grid views. The first page of the EPUB is also the full front cover.

Daily files are named like:

`Morning Paper 2026-08-12.epub`

When a new EPUB is successfully built, an old same-day HTML version is removed so the library does not show duplicate editions.

The EPUB is built completely on-device with no Calibre, server, image API, or AI image generation required. Morning Paper includes its own lightweight ZIP/EPUB writer and generates the cover as scalable black-and-white SVG, optimized for e-ink.

## Clean article text
Every story gets a final sanitation pass before it is written into the paper. The sanitizer:
- decodes double-encoded RSS/HTML,
- removes HTML/XML tags,
- removes `href` fragments and raw attributes,
- strips giant/tracking URLs from article text,
- removes common newsletter, “continue reading”, image-caption and page-boilerplate lines,
- preserves paragraph breaks where possible,
- refuses to label malformed page output as a full article.

If a publisher blocks automated article fetching, Morning Paper shows a **clean feed excerpt** instead of raw markup. If even the feed excerpt is unusable, it shows a short source-link-only notice rather than pages of HTML or tracking links.

This does not bypass subscriptions, logins, bot protection, or paywalls.

## Automatic morning delivery
Morning Paper can build itself before you wake up.

- Automatic morning delivery uses KOReader's hardware wake scheduler when supported.
- Delivery presets run from **5:30 AM through 8:00 AM**; default is **6:30 AM**.
- Automatic delivery is opt-in.
- The plugin attempts to bring Wi-Fi online, builds the dated EPUB silently, then turns Wi-Fi back off if it was originally off.
- The status screen shows the next scheduled wake and the last delivery result.
- Stories are sorted **newest → oldest within each section**.
- Publisher timestamps are intentionally preserved as supplied, so GMT/UTC dates can appear a day ahead of local time.

### Enable automatic delivery
After updating and restarting KOReader:

**Tools → Morning Paper → Automatic delivery → Enable automatic delivery**

Then choose a delivery time. The default is **6:30 AM**.

For fully unattended Wi-Fi startup, KOReader's Wi-Fi action must allow Wi-Fi to turn on automatically.

## How the paper is built
For each story Morning Paper:
1. pulls the current RSS/Atom entry,
2. filters stale dated entries,
3. follows the article link,
4. attempts to extract the publicly available article body,
5. sanitizes the extracted body,
6. falls back to a sanitized publisher RSS excerpt when full text cannot be extracted,
7. shows only a source-link notice if no clean text remains,
8. sorts the section newest-first,
9. creates the dated cover from the issue's leading headlines,
10. packages the cover, table of contents, metadata and stories into one EPUB.

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

The legacy WSJ Markets RSS entry remains in `sources.lua` but is disabled by default because it was observed returning stale 2025 items during August 2026 testing.

## Install / update
If installed through the KOReader community App Store:
1. Refresh the App Store.
2. Update/reinstall Morning Paper.
3. Restart KOReader completely.
4. Tap **Refresh today's paper** once to generate the first EPUB edition and cover.

Generated issues are stored in:

`/mnt/us/documents/Morning Paper/`

## Article labels
Stories may be labeled:
- **Full article** — a clean public article body was extracted.
- **Feed excerpt** — the publisher blocked/limited page extraction, so a sanitized feed excerpt is shown.
- **Source link only** — neither the article page nor the feed supplied enough clean readable text.

## Current limitations
- Article extraction is best-effort because publisher HTML changes over time.
- JavaScript-only sites, bot protection, logins and subscriptions can prevent full-text extraction.
- Scheduled hardware wake and unattended Wi-Fi behavior vary by Kindle/e-reader model and need real-device testing.
- EPUB cover-thumbnail behavior can depend on KOReader's cover cache; reopening/refreshing the file browser may be needed the first time a new issue appears.
- No on-device source editor yet.
