-- WoW Companion: records the player's own stat totals into WoWCompanionDB.stats[<character>], read-only.
-- Plain data in our own SavedVariables: it leaves the game only when the client saves (a /reload, logout or
-- quit), and the addon never asks for one. The overlay reads it at each natural save for the stat check.
-- Only the client's standard, non-protected unit and stat getters are called, never in combat. An API this client
-- lacks is skipped, and a stat it cannot read is left out of the record.
-- Format: stats[name] = { at, level, str, agi, sta, int, spi, armor, ap, crit, dodge, parry, block }.

local WC = WoWCompanion

local STAT_INDEX = { str = 1, agi = 2, sta = 3, int = 4, spi = 5 } -- UnitStat's index per stat
local CHANCES = { crit = "GetCritChance", dodge = "GetDodgeChance", parry = "GetParryChance", block = "GetBlockChance" }
local KEYS = { "level", "str", "agi", "sta", "int", "spi", "armor", "ap", "crit", "dodge", "parry", "block" }

local pending = false -- a record that waited for combat to end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if not ok then return nil end
    return a, b, c
end

local function num(v)
    return type(v) == "number" and v == v and v or nil
end

local function round1(v) return math.floor(v * 10 + 0.5) / 10 end

-- The totals the client reports now (level may be passed in: PLAYER_LEVEL_UP carries the new one).
function WC.ReadStats(level)
    local s = {}
    s.level = num(level) or num(call(UnitLevel, "player"))
    for key, i in pairs(STAT_INDEX) do
        local _, effective = call(UnitStat, "player", i)
        s[key] = num(effective)
    end
    local _, armor = call(UnitArmor, "player")
    s.armor = num(armor)
    local base, pos, neg = call(UnitAttackPower, "player")
    if num(base) then s.ap = base + (num(pos) or 0) + (num(neg) or 0) end
    for key, name in pairs(CHANCES) do
        local v = num(call(_G[name]))
        s[key] = v and round1(v) or nil
    end
    return s
end

local function changed(old, new)
    if type(old) ~= "table" then return true end
    for _, k in ipairs(KEYS) do
        if old[k] ~= new[k] then return true end
    end
    return false
end

-- Records the totals now, or after combat when one is under way. Returns the saved record, or nil when nothing was written.
function WC.RecordStats(level)
    if not WC.db then return nil end
    if InCombatLockdown and InCombatLockdown() then pending = true return nil end
    pending = false
    local s = WC.ReadStats(level)
    if next(s) == nil then return nil end
    local name = call(UnitName, "player")
    if type(name) ~= "string" or name == "" then return nil end
    WC.db.stats = type(WC.db.stats) == "table" and WC.db.stats or {}
    local old = WC.db.stats[name]
    if not changed(old, s) then return old end
    s.at = time()
    WC.db.stats[name] = s
    return s
end

local events = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_LEVEL_UP", "PLAYER_EQUIPMENT_CHANGED", "UNIT_STATS", "PLAYER_REGEN_ENABLED" }) do
    events:RegisterEvent(e)
end
events:SetScript("OnEvent", function(_, event, a)
    if event == "UNIT_STATS" and a ~= "player" then return end
    if event == "PLAYER_REGEN_ENABLED" and not pending then return end
    WC.RecordStats(event == "PLAYER_LEVEL_UP" and a or nil)
end)
