-- Morning Paper source pack (v0.5.0)
-- enabled=false keeps a source available without using it by default.
-- limit controls how many current stories are considered from each feed.
-- max_age_hours filters dated items so stale feeds do not fill the paper.
-- full_text=true means Morning Paper will attempt to fetch the public article page.
-- agenda_only=true means a feed is used only as an editorial/topic signal for
-- the AI Intelligence Desk; its paywalled/full article is NOT copied into the paper.

return {
    {
        section = "Front Page",
        name = "BBC News — Top Stories",
        url = "https://feeds.bbci.co.uk/news/rss.xml",
        limit = 5,
        max_age_hours = 72,
        full_text = true,
    },
    {
        section = "World",
        name = "BBC News — World",
        url = "https://feeds.bbci.co.uk/news/world/rss.xml",
        limit = 4,
        max_age_hours = 72,
        full_text = true,
    },
    {
        section = "U.S.",
        name = "The Guardian — U.S. News",
        url = "https://www.theguardian.com/us-news/rss",
        limit = 4,
        max_age_hours = 72,
        full_text = true,
    },

    -- A conservative/right-of-center counterweight in the raw source pool.
    -- Fox publishes these feeds for personal, non-commercial RSS use.
    {
        section = "U.S.",
        name = "Fox News — Politics",
        url = "https://moxie.foxnews.com/google-publisher/politics.xml",
        limit = 3,
        max_age_hours = 72,
        full_text = true,
    },
    {
        section = "World",
        name = "Fox News — World",
        url = "https://moxie.foxnews.com/google-publisher/world.xml",
        limit = 2,
        max_age_hours = 72,
        full_text = true,
    },

    -- Official Epoch Times RSS feeds. Morning Paper only uses publicly supplied
    -- feed content / publicly accessible article pages and does not bypass login or paywalls.
    {
        section = "U.S.",
        name = "The Epoch Times — U.S.",
        url = "https://feed.theepochtimes.com/us/feed",
        limit = 3,
        max_age_hours = 72,
        full_text = true,
    },
    {
        section = "World",
        name = "The Epoch Times — World",
        url = "https://feed.theepochtimes.com/world/feed",
        limit = 2,
        max_age_hours = 72,
        full_text = true,
    },
    {
        section = "Business & Markets",
        name = "The Epoch Times — Business & Markets",
        url = "https://feed.theepochtimes.com/business/feed",
        limit = 2,
        max_age_hours = 96,
        full_text = true,
    },
    {
        section = "Technology & AI",
        name = "The Epoch Times — Tech",
        url = "https://feed.theepochtimes.com/tech/feed",
        limit = 2,
        max_age_hours = 96,
        full_text = true,
    },

    {
        section = "Business & Markets",
        name = "BBC News — Business",
        url = "https://feeds.bbci.co.uk/news/business/rss.xml",
        limit = 4,
        max_age_hours = 96,
        full_text = true,
    },
    {
        section = "Business & Markets",
        name = "The Guardian — Business",
        url = "https://www.theguardian.com/business/rss",
        limit = 3,
        max_age_hours = 96,
        full_text = true,
    },
    {
        section = "Business & Markets",
        name = "Federal Reserve — Press Releases",
        url = "https://www.federalreserve.gov/feeds/press_all.xml",
        limit = 3,
        max_age_hours = 336,
        full_text = true,
        min_fulltext_chars = 250,
    },
    {
        section = "Business & Markets",
        name = "U.S. Bureau of Labor Statistics — Latest Numbers",
        url = "https://www.bls.gov/feed/bls_latest.rss",
        limit = 3,
        max_age_hours = 336,
        full_text = true,
        min_fulltext_chars = 250,
    },
    {
        section = "Technology & AI",
        name = "Ars Technica",
        url = "https://feeds.arstechnica.com/arstechnica/index",
        limit = 4,
        max_age_hours = 96,
        full_text = true,
    },
    {
        section = "Technology & AI",
        name = "BBC News — Technology",
        url = "https://feeds.bbci.co.uk/news/technology/rss.xml",
        limit = 3,
        max_age_hours = 96,
        full_text = true,
    },
    {
        section = "Science",
        name = "BBC News — Science & Environment",
        url = "https://feeds.bbci.co.uk/news/science_and_environment/rss.xml",
        limit = 3,
        max_age_hours = 120,
        full_text = true,
    },
    {
        section = "Culture",
        name = "The Guardian — Culture",
        url = "https://www.theguardian.com/culture/rss",
        limit = 2,
        max_age_hours = 120,
        full_text = true,
    },

    --------------------------------------------------------------------------
    -- WALL STREET JOURNAL AGENDA SIGNALS
    -- These public RSS feeds are used ONLY to learn what WSJ is putting on its
    -- desks that day. Morning Paper never treats a headline as the hidden article
    -- and never bypasses WSJ subscription controls. If a legacy feed is stale,
    -- max_age_hours automatically excludes it from the AI briefing.
    --------------------------------------------------------------------------
    {
        section = "WSJ Agenda",
        agenda_category = "World News",
        name = "The Wall Street Journal — World News headlines",
        url = "https://feeds.a.dj.com/rss/RSSWorldNews.xml",
        limit = 12,
        max_age_hours = 72,
        full_text = false,
        agenda_only = true,
    },
    {
        section = "WSJ Agenda",
        agenda_category = "U.S. Business",
        name = "The Wall Street Journal — U.S. Business headlines",
        url = "https://feeds.a.dj.com/rss/WSJcomUSBusiness.xml",
        limit = 12,
        max_age_hours = 72,
        full_text = false,
        agenda_only = true,
    },
    {
        section = "WSJ Agenda",
        agenda_category = "Markets",
        name = "The Wall Street Journal — Markets headlines",
        url = "https://feeds.a.dj.com/rss/RSSMarketsMain.xml",
        limit = 12,
        max_age_hours = 72,
        full_text = false,
        agenda_only = true,
    },
    {
        section = "WSJ Agenda",
        agenda_category = "Technology / What's News",
        name = "The Wall Street Journal — Technology headlines",
        url = "https://feeds.a.dj.com/rss/RSSWSJD.xml",
        limit = 12,
        max_age_hours = 72,
        full_text = false,
        agenda_only = true,
    },
    {
        section = "WSJ Agenda",
        agenda_category = "Opinion",
        name = "The Wall Street Journal — Opinion headlines",
        url = "https://feeds.a.dj.com/rss/RSSOpinion.xml",
        limit = 10,
        max_age_hours = 72,
        full_text = false,
        agenda_only = true,
    },
    {
        section = "WSJ Agenda",
        agenda_category = "Lifestyle",
        name = "The Wall Street Journal — Lifestyle headlines",
        url = "https://feeds.a.dj.com/rss/RSSLifestyle.xml",
        limit = 8,
        max_age_hours = 96,
        full_text = false,
        agenda_only = true,
    },
}
