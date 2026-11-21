-- WoW Companion: turns the digest table the companion wrote into panel text.
-- The table is only ever read as data; see docs/digest-format.md.

local WC = WoWCompanion

WC.SCHEMA = 1
WC.STALE_SECONDS = 12 * 60 * 60
WC.LINE_HEIGHT = 14

WC.STALE_NOTE = "Ask your AI client to refresh your digest, then /reload."

local TITLES = {
    next_quests = "Next quests",
    upgrades = "Upgrades",
    keep_materials = "Keep materials",
    notes = "Notes",
}

function WC.FormatAge(seconds)
    if seconds < 60 then return "just now" end
    if seconds < 3600 then return math.floor(seconds / 60) .. " min ago" end
    if seconds < 86400 then return math.floor(seconds / 3600) .. " h ago" end
    return math.floor(seconds / 86400) .. " d ago"
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
    out[#out + 1] = { kind = "header", id = id, text = (closed and "[+] " or "[-] ") .. title }
    if closed then return end
    for _, line in ipairs(lines) do out[#out + 1] = line end
end

-- An item id is only ever used to build a tooltip link, so it must be a plain positive integer.
local function item_id(v)
    local n = tonumber(v)
    if n and n > 0 and n == math.floor(n) and n < 2 ^ 31 then return n end
end

-- Returns the header text and a list of rows for a digest.
-- Row kinds: "text", "header" (has id) and "line" (may carry item, the item id for a tooltip).
function WC.RenderDigest(d, now, player, collapsed)
    if is_empty(d) then return "", text_rows(WC.NO_ADVICE) end
    if d.schema ~= WC.SCHEMA then
        return "", text_rows("This digest uses an unknown format (schema " .. plain(d.schema) .. "); update the addon.")
    end
    if d.character ~= player then
        return "", text_rows("This digest was written for " .. plain(d.character) .. ", not " .. plain(player) .. ".")
    end
    local age = math.max(0, now - (tonumber(d.generated) or 0))
    local header = plain(d.character) .. " \226\128\148 updated " .. WC.FormatAge(age)

    local out = {}
    for _, section in ipairs(type(d.sections) == "table" and d.sections or {}) do
        local title = TITLES[section.id]
        if title and type(section.lines) == "table" and #section.lines > 0 then
            local lines = {}
            for _, line in ipairs(section.lines) do
                local text = "  - " .. plain(line.text)
                if line.quest then text = text .. " [quest " .. plain(line.quest) .. "]" end
                if line.item then text = text .. " [item " .. plain(line.item) .. "]" end
                lines[#lines + 1] = { kind = "line", text = text, item = item_id(line.item) }
            end
            WC.SectionRows(out, section.id, title, lines, collapsed)
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
