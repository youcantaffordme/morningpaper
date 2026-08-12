-- Morning Paper v0.9 — Event Cluster Coverage Net
--
-- The raw RSS/article items are RESEARCH REPORTS, not finished newspaper stories.
-- This layer groups reporting about the same real-world event before the AI desks
-- run. A cluster can contain several outlets plus public paywall-headline signals.
-- The AI therefore receives an evidence packet for an EVENT instead of a pile of
-- unrelated single-publisher articles.
--
-- Nothing here bypasses a paywall. Public RSS headlines/summaries are used only
-- to identify important topics and, when a summary is publicly supplied, as the
-- limited evidence actually present in that summary.

local Base = require("newsroom_v07")
local base_generate = Base.generate
local base_resolve_model = Base.resolveModel

local STOP = {}
for word in ([[
the a an and or but of for to in on at by with from as is are was were be been
being this that these those it its their his her says say said after before amid
over into about new latest live update updates watch report reports reporting
could would should may might will more most less than how why what when where who
]]) :gmatch("%S+") do
    STOP[word] = true
end

local SECTION_ORDER = {
    "Front Page", "World", "U.S.", "Business & Markets",
    "Technology & AI", "Science", "Culture",
}

local SECTION_CAP = {
    ["World"] = 7,
    ["U.S."] = 7,
    ["Business & Markets"] = 7,
    ["Technology & AI"] = 6,
    ["Science"] = 5,
    ["Culture"] = 5,
    ["Front Page"] = 6,
}

local function clean(s)
    return tostring(s or ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

local function normalize_source(s)
    s = clean(s)
    s = s:gsub("%s+—%s+public RSS summary$", "")
    return s
end

local function title_key(s)
    return clean(s):lower():gsub("[^%w%s]", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

local function token_set(s)
    local set, count = {}, 0
    s = title_key(s)
    for word in s:gmatch("%S+") do
        if #word >= 3 and not STOP[word] and not set[word] then
            set[word] = true
            count = count + 1
        end
    end
    return set, count
end

local function similarity(a, b)
    local ak = title_key(a)
    local bk = title_key(b)
    if ak == "" or bk == "" then return 0, 0 end
    if ak == bk then return 1, 99 end

    local aset, ac = token_set(a)
    local bset, bc = token_set(b)
    if ac == 0 or bc == 0 then return 0, 0 end

    local hits = 0
    for word in pairs(aset) do
        if bset[word] then hits = hits + 1 end
    end
    local containment = hits / math.max(1, math.min(ac, bc))
    local union = ac + bc - hits
    local jaccard = union > 0 and hits / union or 0
    return math.max(containment, jaccard), hits
end

local function same_event(a, b)
    local score, hits = similarity(a, b)
    if hits >= 4 and score >= 0.40 then return true end
    if hits >= 3 and score >= 0.50 then return true end
    if hits >= 2 and score >= 0.72 then return true end
    return false
end

local function agenda_section(item)
    local category = tostring(item.agenda_category or "")
    if category == "World News" then return "World" end
    if category == "U.S. Business" or category == "Markets" then return "Business & Markets" end
    if category:find("Technology", 1, true) then return "Technology & AI" end
    return nil
end

local function member_quality(item)
    local mode = clean(item.content_mode):lower()
    if mode:find("full article", 1, true) then return 3 end
    if mode:find("feed excerpt", 1, true) then return 2 end
    return 1
end

local function cluster_score(cluster)
    local outlets, fulls = {}, 0
    local newest = 0
    for _, item in ipairs(cluster.members) do
        outlets[normalize_source(item.source)] = true
        if member_quality(item) == 3 then fulls = fulls + 1 end
        newest = math.max(newest, tonumber(item.published_epoch) or 0)
    end
    local outlet_count = 0
    for _ in pairs(outlets) do outlet_count = outlet_count + 1 end
    local lead_bonus = #(cluster.agenda or {}) * 5
    local diversity_bonus = math.max(0, outlet_count - 1) * 4
    local evidence_bonus = math.min(#cluster.members, 6) * 1.25 + math.min(fulls, 4)
    local freshness = newest > 0 and math.max(0, 2 - ((os.time() - newest) / 86400)) or 0
    return lead_bonus + diversity_bonus + evidence_bonus + freshness, outlet_count, fulls, newest
end

local function best_cluster_headline(cluster)
    local best, best_score = nil, -1
    for _, item in ipairs(cluster.members) do
        local score = member_quality(item) * 10 + math.min(#clean(item.title), 120) / 20
        if score > best_score then
            best, best_score = item, score
        end
    end
    return best and clean(best.title) or "Morning Paper event"
end

local function choose_section(cluster)
    local votes = {}
    for _, item in ipairs(cluster.members) do
        local section = item._research_section or item.section
        if section and section ~= "Front Page" then
            votes[section] = (votes[section] or 0) + 1
        end
    end
    for _, signal in ipairs(cluster.agenda or {}) do
        local mapped = agenda_section(signal)
        if mapped then votes[mapped] = (votes[mapped] or 0) + 2 end
    end

    local best, best_n = nil, -1
    for _, section in ipairs(SECTION_ORDER) do
        if section ~= "Front Page" then
            local n = votes[section] or 0
            if n > best_n then best, best_n = section, n end
        end
    end
    if best and best_n > 0 then return best end
    local first = cluster.members[1]
    return first and (first._research_section or first.section) or "Front Page"
end

local function add_member_to_cluster(cluster, item)
    cluster.members[#cluster.members + 1] = item
    local source = normalize_source(item.source)
    if source ~= "" then cluster.sources[source] = true end
end

local function build_clusters(sections)
    local clusters = {}
    for _, section in ipairs(SECTION_ORDER) do
        for _, original in ipairs((sections or {})[section] or {}) do
            local item = {}
            for k, v in pairs(original) do item[k] = v end
            item._research_section = section

            local best_cluster, best_score = nil, 0
            for _, cluster in ipairs(clusters) do
                local score, hits = similarity(item.title, cluster.anchor)
                if same_event(item.title, cluster.anchor) and score > best_score then
                    best_cluster, best_score = cluster, score
                else
                    -- Also compare against a few member headlines. Two outlets may
                    -- phrase the same event very differently from the first anchor.
                    for i = 1, math.min(#cluster.members, 4) do
                        local ms, mh = similarity(item.title, cluster.members[i].title)
                        if same_event(item.title, cluster.members[i].title) and ms > best_score then
                            best_cluster, best_score = cluster, ms
                        end
                    end
                end
            end

            if best_cluster then
                add_member_to_cluster(best_cluster, item)
            else
                local cluster = { anchor=clean(item.title), members={}, sources={}, agenda={} }
                add_member_to_cluster(cluster, item)
                clusters[#clusters + 1] = cluster
            end
        end
    end
    return clusters
end

local function attach_agenda(clusters, agenda_items)
    local matched = 0
    for _, agenda in ipairs(agenda_items or {}) do
        local best, best_score = nil, 0
        for _, cluster in ipairs(clusters) do
            local score, hits = similarity(agenda.title, cluster.anchor)
            local ok = (hits >= 3 and score >= 0.42) or (hits >= 2 and score >= 0.68)
            if not ok then
                for i = 1, math.min(#cluster.members, 4) do
                    local ms, mh = similarity(agenda.title, cluster.members[i].title)
                    if (mh >= 3 and ms >= 0.42) or (mh >= 2 and ms >= 0.68) then
                        score, ok = ms, true
                        break
                    end
                end
            end
            if ok and score > best_score then best, best_score = cluster, score end
        end
        if best then
            best.agenda[#best.agenda + 1] = agenda
            matched = matched + 1
        end
    end
    return matched
end

local function compact_member(item, budget)
    local source = normalize_source(item.source)
    local headline = clean(item.title)
    local body = clean(item.body or item.description)
    if #body > budget then body = body:sub(1, budget) .. "…" end
    return string.format("[%s] %s — %s", source ~= "" and source or "Source", headline, body)
end

local function cluster_item(cluster)
    local score, outlet_count, fulls, newest = cluster_score(cluster)
    local source_names = {}
    for source in pairs(cluster.sources) do source_names[#source_names + 1] = source end
    table.sort(source_names)

    local ranked = {}
    for _, item in ipairs(cluster.members) do ranked[#ranked + 1] = item end
    table.sort(ranked, function(a, b)
        local aq, bq = member_quality(a), member_quality(b)
        if aq == bq then return (a.published_epoch or 0) > (b.published_epoch or 0) end
        return aq > bq
    end)

    local parts = {}
    for i = 1, math.min(#ranked, 5) do
        parts[#parts + 1] = compact_member(ranked[i], i <= 3 and 320 or 220)
    end
    if #(cluster.agenda or {}) > 0 then
        local leads = {}
        for i = 1, math.min(#cluster.agenda, 3) do
            leads[#leads + 1] = clean(cluster.agenda[i].source) .. ": " .. clean(cluster.agenda[i].title)
        end
        parts[#parts + 1] = "PUBLIC PAYWALL/TOPIC LEADS: " .. table.concat(leads, " | ") .. ". These leads establish importance/topic only; rely on the public reports above for factual details."
    end

    local section = choose_section(cluster)
    local mode = string.format(
        "Coverage Net event cluster · %d reports · %d independent outlets · %d full articles%s",
        #cluster.members, outlet_count, fulls,
        #(cluster.agenda or {}) > 0 and (" · " .. tostring(#cluster.agenda) .. " paywall/topic lead match(es)") or ""
    )

    return {
        title = best_cluster_headline(cluster),
        source = "Coverage Net — " .. table.concat(source_names, "; "),
        date = os.date("%a, %d %b %Y %H:%M:%S %z", newest > 0 and newest or os.time()),
        published_epoch = newest,
        content_mode = mode,
        body = table.concat(parts, "\n\n"),
        description = table.concat(parts, " "),
        link = "",
        coverage_score = score,
        coverage_reports = #cluster.members,
        coverage_outlets = outlet_count,
        coverage_full_articles = fulls,
        coverage_agenda_hits = #(cluster.agenda or {}),
    }, section, score, outlet_count
end

local function clustered_sections(sections, agenda_items)
    local clusters = build_clusters(sections)
    local agenda_matches = attach_agenda(clusters, agenda_items)
    local out = {}
    local multi_source = 0
    local lead_clusters = 0

    for _, cluster in ipairs(clusters) do
        local item, section, score, outlet_count = cluster_item(cluster)
        if outlet_count >= 2 then multi_source = multi_source + 1 end
        if item.coverage_agenda_hits > 0 then lead_clusters = lead_clusters + 1 end
        out[section] = out[section] or {}
        out[section][#out[section] + 1] = item
    end

    for _, section in ipairs(SECTION_ORDER) do
        local list = out[section]
        if list then
            table.sort(list, function(a, b)
                if (a.coverage_score or 0) == (b.coverage_score or 0) then
                    return (a.published_epoch or 0) > (b.published_epoch or 0)
                end
                return (a.coverage_score or 0) > (b.coverage_score or 0)
            end)
            local cap = SECTION_CAP[section] or 6
            while #list > cap do table.remove(list) end
        end
    end

    return out, {
        raw_reports = 0,
        clusters_total = #clusters,
        multi_source_clusters = multi_source,
        lead_matched_clusters = lead_clusters,
        agenda_matches = agenda_matches,
    }
end

-- If Morning Paper is set to Follow KOAssistant but KOAssistant's current-model
-- setting cannot be resolved, prefer the user's known paid Sonnet option rather
-- than silently dropping to a random free router model. The menu can still be
-- explicitly set to OpenRouter Free when desired.
function Base.resolveModel(requested_model)
    local model, source = base_resolve_model(requested_model)
    if requested_model == Base.FOLLOW_MODEL and model == Base.FREE_MODEL then
        return Base.SONNET5_MODEL, "KOAssistant model unavailable; Claude Sonnet 5 fallback"
    end
    return model, source
end

function Base.generate(opts)
    opts = opts or {}
    local raw_count = 0
    for _, section in ipairs(SECTION_ORDER) do
        raw_count = raw_count + #((opts.sections or {})[section] or {})
    end

    local clustered, coverage = clustered_sections(opts.sections or {}, opts.agenda_items or {})
    coverage.raw_reports = raw_count

    local forwarded = {}
    for k, v in pairs(opts) do forwarded[k] = v end
    forwarded.sections = clustered

    local output, err, model, count, stats = base_generate(forwarded)
    stats = stats or {}
    stats.coverage_raw_reports = coverage.raw_reports
    stats.coverage_clusters = coverage.clusters_total
    stats.coverage_multi_source = coverage.multi_source_clusters
    stats.coverage_lead_clusters = coverage.lead_matched_clusters
    stats.coverage_agenda_matches = coverage.agenda_matches

    local coverage_note = string.format(
        "Coverage Net condensed %d research reports into %d event clusters; %d clusters use multiple independent outlets; %d clusters matched public paywall/topic leads.",
        coverage.raw_reports, coverage.clusters_total, coverage.multi_source_clusters, coverage.lead_matched_clusters
    )

    if err then err = tostring(err) .. " | " .. coverage_note end
    if model and not err then
        model = tostring(model) .. string.format(" · Coverage Net %d clusters/%d multi-source/%d lead-matched", coverage.clusters_total, coverage.multi_source_clusters, coverage.lead_matched_clusters)
    end

    return output, err, model, count, stats
end

return Base
