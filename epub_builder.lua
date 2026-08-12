local bit = require("bit")

local EpubBuilder = {}

local bxor = bit.bxor
local band = bit.band
local rshift = bit.rshift

local function u32(n)
    if n < 0 then return n + 4294967296 end
    return n
end

local function le(n, bytes)
    n = u32(n or 0)
    local out = {}
    for _ = 1, bytes do
        out[#out + 1] = string.char(n % 256)
        n = math.floor(n / 256)
    end
    return table.concat(out)
end

local CRC_TABLE = {}
for i = 0, 255 do
    local c = i
    for _ = 1, 8 do
        if band(c, 1) ~= 0 then
            c = bxor(0xEDB88320, rshift(c, 1))
        else
            c = rshift(c, 1)
        end
    end
    CRC_TABLE[i] = c
end

local function crc32(s)
    local crc = 0xFFFFFFFF
    for i = 1, #s do
        local idx = band(bxor(crc, s:byte(i)), 0xFF)
        crc = bxor(rshift(crc, 8), CRC_TABLE[idx])
    end
    return u32(bxor(crc, 0xFFFFFFFF))
end

local function dos_time_date(epoch)
    local t = os.date("*t", epoch or os.time())
    local year = math.max(1980, math.min(2107, t.year))
    local dt = (year - 1980) * 512 + t.month * 32 + t.day
    local tm = t.hour * 2048 + t.min * 32 + math.floor(t.sec / 2)
    return tm, dt
end

local ZipWriter = {}
ZipWriter.__index = ZipWriter

function ZipWriter:new(path)
    local f, err = io.open(path, "wb")
    if not f then return nil, err end
    return setmetatable({ file=f, offset=0, entries={} }, self)
end

function ZipWriter:write(data)
    self.file:write(data)
    self.offset = self.offset + #data
end

function ZipWriter:add(name, data, opts)
    opts = opts or {}
    data = data or ""
    local method = 0 -- Store: EPUB permits uncompressed entries; mimetype must be stored.
    local tm, dt = dos_time_date(opts.epoch)
    local crc = crc32(data)
    local size = #data
    local local_offset = self.offset
    local header = le(0x04034B50, 4)
        .. le(20, 2) .. le(0, 2) .. le(method, 2)
        .. le(tm, 2) .. le(dt, 2)
        .. le(crc, 4) .. le(size, 4) .. le(size, 4)
        .. le(#name, 2) .. le(0, 2)
    self:write(header)
    self:write(name)
    self:write(data)
    self.entries[#self.entries + 1] = {
        name=name, crc=crc, size=size, tm=tm, dt=dt, method=method, offset=local_offset,
    }
end

function ZipWriter:finish()
    local central_offset = self.offset
    for _, e in ipairs(self.entries) do
        local header = le(0x02014B50, 4)
            .. le(20, 2) .. le(20, 2) .. le(0, 2) .. le(e.method, 2)
            .. le(e.tm, 2) .. le(e.dt, 2)
            .. le(e.crc, 4) .. le(e.size, 4) .. le(e.size, 4)
            .. le(#e.name, 2) .. le(0, 2) .. le(0, 2)
            .. le(0, 2) .. le(0, 2) .. le(0, 4)
            .. le(e.offset, 4)
        self:write(header)
        self:write(e.name)
    end
    local central_size = self.offset - central_offset
    local count = #self.entries
    local end_record = le(0x06054B50, 4)
        .. le(0, 2) .. le(0, 2)
        .. le(count, 2) .. le(count, 2)
        .. le(central_size, 4) .. le(central_offset, 4)
        .. le(0, 2)
    self:write(end_record)
    self.file:close()
    self.file = nil
end

local function xesc(s)
    s = tostring(s or "")
    return s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"):gsub("'", "&apos;")
end

local function section_id(s)
    local id = tostring(s or "section"):gsub("[^%w]+", "")
    return id ~= "" and id or "section"
end

local function text_to_xhtml(text)
    if not text or text == "" then return "<p>No text was supplied by this source.</p>" end
    local out = {}
    local normalized = tostring(text):gsub("\r\n", "\n"):gsub("\r", "\n") .. "\n\n"
    for para in normalized:gmatch("(.-)\n%s*\n") do
        para = para:gsub("^%s+", ""):gsub("%s+$", "")
        if para ~= "" then out[#out + 1] = "<p>" .. xesc(para) .. "</p>" end
    end
    if #out == 0 then out[1] = "<p>" .. xesc(text) .. "</p>" end
    return table.concat(out, "\n")
end

local function wrap_words(text, max_chars, max_lines)
    text = tostring(text or "")
    local lines, current = {}, ""
    for word in text:gmatch("%S+") do
        local trial = current == "" and word or (current .. " " .. word)
        if #trial > max_chars and current ~= "" then
            lines[#lines + 1] = current
            current = word
            if #lines >= max_lines then break end
        else
            current = trial
        end
    end
    if #lines < max_lines and current ~= "" then lines[#lines + 1] = current end
    if #lines == max_lines then
        local original_words = 0
        for _ in text:gmatch("%S+") do original_words = original_words + 1 end
        local kept_words = 0
        for _, line in ipairs(lines) do for _ in line:gmatch("%S+") do kept_words = kept_words + 1 end end
        if kept_words < original_words then
            lines[#lines] = lines[#lines]:gsub("[%s%.,;:!%-]+$", "") .. "…"
        end
    end
    return lines
end

local function pick_cover_headlines(sections, order)
    local out, seen = {}, {}
    local function take(items)
        if not items then return end
        for _, item in ipairs(items) do
            local title = tostring(item.title or "")
            local key = title:lower():gsub("%W", "")
            if title ~= "" and not seen[key] then
                seen[key] = true
                out[#out + 1] = title
                if #out >= 3 then return true end
            end
        end
    end
    if take(sections["Front Page"]) then return out end
    for _, section in ipairs(order) do
        if section ~= "Front Page" and take(sections[section]) then break end
    end
    return out
end

local function build_cover_svg(opts)
    local headlines = pick_cover_headlines(opts.sections or {}, opts.section_order or {})
    local y = 460
    local parts = {
        [[<?xml version="1.0" encoding="UTF-8"?>]],
        [[<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="1600" viewBox="0 0 1200 1600">]],
        [[<rect width="1200" height="1600" fill="white"/>]],
        [[<rect x="70" y="70" width="1060" height="1460" fill="none" stroke="black" stroke-width="4"/>]],
        [[<text x="600" y="175" text-anchor="middle" font-family="serif" font-size="76" font-weight="700" fill="black">MORNING PAPER</text>]],
        [[<line x1="105" y1="215" x2="1095" y2="215" stroke="black" stroke-width="5"/>]],
        [[<text x="600" y="285" text-anchor="middle" font-family="serif" font-size="35" font-weight="700" fill="black">]] .. xesc(opts.nice_date) .. [[</text>]],
        [[<text x="600" y="335" text-anchor="middle" font-family="serif" font-size="24" letter-spacing="4" fill="black">MORNING EDITION · ]] .. xesc(opts.edition_time or "") .. [[</text>]],
        [[<line x1="105" y1="380" x2="1095" y2="380" stroke="black" stroke-width="2"/>]],
    }

    if #headlines == 0 then headlines[1] = "Today’s news, collected for your morning read" end
    for i, headline in ipairs(headlines) do
        local max_chars = i == 1 and 31 or 36
        local max_lines = i == 1 and 4 or 3
        local font_size = i == 1 and 48 or 38
        local line_height = i == 1 and 61 or 50
        local lines = wrap_words(headline, max_chars, max_lines)
        if i > 1 then
            parts[#parts + 1] = string.format([[<line x1="160" y1="%d" x2="1040" y2="%d" stroke="black" stroke-width="1.5"/>]], y - 38, y - 38)
        end
        for _, line in ipairs(lines) do
            parts[#parts + 1] = string.format([[<text x="600" y="%d" text-anchor="middle" font-family="serif" font-size="%d" font-weight="700" fill="black">%s</text>]], y, font_size, xesc(line))
            y = y + line_height
        end
        y = y + (i == 1 and 55 or 45)
    end

    parts[#parts + 1] = [[<line x1="105" y1="1390" x2="1095" y2="1390" stroke="black" stroke-width="2"/>]]
    parts[#parts + 1] = [[<text x="600" y="1450" text-anchor="middle" font-family="serif" font-size="24" letter-spacing="2" fill="black">WORLD · U.S. · BUSINESS · TECHNOLOGY · SCIENCE · CULTURE</text>]]
    parts[#parts + 1] = string.format([[<text x="600" y="1495" text-anchor="middle" font-family="serif" font-size="20" fill="black">%d STORIES · %d FULL ARTICLES</text>]], opts.total or 0, opts.full_count or 0)
    parts[#parts + 1] = [[</svg>]]
    return table.concat(parts, "\n")
end

local function build_paper_xhtml(opts)
    local parts = {
        [[<?xml version="1.0" encoding="UTF-8"?>]],
        [[<!DOCTYPE html>]],
        [[<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en"><head><meta charset="utf-8"/>]],
        [[<title>]] .. xesc(opts.title) .. [[</title>]],
        [[<style>body{font-family:serif;line-height:1.5;margin:5%;}h1{font-size:2em;margin-bottom:.1em}h2{margin-top:2em;border-bottom:1px solid #777;padding-bottom:.2em}h3{font-size:1.35em}.article{margin:1.5em 0 2.4em}.meta{font-size:.85em}.mode{font-size:.82em;font-style:italic}.original{font-size:.9em}.rule{border-top:1px solid #aaa;margin-top:2em}.edition-note{font-style:italic}</style></head><body>]],
        [[<h1>Morning Paper</h1><p><strong>]] .. xesc(opts.nice_date) .. [[</strong></p>]],
        string.format([[<p>%d current stories · %d full articles fetched · %d clean fallbacks</p>]], opts.total or 0, opts.full_count or 0, opts.excerpt_count or 0),
        [[<p class="edition-note">Newest stories are listed first. Publisher timestamps are preserved as supplied, including GMT/UTC dates that may be a day ahead of local time.</p>]],
        [[<p class="edition-note">Displayed story text is sanitized before publishing. Morning Paper does not bypass subscriptions, logins, or paywalls.</p>]],
    }

    local article_id = 0
    for _, section in ipairs(opts.section_order or {}) do
        local items = opts.sections[section]
        if items and #items > 0 then
            parts[#parts + 1] = [[<h2 id="]] .. section_id(section) .. [[">]] .. xesc(section) .. [[</h2>]]
            for _, item in ipairs(items) do
                article_id = article_id + 1
                parts[#parts + 1] = [[<section class="article" id="story]] .. article_id .. [["><h3>]] .. xesc(item.title) .. [[</h3>]]
                local meta = xesc(item.source or "")
                if item.date and item.date ~= "" then meta = meta .. " · " .. xesc(item.date) end
                parts[#parts + 1] = [[<div class="meta">]] .. meta .. [[</div>]]
                local mode = xesc(item.content_mode or "")
                if item.content_mode ~= "Full article" and item.extract_error then mode = mode .. " · " .. xesc(item.extract_error) end
                parts[#parts + 1] = [[<div class="mode">]] .. mode .. [[</div>]]
                parts[#parts + 1] = text_to_xhtml(item.body)
                if item.link and item.link ~= "" then
                    parts[#parts + 1] = [[<p class="original"><a href="]] .. xesc(item.link) .. [[">Open original article</a></p>]]
                end
                parts[#parts + 1] = [[<div class="rule"></div></section>]]
            end
        end
    end
    parts[#parts + 1] = [[</body></html>]]
    return table.concat(parts, "\n")
end

local function build_nav_xhtml(opts)
    local parts = {
        [[<?xml version="1.0" encoding="UTF-8"?>]],
        [[<!DOCTYPE html>]],
        [[<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="en" lang="en"><head><title>Contents</title></head><body>]],
        [[<nav epub:type="toc" id="toc"><h1>Contents</h1><ol>]],
        [[<li><a href="cover.xhtml">Cover</a></li>]],
    }
    for _, section in ipairs(opts.section_order or {}) do
        local items = opts.sections[section]
        if items and #items > 0 then
            parts[#parts + 1] = [[<li><a href="paper.xhtml#]] .. section_id(section) .. [[">]] .. xesc(section) .. [[</a></li>]]
        end
    end
    parts[#parts + 1] = [[</ol></nav><nav epub:type="landmarks"><ol><li><a epub:type="cover" href="cover.xhtml">Cover</a></li><li><a epub:type="bodymatter" href="paper.xhtml">Morning Paper</a></li></ol></nav></body></html>]]
    return table.concat(parts, "\n")
end

local function build_ncx(opts)
    local parts = {
        [[<?xml version="1.0" encoding="UTF-8"?>]],
        [[<!DOCTYPE ncx PUBLIC "-//NISO//DTD ncx 2005-1//EN" "http://www.daisy.org/z3986/2005/ncx-2005-1.dtd">]],
        [[<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1"><head><meta name="dtb:uid" content="]] .. xesc(opts.uid) .. [["/></head><docTitle><text>]] .. xesc(opts.title) .. [[</text></docTitle><navMap>]],
        [[<navPoint id="cover" playOrder="1"><navLabel><text>Cover</text></navLabel><content src="cover.xhtml"/></navPoint>]],
    }
    local order = 2
    for _, section in ipairs(opts.section_order or {}) do
        local items = opts.sections[section]
        if items and #items > 0 then
            parts[#parts + 1] = string.format([[<navPoint id="nav%d" playOrder="%d"><navLabel><text>%s</text></navLabel><content src="paper.xhtml#%s"/></navPoint>]], order, order, xesc(section), section_id(section))
            order = order + 1
        end
    end
    parts[#parts + 1] = [[</navMap></ncx>]]
    return table.concat(parts, "\n")
end

local function build_opf(opts)
    return [[<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="bookid">]] .. xesc(opts.uid) .. [[</dc:identifier>
    <dc:title>]] .. xesc(opts.title) .. [[</dc:title>
    <dc:creator>Morning Paper</dc:creator>
    <dc:language>en</dc:language>
    <dc:date>]] .. xesc(opts.date) .. [[</dc:date>
    <meta property="dcterms:modified">]] .. xesc(os.date("!%Y-%m-%dT%H:%M:%SZ")) .. [[</meta>
    <meta name="cover" content="cover-image"/>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="cover-page" href="cover.xhtml" media-type="application/xhtml+xml"/>
    <item id="cover-image" href="cover.svg" media-type="image/svg+xml" properties="cover-image"/>
    <item id="paper" href="paper.xhtml" media-type="application/xhtml+xml"/>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
  </manifest>
  <spine toc="ncx">
    <itemref idref="cover-page"/>
    <itemref idref="paper"/>
  </spine>
  <guide><reference type="cover" title="Cover" href="cover.xhtml"/></guide>
</package>]]
end

function EpubBuilder.build(path, opts)
    opts = opts or {}
    opts.sections = opts.sections or {}
    opts.section_order = opts.section_order or {}
    opts.date = opts.date or os.date("%Y-%m-%d")
    opts.nice_date = opts.nice_date or os.date("%A, %B %d, %Y")
    opts.title = opts.title or ("Morning Paper — " .. opts.nice_date)
    opts.uid = opts.uid or ("urn:morningpaper:" .. opts.date)
    opts.edition_time = opts.edition_time or os.date("%I:%M %p"):gsub("^0", "")

    local z, err = ZipWriter:new(path)
    if not z then return nil, err end

    local ok, build_err = pcall(function()
        -- EPUB requires this exact first entry and it must not be compressed.
        z:add("mimetype", "application/epub+zip")
        z:add("META-INF/container.xml", [[<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>]])
        z:add("OEBPS/content.opf", build_opf(opts))
        z:add("OEBPS/cover.svg", build_cover_svg(opts))
        z:add("OEBPS/cover.xhtml", [[<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en"><head><title>Cover</title><style>html,body{margin:0;padding:0;text-align:center;}img{display:block;width:100%;height:auto;max-height:100vh;object-fit:contain;}</style></head><body><img src="cover.svg" alt="Morning Paper cover"/></body></html>]])
        z:add("OEBPS/nav.xhtml", build_nav_xhtml(opts))
        z:add("OEBPS/toc.ncx", build_ncx(opts))
        z:add("OEBPS/paper.xhtml", build_paper_xhtml(opts))
        z:finish()
    end)

    if not ok then
        if z.file then pcall(function() z.file:close() end) end
        pcall(os.remove, path)
        return nil, tostring(build_err)
    end
    return true
end

return EpubBuilder
