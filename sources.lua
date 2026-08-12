-- Morning Paper source pack.
-- "enabled = false" disables a source without deleting it.
-- "limit" is max stories fetched per refresh.
-- RSS content is publisher-controlled; some feeds provide only headline/excerpt.

return {
    {
        section = "World",
        name = "BBC News — World",
        url = "https://feeds.bbci.co.uk/news/world/rss.xml",
        limit = 6,
    },
    {
        section = "Business & Markets",
        name = "BBC News — Business",
        url = "https://feeds.bbci.co.uk/news/business/rss.xml",
        limit = 6,
    },
    {
        section = "Business & Markets",
        name = "The Wall Street Journal — Markets",
        url = "https://feeds.a.dj.com/rss/RSSMarketsMain.xml",
        limit = 6,
    },
    {
        section = "World",
        name = "The Wall Street Journal — World",
        url = "https://feeds.a.dj.com/rss/RSSWorldNews.xml",
        limit = 5,
    },
    {
        section = "Business & Markets",
        name = "The Wall Street Journal — U.S. Business",
        url = "https://feeds.a.dj.com/rss/WSJcomUSBusiness.xml",
        limit = 5,
    },
    {
        section = "Technology & AI",
        name = "Ars Technica",
        url = "https://feeds.arstechnica.com/arstechnica/index",
        limit = 6,
    },
}
