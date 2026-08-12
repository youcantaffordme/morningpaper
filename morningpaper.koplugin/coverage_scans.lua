-- Morning Paper Wide Coverage Net
--
-- These are headline/summary scans of the SAME public feeds already used by
-- Morning Paper. They intentionally scan deeper than the full-text fetch list.
-- No linked article is fetched from these entries; the public RSS summary is
-- used only as limited corroborating evidence for event clustering.

return {
    { section="Coverage Scan", agenda_category="Front Page", name="BBC News — Top Stories [Coverage Scan]", url="https://feeds.bbci.co.uk/news/rss.xml", limit=18, max_age_hours=72, full_text=false, agenda_only=true },
    { section="Coverage Scan", agenda_category="World", name="BBC News — World [Coverage Scan]", url="https://feeds.bbci.co.uk/news/world/rss.xml", limit=16, max_age_hours=72, full_text=false, agenda_only=true },
    { section="Coverage Scan", agenda_category="U.S.", name="The Guardian — U.S. News [Coverage Scan]", url="https://www.theguardian.com/us-news/rss", limit=16, max_age_hours=72, full_text=false, agenda_only=true },
    { section="Coverage Scan", agenda_category="U.S.", name="Fox News — Politics [Coverage Scan]", url="https://moxie.foxnews.com/google-publisher/politics.xml", limit=16, max_age_hours=72, full_text=false, agenda_only=true },
    { section="Coverage Scan", agenda_category="World", name="Fox News — World [Coverage Scan]", url="https://moxie.foxnews.com/google-publisher/world.xml", limit=14, max_age_hours=72, full_text=false, agenda_only=true },
    { section="Coverage Scan", agenda_category="U.S.", name="The Epoch Times — U.S. [Coverage Scan]", url="https://feed.theepochtimes.com/us/feed", limit=14, max_age_hours=72, full_text=false, agenda_only=true },
    { section="Coverage Scan", agenda_category="World", name="The Epoch Times — World [Coverage Scan]", url="https://feed.theepochtimes.com/world/feed", limit=14, max_age_hours=72, full_text=false, agenda_only=true },
    { section="Coverage Scan", agenda_category="Business & Markets", name="The Epoch Times — Business & Markets [Coverage Scan]", url="https://feed.theepochtimes.com/business/feed", limit=14, max_age_hours=96, full_text=false, agenda_only=true },
    { section="Coverage Scan", agenda_category="Technology & AI", name="The Epoch Times — Tech [Coverage Scan]", url="https://feed.theepochtimes.com/tech/feed", limit=12, max_age_hours=96, full_text=false, agenda_only=true },
    { section="Coverage Scan", agenda_category="Business & Markets", name="BBC News — Business [Coverage Scan]", url="https://feeds.bbci.co.uk/news/business/rss.xml", limit=16, max_age_hours=96, full_text=false, agenda_only=true },
    { section="Coverage Scan", agenda_category="Business & Markets", name="The Guardian — Business [Coverage Scan]", url="https://www.theguardian.com/business/rss", limit=16, max_age_hours=96, full_text=false, agenda_only=true },
    { section="Coverage Scan", agenda_category="Technology & AI", name="Ars Technica [Coverage Scan]", url="https://feeds.arstechnica.com/arstechnica/index", limit=14, max_age_hours=96, full_text=false, agenda_only=true },
    { section="Coverage Scan", agenda_category="Technology & AI", name="BBC News — Technology [Coverage Scan]", url="https://feeds.bbci.co.uk/news/technology/rss.xml", limit=14, max_age_hours=96, full_text=false, agenda_only=true },
    { section="Coverage Scan", agenda_category="Science", name="BBC News — Science & Environment [Coverage Scan]", url="https://feeds.bbci.co.uk/news/science_and_environment/rss.xml", limit=12, max_age_hours=120, full_text=false, agenda_only=true },
    { section="Coverage Scan", agenda_category="Culture", name="The Guardian — Culture [Coverage Scan]", url="https://www.theguardian.com/culture/rss", limit=12, max_age_hours=120, full_text=false, agenda_only=true },
}
