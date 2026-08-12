-- Morning Paper v0.12.2 — direct runtime wiring
--
-- This entrypoint deliberately mutates the proven main_v07 class in-place.
-- KOReader executes this file with dofile(), so every runtime-facing override
-- below is applied to the exact class the plugin loader instantiates.

local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local Device = require("device")
local _ = require("gettext")

local RUNTIME_BUILD = "0.12.2"

-- Expand the research pool once, without duplicating sources if KOReader ever
-- reloads the entrypoint in the same process.
local injected_scans, injected_leads = 0, 0
local ok_sources, sources = pcall(require, "sources")
local ok_scans, scans = pcall(require, "coverage_scans")
local ok_leads, leads = pcall(require, "lead_network")

local function append_unique(target, extras)
    if type(target) ~= "table" or type(extras) ~= "table" then return 0 end
    local seen = {}
    for _, item in ipairs(target) do
        local key = tostring(item and item.url or "") .. "\0" .. tostring(item and item.name or "")
        seen[key] = true
    end
    local added = 0
    for _, item in ipairs(extras) do
        local key = tostring(item and item.url or "") .. "\0" .. tostring(item and item.name or "")
        if not seen[key] then
            target[#target + 1] = item
            seen[key] = true
            added = added + 1
        end
    end
    return added
end

if ok_sources and type(sources) == "table" then
    if ok_scans then injected_scans = append_unique(sources, scans) end
    if ok_leads then injected_leads = append_unique(sources, leads) end
end

local configured_editorial_leads, configured_coverage_scans = 0, 0
if ok_sources and type(sources) == "table" then
    for _, src in ipairs(sources) do
        if src and src.agenda_only then
            if tostring(src.name or ""):find("[Coverage Scan]", 1, true) then
                configured_coverage_scans = configured_coverage_scans + 1
            else
                configured_editorial_leads = configured_editorial_leads + 1
            end
        end
    end
end

-- Load the consensus newsroom before main_v07 captures newsroom_v07. If this
-- enhancement ever fails, Morning Paper still loads and exposes the failure in
-- Runtime & system check instead of silently disappearing from KOReader.
local lead_runtime_ok, lead_runtime = pcall(require, "newsroom_v12")
local lead_runtime_error = lead_runtime_ok and nil or tostring(lead_runtime)

local Base = require("main_v07")

-- Capture the proven implementations before replacing runtime-facing methods.
local base_init = Base.init
local base_save_auto = Base.saveAutoSettings
local base_add_menu = Base.addToMainMenu

local CADENCE_LABELS = {
    daily = "Every morning",
    weekdays = "Weekdays",
    weekly = "Once a week",
    manual = "Manual only",
}

local DAYS = {
    { label="Sunday", wday=1 },
    { label="Monday", wday=2 },
    { label="Tuesday", wday=3 },
    { label="Wednesday", wday=4 },
    { label="Thursday", wday=5 },
    { label="Friday", wday=6 },
    { label="Saturday", wday=7 },
}

local DELIVERY_TIMES = {
    { label="5:30 AM", hour=5, minute=30 },
    { label="6:00 AM", hour=6, minute=0 },
    { label="6:30 AM", hour=6, minute=30 },
    { label="7:00 AM", hour=7, minute=0 },
    { label="7:30 AM", hour=7, minute=30 },
    { label="8:00 AM", hour=8, minute=0 },
}

local function valid_cadence(value)
    return value == "daily" or value == "weekdays" or value == "weekly" or value == "manual"
end

local function day_is_allowed(epoch, cadence, weekly_wday)
    local wday = os.date("*t", epoch).wday
    if cadence == "daily" then return true end
    if cadence == "weekdays" then return wday >= 2 and wday <= 6 end
    if cadence == "weekly" then return wday == weekly_wday end
    return false
end

local function next_delivery_epoch(hour, minute, cadence, weekly_wday)
    if cadence == "manual" then return nil end
    local now = os.time()
    local today = os.date("*t", now)
    for offset = 0, 14 do
        local target = os.time{
            year=today.year,
            month=today.month,
            day=today.day + offset,
            hour=hour,
            min=minute,
            sec=0,
        }
        if target > now + 30 and day_is_allowed(target, cadence, weekly_wday) then
            return target
        end
    end
    return nil
end

function Base:init()
    local stored = G_reader_settings:readSetting("morningpaper_auto_cadence", nil)
    if not valid_cadence(stored) then
        stored = G_reader_settings:readSetting("morningpaper_auto_enabled", false) and "daily" or "manual"
    end
    self.auto_cadence = stored
    self.auto_weekly_wday = tonumber(G_reader_settings:readSetting("morningpaper_auto_weekly_wday", 1)) or 1
    if self.auto_weekly_wday < 1 or self.auto_weekly_wday > 7 then self.auto_weekly_wday = 1 end
    self.runtime_build = RUNTIME_BUILD

    base_init(self)

    -- main_v07 keeps this boolean as the wake callback safety gate. Keep it in
    -- sync with cadence, then replace any legacy daily wake with the real cadence.
    self.auto_enabled = self.auto_cadence ~= "manual"
    self:saveAutoSettings()
    self:scheduleAutoDelivery(true)
end

function Base:saveAutoSettings()
    base_save_auto(self)
    G_reader_settings:saveSetting("morningpaper_auto_cadence", self.auto_cadence or "manual")
    G_reader_settings:saveSetting("morningpaper_auto_weekly_wday", self.auto_weekly_wday or 1)
    G_reader_settings:saveSetting("morningpaper_runtime_build", RUNTIME_BUILD)
    G_reader_settings:flush()
end

function Base:scheduleAutoDelivery(remove_existing)
    if not Device.wakeup_mgr then
        self.auto_next_epoch = nil
        return false
    end

    if remove_existing ~= false and self.auto_callback then
        pcall(function() Device.wakeup_mgr:removeTasks(nil, self.auto_callback) end)
    end

    local cadence = valid_cadence(self.auto_cadence) and self.auto_cadence or "manual"
    if cadence == "manual" then
        self.auto_next_epoch = nil
        return true
    end

    local target = next_delivery_epoch(
        self.auto_hour or 6,
        self.auto_minute or 30,
        cadence,
        self.auto_weekly_wday or 1
    )
    if not target then
        self.auto_next_epoch = nil
        return false
    end

    self.auto_next_epoch = target
    Device.wakeup_mgr:addTask(math.max(60, target - os.time()), self.auto_callback)
    return true
end

function Base:setAutoCadence(cadence)
    if not valid_cadence(cadence) then return end
    self.auto_cadence = cadence
    self.auto_enabled = cadence ~= "manual"
    self.last_auto_status = self.auto_enabled and ("Scheduled · " .. CADENCE_LABELS[cadence]) or "Manual only"
    self:saveAutoSettings()

    local supported = self:scheduleAutoDelivery(true)
    if self.auto_enabled and not supported then
        UIManager:show(InfoMessage:new{
            text=_("This device does not expose KOReader's hardware wake scheduler, so automatic delivery is unavailable here."),
        })
    end
end

-- Preserve compatibility with the old toggle and any saved callback paths.
function Base:setAutoEnabled(enabled)
    self:setAutoCadence(enabled and "daily" or "manual")
end

function Base:setWeeklyDay(wday)
    wday = tonumber(wday)
    if not wday or wday < 1 or wday > 7 then return end
    self.auto_weekly_wday = wday
    self:saveAutoSettings()
    if self.auto_cadence == "weekly" then self:scheduleAutoDelivery(true) end
end

function Base:setDeliveryTime(hour, minute)
    self.auto_hour = hour
    self.auto_minute = minute
    self:saveAutoSettings()
    if self.auto_cadence ~= "manual" then self:scheduleAutoDelivery(true) end
end

function Base:autoStatusText()
    local cadence = valid_cadence(self.auto_cadence) and self.auto_cadence or "manual"
    local delivery = os.date("%I:%M %p", os.time{
        year=2000,
        month=1,
        day=1,
        hour=self.auto_hour or 6,
        min=self.auto_minute or 30,
        sec=0,
    }):gsub("^0", "")
    local next_text = self.auto_next_epoch
        and os.date("%a %b %d, %I:%M %p", self.auto_next_epoch):gsub(" 0", " ")
        or "Not scheduled"
    local weekly_line = ""
    if cadence == "weekly" then
        local selected = DAYS[self.auto_weekly_wday or 1]
        weekly_line = "\nWeekly day: " .. (selected and selected.label or "Sunday")
    end

    return string.format(
        "Delivery frequency: %s%s\nDelivery time: %s\nNext delivery: %s\nLast result: %s",
        CADENCE_LABELS[cadence] or cadence,
        weekly_line,
        delivery,
        next_text,
        self.last_auto_status or "Unknown"
    )
end

function Base:runtimeDiagnosticsText()
    local wake = Device.wakeup_mgr and "available" or "NOT AVAILABLE"
    local lead_version = lead_runtime_ok and type(lead_runtime) == "table"
        and tostring(lead_runtime.CONSENSUS_LEAD_DESK_VERSION or "loaded") or nil
    local lead_state = lead_runtime_ok and ("loaded · " .. lead_version)
        or ("ERROR: " .. tostring(lead_runtime_error or "unknown"))
    local source_state
    if ok_sources and type(sources) == "table" then
        source_state = tostring(#sources) .. " configured sources"
    else
        source_state = "ERROR loading sources.lua"
    end

    return table.concat({
        "Morning Paper runtime: " .. RUNTIME_BUILD,
        "Menu engine: direct core cadence wiring",
        "Wake scheduler: " .. wake,
        "Consensus Lead Desk: " .. lead_state,
        "Coverage scan feeds configured: " .. tostring(configured_coverage_scans),
        "Editorial/paywall lead feeds configured: " .. tostring(configured_editorial_leads),
        "New coverage definitions injected this load: " .. tostring(injected_scans),
        "New paywall lead definitions injected this load: " .. tostring(injected_leads),
        "Research pool: " .. source_state,
        "",
        self:autoStatusText(),
        "",
        "AI enabled: " .. (self.ai_enabled and "ON" or "OFF"),
        "Last AI result: " .. tostring(self.last_ai_status or "Unknown"),
    }, "\n")
end

function Base:addToMainMenu(menu_items)
    -- Build the proven base menu first, then replace the legacy delivery submenu
    -- in the same table KOReader will render.
    base_add_menu(self, menu_items)
    local root = menu_items.morning_paper
    if not root or not root.sub_item_table then return end

    local frequency = {
        {
            text=_("Every morning"),
            checked_func=function() return self.auto_cadence == "daily" end,
            callback=function()
                self:setAutoCadence("daily")
                UIManager:show(InfoMessage:new{ text=self:autoStatusText() })
            end,
        },
        {
            text=_("Weekdays"),
            checked_func=function() return self.auto_cadence == "weekdays" end,
            callback=function()
                self:setAutoCadence("weekdays")
                UIManager:show(InfoMessage:new{ text=self:autoStatusText() })
            end,
        },
        {
            text=_("Once a week"),
            checked_func=function() return self.auto_cadence == "weekly" end,
            callback=function()
                self:setAutoCadence("weekly")
                UIManager:show(InfoMessage:new{ text=self:autoStatusText() })
            end,
        },
        {
            text=_("Manual only"),
            checked_func=function() return self.auto_cadence == "manual" end,
            callback=function()
                self:setAutoCadence("manual")
                UIManager:show(InfoMessage:new{ text=self:autoStatusText() })
            end,
        },
    }

    local weekly_days = {}
    for _, day in ipairs(DAYS) do
        local d = day
        weekly_days[#weekly_days + 1] = {
            text=_(d.label),
            checked_func=function() return self.auto_weekly_wday == d.wday end,
            callback=function()
                self:setWeeklyDay(d.wday)
                UIManager:show(InfoMessage:new{ text=self:autoStatusText() })
            end,
        }
    end

    local times = {}
    for _, preset in ipairs(DELIVERY_TIMES) do
        local p = preset
        times[#times + 1] = {
            text=p.label,
            checked_func=function() return self.auto_hour == p.hour and self.auto_minute == p.minute end,
            callback=function()
                self:setDeliveryTime(p.hour, p.minute)
                UIManager:show(InfoMessage:new{ text=self:autoStatusText() })
            end,
        }
    end

    local items = root.sub_item_table
    items[3] = {
        text=_("Automatic delivery · " .. RUNTIME_BUILD),
        sub_item_table={
            { text=_("Frequency"), sub_item_table=frequency },
            {
                text=_("Weekly delivery day"),
                enabled_func=function() return self.auto_cadence == "weekly" end,
                sub_item_table=weekly_days,
            },
            { text=_("Delivery time"), sub_item_table=times },
            {
                text=_("Delivery status"),
                separator=true,
                callback=function()
                    UIManager:show(InfoMessage:new{ text=self:autoStatusText() })
                end,
            },
            {
                text=_("Runtime check · " .. RUNTIME_BUILD),
                callback=function()
                    UIManager:show(InfoMessage:new{ text=self:runtimeDiagnosticsText() })
                end,
            },
        },
    }

    -- Add a permanent diagnostic entry so a running build can be verified without
    -- relying on App Store metadata.
    table.insert(items, #items, {
        text=_("Runtime & system check · " .. RUNTIME_BUILD),
        callback=function()
            UIManager:show(InfoMessage:new{ text=self:runtimeDiagnosticsText() })
        end,
    })

    -- Keep About last and make the running build explicit.
    items[#items] = {
        text=_("About"),
        callback=function()
            UIManager:show(InfoMessage:new{
                text=_("Morning Paper " .. RUNTIME_BUILD .. " uses a consensus lead-first AI newsroom. Major public paywall headlines act as importance signals, accessible reporting supplies the evidence, and automatic delivery supports every morning, weekdays, weekly, or manual-only schedules."),
            })
        end,
    }
end

return Base
