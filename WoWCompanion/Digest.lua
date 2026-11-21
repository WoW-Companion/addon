-- WoW Companion: turns the digest table the companion wrote into panel text.
-- The table is only ever read as data; see docs/digest-format.md.

local WC = WoWCompanion
local L = WC.L

WC.SCHEMA = 1
WC.MAX_EXTRA = 3 -- dungeons and talents show at most this many entries
WC.STALE_SECONDS = 12 * 60 * 60
WC.LINE_HEIGHT = 14

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

local function is_empty(d)
    return type(d) ~= "table" or next(d) == nil
end

local function text_rows(text)
    return { { kind = "text", text = text } }
end

-- A collapsible section header row followed by its lines (omitted when collapsed).
function WC.SectionRows(out, id, title, lines, collapsed)
    local closed = collapsed and collapsed[id] == true
    out[#out + 1] = { kind = "header", id = id, text = string.format(closed and L.CLOSED_SECTION or L.OPEN_SECTION, title) }
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

-- Builds the rows of the optional schema 1.2 lists: { text, id } per entry, at most MAX_EXTRA.
-- build(entry) returns the line text and the id to link, or nil to skip the entry.
local function extra_lines(list, kind, build)
    local lines = {}
    for _, e in ipairs(type(list) == "table" and list or {}) do
        if #lines >= WC.MAX_EXTRA then break end
        local text, id = nil, nil
        if type(e) == "table" and e.line then text, id = build(e) end
        if text then lines[#lines + 1] = { kind = "line", text = text, [kind] = id and item_id(id) or nil } end
    end
    return lines
end

-- Returns the header text and a list of rows for a digest.
-- Row kinds: "text", "header" (has id) and "line" (may carry item, the item id for a tooltip).
-- show (optional) maps a settings section id to false to hide that digest section.
function WC.RenderDigest(d, now, player, collapsed, show)
    if is_empty(d) then return "", text_rows(WC.NO_ADVICE) end
    if not WC.SchemaOK(d.schema) then
        return "", text_rows(string.format(L.UNKNOWN_SCHEMA, plain(d.schema)))
    end
    if d.character ~= player then
        return "", text_rows(string.format(L.WRONG_CHARACTER, plain(d.character), plain(player)))
    end
    local age = math.max(0, now - (tonumber(d.generated) or 0))
    local header = string.format(L.DIGEST_HEADER, plain(d.character), WC.FormatAge(age))

    local out = {}
    for _, section in ipairs(type(d.sections) == "table" and d.sections or {}) do
        local title = TITLES[section.id]
        local hidden = show and show[WC.SECTION_OF[section.id]] == false
        if title and not hidden and type(section.lines) == "table" and #section.lines > 0 then
            local lines = {}
            for _, line in ipairs(section.lines) do
                local text = string.format(L.LINE, plain(line.text))
                if line.quest then text = text .. string.format(L.LINE_QUEST, plain(line.quest)) end
                if line.item then text = text .. string.format(L.LINE_ITEM, plain(line.item)) end
                lines[#lines + 1] = { kind = "line", text = text, item = item_id(line.item) }
            end
            WC.SectionRows(out, section.id, title, lines, collapsed)
        end
    end
    local extras = {
        { "dungeons", d.dungeons, "item", function(e)
            local name = e.name and string.format(L.DUNGEON_NAME, plain(e.name)) or ""
            return string.format(L.LINE, name .. plain(e.line)), e.item_id
        end },
        { "talents", d.talents, "spell", function(e) return string.format(L.LINE, plain(e.line)), e.spell_id end },
    }
    for _, x in ipairs(extras) do
        local lines = extra_lines(x[2], x[3], x[4])
        if #lines > 0 and not (show and show[x[1]] == false) then
            WC.SectionRows(out, x[1], L[x[1]], lines, collapsed)
        end
    end
    if #out == 0 then return header, text_rows(WC.NO_ADVICE) end
    if age > WC.STALE_SECONDS then table.insert(out, 1, { kind = "text", text = WC.STALE_NOTE }) end
    return header, out
end

-- Flattens rows to plain text, one row per line.
function WC.RowsText(rows)
    local t = {}
    for i, r in ipairs(rows) do t[i] = r.text end
    return table.concat(t, "\n")
end
