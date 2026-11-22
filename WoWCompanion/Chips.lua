-- WoW Companion: character to-dos (talent points, class training, gear upgrades) as a row of icon chips
-- under the panel header. This file is data and state only; Panel.lua draws the chips.
-- A new kind (dungeons, professions) is one CHIP_DEFS entry, its CHIP_ORDER id, a chip-name string and
-- a chips.<id> setting row, plus whatever collects its count in WC.BuildChips.

local WC = WoWCompanion
local L = WC.L

WC.CHIP_SIZE, WC.CHIP_GAP = 24, 6
WC.CHIP_PULSE_SECONDS = 5
WC.CHIP_ORDER = { "talent", "training", "upgrade" }

-- The class icon from the client's own art, else the talent icon.
local function class_icon()
    local token = UnitClass and select(2, UnitClass("player"))
    if type(token) == "string" and token:match("^%u+$") then return "Interface\\Icons\\ClassIcon_" .. token end
    return WC.ICONS.talent
end

WC.ICONS.gear = "Interface\\Icons\\INV_Chest_Plate16"

local function line(text, color) return { text = text, color = color or WC.COLORS.white } end

-- Per kind: its icon and the tooltip lines for a chip ({ kind, count, entry, items }).
WC.CHIP_DEFS = {
    talent = {
        icon = function() return WC.ICONS.talent end,
        tip = function(chip)
            local out = { line(WC.UnspentText(chip.count) or chip.entry.title, WC.COLORS.gold) }
            if chip.entry.nextPick then out[#out + 1] = line(string.format(L.CHIP_NEXT_IN_PLAN, (chip.entry.nextPick:gsub("^[^:]-:%s*", "")))) end
            return out
        end,
    },
    training = {
        icon = class_icon,
        tip = function(chip)
            local e = chip.entry
            local lvl = tonumber(e.level)
            local out = { line(lvl and string.format(L.CHIP_TRAINING_HEAD, math.floor(lvl)) or L.CHIP_TRAINING_HEAD_NOLEVEL, WC.COLORS.gold) }
            for _, sp in ipairs(e.spells or {}) do out[#out + 1] = line(WC.SpellLabel(sp)) end
            if #out == 1 then out[1] = line(e.title, WC.COLORS.gold) end -- a line with no spell list shows its text
            return out
        end,
    },
    upgrade = {
        icon = function() return WC.ICONS.gear end,
        tip = function(chip)
            local out = { line(string.format(chip.count == 1 and L.CHIP_UPGRADES_ONE or L.CHIP_UPGRADES_MANY, chip.count), WC.COLORS.gold) }
            for i, it in ipairs(chip.items) do
                if i > 3 then break end
                local meta = {}
                if it.slot then meta[#meta + 1] = it.slot end
                if it.ilvl then meta[#meta + 1] = string.format(L.ILVL, it.ilvl) end
                out[#out + 1] = line(#meta > 0 and string.format(L.CHIP_UPGRADE_LINE, it.title, table.concat(meta, ", ")) or it.title)
            end
            return out
        end,
    },
}

-- The chips for what RenderDigest found: found.talent = { count, entry }, found.training = { entries },
-- found.upgrade = { entries }. A kind with nothing to do has no chip. d is the digest entry (for the live
-- talent fallback). Returns an ordered list of { kind, count, icon, entry, items }.
function WC.BuildChips(found, d)
    local chips = {}
    local talent = found.talent
    if not talent then
        -- the live count can be ahead of the digest (a level-up since it was written)
        local n = WC.UnspentTalentPoints()
        if n and n >= 1 then
            local first = type(d) == "table" and type(d.talents) == "table" and type(d.talents[1]) == "table" and d.talents[1] or {}
            local text = WC.UnspentText(n)
            local entry = WC.MakeEntry("talent", "talent", {}, { title = text, points = n, ask = { kind = "talent_points", subject = text },
                nextPick = type(first.line) == "string" and first.line:gsub("|", "||") or nil })
            talent = { count = n, entry = entry }
        end
    end
    local list = {}
    if talent then list.talent = { count = talent.count, entry = talent.entry } end
    if #found.training > 0 then
        local n = 0
        for _, e in ipairs(found.training) do n = n + math.max(1, #(e.spells or {})) end
        list.training = { count = n, entry = found.training[1] }
    end
    if #found.upgrade > 0 then
        local items, details, titles = {}, {}, {}
        for i, e in ipairs(found.upgrade) do
            items[i] = { title = e.title, slot = e.slot, ilvl = e.ilvl }
            details[#details + 1] = i <= 6 and e.title or nil
            if i <= 3 then titles[#titles + 1] = e.title end
        end
        local n = #found.upgrade
        local title = string.format(n == 1 and L.CHIP_UPGRADES_ONE or L.CHIP_UPGRADES_MANY, n)
        local entry = WC.MakeEntry("upgrade", "upgrades", {}, { title = title, ask = { kind = "upgrades", subject = table.concat(titles, "; ") } })
        entry.details = details
        list.upgrade = { count = n, entry = entry, items = items }
    end
    for _, id in ipairs(WC.CHIP_ORDER) do
        local c = list[id]
        if c then
            chips[#chips + 1] = { kind = id, count = c.count, entry = c.entry, items = c.items or {}, icon = WC.CHIP_DEFS[id].icon() }
        end
    end
    return chips
end

-- The chips the settings let through.
function WC.VisibleChips(chips)
    local out = {}
    if not WC.Setting("showChips") then return out end
    for _, c in ipairs(chips or {}) do
        if c.count >= 1 and WC.Setting("chips." .. c.kind) ~= false then out[#out + 1] = c end
    end
    return out
end

-- The tooltip of a chip as { text, color } lines, ending with the click hint.
function WC.ChipTipLines(chip)
    local out = WC.CHIP_DEFS[chip.kind].tip(chip)
    out[#out + 1] = line(L.CHIP_CLICK_HINT, WC.COLORS.grey)
    return out
end

-- Where each of n chips sits in a row `width` wide, wrapping to new rows: { { x, y } ... } from the row's
-- top left, and the total height (0 for no chips).
function WC.ChipLayout(n, width, size, gap)
    size, gap = size or WC.CHIP_SIZE, gap or WC.CHIP_GAP
    local cols = math.max(1, math.floor((width + gap) / (size + gap)))
    local pos = {}
    for i = 1, n do
        pos[i] = { x = ((i - 1) % cols) * (size + gap), y = math.floor((i - 1) / cols) * (size + gap) }
    end
    local rows = n > 0 and math.ceil(n / cols) or 0
    return pos, rows > 0 and rows * size + (rows - 1) * gap or 0
end

-- ------------------------------------------------------------ "something new": pulse until hovered

WC.chipState = {}

function WC.Now() return (GetTime and GetTime()) or time() end

-- Compares every chip's count with the last one seen. A count that goes up marks the chip new: it pulses
-- for CHIP_PULSE_SECONDS and stays highlighted until hovered. The first sight of a kind, and a count
-- that goes down, mark nothing. Call with every chip, shown or not.
function WC.ChipsNote(chips, now)
    now = now or WC.Now()
    local counts = {}
    for _, c in ipairs(chips) do counts[c.kind] = c.count end
    for _, id in ipairs(WC.CHIP_ORDER) do
        local st = WC.chipState[id]
        local n = counts[id] or 0
        if not st then
            WC.chipState[id] = { seen = n }
        else
            if n > st.seen and WC.Setting("chipPulse") then st.new, st.untilT = true, now + WC.CHIP_PULSE_SECONDS end
            if n == 0 then st.new = nil end
            st.seen = n
        end
    end
end

function WC.ChipNew(kind)
    local st = WC.chipState[kind]
    return st and st.new == true and WC.Setting("chipPulse") or false
end

function WC.ChipPulsing(kind, now)
    local st = WC.chipState[kind]
    return WC.ChipNew(kind) and (now or WC.Now()) < (st.untilT or 0)
end

-- Hovering clears the highlight.
function WC.ChipHovered(kind)
    local st = WC.chipState[kind]
    if st then st.new, st.untilT = nil, nil end
end
