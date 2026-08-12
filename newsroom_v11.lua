-- Morning Paper v0.11 — Lead-First Editorial Agenda
--
-- Wide Coverage Net already uses Coverage Scan entries as corroborating research.
-- They should NOT crowd the 45-line editorial agenda shown to the Front Page AI.
-- This wrapper keeps every scan available to Coverage Net, but reorders the input
-- so genuine paywall/topic leads come first. That makes WSJ/Bloomberg/FT/NYT/etc.
-- act like assignment-desk leads while accessible reporting supplies the facts.

local Base = require("newsroom_v09")
local base_generate = Base.generate

local function is_coverage_scan(item)
    return tostring(item and item.source or ""):find("[Coverage Scan]", 1, true) ~= nil
end

local function by_newest(a, b)
    return (tonumber(a and a.published_epoch) or 0) > (tonumber(b and b.published_epoch) or 0)
end

function Base.generate(opts)
    opts = opts or {}
    local leads, scans = {}, {}
    for _, item in ipairs(opts.agenda_items or {}) do
        if is_coverage_scan(item) then scans[#scans + 1] = item
        else leads[#leads + 1] = item end
    end
    table.sort(leads, by_newest)
    table.sort(scans, by_newest)

    -- IMPORTANT: the v0.10 Coverage Net still receives BOTH lists, so scans can
    -- join event clusters. Leads are simply placed first so the base newsroom's
    -- capped editorial-agenda prompt is actually a paywall lead desk.
    local agenda = {}
    for _, item in ipairs(leads) do agenda[#agenda + 1] = item end
    for _, item in ipairs(scans) do agenda[#agenda + 1] = item end

    local forwarded = {}
    for k, v in pairs(opts) do forwarded[k] = v end
    forwarded.agenda_items = agenda

    local output, err, model, count, stats = base_generate(forwarded)
    stats = stats or {}
    stats.paywall_leads_scanned = #leads
    stats.coverage_scans_available = #scans

    if model and not err then
        model = tostring(model) .. string.format(" · Lead Desk %d fresh signals", #leads)
    elseif err then
        err = tostring(err) .. string.format(" | Lead Desk supplied %d paywall/topic signals before %d coverage scans.", #leads, #scans)
    end

    return output, err, model, count, stats
end

return Base
