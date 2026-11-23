-- WoW Companion: character to-dos (talent points, class training, gear upgrades) as a row of icon chips
-- under the panel header. This file is data and state only; Panel.lua draws the chips.
-- A new kind (dungeons, professions) is one CHIP_DEFS entry, its CHIP_ORDER id, a chip-name string and
-- a chips.<id> setting row, plus whatever collects its count in WC.BuildChips.

local WC = WoWCompanion
local L = WC.L

WC.CHIP_SIZE, WC.CHIP_GAP = 24, 6
WC.CHIP_PULSE_SECONDS = 5
WC.CHIP_ORDER = { "talent", "training", "upgrade", "stats" }

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
    stats = {
        icon = function() return WC.ICONS.stats end,
        tip = function(chip)
            local e = chip.entry
            if not e.hasStats then return { line(L.CHIP_STATS_NONE, WC.COLORS.gold) } end
            local out = { line(e.title, WC.COLORS.gold) }
            for _, t in ipairs(e.details or {}) do out[#out + 1] = line(t) end
            return out
        end,
    },
    upgrade = {
        icon = function() return WC.ICONS.gear end,
        tip = function(chip)
            local planned = false
            for _, it in ipairs(chip.items) do if WC.HasUpgradePath(it) then planned = true end end
            local head = planned and L.CHIP_UPGRADES_GET or (chip.count == 1 and L.CHIP_UPGRADES_ONE or L.CHIP_UPGRADES_MANY)
            local out = { line(string.format(head, chip.count), WC.COLORS.gold) }
            for i, it in ipairs(chip.items) do
                if i > WC.CHIP_UPGRADE_MAX then break end
                out[#out + 1] = line(WC.UpgradeMain(it))
                local sub = WC.UpgradeSub(it, true)
                if sub then out[#out + 1] = line(sub, WC.COLORS.dim) end
            end
            if chip.count > WC.CHIP_UPGRADE_MAX then
                out[#out + 1] = line(string.format(L.CHIP_UPGRADES_MORE, chip.count - WC.CHIP_UPGRADE_MAX), WC.COLORS.grey)
            end
            return out
        end,
    },
}

-- ------------------------------------------------------------ upgrade lines in plain words

WC.CHIP_UPGRADE_MAX = 4

-- The path icon per way of getting an item, all the client's own art.
WC.PATH_ICONS = {
    quest = "Interface\\GossipFrame\\AvailableQuestIcon",
    craft = "Interface\\Icons\\Trade_BlackSmithing",
    auction = "Interface\\Icons\\INV_Misc_Coin_01",
    dungeon = "Interface\\Icons\\INV_Misc_Map_01",
    creature = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
}

-- Whether an upgrade (entry or chip item) came from a digest that says how to get it.
function WC.HasUpgradePath(u)
    return type(u) == "table" and type(u.how) == "string" and u.how ~= ""
end

-- The item's name from a digest line's text: no "Equip " lead and no "(... ilvl ...)" tail.
function WC.UpgradeName(u)
    local t = tostring(u.title or "")
    t = t:gsub("%s*%([^)]*ilvl[^)]*%)", ""):gsub("^Equip%s+", "")
    return t
end

-- "<Slot>: <Item> - <gain>"; an older digest has no gain, and a line with no slot is the item alone.
function WC.UpgradeMain(u)
    local out = WC.UpgradeName(u)
    -- an older digest's line can already lead with the slot ("back: Traveler's Shawl"): never say it twice
    local slot = u.slot
    if slot and slot ~= "" and out:lower():sub(1, #slot + 1) ~= slot:lower() .. ":" then out = slot .. ": " .. out end
    if u.gain and u.gain ~= "" then out = out .. " \226\128\148 " .. u.gain end
    return out
end

local function inline_icon(path, size) return "|T" .. path .. ":" .. size .. "|t " end

-- What the player wears in the slot, from the digest's `replaces` ("instead of your Flimsy Chain Cloak").
function WC.UpgradeWorn(u)
    local r = type(u.replaces) == "string" and u.replaces or ""
    local worn = r:match("^[Ii]nstead of your (.+)$")
    if worn then return worn end
    if r == "" or r:lower():find("empty slot", 1, true) or r:lower():find("nothing", 1, true) then return L.CARD_NOTHING_WORN end
    return r
end

-- The dim second line: the path icon, how to get it, and "from level N" when it can't be worn yet. Nil with
-- nothing to say. inline puts the icon in the text (a tooltip line); the panel draws it as a texture.
function WC.UpgradeSub(u, inline)
    if not WC.HasUpgradePath(u) then return nil end -- an older digest: just "<Slot>: <Item>"
    local parts = { u.how }
    local wear = u.wear
    if type(wear) == "string" and wear ~= "" and not wear:lower():find("^wear now") then
        parts[#parts + 1] = wear:sub(1, 1):lower() .. wear:sub(2)
    elseif not wear and u.atLevel then
        parts[#parts + 1] = string.format(L.FROM_LEVEL, math.floor(u.atLevel))
    end
    if #parts == 0 then return nil end
    local text = table.concat(parts, " \194\183 ")
    local icon = WC.PATH_ICONS[u.pathKind]
    return (inline and icon) and inline_icon(icon, 12) .. text or text
end

-- The Stats chip's entry from the digest's `stats` ({ insights = 1-3 strings, profile, asks }). Without one the
-- chip still shows, saying how to get a stat check. Its card holds the insights and the asks as question chips.
function WC.StatsEntry(s)
    local insights = {}
    if type(s) == "table" and type(s.insights) == "table" then
        for _, t in ipairs(s.insights) do
            if type(t) == "string" and #insights < 3 then
                t = t:gsub("|", ""):gsub("^%s+", ""):gsub("%s+$", "")
                if t ~= "" then insights[#insights + 1] = t:sub(1, 160) end
            end
        end
    end
    if #insights == 0 then
        return WC.MakeEntry("stats", "stats", { details = { L.CHIP_STATS_NONE } }, { title = L.CHIP_STATS_TITLE, asks = {} })
    end
    local profile = type(s.profile) == "string" and s.profile:gsub("|", ""):gsub("^%s+", ""):gsub("%s+$", "") or ""
    local entry = WC.MakeEntry("stats", "stats", { asks = s.asks, ref = s.ref }, { title = profile ~= "" and profile:sub(1, 60) or L.CHIP_STATS_TITLE })
    entry.details, entry.hasStats = insights, true
    return entry
end

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
            items[i] = e
            details[#details + 1] = i <= 6 and WC.UpgradeName(e) or nil
            if i <= 3 then titles[#titles + 1] = e.title end
        end
        local n = #found.upgrade
        local title = string.format(n == 1 and L.CHIP_UPGRADES_ONE or L.CHIP_UPGRADES_MANY, n)
        local entry = WC.MakeEntry("upgrade", "upgrades", {}, { title = title, ask = { kind = "upgrades", subject = table.concat(titles, "; ") } })
        entry.details = details
        entry.upgrades = found.upgrade
        local asks = {}
        for _, e in ipairs(found.upgrade) do
            for _, a in ipairs(e.asks or {}) do if #asks < 3 then asks[#asks + 1] = a end end
            if not entry.quest and e.pathKind == "quest" and e.quest and #WC.QuestSteps(e.quest) > 0 then entry.quest = e.quest end
        end
        entry.asks = asks -- per item, from the digest; never a question built from this summary
        list.upgrade = { count = n, entry = entry, items = items }
    end
    list.stats = { count = 1, noBadge = true, entry = WC.StatsEntry(type(d) == "table" and d.stats or nil) }
    for _, id in ipairs(WC.CHIP_ORDER) do
        local c = list[id]
        if c then
            chips[#chips + 1] = { kind = id, count = c.count, entry = c.entry, items = c.items or {}, noBadge = c.noBadge, icon = WC.CHIP_DEFS[id].icon() }
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
