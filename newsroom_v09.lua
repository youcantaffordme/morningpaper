-- Morning Paper v0.10 — Wide Event Cluster Coverage Net
--
-- Raw RSS/article items are RESEARCH REPORTS, not finished newspaper stories.
-- This layer groups reporting about the same real-world event before AI desks
-- run. It also consumes deeper public RSS headline/summary scans as limited
-- corroborating evidence, while public paywall feeds remain importance/topic
-- leads only. Nothing here bypasses a paywall or reconstructs hidden text.

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
    ["World"] = 8,
    ["U.S."] = 8,
    ["Business & Markets"] = 8,
    ["Technology & AI"] = 7,
    ["Science"] = 6,
    ["Culture"] = 6,
    ["Front Page"] = 7,
}

local function clean(s)
    return tostring(s or ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

local function strip_scan_label(s)
    s = clean(s)
    return s:gsub("%s*%[Coverage Scan%]%s*$", "")
end

local function normalize_source(s)
    s = strip_scan_label(s)
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
    for word in pairs(aset) do if bset[word] then hits = hits + 1 end end
    local containment = hits / math.max(1, math.min(ac, bc))
    local union = ac + bc - hits
    local jaccard = union > 0 and hits / union or 0
    return math.max(containment, jaccard), hits
end

local function same_event(a, b)
    local score, hits = similarity(a, b)
    if hits >= 5 and score >= 0.34 then return true end
    if hits >= 4 and score >= 0.40 then return true end
    if hits >= 3 and score >= 0.50 then return true end
    if hits >= 2 and score >= 0.72 then return true end
    return false
end

local function agenda_section(item)
    local category = tostring(item.agenda_category or "")
    for _, section in ipairs(SECTION_ORDER) do
        if category == section then return section end
    end
    if category == "World News" then return "World" end
    if category == "U.S. Business" or category == "Markets" then return "Business & Markets" end
    if category:find("Technology", 1, true) then return "Technology & AI" end
    return nil
end

local function is_coverage_scan(item)
    return tostring(item.source or ""):find("[Coverage Scan]", 1, true) ~= nil
end

local function is_paywall_lead(item)
    return not is_coverage_scan(item)
end

local function member_quality(item)
    local mode = clean(item.content_mode):lower()
    if mode:find("full article", 1, true) then return 4 end
    if mode:find("public rss summary", 1, true) then return 2 end
    if mode:find("feed excerpt", 1, true) then return 2 end
    return 1
end

local function member_match_text(item)
    local summary = clean(item.description or item.body):sub(1, 180)
    return clean(item.title) .. " " .. summary
end

local function cluster_score(cluster)
    local outlets, fulls, summaries = {}, 0, 0
    local newest = 0
    for _, item in ipairs(cluster.members) do
        local src = normalize_source(item.source)
        if src ~= "" then outlets[src] = true end
        local q = member_quality(item)
        if q >= 4 then fulls = fulls + 1 end
        if tostring(item.content_mode or ""):lower():find("public rss summary", 1, true) then summaries = summaries + 1 end
        newest = math.max(newest, tonumber(item.published_epoch) or 0)
    end
    local outlet_count = 0
    for _ in pairs(outlets) do outlet_count = outlet_count + 1 end
    local lead_bonus = math.min(#(cluster.agenda or {}), 3) * 5
    local diversity_bonus = math.max(0, outlet_count - 1) * 5
    local evidence_bonus = math.min(#cluster.members, 8) * 1.25 + math.min(fulls, 4) * 1.5 + math.min(summaries, 4) * 0.5
    local freshness = newest > 0 and math.max(0, 2 - ((os.time() - newest) / 86400)) or 0
    return lead_bonus + diversity_bonus + evidence_bonus + freshness, outlet_count, fulls, newest
end

local function best_cluster_headline(cluster)
    local best, best_score = nil, -1
    for _, item in ipairs(cluster.members) do
        local score = member_quality(item) * 10 + math.min(#clean(item.title), 120) / 20
        if score > best_score then best, best_score = item, score end
    end
    return best and clean(best.title) or "Morning Paper event"
end

local function choose_section(cluster)
    local votes = {}
    for _, item in ipairs(cluster.members) do
        local section = item._research_section or item.section
        if section and section ~= "Front Page" then votes[section] = (votes[section] or 0) + 1 end
    end
    for _, signal in ipairs(cluster.agenda or {}) do
        local mapped = agenda_section(signal)
        if mapped and mapped ~= "Front Page" then votes[mapped] = (votes[mapped] or 0) + 2 end
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

local function has_member(cluster, candidate)
    local csource = normalize_source(candidate.source)
    local ctitle = title_key(candidate.title)
    for _, item in ipairs(cluster.members or {}) do
        if normalize_source(item.source) == csource and title_key(item.title) == ctitle then return true end
    end
    return false
end

local function add_member_to_cluster(cluster, item)
    if has_member(cluster, item) then return false end
    cluster.members[#cluster.members + 1] = item
    local source = normalize_source(item.source)
    if source ~= "" then cluster.sources[source] = true end
    return true
end

local function best_cluster_match(clusters, item)
    local best_cluster, best_score = nil, 0
    local candidate_title = clean(item.title)
    for _, cluster in ipairs(clusters) do
        local score = similarity(candidate_title, cluster.anchor)
        local ok = same_event(candidate_title, cluster.anchor)
        for i = 1, math.min(#cluster.members, 5) do
            local member = cluster.members[i]
            local ms = similarity(candidate_title, member.title)
            local contextual = similarity(candidate_title, member_match_text(member))
            local local_score = math.max(ms, contextual)
            local local_ok = same_event(candidate_title, member.title) or same_event(candidate_title, member_match_text(member))
            if local_ok and local_score > score then score, ok = local_score, true end
        end
        if ok and score > best_score then best_cluster, best_score = cluster, score end
    end
    return best_cluster, best_score
end

local function build_clusters(sections)
    local clusters = {}
    for _, section in ipairs(SECTION_ORDER) do
        for _, original in ipairs((sections or {})[section] or {}) do
            local item = {}
            for k, v in pairs(original) do item[k] = v end
            item._research_section = section
            local best_cluster = best_cluster_match(clusters, item)
            if best_cluster then
                add_member_to_cluster(best_cluster, item)
            else
                local cluster = { anchor=clean(item.title), members={}, sources={}, agenda={}, scan_seed=false }
                add_member_to_cluster(cluster, item)
                clusters[#clusters + 1] = cluster
            end
        end
    end
    return clusters
end

local function synthetic_scan_member(item)
    local summary = clean(item.description)
    if #summary < 55 then return nil end
    return {
        title = clean(item.title),
        source = strip_scan_label(item.source),
        date = item.date or "",
        published_epoch = tonumber(item.published_epoch) or 0,
        content_mode = "Public RSS summary — limited evidence",
        body = summary,
        description = summary,
        link = item.link or "",
        _research_section = agenda_section(item) or "Front Page",
    }
end

local function attach_coverage_scans(clusters, agenda_items)
    local summary_evidence, seeded = 0, 0
    for _, scan in ipairs(agenda_items or {}) do
        if is_coverage_scan(scan) then
            local member = synthetic_scan_member(scan)
            if member then
                local best = best_cluster_match(clusters, member)
                if best then
                    if add_member_to_cluster(best, member) then summary_evidence = summary_evidence + 1 end
                else
                    local cluster = { anchor=clean(member.title), members={}, sources={}, agenda={}, scan_seed=true }
                    add_member_to_cluster(cluster, member)
                    clusters[#clusters + 1] = cluster
                    summary_evidence = summary_evidence + 1
                    seeded = seeded + 1
                end
            end
        end
    end
    return summary_evidence, seeded
end

local function attach_paywall_leads(clusters, agenda_items)
    local matched = 0
    for _, agenda in ipairs(agenda_items or {}) do
        if is_paywall_lead(agenda) then
            local best, best_score = best_cluster_match(clusters, agenda)
            if best and best_score > 0 then
                best.agenda[#best.agenda + 1] = agenda
                matched = matched + 1
            end
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
    for i = 1, math.min(#ranked, 7) do
        local budget = i <= 3 and 430 or (i <= 5 and 300 or 220)
        parts[#parts + 1] = compact_member(ranked[i], budget)
    end
    if #(cluster.agenda or {}) > 0 then
        local leads = {}
        for i = 1, math.min(#cluster.agenda, 4) do
            leads[#leads + 1] = clean(cluster.agenda[i].source) .. ": " .. clean(cluster.agenda[i].title)
        end
        parts[#parts + 1] = "PUBLIC PAYWALL/TOPIC LEADS: " .. table.concat(leads, " | ") .. ". These leads establish importance/topic only; factual details must come from the public reports above."
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
        coverage_scan_seed = cluster.scan_seed and true or false,
    }, section, score, outlet_count
end

local function clustered_sections(sections, agenda_items)
    local clusters = build_clusters(sections)
    local scan_evidence, scan_seed_clusters = attach_coverage_scans(clusters, agenda_items)
    local agenda_matches = attach_paywall_leads(clusters, agenda_items)
    local out = {}
    local multi_source, lead_clusters = 0, 0

    for _, cluster in ipairs(clusters) do
        local item, section, _, outlet_count = cluster_item(cluster)
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
            local cap = SECTION_CAP[section] or 7
            while #list > cap do table.remove(list) end
        end
    end

    return out, {
        raw_reports = 0,
        clusters_total = #clusters,
        multi_source_clusters = multi_source,
        lead_matched_clusters = lead_clusters,
        agenda_matches = agenda_matches,
        scan_summary_evidence = scan_evidence,
        scan_seed_clusters = scan_seed_clusters,
    }
end

-- Follow KOAssistant when it can be resolved. If it cannot, do not silently
-- route a serious newspaper through a random free model; use Sonnet 5 instead.
function Base.resolveModel(requested_model)
    local model, source = base_resolve_model(requested_model)
    local follows = requested_model == nil or requested_model == "" or requested_model == Base.FOLLOW_MODEL
    if follows and model == Base.FREE_MODEL then
        return Base.SONNET5_MODEL, "KOAssistant model unavailable; Claude Sonnet 5 fallback"
    end
    return model, source
end

function Base.generate(opts)
    opts = opts or {}
    local raw_count = 0
    for _, section in ipairs(SECTION_ORDER) do raw_count = raw_count + #((opts.sections or {})[section] or {}) end

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
    stats.coverage_scan_summaries = coverage.scan_summary_evidence
    stats.coverage_scan_seed_clusters = coverage.scan_seed_clusters

    local coverage_note = string.format(
        "Coverage Net: %d full/excerpt research reports + %d public RSS corroboration summaries -> %d event clusters; %d clusters use multiple independent outlets; %d clusters matched public paywall/topic leads.",
        coverage.raw_reports, coverage.scan_summary_evidence, coverage.clusters_total, coverage.multi_source_clusters, coverage.lead_matched_clusters
    )

    if err then err = tostring(err) .. " | " .. coverage_note end
    if model and not err then
        model = tostring(model) .. string.format(
            " · Coverage Net %d clusters/%d multi-source/%d lead-matched/%d RSS corroborations",
            coverage.clusters_total, coverage.multi_source_clusters, coverage.lead_matched_clusters, coverage.scan_summary_evidence
        )
    end

    return output, err, model, count, stats
end

return Base
