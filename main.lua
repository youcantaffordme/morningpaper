-- Morning Paper v0.10 keeps the proven v0.7 KOReader UI/build pipeline.
-- First widen the research net with public RSS headline/summary scans. These do
-- not fetch linked articles; they give the event-clustering newsroom more
-- corroborating headlines/summaries without multiplying full-page downloads.
local ok_sources, sources = pcall(require, "sources")
local ok_scans, scans = pcall(require, "coverage_scans")
if ok_sources and ok_scans and type(sources) == "table" and type(scans) == "table" then
    for _, scan in ipairs(scans) do sources[#sources + 1] = scan end
end

-- Then patch the stable newsroom in place with event-level Coverage Net logic.
require("newsroom_v09")
return require("main_v07")
