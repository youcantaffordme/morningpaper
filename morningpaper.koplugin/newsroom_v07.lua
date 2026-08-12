local http = require("socket.http")
local ltn12 = require("ltn12")
local rapidjson = require("rapidjson")
local socket = require("socket")
local socketutil = require("socketutil")
local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")

local Newsroom = {}

local ENDPOINT = "https://openrouter.ai/api/v1/chat/completions"
local FOLLOW_MODEL = "__follow_koassistant__"
local FREE_MODEL = "openrouter/free"
local SONNET5_MODEL = "anthropic/claude-sonnet-5"

Newsroom.DEFAULT_MODEL = FOLLOW_MODEL
Newsroom.FOLLOW_MODEL = FOLLOW_MODEL
Newsroom.FREE_MODEL = FREE_MODEL
Newsroom.SONNET5_MODEL = SONNET5_MODEL

local SECTION_ORDER = {
    "Front Page", "World", "U.S.", "Business & Markets",
    "Technology & AI", "Science", "Culture",
}

local SECTION_POLICY = {
    ["Front Page"] = { max = 3, min_reports = 1 },
    ["World"] = { max = 2, min_reports = 1 },
    ["U.S."] = { max = 2, min_reports = 1 },
    ["Business & Markets"] = { max = 3, min_reports = 1 },
    ["Technology & AI"] = { max = 2, min_reports = 1 },
    ["Science"] = { max = 1, min_reports = 1 },
    ["Culture"] = { max = 1, min_reports = 1 },
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

local function koassistant_settings()
    return load_lua_table(DataStorage:getSettingsDir() .. "/koassistant_settings.lua")
end

function Newsroom.findOpenRouterKey(explicit_key)
    if nonempty(explicit_key) then return explicit_key, "Morning Paper settings" end

    local ko_settings = koassistant_settings()
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

local function normalize_for_openrouter(provider, model)
    if not nonempty(model) then return nil end
    model = tostring(model)
    if model:find("/", 1, true) then return model end

    local prefixes = {
        anthropic = "anthropic/",
        openai = "openai/",
        gemini = "google/",
        google = "google/",
        deepseek = "deepseek/",
        xai = "x-ai/",
        mistral = "mistralai/",
        perplexity = "perplexity/",
    }
    local prefix = prefixes[provider]
    if prefix then
        if provider == "anthropic" then
            model = model:gsub("claude%-sonnet%-4%-6", "claude-sonnet-4.6")
            model = model:gsub("claude%-opus%-4%-8", "claude-opus-4.8")
            model = model:gsub("claude%-haiku%-4%-5", "claude-haiku-4.5")
        end
        return prefix .. model
    end
    return model
end

local function candidate_model(container, provider)
    if type(container) ~= "table" then return nil end
    if nonempty(container.model) then return container.model end
    local ps = container.provider_settings
    if type(ps) == "table" and provider and type(ps[provider]) == "table" and nonempty(ps[provider].model) then
        return ps[provider].model
    end
    local defaults = container.provider_default_models
    if type(defaults) == "table" and provider and nonempty(defaults[provider]) then
        return defaults[provider]
    end
    return nil
end

function Newsroom.findKOAssistantModel()
    local ko_settings = koassistant_settings()
    if not ko_settings then return nil, "KOAssistant settings not found" end

    local features = type(ko_settings.features) == "table" and ko_settings.features or {}
    local provider = features.provider or ko_settings.provider or features.default_provider or ko_settings.default_provider
    local model = candidate_model(features, provider) or candidate_model(ko_settings, provider)

    if not nonempty(model) then
        local defaults = features.provider_default_models or ko_settings.provider_default_models
        if type(defaults) == "table" and nonempty(defaults.openrouter) then
            provider = "openrouter"
            model = defaults.openrouter
        end
    end

    if not nonempty(model) then
        local ps = features.provider_settings or ko_settings.provider_settings
        if type(ps) == "table" and type(ps.openrouter) == "table" and nonempty(ps.openrouter.model) then
            provider = "openrouter"
            model = ps.openrouter.model
        end
    end

    if not nonempty(model) then return nil, "KOAssistant model not found" end

    local normalized = normalize_for_openrouter(provider, model)
    if normalized == "claude-sonnet-5" then normalized = SONNET5_MODEL end
    return normalized, "KOAssistant current model"
end

function Newsroom.resolveModel(requested_model)
    local requested = nonempty(requested_model) and requested_model or FOLLOW_MODEL
    if requested == FOLLOW_MODEL then
        local koa_model, source = Newsroom.findKOAssistantModel()
        if koa_model then return koa_model, source end
        return FREE_MODEL, "KOAssistant model unavailable; free-router fallback"
    end
    return requested, "Morning Paper model setting"
end

local function clip(s, n)
    s = tostring(s or ""):gsub("%s+", " ")
    if #s <= n then return s end
    return s:sub(1, n) .. "…"
end

local function normalize_key(s)
    return tostring(s or ""):lower():gsub("[^%w%s]", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

local function short_words(s, max_words, max_chars)
    local out, chars = {}, 0
    for word in tostring(s or ""):gmatch("%S+") do
        local add = #word + (#out > 0 and 1 or 0)
        if #out >= max_words or (max_chars and chars + add > max_chars) then break end
        out[#out + 1] = word
        chars = chars + add
    end
    local text = table.concat(out, " ")
    if text == "" then text = "Morning Paper story" end
    return text:gsub("[%.,;:!?%-]+$", "")
end

local function report_record(item, section, id, body_chars)
    return string.format(
        "REPORT %s\nOutlet: %s\nDesk: %s\nPublished: %s\nHeadline: %s\nMaterial quality: %s\nAccessible reporting: %s",
        id,
        clip(item.source or "Unknown", 100),
        clip(section or item.section or "", 60),
        clip(item.date or "", 100),
        clip(item.title or "", 260),
        clip(item.content_mode or "", 80),
        clip(item.body or item.description or "", body_chars or 1600)
    )
end

local function build_section_material(sections, section, global_mode)
    local records = {}
    local id = 0
    if global_mode then
        for _, s in ipairs(SECTION_ORDER) do
            for _, item in ipairs(sections[s] or {}) do
                id = id + 1
                records[#records + 1] = report_record(item, s, tostring(id), 900)
                if id >= 48 then return table.concat(records, "\n\n"), id end
            end
        end
    else
        for _, item in ipairs(sections[section] or {}) do
            id = id + 1
            records[#records + 1] = report_record(item, section, tostring(id), 1800)
            if id >= 18 then break end
        end
    end
    return table.concat(records, "\n\n"), id
end

local function build_agenda(agenda_items)
    local out = {}
    for i = 1, math.min(#(agenda_items or {}), 45) do
        local item = agenda_items[i]
        out[#out + 1] = string.format(
            "AGENDA %d | %s | %s | %s | %s",
            i,
            clip(item.source or "WSJ", 80),
            clip(item.agenda_category or "Agenda", 60),
            clip(item.date or "", 80),
            clip(item.title or "", 240)
        )
    end
    return table.concat(out, "\n")
end

local SYSTEM_PROMPT = [[
You are the newsroom and editorial board for MORNING PAPER, a personal daily newspaper. Your output is original journalism-style synthesis built only from the supplied research packet.

EDITORIAL STANDARD
- Fact-first, multi-source, evidence-weighted, politically nonaligned.
- Do not manufacture left/right symmetry. If the evidence is lopsided, say so plainly. If credible accounts genuinely conflict, explain the conflict and why.
- Treat every outlet as potentially incomplete. Reconcile overlap, identify meaningful framing differences, and distinguish facts from allegations, predictions, spin, analysis, and opinion.
- Use ONLY supplied material. Do not browse, rely on memory, or invent missing context.
- WSJ AGENDA entries are public headline/topic signals only. They may influence importance, but are never evidence for details hidden behind a paywall.
- Prefer primary documents/data when supplied, while explaining them in ordinary language and checking them against independent reporting when available.

WHAT A MORNING PAPER STORY MUST DO
Write a real newspaper article, not a bullet summary and not a source-by-source recap. Naturally explain what happened, what is firmly established, why it matters now, the context needed to understand it, how it may affect current political/social/economic tensions when supported, where credible interpretations differ, what remains uncertain, and what to watch next.

STYLE
- Strong concise headline; never use the first sentence as the headline.
- A separate short TOC headline of 4–9 words for navigation.
- A one-sentence dek that adds useful context instead of repeating the headline.
- Natural newspaper prose, roughly 300–650 words when the evidence supports it.
- No repetitive FACTS/WHY IT MATTERS labels unless a rare story truly benefits.
- No clickbait, partisan cheerleading, fake balance, or ideological adjectives unless directly relevant.
- Do not reproduce source wording; never quote more than eight consecutive words from any supplied source.
- Each story should normally draw on multiple independent reports when possible. A strong single-source breaking item is allowed only when the limitation is clear.

EDITORIAL SELECTION
- Prioritize consequential developments: governance, elections, war/security, diplomacy, economy/markets, major companies, technology, public safety, institutions, and broad social effects.
- Novelty/entertainment should not displace more consequential news on the Front Page.
- Do not repeat an event already listed in EXCLUDE STORIES.
- Use a stable story_key: 3–8 lowercase words naming the event/topic, so later desks can avoid duplicates.
]]

local function response_schema(section, target)
    return {
        type = "json_schema",
        json_schema = {
            name = "morning_paper_" .. section:gsub("[^%w]", "_"):lower(),
            strict = true,
            schema = {
                type = "object",
                properties = {
                    articles = {
                        type = "array",
                        minItems = target,
                        maxItems = target,
                        items = {
                            type = "object",
                            properties = {
                                section = { type = "string", enum = { section } },
                                headline = { type = "string" },
                                toc_title = { type = "string" },
                                dek = { type = "string" },
                                story_key = { type = "string" },
                                body = { type = "string" },
                                sources = { type = "array", items = { type = "string" } },
                            },
                            required = { "section", "headline", "toc_title", "dek", "story_key", "body", "sources" },
                            additionalProperties = false,
                        },
                    },
                },
                required = { "articles" },
                additionalProperties = false,
            },
        },
    }
end

local function decode_articles(text)
    if type(text) ~= "string" or text == "" then return nil end
    local candidates = { text }
    candidates[#candidates + 1] = text:gsub("^%s*```[%w_%-]*%s*", ""):gsub("%s*```%s*$", "")
    local stripped = candidates[#candidates]
    local s = stripped:find("{", 1, true)
    local e
    for i = #stripped, 1, -1 do if stripped:sub(i, i) == "}" then e = i break end end
    if s and e and e >= s then candidates[#candidates + 1] = stripped:sub(s, e) end

    for _, candidate in ipairs(candidates) do
        local ok, decoded = pcall(rapidjson.decode, candidate)
        if ok and type(decoded) == "table" then
            if type(decoded.articles) == "table" then return decoded.articles end
            if #decoded > 0 then return decoded end
        end
    end
    return nil
end

local function raw_request(api_key, model, system_prompt, user_prompt, schema, max_tokens, structured)
    local body = {
        model = model,
        max_tokens = max_tokens or 5200,
        messages = {
            { role = "system", content = system_prompt },
            { role = "user", content = user_prompt },
        },
        plugins = { { id = "response-healing" } },
    }
    if structured then body.response_format = schema end

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
        return nil, "OpenRouter HTTP " .. tostring(code) .. ": " .. clip(raw ~= "" and raw or status, 420), code
    end

    local response, decode_err = rapidjson.decode(raw)
    if not response then return nil, "Could not decode OpenRouter response: " .. tostring(decode_err) end
    local choice = response.choices and response.choices[1]
    local content = choice and choice.message and choice.message.content
    if type(content) ~= "string" or content == "" then return nil, "OpenRouter returned no newsroom text" end

    local cost = nil
    if type(response.usage) == "table" then cost = tonumber(response.usage.cost or response.usage.total_cost) end
    return { content=content, model=response.model or model, finish_reason=choice and choice.finish_reason, cost=cost }
end

local function request_articles(api_key, model, section, target, user_prompt)
    local schema = response_schema(section, target)
    local response, err = raw_request(api_key, model, SYSTEM_PROMPT, user_prompt, schema, 6200, true)
    local retried_unstructured = false

    if not response then
        retried_unstructured = true
        response, err = raw_request(
            api_key, model, SYSTEM_PROMPT,
            user_prompt .. "\n\nReturn ONLY valid JSON with a top-level articles array and exactly " .. tostring(target) .. " articles.",
            schema, 6200, false
        )
    end
    if not response then return nil, err, nil, retried_unstructured end

    local articles = decode_articles(response.content)
    if type(articles) ~= "table" then
        if response.finish_reason == "length" then return nil, "AI response was truncated", response, retried_unstructured end
        return nil, "AI returned unusable newsroom JSON", response, retried_unstructured
    end
    return articles, nil, response, retried_unstructured
end

local function target_for(section, report_count, total_count)
    local max_target = (SECTION_POLICY[section] and SECTION_POLICY[section].max) or 1
    if section == "Front Page" then
        if total_count >= 12 then return 3 end
        if total_count >= 5 then return 2 end
        return total_count > 0 and 1 or 0
    end
    if report_count <= 0 then return 0 end
    if max_target >= 3 and report_count >= 8 then return 3 end
    if max_target >= 2 and report_count >= 3 then return 2 end
    return 1
end

local function exclusions_text(generated)
    if #generated == 0 then return "None." end
    local out = {}
    for _, item in ipairs(generated) do out[#out + 1] = "- " .. tostring(item.story_key or item.title or "") .. " | " .. tostring(item.title or "") end
    return table.concat(out, "\n")
end

local function clean_article(article, section, model_used, ordinal)
    if type(article) ~= "table" then return nil end
    local headline = nonempty(article.headline) and tostring(article.headline) or tostring(article.title or "")
    local body = tostring(article.body or "")
    if not nonempty(headline) or not nonempty(body) then return nil end

    local toc_title = nonempty(article.toc_title) and tostring(article.toc_title) or short_words(headline, 8, 58)
    toc_title = short_words(toc_title, 9, 64)
    headline = short_words(headline, 16, 120)
    local dek = nonempty(article.dek) and tostring(article.dek) or ""
    local story_key = nonempty(article.story_key) and normalize_key(article.story_key) or normalize_key(toc_title)

    local sources = {}
    if type(article.sources) == "table" then
        local seen = {}
        for _, source in ipairs(article.sources) do
            source = tostring(source or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if source ~= "" and not seen[source] then seen[source] = true; sources[#sources + 1] = source end
        end
    end

    return {
        title=headline, toc_title=toc_title, dek=dek, story_key=story_key,
        source="Morning Paper Newsroom", date=os.date("%a, %d %b %Y %H:%M:%S %z"),
        published_epoch=os.time() - (ordinal or 0), content_mode="AI-enhanced multi-source reporting",
        model_used=model_used, body=body, sources=sources, link="",
    }
end

function Newsroom.generate(opts)
    opts = opts or {}
    local api_key = opts.api_key
    if not nonempty(api_key) then return nil, "No OpenRouter API key configured" end

    local sections = opts.sections or {}
    local total_reports = 0
    for _, section in ipairs(SECTION_ORDER) do total_reports = total_reports + #(sections[section] or {}) end
    if total_reports == 0 then return nil, "No accessible reporting was available" end

    local selected_model, model_source = Newsroom.resolveModel(opts.model)
    local agenda = build_agenda(opts.agenda_items or {})
    local output, generated, warnings = {}, {}, {}
    local stats = { calls=0, retries=0, cost=0, cost_known=false, model_source=model_source, section_counts={}, models={} }

    local ordinal = 0
    for _, section in ipairs(SECTION_ORDER) do
        local global_mode = section == "Front Page"
        local material, report_count = build_section_material(sections, section, global_mode)
        local target = target_for(section, report_count, total_reports)
        if target > 0 and material ~= "" then
            local desk_instruction
            if section == "Front Page" then
                desk_instruction = "Choose the " .. target .. " most consequential DISTINCT developments in the full research packet. Front Page is an editorial selection desk, not a category. Avoid novelty stories when major political, economic, geopolitical, security, institutional, or technology developments are available."
            else
                desk_instruction = "Produce exactly " .. target .. " distinct " .. section .. " story/stories from this desk's research. Prefer the most consequential developments not already used on the Front Page or earlier desks."
            end

            local prompt = string.format([[
EDITION: %s
DESK: %s
TARGET: exactly %d finished Morning Paper stories

%s

EXCLUDE STORIES ALREADY PUBLISHED
%s

ACCESSIBLE RESEARCH
%s

WSJ / EDITORIAL AGENDA SIGNALS
These are public headline signals only, never evidence for undisclosed details:
%s

Return the finished %s desk now.]],
                tostring(opts.nice_date or opts.date or "Today"), section, target, desk_instruction,
                exclusions_text(generated), material, agenda ~= "" and agenda or "None available.", section
            )

            local articles, err, response, retried = request_articles(api_key, selected_model, section, target, prompt)
            stats.calls = stats.calls + 1
            if retried then stats.retries = stats.retries + 1 end
            if response and response.cost then stats.cost = stats.cost + response.cost; stats.cost_known = true end
            if response and nonempty(response.model) then stats.models[response.model] = true end

            if not articles then warnings[#warnings + 1] = section .. ": " .. tostring(err)
            else
                local accepted, local_keys = 0, {}
                for _, article in ipairs(articles) do
                    ordinal = ordinal + 1
                    local item = clean_article(article, section, response and response.model or selected_model, ordinal)
                    if item and item.story_key ~= "" and not local_keys[item.story_key] then
                        local duplicate = false
                        for _, prior in ipairs(generated) do if item.story_key == prior.story_key then duplicate = true break end end
                        if not duplicate then
                            local_keys[item.story_key] = true
                            output[section] = output[section] or {}
                            output[section][#output[section] + 1] = item
                            generated[#generated + 1] = item
                            accepted = accepted + 1
                        end
                    end
                end
                stats.section_counts[section] = accepted
                if accepted < target then warnings[#warnings + 1] = string.format("%s returned %d/%d distinct stories", section, accepted, target) end
            end
        end
    end

    local count = #generated
    local minimum = math.min(6, math.max(3, math.floor(total_reports / 6)))
    if count < minimum then
        return nil, string.format("AI newsroom produced only %d stories; minimum for this edition is %d. %s", count, minimum, table.concat(warnings, " | ")), selected_model, count, stats
    end

    stats.warnings = warnings
    local model_names = {}
    for model_name in pairs(stats.models) do model_names[#model_names + 1] = model_name end
    table.sort(model_names)
    local model_summary = selected_model
    if #model_names == 1 then model_summary = model_names[1]
    elseif #model_names > 1 then model_summary = selected_model .. " (routed across " .. tostring(#model_names) .. " models)" end
    return output, nil, model_summary, count, stats
end

return Newsroom
