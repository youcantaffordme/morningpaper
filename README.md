# Morning Paper for KOReader

A Kindle/KOReader-first personal newspaper plugin.

## What it does
- Adds **Morning Paper** to KOReader's menu.
- Pulls configured RSS/Atom feeds over Wi-Fi.
- Deduplicates headlines.
- Groups stories into newspaper-style sections.
- Creates one dated HTML issue with a table of contents.
- Opens the issue directly in KOReader.
- Keeps source attribution and original article links.
- Does **not** bypass publisher paywalls or subscriptions.

## Included sources in v0.1
- BBC World
- BBC Business
- The Wall Street Journal — Markets RSS
- The Wall Street Journal — World RSS
- The Wall Street Journal — U.S. Business RSS
- Ars Technica

RSS feeds are controlled by publishers. Some provide only a headline or excerpt. If a linked article is subscription-only, Morning Paper does not unlock it.

## Install on Kindle / KOReader
1. Download this repository as a ZIP.
2. Extract it and rename the folder to **morningpaper.koplugin** if necessary.
3. Copy that folder to `/mnt/us/koreader/plugins/`.
4. Restart KOReader completely.
5. Open the KOReader menu → **Morning Paper**.
6. Tap **Refresh today's paper**.

Generated issues are saved to `/mnt/us/documents/Morning Paper/`.

## Customize
Edit `sources.lua` to add, remove, disable, or change feed limits.

## Status
This is an early public prototype and has not yet been hardware-tested across Kindle/KOReader versions. Expect rapid updates.

## Planned next
- On-device source toggles/editor
- Scheduled morning refresh
- Archive cleanup
- Better duplicate-story clustering
- California/local source pack
- Fed/SEC/BLS primary-source market pack
- Optional AI morning brief
- Optional authenticated access for publications the user personally subscribes to, where permitted
