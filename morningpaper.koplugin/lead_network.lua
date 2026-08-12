-- Morning Paper v0.11 — Fresh Paywall Lead Network
--
-- These feeds are PUBLIC headline/topic signals only. They are intentionally
-- agenda_only: Morning Paper never fetches or reconstructs hidden subscriber text.
-- Their job is to tell the newsroom which stories major paywalled publications
-- are emphasizing today. Coverage Net then looks for the same event in the
-- accessible BBC/Fox/Guardian/Epoch/Ars/etc. research and RSS scans.
--
-- Google News RSS search is used here as a freshness layer because several old
-- publisher RSS endpoints can remain online while serving stale archives.

return {
    {
        section = "Paywall Lead Network",
        agenda_category = "Front Page",
        name = "The Wall Street Journal — fresh headline leads [PAYWALL LEAD]",
        url = "https://news.google.com/rss/search?q=site%3Awsj.com%20when%3A1d&hl=en-US&gl=US&ceid=US%3Aen",
        limit = 18,
        max_age_hours = 48,
        full_text = false,
        agenda_only = true,
    },
    {
        section = "Paywall Lead Network",
        agenda_category = "Front Page",
        name = "Bloomberg — fresh headline leads [PAYWALL LEAD]",
        url = "https://news.google.com/rss/search?q=site%3Abloomberg.com%20when%3A1d&hl=en-US&gl=US&ceid=US%3Aen",
        limit = 16,
        max_age_hours = 48,
        full_text = false,
        agenda_only = true,
    },
    {
        section = "Paywall Lead Network",
        agenda_category = "Front Page",
        name = "Financial Times — fresh headline leads [PAYWALL LEAD]",
        url = "https://news.google.com/rss/search?q=site%3Aft.com%20when%3A1d&hl=en-US&gl=US&ceid=US%3Aen",
        limit = 14,
        max_age_hours = 48,
        full_text = false,
        agenda_only = true,
    },
    {
        section = "Paywall Lead Network",
        agenda_category = "Front Page",
        name = "The New York Times — fresh headline leads [PAYWALL LEAD]",
        url = "https://news.google.com/rss/search?q=site%3Anytimes.com%20when%3A1d&hl=en-US&gl=US&ceid=US%3Aen",
        limit = 14,
        max_age_hours = 48,
        full_text = false,
        agenda_only = true,
    },
    {
        section = "Paywall Lead Network",
        agenda_category = "Front Page",
        name = "The Washington Post — fresh headline leads [PAYWALL LEAD]",
        url = "https://news.google.com/rss/search?q=site%3Awashingtonpost.com%20when%3A1d&hl=en-US&gl=US&ceid=US%3Aen",
        limit = 12,
        max_age_hours = 48,
        full_text = false,
        agenda_only = true,
    },
    {
        section = "Paywall Lead Network",
        agenda_category = "Front Page",
        name = "Barron's — fresh headline leads [PAYWALL LEAD]",
        url = "https://news.google.com/rss/search?q=site%3Abarrons.com%20when%3A1d&hl=en-US&gl=US&ceid=US%3Aen",
        limit = 10,
        max_age_hours = 48,
        full_text = false,
        agenda_only = true,
    },
    {
        section = "Paywall Lead Network",
        agenda_category = "Front Page",
        name = "The Economist — fresh headline leads [PAYWALL LEAD]",
        url = "https://news.google.com/rss/search?q=site%3Aeconomist.com%20when%3A2d&hl=en-US&gl=US&ceid=US%3Aen",
        limit = 10,
        max_age_hours = 72,
        full_text = false,
        agenda_only = true,
    },
}
