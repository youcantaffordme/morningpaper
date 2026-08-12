local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local ConfirmBox = require("ui/widget/confirmbox")
local NetworkMgr = require("ui/network/manager")
local DataStorage = require("datastorage")
local Device = require("device")
local lfs = require("libs/libkoreader-lfs")
local ArticleFetcher = require("article_fetcher")
local EpubBuilder = require("epub_builder")
local _ = require("gettext")
local T = require("ffi/util").template

local MorningPaper = WidgetContainer:extend{
    name = "morningpaper",
    is_doc_only = false,
}

local MONTHS = {
    Jan=1, Feb=2, Mar=3, Apr=4, May=5, Jun=6,
    Jul=7, Aug=8, Sep=9, Oct=10, Nov=11, Dec=12,
}

local SECTION_ORDER = {
    "Front Page", "World", "U.S.", "Business & Markets",
    "Technology & AI", "Science", "Culture",
}

local DELIVERY_TIMES = {
    { label="5:30 AM", hour=5, minute=30 },
    { label="6:00 AM", hour=6, minute=0 },
    { label="6:30 AM", hour=6, minute=30 },
    { label="7:00 AM", hour=7, minute=0 },
    { label="7:30 AM", hour=7, minute=30 },
    { label="8:00 AM", hour=8, minute=0 },
}

local function safe_mkdir(path)
    if lfs.attributes(path, "mode") ~= "directory" then pcall(lfs.mkdir, path) end
end

local function raw_tag(block, name)
    local value = block:match("<" .. name .. "[^>]*>(.-)</" .. name .. ">")
    if not value then return "" end
    return value:gsub("<!%[CDATA%[(.-)%]%]>", "%1")
end

local function clean_tag(block, name)
    return ArticleFetcher.cleanText(raw_tag(block, name))
end

local function decode_link(s)
    s = tostring(s or ""):gsub("<!%[CDATA%[(.-)%]%]>", "%1")
    for _ = 1, 3 do
        local before = s
        s = s:gsub("&amp;", "&"):gsub("&#38;", "&"):gsub("&quot;", '"'):gsub("&#39;", "'")
        if s == before then break end
    end
    return s:gsub("^%s+", ""):gsub("%s+$", "")
end

local function parse_rss(xml, limit)
    local out = {}
    for item in xml:gmatch("<item.-</item>") do
        local title = clean_tag(item, "title")
        local link = decode_link(raw_tag(item, "link"))
        local desc = ArticleFetcher.cleanText(raw_tag(item, "description"))
        if desc == "" then desc = ArticleFetcher.cleanText(raw_tag(item, "content:encoded")) end
        local date = clean_tag(item, "pubDate")
        if title ~= "" then
            out[#out + 1] = { title=title, link=link, description=desc, date=date }
            if #out >= limit then break end
        end
    end
    return out
end

local function parse_atom(xml, limit)
    local out = {}
    for entry in xml:gmatch("<entry.-</entry>") do
        local title = clean_tag(entry, "title")
        local summary = ArticleFetcher.cleanText(raw_tag(entry, "summary"))
        if summary == "" then summary = ArticleFetcher.cleanText(raw_tag(entry, "content")) end
        local link = entry:match("<link[^>]-href=\"(.-)\"") or entry:match("<link[^>]-href='(.-)'") or ""
        if title ~= "" then
            out[#out + 1] = {
                title=title,
                link=decode_link(link),
                description=summary,
                date=clean_tag(entry, "updated"),
            }
            if #out >= limit then break end
        end
    end
    return out
end

local function normalize_title(s)
    return ((s or ""):lower():gsub("[%p%c]", " "):gsub("%s+", " "))
end

local function local_utc_offset(epoch)
    epoch = epoch or os.time()
    local local_t = os.date("*t", epoch)
    local utc_t = os.date("!*t", epoch)
    return os.difftime(os.time(local_t), os.time(utc_t))
end

local function parse_zone_offset(zone)
    if not zone or zone == "" then return nil end
    zone = zone:upper()
    if zone == "GMT" or zone == "UTC" or zone == "UT" or zone == "Z" then return 0 end
    local sign, hh, mm = zone:match("^([%+%-])(%d%d)(%d%d)$")
    if not sign then return nil end
    local seconds = tonumber(hh) * 3600 + tonumber(mm) * 60
    return sign == "-" and -seconds or seconds
end

local function make_epoch(year, mon, day, hour, min, sec, zone)
    local naive = os.time{
        year=tonumber(year), month=tonumber(mon), day=tonumber(day),
        hour=tonumber(hour) or 0, min=tonumber(min) or 0, sec=tonumber(sec) or 0,
    }
    if not naive then return nil end
    local zone_offset = parse_zone_offset(zone)
    if zone_offset ~= nil then return naive + local_utc_offset(naive) - zone_offset end
    return naive
end

local function parse_date_epoch(s)
    if not s or s == "" then return nil end

    local day, mon, year, hour, min, sec, zone = s:match("(%d%d?)%s+(%a%a%a)%s+(%d%d%d%d)%s+(%d%d):(%d%d):(%d%d)%s*([%+%-]%d%d%d%d)")
    if not day then
        day, mon, year, hour, min, sec, zone = s:match("(%d%d?)%s+(%a%a%a)%s+(%d%d%d%d)%s+(%d%d):(%d%d):(%d%d)%s*(%a+)")
    end
    if day and MONTHS[mon] then return make_epoch(year, MONTHS[mon], day, hour, min, sec, zone) end

    year, mon, day, hour, min, sec, zone = s:match("(%d%d%d%d)%-(%d%d)%-(%d%d)[T%s](%d%d):(%d%d):(%d%d)([Zz])")
    if year then return make_epoch(year, mon, day, hour, min, sec, zone) end

    local zhour, zmin
    year, mon, day, hour, min, sec, zhour, zmin = s:match("(%d%d%d%d)%-(%d%d)%-(%d%d)[T%s](%d%d):(%d%d):(%d%d)([%+%-]%d%d):?(%d%d)")
    if year then return make_epoch(year, mon, day, hour, min, sec, zhour .. zmin) end

    year, mon, day, hour, min, sec = s:match("(%d%d%d%d)%-(%d%d)%-(%d%d)[T%s](%d%d):(%d%d):?(%d%d?)")
    if year then return make_epoch(year, mon, day, hour, min, sec, nil) end

    year, mon, day = s:match("(%d%d%d%d)%-(%d%d)%-(%d%d)")
    if year then return make_epoch(year, mon, day, 12, 0, 0, nil) end
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
        headers={
            ["User-Agent"]="KOReader MorningPaper/0.4",
            ["Accept"]="application/rss+xml, application/atom+xml, application/xml, text/xml, */*",
        },
    }
    if not ok then return nil, tostring(code or status or "request failed") end
    code = tonumber(code) or 0
    if code >= 300 and code < 400 and headers and (headers.location or headers.Location) then
        return nil, "feed redirected; update its URL"
    end
    if code >= 400 then return nil, "HTTP " .. tostring(code) end
    return table.concat(chunks), nil
end

local function seconds_until(hour, minute)
    local now = os.time()
    local t = os.date("*t", now)
    local target = os.time{
        year=t.year, month=t.month, day=t.day,
        hour=hour, min=minute, sec=0,
    }
    if target <= now + 30 then target = target + 24 * 60 * 60 end
    return math.max(60, target - now), target
end

function MorningPaper:init()
    local ok, sources = pcall(require, "sources")
    if ok and type(sources) == "table" then
        self.sources = sources
    else
        self.sources, self.sources_error = {}, tostring(sources)
    end

    self.output_dir = "/mnt/us/documents/Morning Paper"
    if lfs.attributes("/mnt/us/documents", "mode") ~= "directory" then
        self.output_dir = DataStorage:getDataDir() .. "/Morning Paper"
    end
    safe_mkdir(self.output_dir)

    self.auto_enabled = G_reader_settings:readSetting("morningpaper_auto_enabled", false)
    self.auto_hour = G_reader_settings:readSetting("morningpaper_auto_hour", 6)
    self.auto_minute = G_reader_settings:readSetting("morningpaper_auto_minute", 30)
    self.last_auto_status = G_reader_settings:readSetting("morningpaper_last_auto_status", "Never run")
    self.auto_callback = function() self:onAutoDeliveryWake() end

    if self.auto_enabled then self:scheduleAutoDelivery(true) end
    self.ui.menu:registerToMainMenu(self)
end

function MorningPaper:saveAutoSettings()
    G_reader_settings:saveSetting("morningpaper_auto_enabled", self.auto_enabled)
    G_reader_settings:saveSetting("morningpaper_auto_hour", self.auto_hour)
    G_reader_settings:saveSetting("morningpaper_auto_minute", self.auto_minute)
    G_reader_settings:saveSetting("morningpaper_last_auto_status", self.last_auto_status)
    G_reader_settings:flush()
end

function MorningPaper:scheduleAutoDelivery(remove_existing)
    if not Device.wakeup_mgr then
        self.auto_next_epoch = nil
        return false
    end
    if remove_existing ~= false and self.auto_callback then
        pcall(function() Device.wakeup_mgr:removeTasks(nil, self.auto_callback) end)
    end
    if not self.auto_enabled then
        self.auto_next_epoch = nil
        return true
    end
    local delay, target = seconds_until(self.auto_hour, self.auto_minute)
    self.auto_next_epoch = target
    Device.wakeup_mgr:addTask(delay, self.auto_callback)
    return true
end

function MorningPaper:setAutoEnabled(enabled)
    self.auto_enabled = enabled and true or false
    self.last_auto_status = self.auto_enabled and "Scheduled" or "Disabled"
    self:saveAutoSettings()
    local supported = self:scheduleAutoDelivery(true)
    if self.auto_enabled and not supported then
        UIManager:show(InfoMessage:new{ text=_("This device does not expose KOReader's hardware wake scheduler, so automatic delivery is unavailable here.") })
    end
end

function MorningPaper:setDeliveryTime(hour, minute)
    self.auto_hour, self.auto_minute = hour, minute
    self:saveAutoSettings()
    if self.auto_enabled then self:scheduleAutoDelivery(true) end
end

function MorningPaper:autoStatusText()
    local enabled = self.auto_enabled and "ON" or "OFF"
    local delivery = os.date("%I:%M %p", os.time{year=2000, month=1, day=1, hour=self.auto_hour, min=self.auto_minute, sec=0}):gsub("^0", "")
    local next_text = self.auto_next_epoch and os.date("%a %b %d, %I:%M %p", self.auto_next_epoch):gsub(" 0", " ") or "Not scheduled"
    return string.format("Auto delivery: %s\nDelivery time: %s\nNext delivery: %s\nLast result: %s", enabled, delivery, next_text, self.last_auto_status or "Unknown")
end

function MorningPaper:onAutoDeliveryWake()
    if not self.auto_enabled then return end
    self:scheduleAutoDelivery(false)

    local wifi_was_on = NetworkMgr:getWifiState() and true or false
    local function finish(status)
        self.last_auto_status = status
        self:saveAutoSettings()
        if not wifi_was_on and NetworkMgr:getWifiState() and type(NetworkMgr.turnOffWifi) == "function" then
            UIManager:scheduleIn(20, function() pcall(function() NetworkMgr:turnOffWifi() end) end)
        end
    end

    local function run()
        local ok, result = pcall(function() return self:buildPaper{automatic=true} end)
        if ok and result then
            finish("Delivered " .. os.date("%Y-%m-%d %H:%M"))
        elseif ok then
            finish("Delivery failed while building paper")
        else
            finish("Delivery error: " .. tostring(result))
        end
    end

    local started = NetworkMgr:goOnlineToRun(run)
    if not started then finish("Could not auto-enable Wi-Fi; set KOReader Wi-Fi action to Turn on") end
end

function MorningPaper:onCloseWidget()
    if Device.wakeup_mgr and self.auto_callback then
        pcall(function() Device.wakeup_mgr:removeTasks(nil, self.auto_callback) end)
    end
end

function MorningPaper:latestPath()
    local best, best_mtime
    if lfs.attributes(self.output_dir, "mode") ~= "directory" then return nil end
    for file in lfs.dir(self.output_dir) do
        if file:match("^Morning Paper %d%d%d%d%-%d%d%-%d%d%.epub$") or file:match("^Morning Paper %d%d%d%d%-%d%d%-%d%d%.html$") then
            local path = self.output_dir .. "/" .. file
            local attrs = lfs.attributes(path)
            if attrs and (not best_mtime or attrs.modification > best_mtime) then
                best, best_mtime = path, attrs.modification
            end
        end
    end
    return best
end

function MorningPaper:openLatest()
    local path = self:latestPath()
    if not path then
        UIManager:show(InfoMessage:new{ text=_("No Morning Paper issue exists yet. Refresh today's paper first.") })
        return
    end
    self.ui:onClose()
    require("apps/reader/readerui"):showReader(path)
end

function MorningPaper:buildPaper(opts)
    opts = opts or {}
    if self.sources_error then
        if not opts.automatic then UIManager:show(InfoMessage:new{ text="Morning Paper could not load sources.lua:\n" .. self.sources_error }) end
        return false
    end

    local issue_epoch = os.time()
    local issue_date = os.date("%Y-%m-%d", issue_epoch)
    local nice_date = os.date("%A, %B %d, %Y", issue_epoch)
    local edition_time = os.date("%I:%M %p", issue_epoch):gsub("^0", "")

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
                        item.published_epoch = parse_date_epoch(item.date) or 0
                        item.content_mode = "Feed excerpt"
                        item.body = ArticleFetcher.cleanText(item.description)

                        if src.full_text ~= false and item.link ~= "" then
                            local body, mode, final_url = ArticleFetcher.fetch(item.link, {min_chars=src.min_fulltext_chars or 350})
                            if body and body ~= "" then
                                item.body = ArticleFetcher.cleanText(body)
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

                        -- Final safety pass: never let raw markup, giant hrefs or tracking URLs into the edition.
                        item.body = ArticleFetcher.cleanText(item.body)
                        if item.body == "" or #item.body < 60 then
                            item.body = "A clean full-text copy was not available from this publisher. Use “Open original article” below to read it on the source site."
                            item.content_mode = "Source link only"
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

    for _, section in ipairs(SECTION_ORDER) do
        local items = sections[section]
        if items then
            table.sort(items, function(a, b)
                local ae, be = a.published_epoch or 0, b.published_epoch or 0
                if ae == be then return (a.title or "") < (b.title or "") end
                return ae > be
            end)
        end
    end

    local path = self.output_dir .. "/Morning Paper " .. issue_date .. ".epub"
    local ok, err = EpubBuilder.build(path, {
        date=issue_date,
        nice_date=nice_date,
        edition_time=edition_time,
        title="Morning Paper — " .. nice_date,
        uid="urn:morningpaper:" .. issue_date,
        sections=sections,
        section_order=SECTION_ORDER,
        total=total,
        full_count=full_count,
        excerpt_count=excerpt_count,
    })

    if not ok then
        if not opts.automatic then UIManager:show(InfoMessage:new{ text="Could not build EPUB edition:\n" .. tostring(err) }) end
        return false
    end

    -- Remove the old same-day HTML edition after a successful EPUB build so the library does not show duplicates.
    pcall(os.remove, self.output_dir .. "/Morning Paper " .. issue_date .. ".html")

    if not opts.automatic then
        local note = ""
        if stale_count > 0 then note = note .. "\n" .. stale_count .. " stale feed entries skipped." end
        if #failures > 0 then note = note .. "\n" .. #failures .. " source feeds had errors." end
        UIManager:show(ConfirmBox:new{
            text=T(_("Morning Paper created with %1 stories.\n%2 full articles fetched.\nA dated newspaper cover was embedded.\n\n%3%4"), total, full_count, path, note),
            ok_text=_("Open"),
            ok_callback=function() self.ui:onClose(); require("apps/reader/readerui"):showReader(path) end,
            cancel_text=_("Close"),
        })
    end
    return true
end

function MorningPaper:showSources()
    if self.sources_error then UIManager:show(InfoMessage:new{ text=self.sources_error }); return end
    local lines = {}
    for _, src in ipairs(self.sources) do
        local state = src.enabled == false and "OFF" or "ON"
        lines[#lines + 1] = string.format("[%s] %s — %s\n%s", state, src.section, src.name, src.url)
    end
    UIManager:show(InfoMessage:new{ text=table.concat(lines, "\n\n") })
end

function MorningPaper:addToMainMenu(menu_items)
    local auto_submenu = {
        {
            text=_("Enable automatic delivery"),
            checked_func=function() return self.auto_enabled end,
            callback=function()
                self:setAutoEnabled(not self.auto_enabled)
                UIManager:show(InfoMessage:new{ text=self:autoStatusText() })
            end,
        },
        { text=_("Delivery time"), separator=true },
    }

    for _, preset in ipairs(DELIVERY_TIMES) do
        local p = preset
        auto_submenu[#auto_submenu + 1] = {
            text=p.label,
            checked_func=function() return self.auto_hour == p.hour and self.auto_minute == p.minute end,
            callback=function()
                self:setDeliveryTime(p.hour, p.minute)
                UIManager:show(InfoMessage:new{ text=self:autoStatusText() })
            end,
        }
    end

    auto_submenu[#auto_submenu + 1] = {
        text=_("Auto-delivery status"),
        separator=true,
        callback=function() UIManager:show(InfoMessage:new{ text=self:autoStatusText() }) end,
    }

    menu_items.morning_paper = {
        text=_("Morning Paper"),
        sorting_hint="tools",
        sub_item_table={
            { text=_("Refresh today's paper"), callback=function() NetworkMgr:runWhenOnline(function() self:buildPaper() end) end },
            { text=_("Open latest paper"), callback=function() self:openLatest() end },
            { text=_("Automatic delivery"), sub_item_table=auto_submenu },
            { text=_("Sources"), callback=function() self:showSources() end },
            {
                text=_("About"),
                callback=function()
                    UIManager:show(InfoMessage:new{ text=_("Morning Paper 0.4 creates a real EPUB edition every day with an embedded newspaper-style cover, date, edition time and top headlines. It keeps newest-first ordering, clean article filtering and optional hardware-wake morning delivery. Publisher paywalls are not bypassed.") })
                end,
            },
        },
    }
end

return MorningPaper
