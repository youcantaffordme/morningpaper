-- Morning Paper v0.8 Coverage Net
--
-- Keep the proven v0.7 newsroom module as the object main_v07 receives, and
-- enhance its generate() method in place. This avoids swapping package.loaded
-- entries during plugin startup, which proved fragile on KOReader.
--
-- Coverage Net never bypasses a paywall. Public RSS headlines/summaries are
-- editorial leads and limited evidence only. The actual Morning Paper story is
-- written from public material the plugin really received, preferably
-- corroborated across multiple independent sources.

local Base = require("newsroom_v07")
local base_generate = Base.generate

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

local STOP = {
    the=true, a=true, an=true, ["and"]=true, ["or"]=true, but=true, of=true, ["for"]=true, to=true,
    ["in"]=true, on=true, at=true, by=true, with=true, from=true, as=true, is=true, are=true,
    was=true, were=true, be=true, been=true, being=true, this=true, that=true, these=true,
    those=true, it=true, its=true, their=true, his=true, her=true, says=true, say=true,
    after=true, before=true, amid=true, over=true, into=true, about=true, new=true,
}

local function token_set(s)
    local set, count = {}, 0
    s = clean(s):lower():gsub("[^%w%s]", " ")
    for word in s:gmatch("%S+") do
        if #word >= 3 and not STOP[word] and not set[word] then
            set[word] = true
            count = count + 1
        end
    end
    return set, count
end

local function overlap_score(agenda_title, item)
    local a, ac = token_set(agenda_title)
    if ac == 0 then return 0, 0 end
    local haystack = clean(item.title) .. " " .. clean(item.description) .. " " .. clean(item.body):sub(1, 700)
    local b = token_set(haystack)
    local hits = 0
    for word in pairs(a) do if b[word] then hits = hits + 1 end end
    return hits / math.max(3, math.min(ac, 8)), hits
end

local function agenda_section(item)
    local category = tostring(item.agenda_category or "")
    if category == "World News" then return "World" end
    if category == "U.S. Business" or category == "Markets" then return "Business & Markets" end
    if category:find("Technology", 1, true) then return "Technology & AI" end
    -- Opinion/lifestyle stay agenda signals rather than factual evidence.
    return nil
end

local function already_has(items, candidate)
    local ctitle = clean(candidate.title):lower()
    local csource = clean(candidate.source):lower()
    for _, item in ipairs(items or {}) do
        if clean(item.title):lower() == ctitle and clean(item.source):lower() == csource then return true end
    end
    return false
end

local function add_public_feed_summaries(sections, agenda_items)
    local added = 0
    for _, item in ipairs(agenda_items or {}) do
        local section = agenda_section(item)
        local summary, headline = clean(item.description), clean(item.title)
        if section and headline ~= "" and #summary >= 70 then
            sections[section] = sections[section] or {}
            local candidate = {
                title = headline,
                source = clean(item.source or "Public RSS") .. " — public RSS summary",
                date = item.date or "",
                published_epoch = item.published_epoch or 0,
                content_mode = "Public RSS headline/summary — limited evidence",
                body = "PUBLIC FEED MATERIAL ONLY. Use only facts explicitly stated below. Do not infer, recreate, or attribute undisclosed details from any subscriber-only article. Corroborate with independent supplied reporting whenever possible.\n\n" .. summary,
                description = summary,
                link = item.link or "",
                agenda_seed = headline,
            }
            if not already_has(sections[section], candidate) then
                sections[section][#sections[section] + 1] = candidate
                added = added + 1
            end
        end
    end
    return added
end

local function promote_correlated_public_reports(sections, original_sections, agenda_items)
    local promoted = 0
    local all = {}
    for original_section, items in pairs(original_sections or {}) do
        for _, item in ipairs(items or {}) do all[#all + 1] = { section=original_section, item=item } end
    end

    for _, agenda in ipairs(agenda_items or {}) do
        local target = agenda_section(agenda)
        if target then
            local matches = {}
            for _, record in ipairs(all) do
                local score, hits = overlap_score(agenda.title, record.item)
                if hits >= 2 and score >= 0.24 then
                    matches[#matches + 1] = { score=score, record=record }
                end
            end
            table.sort(matches, function(a, b)
                if a.score == b.score then
                    return (a.record.item.published_epoch or 0) > (b.record.item.published_epoch or 0)
                end
                return a.score > b.score
            end)

            for i = 1, math.min(3, #matches) do
                local src = matches[i].record.item
                sections[target] = sections[target] or {}
                if not already_has(sections[target], src) then
                    local copy = {}
                    for k, v in pairs(src) do copy[k] = v end
                    copy.content_mode = clean(copy.content_mode) .. " · agenda-correlated public reporting"
                    copy.agenda_seed = agenda.title
                    sections[target][#sections[target] + 1] = copy
                    promoted = promoted + 1
                end
            end
        end
    end
    return promoted
end

-- Patch the SAME newsroom table main_v07 already knows how to use.
function Base.generate(opts)
    opts = opts or {}
    local original = opts.sections or {}
    local expanded = clone_sections(original)
    local summary_count = add_public_feed_summaries(expanded, opts.agenda_items or {})
    local promoted_count = promote_correlated_public_reports(expanded, original, opts.agenda_items or {})

    local forwarded = {}
    for k, v in pairs(opts) do forwarded[k] = v end
    forwarded.sections = expanded

    local output, err, model, count, stats = base_generate(forwarded)
    stats = stats or {}
    stats.public_rss_evidence = summary_count
    stats.agenda_correlations = promoted_count
    return output, err, model, count, stats
end

return Base
