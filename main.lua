local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local ConfirmBox = require("ui/widget/confirmbox")
local NetworkMgr = require("ui/network/manager")
local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")
local ArticleFetcher = require("article_fetcher")
local _ = require("gettext")
local T = require("ffi/util").template

local MorningPaper = WidgetContainer:extend{
    name = "morningpaper",
    is_doc_only = false,
}

local MONTHS = {
    Jan = 1, Feb = 2, Mar = 3, Apr = 4, May = 5, Jun = 6,
    Jul = 7, Aug = 8, Sep = 9, Oct = 10, Nov = 11, Dec = 12,
}

local SECTION_ORDER = {
    "Front Page", "World", "U.S.", "Business & Markets",
    "Technology & AI", "Science", "Culture",
}

local function safe_mkdir(path)
    if lfs.attributes(path, "mode") ~= "directory" then pcall(lfs.mkdir, path) end
end

local function html_escape(s)
    s = tostring(s or "")
    return s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;")
end

local function utf8_char(code)
    if not code or code < 0 then return "" end
    if code <= 0x7F then
        return string.char(code)
    elseif code <= 0x7FF then
        return string.char(0xC0 + math.floor(code / 0x40), 0x80 + (code % 0x40))
    elseif code <= 0xFFFF then
        return string.char(0xE0 + math.floor(code / 0x1000), 0x80 + (math.floor(code / 0x40) % 0x40), 0x80 + (code % 0x40))
    end
    return ""
end

local function decode_entities(s)
    s = tostring(s or "")
    s = s:gsub("&#x([0-9A-Fa-f]+);", function(hex) return utf8_char(tonumber(hex, 16)) end)
    s = s:gsub("&#([0-9]+);", function(dec) return utf8_char(tonumber(dec, 10)) end)
    local entities = { amp="&", lt="<", gt=">", quot='"', apos="'", nbsp=" ", ndash="–", mdash="—", rsquo="’", lsquo="‘", rdquo="”", ldquo="“", hellip="…" }
    s = s:gsub("&([%a]+);", function(name) return entities[name] or "&" .. name .. ";" end)
    return s
end

local function strip_tags(s)
    s = tostring(s or "")
    s = s:gsub("<!%[CDATA%[(.-)%]%]>", "%1")
    s = s:gsub("<script.-</script>", " "):gsub("<style.-</style>", " "):gsub("<[^>]->", " ")
    s = decode_entities(s):gsub("%s+", " ")
    return s:gsub("^%s+", ""):gsub("%s+$", "")
end

local function tag(block, name)
    local a = block:match("<" .. name .. "[^>]*>(.-)</" .. name .. ">")
    return a and strip_tags(a) or ""
end

local function parse_rss(xml, limit)
    local out = {}
    for item in xml:gmatch("<item.-</item>") do
        local title = tag(item, "title")
        local link = tag(item, "link")
        local desc = tag(item, "description")
        if desc == "" then desc = tag(item, "content:encoded") end
        if title ~= "" then
            out[#out + 1] = { title=title, link=link, description=desc, date=tag(item, "pubDate") }
            if #out >= limit then break end
        end
    end
    return out
end

local function parse_atom(xml, limit)
    local out = {}
    for entry in xml:gmatch("<entry.-</entry>") do
        local title = tag(entry, "title")
        local summary = tag(entry, "summary")
        if summary == "" then summary = tag(entry, "content") end
        local link = entry:match("<link[^>]-href=\"(.-)\"") or entry:match("<link[^>]-href='(.-)'") or ""
        if title ~= "" then
            out[#out + 1] = { title=title, link=decode_entities(link), description=summary, date=tag(entry, "updated") }
            if #out >= limit then break end
        end
    end
    return out
end

local function normalize_title(s)
    return ((s or ""):lower():gsub("[%p%c]", " "):gsub("%s+", " "))
end

local function parse_date_epoch(s)
    if not s or s == "" then return nil end
    local day, mon, year, hour, min, sec = s:match("(%d%d?)%s+(%a%a%a)%s+(%d%d%d%d)%s+(%d%d):(%d%d):?(%d%d?)")
    if day and MONTHS[mon] then
        return os.time{ year=tonumber(year), month=MONTHS[mon], day=tonumber(day), hour=tonumber(hour), min=tonumber(min), sec=tonumber(sec) or 0 }
    end
    year, mon, day, hour, min, sec = s:match("(%d%d%d%d)%-(%d%d)%-(%d%d)[T%s](%d%d):(%d%d):?(%d%d?)")
    if year then
        return os.time{ year=tonumber(year), month=tonumber(mon), day=tonumber(day), hour=tonumber(hour), min=tonumber(min), sec=tonumber(sec) or 0 }
    end
    year, mon, day = s:match("(%d%d%d%d)%-(%d%d)%-(%d%d)")
    if year then
        return os.time{ year=tonumber(year), month=tonumber(mon), day=tonumber(day), hour=12, min=0, sec=0 }
    end
    return nil
end

local function is_fresh(date_text, max_age_hours)
    if not max_age_hours then return true end
    local published = parse_date_epoch(date_text)
    if not published then return true end
    local age_hours = (os.time() - published) / 3600
    return age_hours <= max_age_hours and age_hours >= -48
end

local function http_get(url)
    local http = require("socket.http")
    local ltn12 = require("ltn12")
    local chunks = {}
    http.TIMEOUT = 12
    local ok, code, headers, status = http.request{
        url=url,
        sink=ltn12.sink.table(chunks),
        headers={ ["User-Agent"]="KOReader MorningPaper/0.2", ["Accept"]="application/rss+xml, application/atom+xml, application/xml, text/xml, */*" },
    }
    if not ok then return nil, tostring(code or status or "request failed") end
    code = tonumber(code) or 0
    if code >= 300 and code < 400 and headers and (headers.location or headers.Location) then
        return nil, "feed redirected; update its URL"
    end
    if code >= 400 then return nil, "HTTP " .. tostring(code) end
    return table.concat(chunks), nil
end

local function text_to_html(text)
    if not text or text == "" then return "" end
    local out = {}
    local normalized = text:gsub("\r\n", "\n"):gsub("\r", "\n")
    normalized = normalized .. "\n\n"
    for para in normalized:gmatch("(.-)\n%s*\n") do
        para = para:gsub("^%s+", ""):gsub("%s+$", "")
        if para ~= "" then out[#out + 1] = "<p>" .. html_escape(para) .. "</p>" end
    end
    if #out == 0 then out[1] = "<p>" .. html_escape(text) .. "</p>" end
    return table.concat(out, "\n")
end

function MorningPaper:init()
    local ok, sources = pcall(require, "sources")
    if ok and type(sources) == "table" then self.sources = sources else self.sources, self.sources_error = {}, tostring(sources) end
    self.output_dir = "/mnt/us/documents/Morning Paper"
    if lfs.attributes("/mnt/us/documents", "mode") ~= "directory" then self.output_dir = DataStorage:getDataDir() .. "/Morning Paper" end
    safe_mkdir(self.output_dir)
    self.ui.menu:registerToMainMenu(self)
end

function MorningPaper:latestPath()
    local best, best_mtime
    if lfs.attributes(self.output_dir, "mode") ~= "directory" then return nil end
    for f in lfs.dir(self.output_dir) do
        if f:match("^Morning Paper %d%d%d%d%-%d%d%-%d%d%.html$") then
            local p = self.output_dir .. "/" .. f
            local a = lfs.attributes(p)
            if a and (not best_mtime or a.modification > best_mtime) then best, best_mtime = p, a.modification end
        end
    end
    return best
end

function MorningPaper:openLatest()
    local p = self:latestPath()
    if not p then UIManager:show(InfoMessage:new{ text=_("No Morning Paper issue exists yet. Refresh today's paper first.") }); return end
    self.ui:onClose()
    require("apps/reader/readerui"):showReader(p)
end

function MorningPaper:buildPaper()
    if self.sources_error then UIManager:show(InfoMessage:new{ text="Morning Paper could not load sources.lua:\n" .. self.sources_error }); return end

    local sections, seen, failures = {}, {}, {}
    local total, full_count, excerpt_count, stale_count = 0, 0, 0, 0
    local article_counter = 0

    for _, src in ipairs(self.sources) do
        if src.enabled ~= false then
            local xml, err = http_get(src.url)
            if not xml then
                failures[#failures + 1] = src.name .. ": " .. tostring(err)
            else
                local items = parse_rss(xml, src.limit or 3)
                if #items == 0 then items = parse_atom(xml, src.limit or 3) end
                sections[src.section] = sections[src.section] or {}
                for _, item in ipairs(items) do
                    local key = normalize_title(item.title)
                    if not is_fresh(item.date, src.max_age_hours) then
                        stale_count = stale_count + 1
                    elseif key ~= "" and not seen[key] then
                        seen[key] = true
                        item.source = src.name
                        item.content_mode = "Feed excerpt"
                        item.body = item.description

                        if src.full_text ~= false and item.link ~= "" then
                            local body, mode, final_url = ArticleFetcher.fetch(item.link, { min_chars=src.min_fulltext_chars or 350 })
                            if body then
                                item.body = body
                                item.content_mode = "Full article"
                                item.extract_mode = mode
                                item.link = final_url or item.link
                                full_count = full_count + 1
                            else
                                item.extract_error = mode
                                excerpt_count = excerpt_count + 1
                            end
                        else
                            excerpt_count = excerpt_count + 1
                        end

                        sections[src.section][#sections[src.section] + 1] = item
                        total = total + 1
                        article_counter = article_counter + 1
                        if article_counter % 4 == 0 then collectgarbage("collect") end
                    end
                end
            end
        end
    end

    local path = self.output_dir .. "/Morning Paper " .. os.date("%Y-%m-%d") .. ".html"
    local f, ferr = io.open(path, "wb")
    if not f then UIManager:show(InfoMessage:new{ text="Could not write paper:\n" .. tostring(ferr) }); return end

    f:write([[<!doctype html><html><head><meta charset="utf-8"><title>Morning Paper</title><style>
body{font-family:serif;line-height:1.5;max-width:48em;margin:auto;padding:1.2em}h1{font-size:2em;margin-bottom:.1em}h2{margin-top:2em;border-bottom:1px solid #777;padding-bottom:.2em}h3{font-size:1.35em}.article{margin:1.5em 0 2.4em}.meta{font-size:.85em}.mode{font-size:.82em;font-style:italic}.toc a{text-decoration:none}.original{font-size:.9em}.rule{border-top:1px solid #aaa;margin-top:2em}</style></head><body>]])
    f:write("<h1>Morning Paper</h1><p><strong>" .. html_escape(os.date("%A, %B %d, %Y")) .. "</strong></p>")
    f:write("<p>" .. total .. " current stories · " .. full_count .. " full articles fetched · " .. excerpt_count .. " feed excerpts</p>")
    f:write("<p><em>Morning Paper uses publisher-provided feeds and publicly reachable article pages. It does not bypass subscriptions or paywalls.</em></p>")
    f:write("<h2>Contents</h2><div class='toc'><ul>")
    for _, section in ipairs(SECTION_ORDER) do
        if sections[section] and #sections[section] > 0 then f:write("<li><a href='#" .. section:gsub("%W","") .. "'>" .. html_escape(section) .. "</a> (" .. #sections[section] .. ")</li>") end
    end
    f:write("</ul></div>")

    local article_id = 0
    for _, section in ipairs(SECTION_ORDER) do
        local items = sections[section]
        if items and #items > 0 then
            f:write("<h2 id='" .. section:gsub("%W","") .. "'>" .. html_escape(section) .. "</h2>")
            for _, item in ipairs(items) do
                article_id = article_id + 1
                f:write("<div class='article' id='story" .. article_id .. "'><h3>" .. html_escape(item.title) .. "</h3>")
                f:write("<div class='meta'>" .. html_escape(item.source))
                if item.date ~= "" then f:write(" · " .. html_escape(item.date)) end
                f:write("</div><div class='mode'>" .. html_escape(item.content_mode))
                if item.content_mode ~= "Full article" and item.extract_error then f:write(" · " .. html_escape(item.extract_error)) end
                f:write("</div>")
                if item.body and item.body ~= "" then f:write(text_to_html(item.body)) else f:write("<p>No text was supplied by this source.</p>") end
                if item.link ~= "" then f:write("<p class='original'><a href='" .. html_escape(item.link) .. "'>Open original article</a></p>") end
                f:write("<div class='rule'></div></div>")
            end
        end
    end

    if #failures > 0 or stale_count > 0 then
        f:write("<h2>Source notes</h2>")
        if stale_count > 0 then f:write("<p>Skipped " .. stale_count .. " stale feed entries.</p>") end
        if #failures > 0 then f:write("<ul>"); for _, e in ipairs(failures) do f:write("<li>" .. html_escape(e) .. "</li>") end; f:write("</ul>") end
    end
    f:write("</body></html>")
    f:close()

    UIManager:show(ConfirmBox:new{
        text=T(_("Morning Paper created with %1 stories.\n%2 full articles fetched.\n\n%3"), total, full_count, path),
        ok_text=_("Open"),
        ok_callback=function() self.ui:onClose(); require("apps/reader/readerui"):showReader(path) end,
        cancel_text=_("Close"),
    })
end

function MorningPaper:showSources()
    if self.sources_error then UIManager:show(InfoMessage:new{ text=self.sources_error }); return end
    local lines = {}
    for _, s in ipairs(self.sources) do
        local state = s.enabled == false and "OFF" or "ON"
        lines[#lines + 1] = string.format("[%s] %s — %s\n%s", state, s.section, s.name, s.url)
    end
    UIManager:show(InfoMessage:new{ text=table.concat(lines, "\n\n") })
end

function MorningPaper:addToMainMenu(menu_items)
    menu_items.morning_paper = {
        text=_("Morning Paper"),
        sorting_hint="tools",
        sub_item_table={
            { text=_("Refresh today's paper"), callback=function() NetworkMgr:runWhenOnline(function() self:buildPaper() end) end },
            { text=_("Open latest paper"), callback=function() self:openLatest() end },
            { text=_("Sources"), callback=function() self:showSources() end },
            { text=_("About"), callback=function() UIManager:show(InfoMessage:new{ text=_("Morning Paper 0.2 fetches fresh RSS/Atom headlines, then attempts to extract the publicly available full article body. If a publisher limits access, it falls back to the feed excerpt. Paywalls are not bypassed.") }) end },
        },
    }
end

return MorningPaper
