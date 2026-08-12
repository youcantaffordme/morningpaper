-- Morning Paper v0.12.3 — Consensus Lead Desk
--
-- Public headlines from major paywalled publications are agenda signals only.
-- This layer clusters those signals by event before the newsroom runs. Multiple
-- feeds from the SAME publication count only once toward consensus, so a story
-- repeated across WSJ sections cannot masquerade as multi-outlet agreement.
-- Hidden subscriber text is never fetched, inferred, or treated as evidence.

local Base = require("newsroom_v09")
local base_generate = Base.generate

Base.CONSENSUS_LEAD_DESK_VERSION = "0.12.3"

local STOP = {}
for word in ([[
the a an and or but of for to in on at by with from as is are was were be been
being this that these those it its their his her says say said after before amid
over into about new latest live update updates watch report reports reporting
could would should may might will more most less than how why what when where who
]]) :gmatch("%S+") do
    STOP[word] = true
end

local function clean(s)
    return tostring(s or ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

local function title_key(s)
    return clean(s):lower():gsub("[^%w%s]", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

local function token_set(s)
    local set, count = {}, 0
    for word in title_key(s):gmatch("%S+") do
        if #word >= 3 and not STOP[word] and not set[word] then
            set[word] = true
            count = count + 1
        end
    end
    return set, count
end

local function similarity(a, b)
    local ak, bk = title_key(a), title_key(b)
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

local function same_lead_event(a, b)
    local score, hits = similarity(a, b)
    if hits >= 5 and score >= 0.32 then return true end
    if hits >= 4 and score >= 0.38 then return true end
    if hits >= 3 and score >= 0.48 then return true end
    if hits >= 2 and score >= 0.68 then return true end
    return false
end

local function is_coverage_scan(item)
    return tostring(item and item.source or ""):find("[Coverage Scan]", 1, true) ~= nil
end

local CANONICAL_PUBLISHERS = {
    "The Wall Street Journal",
    "Bloomberg",
    "Financial Times",
    "The New York Times",
    "The Washington Post",
    "Barron's",
    "The Economist",
}

local function publisher_name(source)
    local s = clean(source)
    s = s:gsub("%s*%[PAYWALL LEAD%]%s*$", "")

    -- Canonicalize every feed belonging to the same publication. This is
    -- especially important for the legacy WSJ World/Markets/Tech/etc. feeds.
    for _, publisher in ipairs(CANONICAL_PUBLISHERS) do
        if s:sub(1, #publisher) == publisher then return publisher end
    end

    s = s:gsub("%s+—%s+fresh headline leads.*$", "")
    s = s:gsub("%s+%-+%s+fresh headline leads.*$", "")
    return clean(s)
end

local function strip_publisher_suffix(title, publisher)
    local t = clean(title)
    if publisher == "" then return t end
    for _, sep in ipairs({" - ", " — ", " | "}) do
        local suffix = sep .. publisher
        if #t > #suffix and t:sub(-#suffix) == suffix then
            return clean(t:sub(1, #t - #suffix))
        end
    end
    return t
end

local function clone(item)
    local out = {}
    for k, v in pairs(item or {}) do out[k] = v end
    return out
end

local function best_cluster(clusters, lead)
    local best, best_score = nil, 0
    for _, cluster in ipairs(clusters) do
        local lead_title = lead._lead_match_title or lead.title
        local score = similarity(lead_title, cluster.anchor)
        local ok = same_lead_event(lead_title, cluster.anchor)
        for _, member in ipairs(cluster.members) do
            local member_title = member._lead_match_title or member.title
            local ms = similarity(lead_title, member_title)
            if same_lead_event(lead_title, member_title) and ms > score then
                score, ok = ms, true
            end
        end
        if ok and score > best_score then best, best_score = cluster, score end
    end
    return best
end

local function cluster_leads(leads)
    local clusters = {}
    for _, original in ipairs(leads) do
        local lead = clone(original)
        lead._lead_publisher = publisher_name(lead.source)
        lead._lead_match_title = strip_publisher_suffix(lead.title, lead._lead_publisher)
        local cluster = best_cluster(clusters, lead)
        if not cluster then
            cluster = { anchor=clean(lead._lead_match_title or lead.title), members={}, publishers={}, newest=0 }
            clusters[#clusters + 1] = cluster
        end
        cluster.members[#cluster.members + 1] = lead
        if lead._lead_publisher ~= "" then cluster.publishers[lead._lead_publisher] = true end
        cluster.newest = math.max(cluster.newest, tonumber(lead.published_epoch) or 0)
    end

    for _, cluster in ipairs(clusters) do
        local publisher_count = 0
        for _ in pairs(cluster.publishers) do publisher_count = publisher_count + 1 end
        cluster.publisher_count = publisher_count
        local age_hours = cluster.newest > 0 and math.max(0, (os.time() - cluster.newest) / 3600) or 72
        local freshness = math.max(0, 36 - age_hours)
        -- Independent publisher consensus dominates; raw duplicate headline count
        -- is intentionally not part of the score.
        cluster.priority_score = publisher_count * 100 + freshness
    end

    table.sort(clusters, function(a, b)
        if a.priority_score == b.priority_score then return a.newest > b.newest end
        return a.priority_score > b.priority_score
    end)
    return clusters
end

local function prioritized_agenda(items)
    local leads, scans = {}, {}
    for _, item in ipairs(items or {}) do
        if is_coverage_scan(item) then scans[#scans + 1] = clone(item)
        else leads[#leads + 1] = clone(item) end
    end

    local clusters = cluster_leads(leads)
    local ordered = {}
    local consensus_clusters = 0
    local forwarded_leads = 0

    for rank, cluster in ipairs(clusters) do
        if cluster.publisher_count >= 2 then consensus_clusters = consensus_clusters + 1 end
        table.sort(cluster.members, function(a, b)
            return (tonumber(a.published_epoch) or 0) > (tonumber(b.published_epoch) or 0)
        end)

        -- Forward only the newest signal from each independent publisher for this
        -- event. newsroom_v09's lead bonus therefore measures publisher consensus,
        -- not duplicate feeds/headlines from one outlet.
        local publisher_seen = {}
        for _, lead in ipairs(cluster.members) do
            local publisher = lead._lead_publisher ~= "" and lead._lead_publisher or publisher_name(lead.source)
            if publisher ~= "" and not publisher_seen[publisher] then
                publisher_seen[publisher] = true
                lead.lead_rank = rank
                lead.lead_consensus = cluster.publisher_count
                lead.lead_priority_score = cluster.priority_score
                lead.agenda_category = string.format(
                    "Front Page Priority #%d · %d major publication%s",
                    rank, cluster.publisher_count, cluster.publisher_count == 1 and "" or "s"
                )
                ordered[#ordered + 1] = lead
                forwarded_leads = forwarded_leads + 1
            end
        end
    end

    table.sort(scans, function(a, b)
        return (tonumber(a.published_epoch) or 0) > (tonumber(b.published_epoch) or 0)
    end)
    for _, scan in ipairs(scans) do ordered[#ordered + 1] = scan end

    return ordered, #leads, forwarded_leads, #clusters, consensus_clusters
end

function Base.generate(opts)
    opts = opts or {}
    local agenda, lead_count, forwarded_leads, lead_clusters, consensus_clusters = prioritized_agenda(opts.agenda_items or {})

    local forwarded = {}
    for k, v in pairs(opts) do forwarded[k] = v end
    forwarded.agenda_items = agenda

    local output, err, model, count, stats = base_generate(forwarded)
    stats = stats or {}
    stats.paywall_leads_scanned = lead_count
    stats.paywall_leads_forwarded = forwarded_leads
    stats.paywall_lead_clusters = lead_clusters
    stats.paywall_consensus_clusters = consensus_clusters
    stats.consensus_lead_desk_version = Base.CONSENSUS_LEAD_DESK_VERSION

    local note = string.format(
        "Consensus Lead Desk: %d fresh signals -> %d unique publisher/event signals across %d topics; %d topics appeared across 2+ major publications.",
        lead_count, forwarded_leads, lead_clusters, consensus_clusters
    )
    if model and not err then
        model = tostring(model) .. string.format(
            " · Lead Desk %d raw/%d unique/%d consensus topics",
            lead_count, forwarded_leads, consensus_clusters
        )
    elseif err then
        err = tostring(err) .. " | " .. note
    end

    return output, err, model, count, stats
end

return Base
