-- Morning Paper source pack (v0.2)
-- enabled=false keeps a source available without using it by default.
-- limit controls how many current stories are considered from each feed.
-- max_age_hours filters dated items so stale feeds do not fill the paper.
-- full_text=true means Morning Paper will attempt to fetch the public article page.

return {
    {
        section = "Front Page",
        name = "BBC News — Top Stories",
        url = "https://feeds.bbci.co.uk/news/rss.xml",
        limit = 4,
        max_age_hours = 72,
        full_text = true,
    },
    {
        section = "World",
        name = "BBC News — World",
        url = "https://feeds.bbci.co.uk/news/world/rss.xml",
        limit = 3,
        max_age_hours = 72,
        full_text = true,
    },
    {
        section = "U.S.",
        name = "The Guardian — U.S. News",
        url = "https://www.theguardian.com/us-news/rss",
        limit = 3,
        max_age_hours = 72,
        full_text = true,
    },
    {
        section = "Business & Markets",
        name = "BBC News — Business",
        url = "https://feeds.bbci.co.uk/news/business/rss.xml",
        limit = 3,
        max_age_hours = 96,
        full_text = true,
    },
    {
        section = "Business & Markets",
        name = "The Guardian — Business",
        url = "https://www.theguardian.com/business/rss",
        limit = 2,
        max_age_hours = 96,
        full_text = true,
    },
    {
        section = "Business & Markets",
        name = "Federal Reserve — Press Releases",
        url = "https://www.federalreserve.gov/feeds/press_all.xml",
        limit = 2,
        max_age_hours = 336,
        full_text = true,
        min_fulltext_chars = 250,
    },
    {
        section = "Business & Markets",
        name = "U.S. Bureau of Labor Statistics — Latest Numbers",
        url = "https://www.bls.gov/feed/bls_latest.rss",
        limit = 2,
        max_age_hours = 336,
        full_text = true,
        min_fulltext_chars = 250,
    },
    {
        section = "Technology & AI",
        name = "Ars Technica",
        url = "https://feeds.arstechnica.com/arstechnica/index",
        limit = 3,
        max_age_hours = 96,
        full_text = true,
    },
    {
        section = "Technology & AI",
        name = "BBC News — Technology",
        url = "https://feeds.bbci.co.uk/news/technology/rss.xml",
        limit = 2,
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

    -- Disabled because these legacy WSJ RSS feeds were observed serving stale
    -- 2025 entries in August 2026. They are kept here for future re-testing.
    {
        section = "Business & Markets",
        name = "The Wall Street Journal — Markets (legacy RSS)",
        url = "https://feeds.a.dj.com/rss/RSSMarketsMain.xml",
        limit = 3,
        max_age_hours = 96,
        full_text = true,
        enabled = false,
    },
}
