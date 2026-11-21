-- WoW Companion: turns the digest table the companion wrote into panel text.
-- The table is only ever read as data; see docs/digest-format.md.

local WC = WoWCompanion
local L = WC.L

WC.SCHEMA = 1
WC.MAX_EXTRA = 3 -- dungeons and talents show at most this many entries
WC.STALE_SECONDS = 12 * 60 * 60
WC.LINE_HEIGHT = 14
WC.CAPTURE_GRACE = 15 * 60 -- a capture this much newer than the digest makes it out of date (a /reload right after a fresh digest re-saves the capture)

WC.STALE_NOTE = L.STALE_NOTE

local TITLES = {
    next_quests = L.next_quests,
    upgrades = L.upgrades,
    keep_materials = L.keep_materials,
    notes = L.notes,
}

function WC.FormatAge(seconds)
    if seconds < 60 then return L.AGE_NOW end
    if seconds < 3600 then return string.format(L.AGE_MINUTES, math.floor(seconds / 60)) end
    if seconds < 86400 then return string.format(L.AGE_HOURS, math.floor(seconds / 3600)) end
    return string.format(L.AGE_DAYS, math.floor(seconds / 86400))
end

local function plain(s)
    return (tostring(s):gsub("|", "||"))
end

-- The subject of an "ask about this" question: the line's own text, with the item id when it has one.
-- Pipes are dropped so a digest line cannot put escape codes into the Ask box.
local function ask_subject(text, id)
    local s = tostring(text):gsub("|", "")
    return id and string.format(L.ASK_ITEM_SUBJECT, s, id) or s
end

-- Which template a section's lines use, by section id.
local ASK_KIND = { next_quests = "quest", upgrades = "upgrade", keep_materials = "material" }

local function is_empty(d)
    return type(d) ~= "table" or next(d) == nil
end

local function text_rows(text)
    return { { kind = "text", text = text } }
end

-- A collapsible section header row followed by its lines (omitted when collapsed).
function WC.SectionRows(out, id, title, lines, collapsed)
    local closed = collapsed and collapsed[id] == true
    out[#out + 1] = { kind = "header", id = id, title = title, text = string.format(closed and L.CLOSED_SECTION or L.OPEN_SECTION, title) }
    if closed then return end
    for _, line in ipairs(lines) do out[#out + 1] = line end
end

-- An item id is only ever used to build a tooltip link, so it must be a plain positive integer.
local function item_id(v)
    local n = tonumber(v)
    if n and n > 0 and n == math.floor(n) and n < 2 ^ 31 then return n end
end

-- Schema 1 digests are numbered 1, or "1", "1.0", "1.1", "1.2"; any other major version is refused.
function WC.SchemaOK(v)
    if v == WC.SCHEMA then return true end
    return type(v) == "string" and (v == "1" or v:match("^1%.%d+$") ~= nil)
end

-- Schema 2 digests hold one schema 1.x digest per character; "2" and "2.x" are accepted.
function WC.Schema2OK(v)
    return type(v) == "string" and (v == "2" or v:match("^2%.%d+$") ~= nil)
end

-- The digest table to show for player, and whether the file was schema 2. Returns nil when the file
-- has no entry for this character: no characters[player] (or a case-insensitive match) in a schema 2
-- file, or a schema 1 digest written for someone else. An unknown schema is returned as is, so the
-- caller can say so.
function WC.EntryFor(d, player)
    if is_empty(d) then return nil end
    if WC.Schema2OK(d.schema) then
        local chars = type(d.characters) == "table" and d.characters or {}
        local e = chars[player]
        if e == nil and type(player) == "string" then
            local want = player:lower()
            for name, c in pairs(chars) do
                if type(name) == "string" and name:lower() == want then e = c break end
            end
        end
        return type(e) == "table" and e or nil, true
    end
    if WC.SchemaOK(d.schema) and d.character ~= player then return nil end
    return d
end

-- The (up to 5) character names a schema 2 file holds digests for, sorted.
local function digest_names(d)
    local names = {}
    for name, c in pairs(WC.Schema2OK(d.schema) and type(d.characters) == "table" and d.characters or {}) do
        if type(name) == "string" and type(c) == "table" then names[#names + 1] = plain(name) end
    end
    table.sort(names)
    while #names > 5 do table.remove(names) end
    return names
end

-- The how-to-get-a-digest steps as text rows.
local function hint_rows(out)
    for _, key in ipairs({ "HINT_RELOAD", "HINT_ASK", "HINT_RELOAD_AGAIN" }) do
        out[#out + 1] = { kind = "text", text = L[key] }
    end
    return out
end

-- Rows for a missing or empty digest file.
local function empty_rows()
    return hint_rows(text_rows(WC.NO_ADVICE))
end

-- Rows for a file that has no digest for player.
local function miss_rows(d, player)
    local out = text_rows(string.format(L.NO_ENTRY, plain(player)))
    hint_rows(out)
    local names = digest_names(d)
    if #names > 0 then out[#out + 1] = { kind = "text", text = string.format(L.DIGESTS_HERE, table.concat(names, ", ")) } end
    return out
end

-- Builds the rows of the optional schema 1.2 lists: { text, id } per entry, at most MAX_EXTRA.
-- build(entry) returns the line text and the id to link, or nil to skip the entry.
local function extra_lines(list, kind, build)
    local lines = {}
    for _, e in ipairs(type(list) == "table" and list or {}) do
        if #lines >= WC.MAX_EXTRA then break end
        local text, id, ask = nil, nil, nil
        if type(e) == "table" and e.line then text, id, ask = build(e) end
        if text then lines[#lines + 1] = { kind = "line", text = text, [kind] = id and item_id(id) or nil, ask = ask } end
    end
    return lines
end

-- The current character's last capture time from ForeverScribe's global (read only), or nil
-- when it is not loaded or has no capture for this character.
function WC.CapturedAt(fs, player, realm)
    local chars = type(fs) == "table" and type(fs.chars) == "table" and fs.chars or nil
    if not chars then return nil end
    local rec = realm and chars[realm .. ":" .. player]
    if type(rec) ~= "table" then
        rec = nil
        for _, c in pairs(chars) do
            local snap = type(c) == "table" and c.snapshot
            local id = type(snap) == "table" and snap.identity
            if type(id) == "table" and id.name == player then rec = c break end
        end
    end
    local snap = rec and rec.snapshot
    return type(snap) == "table" and tonumber(snap.capturedAt) or nil
end

-- True when advice from digest entry d may be out of date: the capture is more than CAPTURE_GRACE
-- newer than the digest, or the digest is older than STALE_SECONDS. The digest carries no level
-- field, so there is no level-up rule. captured may be nil.
function WC.DigestOutdated(d, now, captured)
    local gen = tonumber(d.generated) or 0
    if captured and captured - gen > WC.CAPTURE_GRACE then return true end
    return math.max(0, now - gen) > WC.STALE_SECONDS
end

-- The current character's last capture time, or nil.
function WC.OwnCapturedAt(player)
    return WC.CapturedAt(ForeverScribeDB, player, GetRealmName and GetRealmName())
end

-- Returns the header text and a list of rows for a digest.
-- Row kinds: "text", "header" (has id) and "line" (may carry item, the item id for a tooltip).
-- show (optional) maps a settings section id to false to hide that digest section.
-- captured (optional) is the character's last ForeverScribe capture time; see WC.CapturedAt.
function WC.RenderDigest(d, now, player, collapsed, show, captured)
    if is_empty(d) then return "", empty_rows() end
    local e = WC.EntryFor(d, player)
    if not e then return "", miss_rows(d, player) end
    d = e
    if not WC.SchemaOK(d.schema) then
        return "", text_rows(string.format(L.UNKNOWN_SCHEMA, plain(d.schema)))
    end
    local age = math.max(0, now - (tonumber(d.generated) or 0))
    local header = string.format(L.DIGEST_HEADER, plain(d.character or player), WC.FormatAge(age))

    local out = {}
    for _, section in ipairs(type(d.sections) == "table" and d.sections or {}) do
        local title = TITLES[section.id]
        local hidden = show and show[WC.SECTION_OF[section.id]] == false
        if title and not hidden and type(section.lines) == "table" and #section.lines > 0 then
            local lines = {}
            for _, line in ipairs(section.lines) do
                local text = string.format(L.LINE, plain(line.text))
                local id = item_id(line.item)
                local kind = ASK_KIND[section.id]
                local ask = kind and { kind = kind, subject = ask_subject(line.text, kind ~= "quest" and id or nil) } or nil
                lines[#lines + 1] = { kind = "line", text = text, item = id, quest = item_id(line.quest), ask = ask }
            end
            WC.SectionRows(out, section.id, title, lines, collapsed)
        end
    end
    local extras = {
        { "dungeons", d.dungeons, "item", function(e)
            local name = e.name and string.format(L.DUNGEON_NAME, plain(e.name)) or ""
            return string.format(L.LINE, name .. plain(e.line)), e.item_id, { kind = "dungeon", subject = ask_subject(e.name or e.line) }
        end },
        { "talents", d.talents, "spell", function(e)
            return string.format(L.LINE, plain(e.line)), e.spell_id, { kind = "talent", subject = ask_subject(e.line) }
        end },
    }
    for _, x in ipairs(extras) do
        local lines = extra_lines(x[2], x[3], x[4])
        if #lines > 0 and not (show and show[x[1]] == false) then
            WC.SectionRows(out, x[1], L[x[1]], lines, collapsed)
        end
    end
    if #out == 0 then out = text_rows(WC.NO_ADVICE) end
    if captured and captured - (tonumber(d.generated) or 0) > WC.CAPTURE_GRACE then
        table.insert(out, 1, { kind = "text", text = L.OLDER_THAN_CAPTURE })
    end
    if age > WC.STALE_SECONDS then table.insert(out, 1, { kind = "text", text = WC.STALE_NOTE }) end
    return header, out
end

-- Compact view: each section keeps its header and first line; a section listed in expanded
-- (a table) keeps all its lines. A header with hidden lines shows the closed marker. Returns new rows.
function WC.CompactRows(rows, expanded)
    local out, head, count = {}, nil, 0
    for _, r in ipairs(rows) do
        if r.kind == "header" then
            head = { kind = "header", id = r.id, title = r.title, text = r.text }
            count = 0
            out[#out + 1] = head
        elseif r.kind == "line" and head then
            count = count + 1
            if count == 1 or expanded[head.id] then
                out[#out + 1] = r
            elseif count == 2 then
                head.text = string.format(L.CLOSED_SECTION, head.title)
            end
        else
            head = nil
            out[#out + 1] = r
        end
    end
    return out
end

-- Flattens rows to plain text, one row per line.
function WC.RowsText(rows)
    local t = {}
    for i, r in ipairs(rows) do t[i] = r.text end
    return table.concat(t, "\n")
end

-- The question "ask about this" pre-fills for a row, or nil when the row has none.
function WC.AskTemplate(row)
    local a = row and row.ask
    local tpl = a and rawget(L, "ASK_ABOUT_" .. a.kind)
    return tpl and string.format(tpl, a.subject) or nil
end
