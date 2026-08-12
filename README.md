# Morning Paper for KOReader

A Kindle/KOReader-first personal newspaper plugin that turns accessible reporting from many outlets into a dated, automatically delivered EPUB.

## v0.7.0 — full AI newsroom

Morning Paper now treats source articles as a **newsroom research packet**, not as the finished newspaper.

When the AI newsroom is enabled, the plugin:

1. fetches fresh RSS/Atom stories,
2. attempts to extract clean publicly accessible article text,
3. filters stale or malformed feed entries,
4. collects fresh public WSJ headline feeds as **agenda signals only**,
5. runs a separate editorial pass for Front Page and each major desk,
6. compares overlapping reporting and writes original Morning Paper stories,
7. publishes the finished stories into the normal newspaper sections,
8. moves the underlying source references into a compact **Sources & Further Reading** appendix,
9. packages everything into a dated EPUB with a generated newspaper cover and full table of contents.

The main paper is no longer an RSS reader with an AI summary bolted on top.

### Editorial standard

Morning Paper asks the newsroom model to be:

- fact-first,
- multi-source,
- evidence-weighted,
- politically nonaligned,
- explicit about uncertainty,
- aware of meaningful differences in framing,
- unwilling to manufacture false left/right symmetry.

A finished story should naturally explain what happened, what is firmly established, why it matters now, the context needed to understand it, how it may affect the current political/social/economic climate when supported by the research, where credible interpretations differ, what remains uncertain, and what to watch next.

The newsroom is told to use only the supplied research packet. It does not browse or invent missing facts.

## Full newspaper structure

A successful AI edition keeps the familiar newspaper sections:

- Front Page
- World
- U.S.
- Business & Markets
- Technology & AI
- Science
- Culture
- Sources & Further Reading

The newsroom is generated **desk by desk** instead of relying on one huge AI response. Front Page performs a global editorial pass over the research packet; the remaining desks then publish the most consequential non-duplicate stories from their areas.

With a large research packet the edition can produce roughly 8–14 original stories, depending on what the day's reporting supports and which desk calls succeed.

If the newsroom produces too few usable stories to resemble a real newspaper, Morning Paper refuses to pretend the run succeeded and falls back to the transparent source-article edition instead.

## Better table of contents

v0.7 separates the article's display headline from its navigation headline.

Every AI story can have:

- a full newspaper headline,
- a short 4–9 word **TOC headline**,
- a one-sentence dek,
- the full article body.

Both EPUB3 navigation and the legacy NCX table of contents now support nested entries:

**Section → concise story headline**

This keeps the TOC useful on a small e-ink screen instead of trying to squeeze a long sentence into each row.

The source appendix intentionally stays as one TOC section rather than expanding dozens of research references into the main navigation.

## Cleaner source appendix

The underlying reporting is still available for transparency, but it no longer takes over the newspaper.

**Sources & Further Reading** groups compact source references by research desk and includes the source headline, outlet, publication time and original link when available.

WSJ entries are clearly marked as public agenda/headline signals. Morning Paper does not access, reconstruct or bypass subscriber-only WSJ article text.

## AI model controls

Go to:

**Tools → Morning Paper → AI Newsroom → Model**

Options include:

- **Follow KOAssistant** — mirror KOAssistant's current model when it can be resolved,
- **Claude Sonnet 5** — `anthropic/claude-sonnet-5`,
- **OpenRouter Free** — `openrouter/free`,
- **Custom OpenRouter model…**

The AI status screen now shows both the configured choice and the **effective model** that will actually be requested.

Morning Paper first tries its own saved OpenRouter key. If none is set, it tries to reuse an OpenRouter key already configured in KOAssistant.

Because v0.7 runs separate newsroom desks, a full edition can use several AI requests instead of the old single-request design. This improves reliability and section coverage but can cost more when a paid model is selected. When OpenRouter returns cost metadata, Morning Paper records and displays the reported edition cost.

## Front Page selection

Front Page is now a real editorial selection pass over the entire research packet rather than simply inheriting the first feed's ordering.

The newsroom is instructed to prioritize consequential developments such as governance, elections, security, diplomacy, the economy, markets, major companies, technology, public safety and institutions. Novelty or entertainment stories should not displace more consequential developments when stronger news is available.

A stable story key is generated for every article so later desks can avoid republishing the same event.

## Source mix

The default research pool includes BBC, The Guardian, Fox News, The Epoch Times, Ars Technica and primary economic sources including the Federal Reserve and Bureau of Labor Statistics.

Public WSJ RSS feeds for World News, U.S. Business, Markets, Technology/What's News, Opinion and Lifestyle are used only as agenda/topic signals. Stale feed entries are filtered automatically.

## Clean article extraction

Every accessible source story gets a final sanitation pass before it enters the newsroom research packet. The sanitizer:

- decodes double-encoded RSS/HTML,
- removes HTML/XML tags,
- removes `href` fragments and raw attributes,
- strips giant/tracking URLs,
- removes common newsletter, “continue reading”, image-caption and page-boilerplate lines,
- preserves paragraph breaks where possible,
- refuses to label malformed page output as a full article.

If a publisher blocks automated article fetching, Morning Paper uses a clean feed excerpt instead. If even the excerpt is unusable, the research item becomes source-link-only.

Morning Paper does not bypass subscriptions, logins, bot protection or paywalls.

## Automatic morning delivery

Morning Paper can build itself before you wake up.

- Automatic delivery uses KOReader's hardware wake scheduler when supported.
- Delivery presets run from **5:30 AM through 8:00 AM**; default is **6:30 AM**.
- Automatic delivery is opt-in.
- The plugin attempts to bring Wi-Fi online, builds the dated EPUB silently, then turns Wi-Fi back off if it was originally off.
- The status screen shows the next scheduled wake and the last delivery result.
- Publisher timestamps remain as supplied, including GMT/UTC dates that may appear a day ahead of local time.

Enable it at:

**Tools → Morning Paper → Automatic delivery → Enable automatic delivery**

For fully unattended Wi-Fi startup, KOReader's Wi-Fi action must allow Wi-Fi to turn on automatically.

## EPUB editions and covers

Generated issues are stored in:

`/mnt/us/documents/Morning Paper/`

and named like:

`Morning Paper 2026-08-12.epub`

Every issue gets a dynamically generated black-and-white newspaper cover containing the issue date, edition time and leading headlines. AI editions show the number of original Morning Paper stories and the number of source reports researched.

Opening a generated paper uses KOReader's normal reader switch path so launcher overlays such as Bookshelf are not deliberately closed first.

## Install / update

If installed through the KOReader community App Store:

1. Refresh the App Store.
2. Update/reinstall Morning Paper.
3. Restart KOReader completely.
4. For the first v0.7 test, choose **AI Newsroom → Model → Claude Sonnet 5** if you want to guarantee that model rather than relying on automatic model detection.
5. Tap **Refresh today's paper** once to regenerate today's issue with the new newsroom.

## Failure behavior

Morning Paper never silently treats a one-story AI result as a successful full edition.

For a substantial research packet, v0.7 enforces a minimum number of original newsroom stories. If too few usable stories survive, the AI newsroom run is considered unsuccessful and the plugin publishes the transparent direct-source fallback instead. The completion dialog explains what happened.

Desk-level warnings do not necessarily destroy an otherwise healthy edition: successful desks are kept as long as the paper still clears the minimum full-edition threshold.

## Current limitations

- AI synthesis can make mistakes; the source appendix is there to make the research trail inspectable.
- Article extraction is best-effort because publisher HTML changes over time.
- JavaScript-only sites, bot protection, logins and subscriptions can prevent full-text extraction.
- Free-router model quality and availability can vary from run to run.
- v0.7's desk-by-desk newsroom uses more requests than the previous single-call design, so paid-model cost can be higher.
- Scheduled hardware wake and unattended Wi-Fi behavior vary by Kindle/e-reader model and need real-device testing.
- EPUB cover-thumbnail behavior can depend on KOReader's cover cache.
- No on-device per-source editor yet.
