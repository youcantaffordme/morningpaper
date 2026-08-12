local http = require("socket.http")
local ltn12 = require("ltn12")

local ArticleFetcher = {}

local function utf8_char(code)
    if not code or code < 0 then return "" end
    if code <= 0x7F then
        return string.char(code)
    elseif code <= 0x7FF then
        return string.char(0xC0 + math.floor(code / 0x40), 0x80 + (code % 0x40))
    elseif code <= 0xFFFF then
        return string.char(
            0xE0 + math.floor(code / 0x1000),
            0x80 + (math.floor(code / 0x40) % 0x40),
            0x80 + (code % 0x40)
        )
    elseif code <= 0x10FFFF then
        return string.char(
            0xF0 + math.floor(code / 0x40000),
            0x80 + (math.floor(code / 0x1000) % 0x40),
            0x80 + (math.floor(code / 0x40) % 0x40),
            0x80 + (code % 0x40)
        )
    end
    return ""
end

local named_entities = {
    amp = "&", lt = "<", gt = ">", quot = '"', apos = "'", nbsp = " ",
    ndash = "–", mdash = "—", hellip = "…", rsquo = "’", lsquo = "‘",
    rdquo = "”", ldquo = "“", bull = "•", middot = "·", copy = "©",
}

local function decode_entities_once(s)
    s = tostring(s or "")
    s = s:gsub("&#x([0-9A-Fa-f]+);", function(hex)
        return utf8_char(tonumber(hex, 16))
    end)
    s = s:gsub("&#([0-9]+);", function(dec)
        return utf8_char(tonumber(dec, 10))
    end)
    s = s:gsub("&([%a]+);", function(name)
        return named_entities[name] or "&" .. name .. ";"
    end)
    return s
end

local function decode_entities_deep(s)
    local prev
    s = tostring(s or "")
    for _ = 1, 4 do
        prev = s
        s = decode_entities_once(s)
        if s == prev then break end
    end
    return s
end

local function remove_block(html, tag)
    local lower = html:lower()
    local open_pat = "<" .. tag
    local close_pat = "</" .. tag .. ">"
    local pos = 1
    local chunks = {}
    while true do
        local s = lower:find(open_pat, pos, true)
        if not s then
            chunks[#chunks + 1] = html:sub(pos)
            break
        end
        chunks[#chunks + 1] = html:sub(pos, s - 1)
        local e = lower:find(close_pat, s, true)
        if not e then
            pos = s + #open_pat
            break
        end
        pos = e + #close_pat
    end
    if pos <= #html and #chunks == 0 then chunks[#chunks + 1] = html:sub(pos) end
    return table.concat(chunks)
end

local boilerplate_phrases = {
    "sign up for the breaking news",
    "sign up for our newsletter",
    "sign up to our newsletter",
    "subscribe to our newsletter",
    "continue reading",
    "read more",
    "advertisement",
    "image source",
    "image caption",
    "cookie policy",
    "privacy policy",
    "terms and conditions",
}

local function is_boilerplate_line(line)
    local lower = line:lower()
    for _, phrase in ipairs(boilerplate_phrases) do
        if lower:find(phrase, 1, true) then return true end
    end
    return false
end

local function strip_urls(s)
    s = s:gsub("https?://[^%s<>'\"]+", " ")
    s = s:gsub("www%.[^%s<>'\"]+", " ")
    s = s:gsub("href%s*=%s*['\"][^'\"]*['\"]", " ")
    s = s:gsub("href%s*=%s*[^%s>]+", " ")
    return s
end

function ArticleFetcher.cleanText(input)
    local s = tostring(input or "")
    if s == "" then return "" end

    s = s:gsub("<!%[CDATA%[(.-)%]%]>", "%1")
    s = decode_entities_deep(s)
    s = s:gsub("<!%-%-.-%-%->", " ")

    for _, tag in ipairs({"script", "style", "noscript", "svg", "nav", "aside", "footer", "form", "button"}) do
        s = remove_block(s, tag)
    end

    -- Preserve paragraph boundaries before deleting the remaining markup.
    s = s:gsub("<[Bb][Rr]%s*/?>", "\n")
    s = s:gsub("</[Pp]%s*>", "\n\n")
    s = s:gsub("</[Ll][Ii]%s*>", "\n")
    s = s:gsub("</[Hh][1-6]%s*>", "\n\n")
    s = s:gsub("<[^>]->", " ")

    -- Some feeds are double-encoded: removing tags can reveal another HTML layer.
    s = decode_entities_deep(s)
    s = s:gsub("<[Bb][Rr]%s*/?>", "\n")
    s = s:gsub("</[Pp]%s*>", "\n\n")
    s = s:gsub("</[Ll][Ii]%s*>", "\n")
    s = s:gsub("</[Hh][1-6]%s*>", "\n\n")
    s = s:gsub("<[^>]->", " ")
    s = strip_urls(s)

    local lines = {}
    s = s:gsub("\r\n", "\n"):gsub("\r", "\n")
    for line in (s .. "\n"):gmatch("(.-)\n") do
        line = line:gsub("[%z\1-\8\11\12\14-\31]", " ")
        line = line:gsub("%s+", " ")
        line = line:gsub("^%s+", ""):gsub("%s+$", "")
        -- Catch malformed tag fragments that survived a broken source feed.
        line = line:gsub("^/?[a-zA-Z][a-zA-Z0-9]*%s*>", "")
        line = line:gsub("</?[a-zA-Z][^>]*>", " ")
        line = line:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" and not is_boilerplate_line(line) then
            lines[#lines + 1] = line
        elseif #lines > 0 and lines[#lines] ~= "" then
            lines[#lines + 1] = ""
        end
    end

    local out = table.concat(lines, "\n")
    out = out:gsub("\n%s*\n%s*\n+", "\n\n")
    out = out:gsub("^%s+", ""):gsub("%s+$", "")
    return out
end

local function isolate_tag(html, tag)
    local lower = html:lower()
    local s = lower:find("<" .. tag, 1, true)
    if not s then return nil end
    local open_end = lower:find(">", s, true)
    if not open_end then return nil end
    local e = lower:find("</" .. tag .. ">", open_end + 1, true)
    if not e then return nil end
    return html:sub(open_end + 1, e - 1)
end

local function paragraphs_from_html(html)
    if not html or html == "" then return {} end
    local cleaned = html
    for _, tag in ipairs({"script", "style", "noscript", "svg", "nav", "aside", "footer", "form", "button"}) do
        cleaned = remove_block(cleaned, tag)
    end

    local paragraphs = {}
    local lower = cleaned:lower()
    local pos = 1
    while true do
        local s = lower:find("<p", pos, true)
        if not s then break end
        local open_end = lower:find(">", s, true)
        if not open_end then break end
        local e = lower:find("</p>", open_end + 1, true)
        if not e then break end
        local text = ArticleFetcher.cleanText(cleaned:sub(open_end + 1, e - 1))
        if #text >= 35 then paragraphs[#paragraphs + 1] = text end
        pos = e + 4
    end
    return paragraphs
end

local function json_string_value(html, key)
    local lower = html:lower()
    local marker = '"' .. key:lower() .. '"'
    local key_pos = lower:find(marker, 1, true)
    if not key_pos then return nil end
    local colon = lower:find(":", key_pos + #marker, true)
    if not colon then return nil end
    local quote = lower:find('"', colon + 1, true)
    if not quote then return nil end
    local out, escaped = {}, false
    local i = quote + 1
    while i <= #html do
        local c = html:sub(i, i)
        if escaped then
            if c == "n" or c == "r" then
                out[#out + 1] = "\n"
            elseif c == "t" then
                out[#out + 1] = " "
            elseif c == '"' then
                out[#out + 1] = '"'
            elseif c == "\\" then
                out[#out + 1] = "\\"
            elseif c == "/" then
                out[#out + 1] = "/"
            elseif c == "u" then
                local hex = html:sub(i + 1, i + 4)
                if hex:match("^[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]$") then
                    out[#out + 1] = utf8_char(tonumber(hex, 16))
                    i = i + 4
                else
                    out[#out + 1] = "u"
                end
            else
                out[#out + 1] = c
            end
            escaped = false
        elseif c == "\\" then
            escaped = true
        elseif c == '"' then
            return table.concat(out)
        else
            out[#out + 1] = c
        end
        i = i + 1
    end
    return nil
end

local function join_paragraphs(paragraphs)
    if not paragraphs or #paragraphs == 0 then return nil end
    return table.concat(paragraphs, "\n\n")
end

local function looks_blocked(html)
    local lower = (html or ""):lower()
    return lower:find("access denied", 1, true)
        or lower:find("enable javascript and cookies", 1, true)
        or lower:find("cf%-challenge")
        or lower:find("captcha", 1, true)
end

local function looks_paywalled(html)
    local lower = (html or ""):lower()
    return lower:find("subscribe to continue", 1, true)
        or lower:find("subscribe to read", 1, true)
        or lower:find("sign in to continue", 1, true)
        or lower:find("already a subscriber", 1, true)
        or lower:find("subscriber%-only")
end

local function resolve_redirect(base, location)
    if not location or location == "" then return nil end
    if location:match("^https?://") then return location end
    local scheme, host = base:match("^(https?)://([^/]+)")
    if not scheme or not host then return location end
    if location:sub(1, 2) == "//" then
        return scheme .. ":" .. location
    elseif location:sub(1, 1) == "/" then
        return scheme .. "://" .. host .. location
    end
    local dir = base:match("^(https?://.*/)") or (scheme .. "://" .. host .. "/")
    return dir .. location
end

local function request(url, redirects)
    redirects = redirects or 0
    local chunks = {}
    http.TIMEOUT = 12
    local ok, code, headers, status = http.request{
        url = url,
        sink = ltn12.sink.table(chunks),
        headers = {
            ["User-Agent"] = "Mozilla/5.0 (KOReader MorningPaper/0.3.1; e-ink reader)",
            ["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        },
    }
    if not ok then return nil, tostring(code or status or "request failed"), url end
    code = tonumber(code) or 0
    if code >= 300 and code < 400 and redirects < 4 and headers then
        local location = headers.location or headers.Location
        local next_url = resolve_redirect(url, location)
        if next_url then return request(next_url, redirects + 1) end
    end
    if code >= 400 then return nil, "HTTP " .. tostring(code), url end
    return table.concat(chunks), nil, url
end

local function good_article_text(text, min_chars)
    if not text or #text < min_chars then return false end
    if text:find("<", 1, true) or text:find(">", 1, true) then return false end
    local url_count = 0
    for _ in text:gmatch("https?://") do url_count = url_count + 1 end
    if url_count > 1 then return false end
    return true
end

function ArticleFetcher.extract(html, min_chars)
    min_chars = min_chars or 350
    if not html or html == "" then return nil, "empty page" end
    if looks_blocked(html) then return nil, "site blocked automated reading" end

    local json_body = json_string_value(html, "articleBody")
    if json_body then
        json_body = ArticleFetcher.cleanText(json_body)
        if good_article_text(json_body, min_chars) then return json_body, "json-ld" end
    end

    local candidate = isolate_tag(html, "article") or isolate_tag(html, "main")
    local paragraphs = paragraphs_from_html(candidate or html)
    local text = join_paragraphs(paragraphs)
    if text then text = ArticleFetcher.cleanText(text) end
    if good_article_text(text, min_chars) then
        return text, candidate and "article" or "paragraphs"
    end

    if looks_paywalled(html) then return nil, "publisher limited this article" end
    return nil, "clean full text not found"
end

function ArticleFetcher.fetch(url, opts)
    opts = opts or {}
    if not url or url == "" then return nil, "no article link", url end
    local html, err, final_url = request(url, 0)
    if not html then return nil, err, final_url end
    local text, mode = ArticleFetcher.extract(html, opts.min_chars or 350)
    if not text then return nil, mode, final_url end
    return ArticleFetcher.cleanText(text), mode, final_url
end

return ArticleFetcher
