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
    if lfs.attributes(path, "mode") ~= "directory" then
        pcall(lfs.mkdir, path)
    end
end

local function html_escape(s)
    s = tostring(s or "")
    s = s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
    s = s:gsub('"', "&quot;")
    return s
end

local function strip_tags(s)
    s = tostring(s or "")
    s = s:gsub("<!%[CDATA%[(.-)%]%]>", "%1")
    s = s:gsub("<script.-</script>", " ")
    s = s:gsub("<style.-</style>", " ")
    s = s:gsub("<[^>]->", " ")
    s = s:gsub("&nbsp;", " ")
    s = s:gsub("&amp;", "&")
    s = s:gsub("&lt;", "<")
    s = s:gsub("&gt;", ">")
    s = s:gsub("&quot;", '"')
    s = s:gsub("&#39;", "'")
    s = s:gsub("%s+", " ")
    return s
end

local function tag(block, name)
    local a = block:match("<" .. name .. "[^>]*>(.-)</" .. name .. ">")
    if a then return strip_tags(a) end
    return ""
end

local function parse_rss(xml, limit)
    local out = {}
    for item in xml:gmatch("<item.-</item>") do
        local title = tag(item, "title")
        local link = tag(item, "link")
        local desc = tag(item, "description")
        if desc == "" then desc = tag(item, "content:encoded") end
        local date = tag(item, "pubDate")
        if title ~= "" then
            table.insert(out, {title=title, link=link, description=desc, date=date})
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
        local date = tag(entry, "updated")
        local link = entry:match('<link[^>]-href=["\'](.-)["\']') or ""
        if title ~= "" then
            table.insert(out, {title=title, link=link, description=summary, date=date})
            if #out >= limit then break end
        end
    end
    return out
end

local function normalize_title(s)
    s = (s or ""):lower()
    s = s:gsub("[%p%c]", " ")
    s = s:gsub("%s+", " ")
    return s
end

local function http_get(url)
    local http = require("socket.http")
    local ltn12 = require("ltn12")
    local chunks = {}
    http.TIMEOUT = 20
    local ok, code, headers, status = http.request{
        url = url,
        sink = ltn12.sink.table(chunks),
        headers = {
            ["User-Agent"] = "KOReader MorningPaper/0.1 (+personal RSS reader)",
            ["Accept"] = "application/rss+xml, application/atom+xml, application/xml, text/xml, */*",
        }
    }
    if not ok then return nil, tostring(code or status or "request failed") end
    if tonumber(code) and tonumber(code) >= 400 then
        return nil, "HTTP " .. tostring(code)
    end
    return table.concat(chunks), nil
end

function MorningPaper:init()
    self.path = self.path or "."
    self.sources = dofile(self.path .. "/sources.lua")
    self.output_dir = "/mnt/us/documents/Morning Paper"
    if lfs.attributes("/mnt/us/documents", "mode") ~= "directory" then
        self.output_dir = DataStorage:getDataDir() .. "/Morning Paper"
    end
    safe_mkdir(self.output_dir)
    self.ui.menu:registerToMainMenu(self)
end

function MorningPaper:latestPath()
    local best, best_mtime
    for f in lfs.dir(self.output_dir) do
        if f:match("^Morning Paper %d%d%d%d%-%d%d%-%d%d%.html$") then
            local p = self.output_dir .. "/" .. f
            local a = lfs.attributes(p)
            if a and (not best_mtime or a.modification > best_mtime) then
                best, best_mtime = p, a.modification
            end
        end
    end
    return best
end

function MorningPaper:openLatest()
    local p = self:latestPath()
    if not p then
        UIManager:show(InfoMessage:new{text=_("No Morning Paper issue exists yet. Tap ‘Refresh today's paper’ first.")})
        return
    end
    self.ui:onClose()
    require("apps/reader/readerui"):showReader(p)
end

function MorningPaper:buildPaper()
    local sections = {}
    local seen = {}
    local total = 0
    local failures = {}

    for _, src in ipairs(self.sources) do
        if src.enabled ~= false then
            local xml, err = http_get(src.url)
            if not xml then
                table.insert(failures, src.name .. ": " .. tostring(err))
            else
                local items = parse_rss(xml, src.limit or 6)
                if #items == 0 then items = parse_atom(xml, src.limit or 6) end
                sections[src.section] = sections[src.section] or {}
                for _, item in ipairs(items) do
                    local key = normalize_title(item.title)
                    if key ~= "" and not seen[key] then
                        seen[key] = true
                        item.source = src.name
                        table.insert(sections[src.section], item)
                        total = total + 1
                    end
                end
            end
        end
    end

    local date = os.date("%Y-%m-%d")
    local nice_date = os.date("%A, %B %d, %Y")
    local path = self.output_dir .. "/Morning Paper " .. date .. ".html"
    local f, ferr = io.open(path, "wb")
    if not f then
        UIManager:show(InfoMessage:new{text="Could not write paper:\n" .. tostring(ferr)})
        return
    end

    f:write([[<!doctype html><html><head><meta charset="utf-8">
<title>Morning Paper</title>
<style>
body{font-family:serif;line-height:1.45;max-width:48em;margin:auto;padding:1.2em}
h1{font-size:2em;margin-bottom:.1em} h2{margin-top:2em;border-bottom:1px solid #777;padding-bottom:.2em}
.article{margin:1.2em 0 1.7em}.meta{font-size:.85em}.summary{margin:.5em 0}
a{color:inherit}.toc a{text-decoration:none}
</style></head><body>]])
    f:write("<h1>Morning Paper</h1><p><strong>" .. html_escape(nice_date) .. "</strong></p>")
    f:write("<p>A personal, source-attributed RSS newspaper. Feed excerpts are shown as supplied by publishers; paywalls are not bypassed.</p>")
    f:write("<h2>Contents</h2><div class='toc'><ul>")
    local order = {"Front Page","World","U.S.","Business & Markets","Technology & AI","Science","Culture"}
    for _, section in ipairs(order) do
        if sections[section] and #sections[section] > 0 then
            f:write("<li><a href='#" .. section:gsub("%W","") .. "'>" .. html_escape(section) .. "</a> (" .. #sections[section] .. ")</li>")
        end
    end
    f:write("</ul></div>")

    for _, section in ipairs(order) do
        local items = sections[section]
        if items and #items > 0 then
            f:write("<h2 id='" .. section:gsub("%W","") .. "'>" .. html_escape(section) .. "</h2>")
            for _, item in ipairs(items) do
                f:write("<div class='article'><h3>")
                if item.link ~= "" then
                    f:write("<a href='" .. html_escape(item.link) .. "'>" .. html_escape(item.title) .. "</a>")
                else
                    f:write(html_escape(item.title))
                end
                f:write("</h3><div class='meta'>" .. html_escape(item.source))
                if item.date ~= "" then f:write(" · " .. html_escape(item.date)) end
                f:write("</div>")
                if item.description ~= "" then
                    f:write("<p class='summary'>" .. html_escape(item.description) .. "</p>")
                end
                f:write("</div>")
            end
        end
    end

    if #failures > 0 then
        f:write("<h2>Feed notes</h2><ul>")
        for _, e in ipairs(failures) do f:write("<li>" .. html_escape(e) .. "</li>") end
        f:write("</ul>")
    end
    f:write("</body></html>")
    f:close()

    UIManager:show(ConfirmBox:new{
        text = T(_("Morning Paper created with %1 stories.\n\n%2"), total, path),
        ok_text = _("Open"),
        ok_callback = function()
            self.ui:onClose()
            require("apps/reader/readerui"):showReader(path)
        end,
        cancel_text = _("Close"),
    })
end

function MorningPaper:showSources()
    local lines = {}
    for _, s in ipairs(self.sources) do
        table.insert(lines, string.format("%s — %s\n%s", s.section, s.name, s.url))
    end
    UIManager:show(InfoMessage:new{
        text = table.concat(lines, "\n\n"),
    })
end

function MorningPaper:addToMainMenu(menu_items)
    menu_items.morning_paper = {
        text = _("Morning Paper"),
        sorting_hint = "more_tools",
        sub_item_table = {
            {
                text = _("Refresh today's paper"),
                callback = function()
                    NetworkMgr:runWhenOnline(function() self:buildPaper() end)
                end,
            },
            {
                text = _("Open latest paper"),
                callback = function() self:openLatest() end,
            },
            {
                text = _("Sources"),
                callback = function() self:showSources() end,
            },
            {
                text = _("About"),
                callback = function()
                    UIManager:show(InfoMessage:new{
                        text = _("Morning Paper builds a clean, source-attributed HTML newspaper from RSS/Atom feeds. It uses feed-provided text only and does not bypass publisher paywalls. Edit sources.lua inside the plugin folder to add/remove feeds.")
                    })
                end,
            },
        },
    }
end

return MorningPaper
