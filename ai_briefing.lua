local http = require("socket.http")
local ltn12 = require("ltn12")
local rapidjson = require("rapidjson")
local socket = require("socket")
local socketutil = require("socketutil")
local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")

local AiBriefing = {}

local DEFAULT_MODEL = "openrouter/free"
local ENDPOINT = "https://openrouter.ai/api/v1/chat/completions"

local function nonempty(s)
    return type(s) == "string" and s:gsub("%s+", "") ~= ""
end

local function load_lua_table(path)
    if not path or lfs.attributes(path, "mode") ~= "file" then return nil end
    local ok, value = pcall(dofile, path)
    if ok and type(value) == "table" then return value end
    return nil
end

-- Prefer a Morning Paper key if the user explicitly saved one. Otherwise, try
-- to reuse an OpenRouter key the reader already configured for KOAssistant.
-- The key never leaves the device except as the Authorization header sent to
-- OpenRouter for the requested synthesis.
function AiBriefing.findOpenRouterKey(explicit_key)
    if nonempty(explicit_key) then return explicit_key, "Morning Paper settings" end

    local settings_dir = DataStorage:getSettingsDir()
    local ko_settings = load_lua_table(settings_dir .. "/koassistant_settings.lua")
    if ko_settings then
        local features = type(ko_settings.features) == "table" and ko_settings.features or {}
        local keys = type(features.api_keys) == "table" and features.api_keys
            or (type(ko_settings.api_keys) == "table" and ko_settings.api_keys or nil)
        if keys and nonempty(keys.openrouter) then
            return keys.openrouter, "KOAssistant settings"
        end
    end

    local candidates = {
        "/mnt/us/koreader/plugins/koassistant.koplugin/apikeys.lua",
        DataStorage:getDataDir() .. "/plugins/koassistant.koplugin/apikeys.lua",
    }
    for _, path in ipairs(candidates) do
        local keys = load_lua_table(path)
        if keys and nonempty(keys.openrouter) then
            return keys.openrouter, "KOAssistant apikeys.lua"
        end
    end

    return nil, "No OpenRouter key found"
end

local function clip(s, n)
    s = tostring(s or ""):gsub("%s+", " ")
    if #s <= n then return s end
    return s:sub(1, n) .. "…"
end

local function sorted_story_pool(sections, section_order)
    local pool = {}
    for _, section in ipairs(section_order or {}) do
        if section ~= "Intelligence Desk" then
            for _, item in ipairs(sections[section] or {}) do
                pool[#pool + 1] = {
                    section = section,
                    source = item.source or "Unknown",
                    title = item.title or "",
                    date = item.date or "",
                    published_epoch = item.published_epoch or 0,
                    body = item.body or item.description or "",
                }
            end
        end
    end
    table.sort(pool, function(a, b)
        return (a.published_epoch or 0) > (b.published_epoch or 0)
    end)
    return pool
end

local function build_material(sections, section_order, agenda_items)
    local pool = sorted_story_pool(sections, section_order)
    local reporting = {}
    local source_counts = {}
    local max_reporting = math.min(#pool, 36)

    for i = 1, max_reporting do
        local item = pool[i]
        source_counts[item.source] = (source_counts[item.source] or 0) + 1
        reporting[#reporting + 1] = string.format(
            "REPORT %d\nSource: %s\nSection: %s\nPublished: %s\nHeadline: %s\nPublic text: %s",
            i,
            clip(item.source, 100),
            clip(item.section, 60),
            clip(item.date, 100),
            clip(item.title, 260),
            clip(item.body, 1200)
        )
    end

    local agenda = {}
    local max_agenda = math.min(#(agenda_items or {}), 60)
    for i = 1, max_agenda do
        local item = agenda_items[i]
        agenda[#agenda + 1] = string.format(
            "AGENDA %d\nOutlet: %s\nDesk: %s\nPublished: %s\nHeadline: %s\nPublic feed note: %s",
            i,
            clip(item.source, 100),
            clip(item.agenda_category or "WSJ", 80),
            clip(item.date, 100),
            clip(item.title, 260),
            clip(item.description, 320)
        )
    end

    return table.concat(reporting, "\n\n"), table.concat(agenda, "\n\n"), source_counts
end

local SYSTEM_PROMPT = [[
You are the Intelligence Desk for a personal morning newspaper. Your job is not to imitate any publisher. Your job is to create original, fact-first synthesis from the source material supplied to you.

Editorial standard:
- Use ONLY the supplied material. Do not browse, guess, fill gaps, or invent facts.
- Wall Street Journal items marked AGENDA are public headline/feed signals only. They may tell you which topics WSJ is emphasizing, but they are NOT evidence for facts hidden behind a paywall. Never reconstruct a WSJ article from its headline.
- Prefer topics that are consequential for business, markets, the economy, public policy, technology, national security, geopolitics, and ordinary life.
- Prefer topics that appear in the fresh WSJ agenda list when the accessible reporting also supports them, but do not let WSJ determine the entire paper.
- Ground each brief in at least two independent accessible reports whenever possible. One primary-source document plus one independent report is also acceptable. If a topic has only one weak source, omit it.
- Separate confirmed facts from allegations, predictions, political claims, analysis, and opinion.
- When credible sources materially disagree, explain the disagreement. Do not force false balance when the underlying evidence is lopsided.
- Include materially different conservative, liberal, institutional, international, or market interpretations when they actually exist in the supplied reporting. Do not assign ideological labels unless necessary to explain the dispute.
- For economic and market stories, explain the mechanism: what changed, why it matters, and what could move next.
- Write clean original prose. Do not reproduce source wording and do not quote more than eight consecutive words from any source.
- Be concise enough for a morning read but substantial enough that the reader understands the issue without opening five articles.

Return ONLY a valid JSON array with 5 to 8 objects. Each object must have exactly:
{
  "title": "an original concise headline",
  "body": "FACTS: ...\n\nWHY IT MATTERS: ...\n\nWHERE COVERAGE DIFFERS: ...\n\nWATCH NEXT: ...",
  "sources": ["Source name", "Source name"]
}

If the reporting does not support 5 responsible multi-source briefs, return fewer rather than inventing material.
]]

local function extract_json_array(text)
    if type(text) ~= "string" then return nil end
    local first = text:find("[", 1, true)
    local last
    for i = #text, 1, -1 do
        if text:sub(i, i) == "]" then last = i break end
    end
    if not first or not last or last < first then return nil end
    return text:sub(first, last)
end

local function make_request(api_key, model, user_prompt)
    local body = {
        model = model or DEFAULT_MODEL,
        temperature = 0.2,
        max_tokens = 3600,
        messages = {
            { role = "system", content = SYSTEM_PROMPT },
            { role = "user", content = user_prompt },
        },
    }

    local encoded, encode_err = rapidjson.encode(body)
    if not encoded then return nil, "Could not encode AI request: " .. tostring(encode_err) end

    local sink = {}
    socketutil:set_timeout(socketutil.LARGE_BLOCK_TIMEOUT, socketutil.LARGE_TOTAL_TIMEOUT)
    local code, _, status = socket.skip(1, http.request{
        url = ENDPOINT,
        method = "POST",
        source = ltn12.source.string(encoded),
        sink = ltn12.sink.table(sink),
        headers = {
            ["Authorization"] = "Bearer " .. api_key,
            ["Content-Type"] = "application/json",
            ["Content-Length"] = #encoded,
            ["X-Title"] = "KOReader Morning Paper",
        },
    })
    socketutil:reset_timeout()

    code = tonumber(code) or 0
    local raw = table.concat(sink)
    if code < 200 or code >= 300 then
        local detail = raw ~= "" and clip(raw, 300) or tostring(status or code or "network error")
        return nil, "OpenRouter request failed: " .. detail
    end

    local response, decode_err = rapidjson.decode(raw)
    if not response then return nil, "Could not decode OpenRouter response: " .. tostring(decode_err) end
    local choice = response.choices and response.choices[1]
    local content = choice and choice.message and choice.message.content
    if type(content) ~= "string" or content == "" then return nil, "OpenRouter returned no briefing text" end
    return content, nil, response.model
end

function AiBriefing.generate(opts)
    opts = opts or {}
    local api_key = opts.api_key
    if not nonempty(api_key) then return nil, "No OpenRouter API key configured" end

    local reporting, agenda = build_material(opts.sections or {}, opts.section_order or {}, opts.agenda_items or {})
    if reporting == "" then return nil, "No accessible reporting was available for AI synthesis" end

    local user_prompt = string.format([[
Issue: %s
Edition generated: %s

ACCESSIBLE REPORTING
%s

WSJ / EDITORIAL AGENDA SIGNALS
The following are public headline/feed signals only. Do not treat them as evidence for details that are not present in ACCESSIBLE REPORTING.
%s

Create the Intelligence Desk now.]],
        tostring(opts.nice_date or opts.date or "Today"),
        tostring(opts.edition_time or "morning"),
        reporting,
        agenda ~= "" and agenda or "No fresh WSJ agenda signals were available."
    )

    local content, err, model_used = make_request(api_key, opts.model or DEFAULT_MODEL, user_prompt)
    if not content then return nil, err end

    local json_text = extract_json_array(content)
    if not json_text then return nil, "AI response was not a JSON briefing array" end
    local decoded, json_err = rapidjson.decode(json_text)
    if type(decoded) ~= "table" then return nil, "Could not parse AI briefing: " .. tostring(json_err) end

    local out = {}
    for _, brief in ipairs(decoded) do
        if type(brief) == "table" and nonempty(brief.title) and nonempty(brief.body) then
            local sources = {}
            if type(brief.sources) == "table" then
                for _, source in ipairs(brief.sources) do
                    if nonempty(source) then sources[#sources + 1] = tostring(source) end
                end
            end
            local body = tostring(brief.body)
            if #sources > 0 then body = body .. "\n\nSOURCES: " .. table.concat(sources, "; ") end
            out[#out + 1] = {
                title = tostring(brief.title),
                source = "Morning Paper Intelligence Desk",
                date = os.date("%a, %d %b %Y %H:%M:%S %z"),
                published_epoch = os.time(),
                content_mode = "AI multi-source synthesis · " .. tostring(model_used or opts.model or DEFAULT_MODEL),
                body = body,
                link = "",
            }
            if #out >= 8 then break end
        end
    end

    if #out == 0 then return nil, "AI produced no usable multi-source briefs" end
    return out, nil, model_used
end

AiBriefing.DEFAULT_MODEL = DEFAULT_MODEL
return AiBriefing
