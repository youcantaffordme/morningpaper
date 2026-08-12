-- Morning Paper v0.11 keeps the proven v0.7 KOReader UI/build pipeline.
--
-- 1) Widen the accessible research net with deep public RSS headline/summary scans.
-- 2) Add a separate FRESH PAYWALL LEAD NETWORK. These entries are agenda-only:
--    they tell the editor what major subscription publications are emphasizing,
--    but their hidden text is never fetched or reconstructed.
-- 3) Coverage Net matches those leads to accessible reporting of the same event.
-- 4) The Lead-First wrapper keeps those paywall signals at the top of the actual
--    editorial agenda, so major subscription headlines can drive Front Page
--    selection while public corroboration supplies the factual reporting.

local ok_sources, sources = pcall(require, "sources")
local ok_scans, scans = pcall(require, "coverage_scans")
local ok_leads, leads = pcall(require, "lead_network")

if ok_sources and type(sources) == "table" then
    if ok_scans and type(scans) == "table" then
        for _, scan in ipairs(scans) do sources[#sources + 1] = scan end
    end
    if ok_leads and type(leads) == "table" then
        for _, lead in ipairs(leads) do sources[#sources + 1] = lead end
    end
end

require("newsroom_v11")
return require("main_v07")
