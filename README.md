# Morning Paper for KOReader

A Kindle/KOReader-first personal newspaper plugin.

## v0.5.0 — Intelligence Desk
Morning Paper now has an optional **AI Intelligence Desk** at the front of each issue.

The goal is not to imitate or reconstruct any publisher. The desk takes the public reporting Morning Paper already fetched from multiple outlets and creates a short set of original, source-grounded briefs that explain:

- **FACTS** — what the accessible reporting actually establishes,
- **WHY IT MATTERS** — economic, political, business, technological, security or everyday consequences,
- **WHERE COVERAGE DIFFERS** — materially different interpretations or disputed claims,
- **WATCH NEXT** — the next event, data point, decision or dependency that could change the story.

The prompt explicitly tells the model not to force false balance: facts remain facts, claims remain claims, and disagreements are identified rather than blended together.

### WSJ agenda signals without copying paid WSJ
Morning Paper now checks the public WSJ RSS headline feeds for World News, U.S. Business, Markets, Technology/What's News, Opinion and Lifestyle.

These entries are **agenda-only**. They tell the Intelligence Desk which topics WSJ is emphasizing that day, but Morning Paper does **not** treat the headline as the hidden article, reconstruct a paywalled article, or bypass WSJ subscription controls. If a legacy WSJ feed is stale, the normal freshness filter excludes it automatically.

The AI then looks for those topics in the accessible reporting already collected from the rest of the source pool. A topic is supposed to be omitted rather than invented when the supplied reporting does not support it.

### Wider viewpoint mix
The default source pool now includes BBC, The Guardian, Fox News, The Epoch Times, Ars Technica and primary economic sources including the Federal Reserve and Bureau of Labor Statistics. The raw source articles remain in their normal sections underneath the Intelligence Desk, so the reader can compare the synthesis with the underlying reporting.

### AI cost and setup
The default model is **`openrouter/free`**, so the synthesis itself can run on OpenRouter's free-model router. An OpenRouter API key is still required.

Morning Paper first tries its own saved OpenRouter key. If none is set, it tries to reuse an OpenRouter key already configured in KOAssistant. You can also set one directly at:

**Tools → Morning Paper → AI Intelligence Desk → Set OpenRouter API key**

AI synthesis is one request per generated issue, not one request per article. If the AI request fails or no key exists, Morning Paper still builds the ordinary source newspaper.

The AI request contains short excerpts of the public reporting Morning Paper already downloaded plus public WSJ headline/feed signals. It does not send your books, highlights or personal reading data.

## v0.4 — real daily EPUB editions with covers
Morning Paper generates each daily issue as a **real EPUB** rather than a plain HTML document.

Every issue gets its own dynamically generated black-and-white newspaper cover containing:
- **MORNING PAPER** masthead,
- the issue date,
- the edition time,
- up to three leading headlines from that issue,
- story/full-article counts,
- a newspaper-style section footer.

The cover is embedded in EPUB metadata as the book cover, so KOReader can use it in cover/grid views. The first page of the EPUB is also the full cover.

Daily files are named like:

`Morning Paper 2026-08-12.epub`

When a new EPUB is successfully built, an old same-day HTML version is removed so the library does not show duplicate editions.

The EPUB is built completely on-device with no Calibre, server, image API, or AI image generation required. Morning Paper includes its own lightweight ZIP/EPUB writer and generates the cover as scalable black-and-white SVG optimized for e-ink.

## Clean article text
Every source story gets a final sanitation pass before it is written into the paper. The sanitizer:
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
For each ordinary source story Morning Paper:
1. pulls the current RSS/Atom entry,
2. filters stale dated entries,
3. follows the article link,
4. attempts to extract the publicly available article body,
5. sanitizes the extracted body,
6. falls back to a sanitized publisher RSS excerpt when full text cannot be extracted,
7. shows only a source-link notice if no clean text remains,
8. sorts the section newest-first.

If AI Intelligence Desk is enabled, Morning Paper then:
9. gathers short excerpts from the accessible reporting,
10. gathers fresh WSJ agenda-only headline signals,
11. makes one multi-source synthesis request,
12. inserts the Intelligence Desk before the ordinary sections,
13. packages the cover, table of contents, metadata, synthesis and source stories into one EPUB.

## Default sections
- Intelligence Desk (when AI is enabled and available)
- Front Page
- World
- U.S.
- Business & Markets
- Technology & AI
- Science
- Culture

## Install / update
If installed through the KOReader community App Store:
1. Refresh the App Store.
2. Update/reinstall Morning Paper.
3. Restart KOReader completely.
4. Tap **Refresh today's paper** once to regenerate today's issue with the new code.

Generated issues are stored in:

`/mnt/us/documents/Morning Paper/`

## Article labels
Ordinary source stories may be labeled:
- **Full article** — a clean public article body was extracted.
- **Feed excerpt** — the publisher blocked/limited page extraction, so a sanitized feed excerpt is shown.
- **Source link only** — neither the article page nor the feed supplied enough clean readable text.

Intelligence Desk stories are labeled **AI multi-source synthesis** and list the source names the model says it used.

## Current limitations
- AI synthesis can make mistakes; the underlying source stories remain in the issue for verification.
- The free OpenRouter router can vary in model quality/availability from one run to another.
- Article extraction is best-effort because publisher HTML changes over time.
- JavaScript-only sites, bot protection, logins and subscriptions can prevent full-text extraction.
- WSJ agenda feeds are legacy public RSS endpoints and may occasionally be stale; stale entries are automatically ignored.
- Scheduled hardware wake and unattended Wi-Fi behavior vary by Kindle/e-reader model and need real-device testing.
- EPUB cover-thumbnail behavior can depend on KOReader's cover cache.
- No on-device per-source editor yet.
