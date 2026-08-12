local Base = require("newsroom_v07")

-- v0.8 Coverage Net
-- Public RSS headline/summary text is useful newsroom evidence, even when the
-- linked article is subscriber-only. We use only the material actually exposed
-- by the public feed. We never infer or reconstruct the undisclosed article.
local Newsroom = {}
for k, v in pairs(Base) do Newsroom[k] = v end

local function nonempty(s)
    return type(s) == "string" and s:gsub("%s+", "") ~= ""
end

local function clean(s)
    return tostring(s or ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

local function clone_sections(sections)
    local out = {}
    for section, items in pairs(sections or {}) do
        out[section] = {}
        for i, item in ipairs(items or {}) do out[section][i] = item end
    end
    return out
end

local function evidence_section(item)
    local category = tostring(item.agenda_category or "")
    if category == "World News" then return "World" end
    if category == "U.S. Business" or category == "Markets" then return "Business & Markets" end
    if category:find("Technology", 1, true) then return "Technology & AI" end
    -- Opinion and lifestyle feeds remain agenda signals only. An opinion-feed
    -- summary can tell the editor a topic is salient, but it is not promoted to
    -- factual evidence simply because it appeared in RSS.
    return nil
end

local function inject_public_feed_evidence(opts)
    local sections = clone_sections(opts.sections or {})
    local added = 0
    local seen = {}

    for _, section in pairs(sections) do
        for _, item in ipairs(section) do
            local key = clean(item.source) .. "|" .. clean(item.title):lower()
            seen[key] = true
        end
    end

    for _, item in ipairs(opts.agenda_items or {}) do
        local section = evidence_section(item)
        local summary = clean(item.description)
        local headline = clean(item.title)
        if section and headline ~= "" and #summary >= 70 then
            local source = clean(item.source or "Public RSS")
            local key = source .. "|" .. headline:lower()
            if not seen[key] then
                sections[section] = sections[section] or {}
                sections[section][#sections[section] + 1] = {
                    title = headline,
                    source = source .. " — public RSS summary",
                    date = item.date or "",
                    published_epoch = item.published_epoch or 0,
                    content_mode = "Public RSS headline/summary — limited evidence",
                    body = "PUBLIC FEED MATERIAL ONLY. Use only facts explicitly stated in this public summary; do not infer, recreate, or attribute details from any subscriber-only article behind it. Prefer corroboration from other supplied reporting whenever possible.\n\n" .. summary,
                    description = summary,
                    link = item.link or "",
                }
                seen[key] = true
                added = added + 1
            end
        end
    end

    return sections, added
end

function Newsroom.generate(opts)
    opts = opts or {}
    local expanded_sections, rss_evidence_count = inject_public_feed_evidence(opts)
    local forwarded = {}
    for k, v in pairs(opts) do forwarded[k] = v end
    forwarded.sections = expanded_sections

    local output, err, model, count, stats = Base.generate(forwarded)
    stats = stats or {}
    stats.public_rss_evidence = rss_evidence_count
    return output, err, model, count, stats
end

return Newsroom
