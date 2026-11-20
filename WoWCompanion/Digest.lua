-- WoW Companion: turns the digest table the companion wrote into panel text.
-- The table is only ever read as data; see docs/digest-format.md.

local WC = WoWCompanion

WC.SCHEMA = 1
WC.STALE_SECONDS = 24 * 60 * 60
WC.LINE_HEIGHT = 14

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

-- Returns the header text and the body text for a digest.
function WC.RenderDigest(d, now, player)
    if is_empty(d) then return "", WC.NO_ADVICE end
    if d.schema ~= WC.SCHEMA then
        return "", "This digest uses an unknown format (schema " .. plain(d.schema) .. "); update the addon."
    end
    if d.character ~= player then
        return "", "This digest was written for " .. plain(d.character) .. ", not " .. plain(player) .. "."
    end
    local age = math.max(0, now - (tonumber(d.generated) or 0))
    local header = plain(d.character) .. " \226\128\148 " .. WC.FormatAge(age)
    if age > WC.STALE_SECONDS then header = header .. " (stale)" end

    local out = {}
    for _, section in ipairs(type(d.sections) == "table" and d.sections or {}) do
        local title = TITLES[section.id]
        if title and type(section.lines) == "table" and #section.lines > 0 then
            out[#out + 1] = title
            for _, line in ipairs(section.lines) do
                local text = "  - " .. plain(line.text)
                if line.quest then text = text .. " [quest " .. plain(line.quest) .. "]" end
                if line.item then text = text .. " [item " .. plain(line.item) .. "]" end
                out[#out + 1] = text
            end
        end
    end
    if #out == 0 then return header, WC.NO_ADVICE end
    return header, table.concat(out, "\n")
end
