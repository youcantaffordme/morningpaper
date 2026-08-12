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

-- Reuse KOAssistant's active OpenRouter model when Morning Paper is still on its
-- default router. KOAssistant stores the active provider/model in features.provider
-- and features.model, so this stays independent of KOAssistant internals/API code.
function AiBriefing.findKOAssistantModel()
    local settings_dir = DataStorage:getSettingsDir()
    local ko_settings = load_lua_table(settings_dir .. "/koassistant_settings.lua")
    if not ko_settings then return nil, "KOAssistant settings not found" end

    local features = type(ko_settings.features) == "table" and ko_settings.features or {}
    local provider = features.provider or ko_settings.provider
    local model = features.model or ko_settings.model

    if provider == "openrouter" and nonempty(model) then
        return model, "KOAssistant current OpenRouter model"
    end
    if provider and provider ~= "openrouter" then
        return nil, "KOAssistant is using " .. tostring(provider) .. ", not OpenRouter"
    end
    return nil, "KOAssistant OpenRouter model not found"
end

function AiBriefing.resolveModel(requested_model)
    local requested = nonempty(requested_model) and requested_model or DEFAULT_MODEL
    if requested == DEFAULT_MODEL then
        local koa_model, source = AiBriefing.findKOAssistantModel()
        if koa_model then return koa_model, source end
    end
    return requested, requested == DEFAULT_MODEL and "Morning Paper free router" or "Morning Paper model setting"
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

Return a JSON object with one key named "briefs". "briefs" must contain 1 to 8 objects. Every brief must contain exactly:
- "title": an original concise headline
- "body": prose formatted as FACTS, WHY IT MATTERS, WHERE COVERAGE DIFFERS, and WATCH NEXT
- "sources": an array of source names actually used

If the reporting does not support five responsible multi-source briefs, return fewer rather than inventing material.
]]

local RESPONSE_FORMAT = {
    type = "json_schema",
    json_schema = {
        name = "morning_paper_intelligence",
        strict = true,
        schema = {
            type = "object",
            properties = {
                briefs = {
                    type = "array",
                    minItems = 1,
                    maxItems = 8,
                    items = {
                        type = "object",
                        properties = {
                            title = { type = "string" },
                            body = { type = "string" },
                            sources = {
                                type = "array",
                                items = { type = "string" },
                            },
                        },
                        required = { "title", "body", "sources" },
                        additionalProperties = false,
                    },
                },
            },
            required = { "briefs" },
            additionalProperties = false,
        },
    },
}

local function as_brief_array(value)
    if type(value) ~= "table" then return nil end
    if type(value.briefs) == "table" then return value.briefs end
    if type(value.articles) == "table" then return value.articles end
    if type(value.items) == "table" then return value.items end
    if #value > 0 then return value end
    return nil
end

local function try_decode(text)
    if type(text) ~= "string" or text == "" then return nil end
    local ok, decoded = pcall(rapidjson.decode, text)
    if ok then
        local briefs = as_brief_array(decoded)
        if briefs then return briefs end
    end
    return nil
end

-- Structured outputs should make the first decode succeed. These fallbacks keep
-- Morning Paper resilient to providers that still wrap JSON in prose/code fences.
local function decode_briefs(text)
    if type(text) ~= "string" then return nil end

    local briefs = try_decode(text)
    if briefs then return briefs end

    local stripped = text
        :gsub("^%s*```[%w_%-]*%s*", "")
        :gsub("%s*```%s*$", "")
    briefs = try_decode(stripped)
    if briefs then return briefs end

    local first_obj = stripped:find("{", 1, true)
    local last_obj
    for i = #stripped, 1, -1 do
        if stripped:sub(i, i) == "}" then last_obj = i break end
    end
    if first_obj and last_obj and last_obj >= first_obj then
        briefs = try_decode(stripped:sub(first_obj, last_obj))
        if briefs then return briefs end
    end

    local first_arr = stripped:find("[", 1, true)
    local last_arr
    for i = #stripped, 1, -1 do
        if stripped:sub(i, i) == "]" then last_arr = i break end
    end
    if first_arr and last_arr and last_arr >= first_arr then
        briefs = try_decode(stripped:sub(first_arr, last_arr))
        if briefs then return briefs end
    end

    return nil
end

local function make_request(api_key, model, user_prompt)
    local body = {
        model = model or DEFAULT_MODEL,
        max_tokens = 6000,
        messages = {
            { role = "system", content = SYSTEM_PROMPT },
            { role = "user", content = user_prompt },
        },
        response_format = RESPONSE_FORMAT,
        plugins = {
            { id = "response-healing" },
        },
    }

    -- Claude 5 models reject sampling controls on some providers. The editorial
    -- prompt + strict JSON schema already make this request deterministic enough,
    -- so Morning Paper deliberately sends no temperature/top_p parameters.

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
        local detail = raw ~= "" and clip(raw, 420) or tostring(status or code or "network error")
        return nil, "OpenRouter request failed: " .. detail
    end

    local response, decode_err = rapidjson.decode(raw)
    if not response then return nil, "Could not decode OpenRouter response: " .. tostring(decode_err) end
    local choice = response.choices and response.choices[1]
    local content = choice and choice.message and choice.message.content
    if type(content) ~= "string" or content == "" then return nil, "OpenRouter returned no briefing text" end
    return content, nil, response.model, choice.finish_reason
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

    local selected_model = AiBriefing.resolveModel(opts.model)
    local content, err, model_used, finish_reason = make_request(api_key, selected_model, user_prompt)
    if not content then return nil, err end

    local decoded = decode_briefs(content)
    if type(decoded) ~= "table" then
        if finish_reason == "length" then
            return nil, "AI briefing was truncated before the structured response completed"
        end
        return nil, "AI returned an unusable structured briefing response"
    end

    local out = {}
    for _, brief in ipairs(decoded) do
        if type(brief) == "table" and nonempty(brief.title) and nonempty(brief.body) then
            local sources = {}
            if type(brief.sources) == "table" then
                for _, source in ipairs(brief.sources) do
                    if nonempty(source) then sources[#sources + 1] = tostring(source) end
                end
            end
            local body_text = tostring(brief.body)
            if #sources > 0 then body_text = body_text .. "\n\nSOURCES: " .. table.concat(sources, "; ") end
            out[#out + 1] = {
                title = tostring(brief.title),
                source = "Morning Paper Intelligence Desk",
                date = os.date("%a, %d %b %Y %H:%M:%S %z"),
                published_epoch = os.time(),
                content_mode = "AI multi-source synthesis · " .. tostring(model_used or selected_model or DEFAULT_MODEL),
                body = body_text,
                link = "",
            }
            if #out >= 8 then break end
        end
    end

    if #out == 0 then return nil, "AI produced no usable multi-source briefs" end
    return out, nil, model_used or selected_model
end

-- Migration: if Morning Paper is still on the original free-router default and
-- KOAssistant is currently using OpenRouter, mirror KOAssistant's chosen model.
if G_reader_settings then
    local current = G_reader_settings:readSetting("morningpaper_ai_model", DEFAULT_MODEL)
    if not nonempty(current) or current == DEFAULT_MODEL then
        local koa_model = AiBriefing.findKOAssistantModel()
        if koa_model then
            G_reader_settings:saveSetting("morningpaper_ai_model", koa_model)
            G_reader_settings:flush()
        end
    end
end

AiBriefing.DEFAULT_MODEL = DEFAULT_MODEL
return AiBriefing
