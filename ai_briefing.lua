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

local ALLOWED_SECTIONS = {
    ["Front Page"] = true,
    ["World"] = true,
    ["U.S."] = true,
    ["Business & Markets"] = true,
    ["Technology & AI"] = true,
    ["Science"] = true,
    ["Culture"] = true,
}

local function nonempty(s)
    return type(s) == "string" and s:gsub("%s+", "") ~= ""
end

local function load_lua_table(path)
    if not path or lfs.attributes(path, "mode") ~= "file" then return nil end
    local ok, value = pcall(dofile, path)
    if ok and type(value) == "table" then return value end
    return nil
end

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
        for _, item in ipairs(sections[section] or {}) do
            pool[#pool + 1] = {
                section = section,
                source = item.source or "Unknown",
                title = item.title or "",
                date = item.date or "",
                published_epoch = item.published_epoch or 0,
                body = item.body or item.description or "",
                content_mode = item.content_mode or "",
            }
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
    local max_reporting = math.min(#pool, 48)

    for i = 1, max_reporting do
        local item = pool[i]
        reporting[#reporting + 1] = string.format(
            "REPORT %d\nOutlet: %s\nOriginal desk: %s\nPublished: %s\nHeadline: %s\nMaterial quality: %s\nAccessible reporting: %s",
            i,
            clip(item.source, 100),
            clip(item.section, 60),
            clip(item.date, 100),
            clip(item.title, 260),
            clip(item.content_mode, 80),
            clip(item.body, 1000)
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

    return table.concat(reporting, "\n\n"), table.concat(agenda, "\n\n")
end

local SYSTEM_PROMPT = [[
You are the newsroom and editorial board for MORNING PAPER, a personal daily newspaper. The supplied material comes from multiple news organizations, public institutions, and public headline feeds. Your job is to turn that research packet into an ORIGINAL newspaper edition, not to summarize articles one by one.

CORE EDITORIAL PHILOSOPHY
- Fact-first, multi-source, evidence-weighted, politically nonaligned.
- Do not manufacture left/right symmetry. If evidence is lopsided, say so plainly. If credible accounts genuinely conflict, explain the conflict and why.
- Separate established facts from allegations, predictions, political messaging, opinion, and unresolved claims.
- Use ONLY supplied reporting. Never browse, guess, invent context, or fill factual gaps from memory.
- WSJ entries marked AGENDA are public headline/topic signals only. They may influence which subjects deserve attention, but they are not evidence for details hidden behind a paywall.
- Prefer primary documents/data when supplied, but explain them in ordinary language and compare them with independent reporting.
- Treat every outlet as potentially incomplete. Compare what multiple outlets agree on, what each emphasizes, what is omitted, and whether those differences materially change the reader's understanding.

WHAT THE READER WANTS
The reader wants the news itself, not a list of what different outlets said. Each Morning Paper article should answer naturally, in polished newspaper prose:
- What happened?
- What is firmly established?
- Why does this matter now?
- What historical, economic, geopolitical, cultural, or institutional context is needed to understand it?
- How might it affect the current political/social/economic climate or existing tensions, when that connection is genuinely supported by the supplied reporting?
- Where do credible interpretations or interests differ?
- What remains uncertain?
- What should an informed reader watch next?

WRITING STANDARD
- Write as MORNING PAPER, not as BBC/Fox/Guardian/Epoch/etc.
- Synthesize overlapping reports about the same event into ONE coherent story.
- Do not merely paraphrase a single source paragraph by paragraph.
- Natural newspaper prose: strong lead, clear context, significance, relevant disagreement, and forward-looking close.
- Simplified enough to understand on a morning read, but more context-rich than a conventional short news article.
- Avoid repetitive labels like "FACTS:" or "WHY IT MATTERS:" unless a rare story genuinely benefits from them.
- Avoid ideological adjectives unless directly relevant and supported.
- No sensationalism, clickbait, or partisan cheerleading.
- Do not reproduce source wording. Never quote more than eight consecutive words from any supplied source.
- Aim for roughly 250–500 words per story. Major Front Page stories may be somewhat longer if the source packet supports it.

EDITION STRUCTURE
Create 8 to 14 stories total when the source material supports them. Use these exact sections:
Front Page
World
U.S.
Business & Markets
Technology & AI
Science
Culture

Front Page should contain roughly 2–3 of the day's most consequential stories. Do not repeat those same stories again in another section. Other sections contain the most important remaining developments. It is fine for a section to have no story if nothing consequential is supported by the supplied material.

A story should normally use multiple independent sources when possible. A consequential breaking story may use one strong source or primary document if that limitation is made clear in the prose. Never create artificial disagreement just to appear bipartisan.

For every article, return the outlet names actually used as evidence. These citations are for transparency; the article itself should read as one coherent Morning Paper story.
]]

local RESPONSE_FORMAT = {
    type = "json_schema",
    json_schema = {
        name = "morning_paper_edition",
        strict = true,
        schema = {
            type = "object",
            properties = {
                articles = {
                    type = "array",
                    minItems = 1,
                    maxItems = 14,
                    items = {
                        type = "object",
                        properties = {
                            section = {
                                type = "string",
                                enum = { "Front Page", "World", "U.S.", "Business & Markets", "Technology & AI", "Science", "Culture" },
                            },
                            title = { type = "string" },
                            body = { type = "string" },
                            sources = { type = "array", items = { type = "string" } },
                        },
                        required = { "section", "title", "body", "sources" },
                        additionalProperties = false,
                    },
                },
            },
            required = { "articles" },
            additionalProperties = false,
        },
    },
}

local function as_article_array(value)
    if type(value) ~= "table" then return nil end
    if type(value.articles) == "table" then return value.articles end
    if type(value.briefs) == "table" then return value.briefs end
    if type(value.items) == "table" then return value.items end
    if #value > 0 then return value end
    return nil
end

local function try_decode(text)
    if type(text) ~= "string" or text == "" then return nil end
    local ok, decoded = pcall(rapidjson.decode, text)
    if ok then return as_article_array(decoded) end
    return nil
end

local function decode_articles(text)
    if type(text) ~= "string" then return nil end
    local articles = try_decode(text)
    if articles then return articles end

    local stripped = text:gsub("^%s*```[%w_%-]*%s*", ""):gsub("%s*```%s*$", "")
    articles = try_decode(stripped)
    if articles then return articles end

    local first_obj = stripped:find("{", 1, true)
    local last_obj
    for i = #stripped, 1, -1 do
        if stripped:sub(i, i) == "}" then last_obj = i break end
    end
    if first_obj and last_obj and last_obj >= first_obj then
        articles = try_decode(stripped:sub(first_obj, last_obj))
        if articles then return articles end
    end

    local first_arr = stripped:find("[", 1, true)
    local last_arr
    for i = #stripped, 1, -1 do
        if stripped:sub(i, i) == "]" then last_arr = i break end
    end
    if first_arr and last_arr and last_arr >= first_arr then
        articles = try_decode(stripped:sub(first_arr, last_arr))
        if articles then return articles end
    end
    return nil
end

local function make_request(api_key, model, user_prompt)
    local body = {
        model = model or DEFAULT_MODEL,
        max_tokens = 9000,
        messages = {
            { role = "system", content = SYSTEM_PROMPT },
            { role = "user", content = user_prompt },
        },
        response_format = RESPONSE_FORMAT,
        plugins = { { id = "response-healing" } },
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
        local detail = raw ~= "" and clip(raw, 420) or tostring(status or code or "network error")
        return nil, "OpenRouter request failed: " .. detail
    end

    local response, decode_err = rapidjson.decode(raw)
    if not response then return nil, "Could not decode OpenRouter response: " .. tostring(decode_err) end
    local choice = response.choices and response.choices[1]
    local content = choice and choice.message and choice.message.content
    if type(content) ~= "string" or content == "" then return nil, "OpenRouter returned no newsroom text" end
    return content, nil, response.model, choice.finish_reason
end

function AiBriefing.generate(opts)
    opts = opts or {}
    local api_key = opts.api_key
    if not nonempty(api_key) then return nil, "No OpenRouter API key configured" end

    local reporting, agenda = build_material(opts.sections or {}, opts.section_order or {}, opts.agenda_items or {})
    if reporting == "" then return nil, "No accessible reporting was available for AI newsroom synthesis" end

    local user_prompt = string.format([[
EDITION DATE: %s
GENERATED: %s

NEWSROOM RESEARCH PACKET
%s

WSJ / EDITORIAL AGENDA SIGNALS
These are public headline/feed signals only. They can help identify consequential topics but are not evidence for undisclosed article details.
%s

Produce today's complete MORNING PAPER editorial edition now.]],
        tostring(opts.nice_date or opts.date or "Today"),
        tostring(opts.edition_time or "morning"),
        reporting,
        agenda ~= "" and agenda or "No fresh WSJ agenda signals were available."
    )

    local selected_model = AiBriefing.resolveModel(opts.model)
    local content, err, model_used, finish_reason = make_request(api_key, selected_model, user_prompt)
    if not content then return nil, err end

    local decoded = decode_articles(content)
    if type(decoded) ~= "table" then
        if finish_reason == "length" then
            return nil, "AI newsroom edition was truncated before the structured response completed"
        end
        return nil, "AI returned an unusable structured newsroom response"
    end

    local sections = {}
    local count = 0
    for _, article in ipairs(decoded) do
        if type(article) == "table" and ALLOWED_SECTIONS[article.section]
            and nonempty(article.title) and nonempty(article.body) then
            local source_names = {}
            if type(article.sources) == "table" then
                for _, source in ipairs(article.sources) do
                    if nonempty(source) then source_names[#source_names + 1] = tostring(source) end
                end
            end
            local body_text = tostring(article.body)
            if #source_names > 0 then
                body_text = body_text .. "\n\nReporting used: " .. table.concat(source_names, "; ")
            end
            sections[article.section] = sections[article.section] or {}
            sections[article.section][#sections[article.section] + 1] = {
                title = tostring(article.title),
                source = "Morning Paper Newsroom",
                date = os.date("%a, %d %b %Y %H:%M:%S %z"),
                published_epoch = os.time() - count,
                content_mode = "AI-enhanced multi-source reporting · " .. tostring(model_used or selected_model or DEFAULT_MODEL),
                body = body_text,
                link = "",
            }
            count = count + 1
            if count >= 14 then break end
        end
    end

    if count == 0 then return nil, "AI produced no usable Morning Paper articles" end
    return sections, nil, model_used or selected_model, count
end

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
