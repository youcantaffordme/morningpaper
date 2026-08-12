-- Morning Paper v0.12 — Delivery Cadence
-- Adds daily, weekday, weekly, and manual delivery without rewriting the proven
-- v0.7 UI/build pipeline. Existing users with automatic delivery enabled migrate
-- to Every Morning automatically.

local MorningPaper = require("main_v07")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local Device = require("device")
local _ = require("gettext")

local old_init = MorningPaper.init
local old_save_auto = MorningPaper.saveAutoSettings
local old_add_menu = MorningPaper.addToMainMenu

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
    { label="5:30 AM", hour=5, minute=30 }, { label="6:00 AM", hour=6, minute=0 },
    { label="6:30 AM", hour=6, minute=30 }, { label="7:00 AM", hour=7, minute=0 },
    { label="7:30 AM", hour=7, minute=30 }, { label="8:00 AM", hour=8, minute=0 },
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
            year=today.year, month=today.month, day=today.day + offset,
            hour=hour, min=minute, sec=0,
        }
        if target > now + 30 and day_is_allowed(target, cadence, weekly_wday) then
            return target
        end
    end
    return nil
end

function MorningPaper:init()
    local stored = G_reader_settings:readSetting("morningpaper_auto_cadence", nil)
    if not valid_cadence(stored) then
        stored = G_reader_settings:readSetting("morningpaper_auto_enabled", false) and "daily" or "manual"
    end
    self.auto_cadence = stored
    self.auto_weekly_wday = tonumber(G_reader_settings:readSetting("morningpaper_auto_weekly_wday", 1)) or 1
    if self.auto_weekly_wday < 1 or self.auto_weekly_wday > 7 then self.auto_weekly_wday = 1 end

    old_init(self)

    -- Keep the old boolean synchronized because the proven wake callback still
    -- uses it as its final safety check.
    self.auto_enabled = self.auto_cadence ~= "manual"
    self:saveAutoSettings()
    self:scheduleAutoDelivery(true)
end

function MorningPaper:saveAutoSettings()
    old_save_auto(self)
    G_reader_settings:saveSetting("morningpaper_auto_cadence", self.auto_cadence or "manual")
    G_reader_settings:saveSetting("morningpaper_auto_weekly_wday", self.auto_weekly_wday or 1)
    G_reader_settings:flush()
end

function MorningPaper:scheduleAutoDelivery(remove_existing)
    if not Device.wakeup_mgr then self.auto_next_epoch = nil; return false end
    if remove_existing ~= false and self.auto_callback then
        pcall(function() Device.wakeup_mgr:removeTasks(nil, self.auto_callback) end)
    end

    local cadence = valid_cadence(self.auto_cadence) and self.auto_cadence or "manual"
    if cadence == "manual" then self.auto_next_epoch = nil; return true end

    local target = next_delivery_epoch(self.auto_hour or 6, self.auto_minute or 30, cadence, self.auto_weekly_wday or 1)
    if not target then self.auto_next_epoch = nil; return false end

    self.auto_next_epoch = target
    Device.wakeup_mgr:addTask(math.max(60, target - os.time()), self.auto_callback)
    return true
end

function MorningPaper:setAutoCadence(cadence)
    if not valid_cadence(cadence) then return end
    self.auto_cadence = cadence
    self.auto_enabled = cadence ~= "manual"
    self.last_auto_status = self.auto_enabled and ("Scheduled · " .. CADENCE_LABELS[cadence]) or "Manual only"
    self:saveAutoSettings()
    local supported = self:scheduleAutoDelivery(true)
    if self.auto_enabled and not supported then
        UIManager:show(InfoMessage:new{ text=_("This device does not expose KOReader's hardware wake scheduler, so automatic delivery is unavailable here.") })
    end
end

-- Backward-compatible bridge for any older menu callback or setting path.
function MorningPaper:setAutoEnabled(enabled)
    self:setAutoCadence(enabled and "daily" or "manual")
end

function MorningPaper:setWeeklyDay(wday)
    wday = tonumber(wday)
    if not wday or wday < 1 or wday > 7 then return end
    self.auto_weekly_wday = wday
    self:saveAutoSettings()
    if self.auto_cadence == "weekly" then self:scheduleAutoDelivery(true) end
end

function MorningPaper:autoStatusText()
    local cadence = valid_cadence(self.auto_cadence) and self.auto_cadence or "manual"
    local delivery = os.date("%I:%M %p", os.time{year=2000, month=1, day=1, hour=self.auto_hour or 6, min=self.auto_minute or 30, sec=0}):gsub("^0", "")
    local next_text = self.auto_next_epoch and os.date("%a %b %d, %I:%M %p", self.auto_next_epoch):gsub(" 0", " ") or "Not scheduled"
    local weekly_line = ""
    if cadence == "weekly" then
        weekly_line = "\nWeekly day: " .. (DAYS[self.auto_weekly_wday or 1] and DAYS[self.auto_weekly_wday or 1].label or "Sunday")
    end
    return string.format(
        "Delivery frequency: %s%s\nDelivery time: %s\nNext delivery: %s\nLast result: %s",
        CADENCE_LABELS[cadence] or cadence, weekly_line, delivery, next_text, self.last_auto_status or "Unknown"
    )
end

function MorningPaper:addToMainMenu(menu_items)
    old_add_menu(self, menu_items)
    if not menu_items.morning_paper or not menu_items.morning_paper.sub_item_table then return end

    local frequency = {
        { text=_("Every morning"), checked_func=function() return self.auto_cadence == "daily" end, callback=function()
            self:setAutoCadence("daily"); UIManager:show(InfoMessage:new{ text=self:autoStatusText() })
        end },
        { text=_("Weekdays"), checked_func=function() return self.auto_cadence == "weekdays" end, callback=function()
            self:setAutoCadence("weekdays"); UIManager:show(InfoMessage:new{ text=self:autoStatusText() })
        end },
        { text=_("Once a week"), checked_func=function() return self.auto_cadence == "weekly" end, callback=function()
            self:setAutoCadence("weekly"); UIManager:show(InfoMessage:new{ text=self:autoStatusText() })
        end },
        { text=_("Manual only"), checked_func=function() return self.auto_cadence == "manual" end, callback=function()
            self:setAutoCadence("manual"); UIManager:show(InfoMessage:new{ text=self:autoStatusText() })
        end },
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

    menu_items.morning_paper.sub_item_table[3] = {
        text=_("Automatic delivery"),
        sub_item_table={
            { text=_("Frequency"), sub_item_table=frequency },
            { text=_("Weekly delivery day"), sub_item_table=weekly_days },
            { text=_("Delivery time"), sub_item_table=times },
            { text=_("Delivery status"), separator=true, callback=function()
                UIManager:show(InfoMessage:new{ text=self:autoStatusText() })
            end },
        },
    }
end

return MorningPaper
