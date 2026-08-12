local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local ConfirmBox = require("ui/widget/confirmbox")
local NetworkMgr = require("ui/network/manager")
local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")
local _ = require("gettext")
local T = require("ffi/util").template

local MorningPaper = WidgetContainer:extend{
    name = "morningpaper",
    is_doc_only = false,
}

local function safe_mkdir(path)
    if lfs.attributes(path, "mode") ~= "directory" then pcall(lfs.mkdir, path) end
end

local function html_escape(s)
    s = tostring(s or "")
    return s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;")
end

local function strip_tags(s)
    s = tostring(s or "")
    s = s:gsub("<!%[CDATA%[(.-)%]%]>", "%1"):gsub("<script.-</script>", " "):gsub("<style.-</style>", " "):gsub("<[^>]->", " ")
    s = s:gsub("&nbsp;", " "):gsub("&amp;", "&"):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", '"'):gsub("&#39;", "'")
    return s:gsub("%s+", " ")
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
            out[#out + 1] = { title=title, link=link, description=summary, date=tag(entry, "updated") }
            if #out >= limit then break end
        end
    end
    return out
end

local function normalize_title(s)
    return ((s or ""):lower():gsub("[%p%c]", " "):gsub("%s+", " "))
end

local function http_get(url)
    local http = require("socket.http")
    local ltn12 = require("ltn12")
    local chunks = {}
    http.TIMEOUT = 20
    local ok, code, _, status = http.request{
        url=url,
        sink=ltn12.sink.table(chunks),
        headers={ ["User-Agent"]="KOReader MorningPaper/0.1", ["Accept"]="application/rss+xml, application/atom+xml, application/xml, text/xml, */*" },
    }
    if not ok then return nil, tostring(code or status or "request failed") end
    if tonumber(code) and tonumber(code) >= 400 then return nil, "HTTP " .. tostring(code) end
    return table.concat(chunks), nil
end

function MorningPaper:init()
    -- KOReader adds the plugin directory to package.path while loading, so
    -- require() is more reliable than depending on a custom self.path field.
    local ok, sources = pcall(require, "sources")
    if ok and type(sources) == "table" then
        self.sources = sources
    else
        self.sources = {}
        self.sources_error = tostring(sources)
    end
    self.output_dir = "/mnt/us/documents/Morning Paper"
    if lfs.attributes("/mnt/us/documents", "mode") ~= "directory" then
        self.output_dir = DataStorage:getDataDir() .. "/Morning Paper"
    end
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
    if not p then
        UIManager:show(InfoMessage:new{ text=_("No Morning Paper issue exists yet. Refresh today's paper first.") })
        return
    end
    self.ui:onClose()
    require("apps/reader/readerui"):showReader(p)
end

function MorningPaper:buildPaper()
    if self.sources_error then
        UIManager:show(InfoMessage:new{ text="Morning Paper could not load sources.lua:\n" .. self.sources_error })
        return
    end
    local sections, seen, failures = {}, {}, {}
    local total = 0
    for _, src in ipairs(self.sources) do
        if src.enabled ~= false then
            local xml, err = http_get(src.url)
            if not xml then
                failures[#failures + 1] = src.name .. ": " .. tostring(err)
            else
                local items = parse_rss(xml, src.limit or 6)
                if #items == 0 then items = parse_atom(xml, src.limit or 6) end
                sections[src.section] = sections[src.section] or {}
                for _, item in ipairs(items) do
                    local key = normalize_title(item.title)
                    if key ~= "" and not seen[key] then
                        seen[key], item.source = true, src.name
                        sections[src.section][#sections[src.section] + 1] = item
                        total = total + 1
                    end
                end
            end
        end
    end

    local path = self.output_dir .. "/Morning Paper " .. os.date("%Y-%m-%d") .. ".html"
    local f, ferr = io.open(path, "wb")
    if not f then UIManager:show(InfoMessage:new{ text="Could not write paper:\n" .. tostring(ferr) }); return end
    f:write([[<!doctype html><html><head><meta charset="utf-8"><title>Morning Paper</title><style>body{font-family:serif;line-height:1.45;max-width:48em;margin:auto;padding:1.2em}h1{font-size:2em;margin-bottom:.1em}h2{margin-top:2em;border-bottom:1px solid #777;padding-bottom:.2em}.article{margin:1.2em 0 1.7em}.meta{font-size:.85em}.summary{margin:.5em 0}a{color:inherit}.toc a{text-decoration:none}</style></head><body>]])
    f:write("<h1>Morning Paper</h1><p><strong>" .. html_escape(os.date("%A, %B %d, %Y")) .. "</strong></p>")
    f:write("<p>Source-attributed RSS newspaper. Feed excerpts are publisher-supplied; paywalls are not bypassed.</p><h2>Contents</h2><div class='toc'><ul>")
    local order = {"Front Page","World","U.S.","Business & Markets","Technology & AI","Science","Culture"}
    for _, section in ipairs(order) do if sections[section] and #sections[section] > 0 then f:write("<li><a href='#" .. section:gsub("%W","") .. "'>" .. html_escape(section) .. "</a> (" .. #sections[section] .. ")</li>") end end
    f:write("</ul></div>")
    for _, section in ipairs(order) do
        local items = sections[section]
        if items and #items > 0 then
            f:write("<h2 id='" .. section:gsub("%W","") .. "'>" .. html_escape(section) .. "</h2>")
            for _, item in ipairs(items) do
                f:write("<div class='article'><h3>")
                if item.link ~= "" then f:write("<a href='" .. html_escape(item.link) .. "'>" .. html_escape(item.title) .. "</a>") else f:write(html_escape(item.title)) end
                f:write("</h3><div class='meta'>" .. html_escape(item.source))
                if item.date ~= "" then f:write(" · " .. html_escape(item.date)) end
                f:write("</div>")
                if item.description ~= "" then f:write("<p class='summary'>" .. html_escape(item.description) .. "</p>") end
                f:write("</div>")
            end
        end
    end
    if #failures > 0 then f:write("<h2>Feed notes</h2><ul>"); for _, e in ipairs(failures) do f:write("<li>" .. html_escape(e) .. "</li>") end; f:write("</ul>") end
    f:write("</body></html>"); f:close()
    UIManager:show(ConfirmBox:new{
        text=T(_("Morning Paper created with %1 stories.\n\n%2"), total, path),
        ok_text=_("Open"),
        ok_callback=function() self.ui:onClose(); require("apps/reader/readerui"):showReader(path) end,
        cancel_text=_("Close"),
    })
end

function MorningPaper:showSources()
    if self.sources_error then UIManager:show(InfoMessage:new{ text=self.sources_error }); return end
    local lines = {}
    for _, s in ipairs(self.sources) do lines[#lines + 1] = string.format("%s — %s\n%s", s.section, s.name, s.url) end
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
            { text=_("About"), callback=function() UIManager:show(InfoMessage:new{ text=_("Morning Paper builds a source-attributed newspaper from RSS/Atom feeds. Publisher paywalls are not bypassed.") }) end },
        },
    }
end

return MorningPaper
