-- WoW Companion: records the player's own character in WoWCompanionDB.characters["<realm>:<name>"] so the
-- WoW Companion app can read it. Format: docs/capture-format.md.
-- Read-only: only the client's documented read APIs are called, nothing is sent and nothing acts. Data leaves
-- the game only when the client saves (logout, /reload, quit); the addon never asks for one.
-- Reads are coalesced and held back while in combat.

local WC = WoWCompanion

WC.CAPTURE_VERSION = 1
local DELAY = 2          -- seconds a change waits so a burst of events is read once
local MAX_QUESTS = 60
local MAX_SPELLS = 1500
local MAX_RECIPES = 600
local BAGS = { 0, 1, 2, 3, 4 }
local BANK_BAGS = { -1, 5, 6, 7, 8, 9, 10 }
local SLOTS = 19         -- equipment slots 1..19

local dirty = {}         -- part name -> true: waiting to be read
local scheduled = false
local waited = 0
local timer = CreateFrame("Frame")
WC.captureTimer = timer
local bankOpen = false

local function round(v, n)
    local m = 10 ^ (n or 0)
    return math.floor(v * m + 0.5) / m
end

-- Item and spell ids from a link: "|Hitem:ID:enchant:g1:g2:g3:g4:suffix:..." or "|Hspell:ID" / "|Henchant:ID".
local function link_fields(link, kind)
    if type(link) ~= "string" then return end
    local rest = link:match(kind .. ":([%-%d:]*)")
    if not rest then return end
    local out = {}
    for f in (rest .. ":"):gmatch("([^:]*):") do out[#out + 1] = tonumber(f) end
    return out
end

local function item_id(link)
    local f = link_fields(link, "item")
    return f and f[1]
end

local function enabled()
    return WC.db ~= nil and WC.Setting("recordCharacter") == true
end

-- The record for this character, created on first use.
local function record()
    if not (WC.db and UnitName and GetRealmName) then return nil end
    local name, realm = UnitName("player"), GetRealmName()
    if type(name) ~= "string" or name == "" then return nil end
    if type(WC.db.characters) ~= "table" then WC.db.characters = {} end
    local key = (realm or "") .. ":" .. name
    local r = WC.db.characters[key]
    if type(r) ~= "table" then
        r = {}
        WC.db.characters[key] = r
    end
    r.version = WC.CAPTURE_VERSION
    r.name, r.realm = name, realm
    return r
end

local readers = {}

function readers.identity(r)
    r.level = UnitLevel("player")
    local _, class = UnitClass("player")
    r.class = class
    local _, race = UnitRace("player")
    r.race = race
    r.faction = UnitFactionGroup and (UnitFactionGroup("player")) or nil
    local version, build = GetBuildInfo()
    r.client = { version = version, build = build }
end

function readers.money(r)
    r.money = GetMoney and GetMoney() or nil
    r.xp = UnitXP and UnitXP("player") or nil
    r.xpMax = UnitXPMax and UnitXPMax("player") or nil
    r.rested = GetXPExhaustion and GetXPExhaustion() or 0
end

function readers.location(r)
    local map, x, y
    if WC.PlayerPos then map, x, y = WC.PlayerPos() end
    if map and x and y then
        r.location = { map = map, x = round(x, 1), y = round(y, 1) }
    else
        r.location = map and { map = map } or nil
    end
    r.hearth = GetBindLocation and GetBindLocation() or nil
end

function readers.equipment(r)
    local eq = {}
    for slot = 1, SLOTS do
        local id = GetInventoryItemID and GetInventoryItemID("player", slot)
        if id then
            local e = { id = id }
            local f = link_fields(GetInventoryItemLink and GetInventoryItemLink("player", slot), "item")
            if f then
                if f[2] and f[2] > 0 then e.enchant = f[2] end
                if f[7] and f[7] ~= 0 then e.suffix = f[7] end
            end
            eq[slot] = e
        end
    end
    r.equipment = eq
end

-- One container: { size, items = { [slot] = { id, count } } }.
local function read_bag(bag)
    local size
    if C_Container and C_Container.GetContainerNumSlots then size = C_Container.GetContainerNumSlots(bag)
    elseif GetContainerNumSlots then size = GetContainerNumSlots(bag) end
    if not size or size <= 0 then return nil end
    local items = {}
    for slot = 1, size do
        local id, count
        if C_Container and C_Container.GetContainerItemInfo then
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info then id, count = info.itemID, info.stackCount end
        elseif GetContainerItemID then
            id = GetContainerItemID(bag, slot)
            if id and GetContainerItemInfo then count = select(2, GetContainerItemInfo(bag, slot)) end
        end
        if id then items[slot] = { id = id, count = count or 1 } end
    end
    return { size = size, items = items }
end

local function read_bags(list)
    local out = {}
    for _, bag in ipairs(list) do out[bag] = read_bag(bag) end
    return out
end

function readers.bags(r)
    r.bags = read_bags(BAGS)
end

function readers.bank(r)
    if not bankOpen then return end -- the last snapshot stays
    r.bank = read_bags(BANK_BAGS)
    r.bankSeenAt = time()
end

function readers.quests(r)
    local list = {}
    local n = GetNumQuestLogEntries and GetNumQuestLogEntries() or 0
    for i = 1, n do
        if #list >= MAX_QUESTS then break end
        local title, level, isHeader, complete, id
        if C_QuestLog and C_QuestLog.GetInfo then
            local info = C_QuestLog.GetInfo(i)
            if info then title, level, isHeader, id = info.title, info.level, info.isHeader, info.questID end
            if info and C_QuestLog.IsComplete and id then complete = C_QuestLog.IsComplete(id) and 1 or nil end
        elseif GetQuestLogTitle then
            local t, lv, _, header, _, isComplete, _, qid = GetQuestLogTitle(i)
            title, level, isHeader, complete, id = t, lv, header, isComplete, qid
        end
        if not isHeader and id then
            local q = { id = id, title = title, level = level }
            if complete == 1 or complete == true then q.complete = true end
            if complete == -1 then q.failed = true end
            local objs = {}
            local count = GetNumQuestLeaderBoards and GetNumQuestLeaderBoards(i) or 0
            for j = 1, count do
                local text, _, done = GetQuestLogLeaderBoard(j, i)
                local o = { text = text, done = done and true or false }
                if type(text) == "string" then
                    local have, need = text:match("(%d+)%s*/%s*(%d+)")
                    if have then o.have, o.need = tonumber(have), tonumber(need) end
                end
                objs[#objs + 1] = o
            end
            if #objs > 0 then q.objectives = objs end
            list[#list + 1] = q
        end
    end
    r.quests = { captured = true, entries = list }
end

function readers.completed(r)
    local set
    if GetQuestsCompleted then
        set = GetQuestsCompleted()
    elseif C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs then
        set = {}
        for _, id in ipairs(C_QuestLog.GetAllCompletedQuestIDs() or {}) do set[id] = true end
    end
    if type(set) ~= "table" then return end -- the client offers none: leave the field out
    local ids = {}
    for id, v in pairs(set) do
        if v and type(id) == "number" then ids[#ids + 1] = id end
    end
    table.sort(ids)
    r.completedQuests = ids
end

function readers.talents(r)
    local trees = {}
    local tabs = GetNumTalentTabs and GetNumTalentTabs() or 0
    for t = 1, tabs do
        local tree = { tree = GetTalentTabInfo(t), nodes = {} }
        for i = 1, GetNumTalents(t) or 0 do
            local name, _, _, _, rank, max = GetTalentInfo(t, i)
            if name then tree.nodes[#tree.nodes + 1] = { name = name, rank = rank or 0, max = max or 0 } end
        end
        trees[#trees + 1] = tree
    end
    r.talents = trees
end

function readers.skills(r)
    local list = {}
    local group
    local primary = TRADE_SKILLS or "Professions"
    local secondary = SECONDARY_SKILLS or "Secondary Skills"
    for i = 1, GetNumSkillLines and GetNumSkillLines() or 0 do
        local name, header, _, rank, _, _, max = GetSkillLineInfo(i)
        if header then
            group = name
        elseif name then
            local s = { name = name, rank = rank or 0, max = max or 0, group = group }
            if group == primary or group == secondary or group == "Professions" or group == "Secondary Skills" then
                s.profession = true
            end
            list[#list + 1] = s
        end
    end
    r.skills = list
end

function readers.spells(r)
    local ids, seen = {}, {}
    for tab = 1, GetNumSpellTabs and GetNumSpellTabs() or 0 do
        local _, _, offset, count = GetSpellTabInfo(tab)
        for index = (offset or 0) + 1, (offset or 0) + (count or 0) do
            if #ids >= MAX_SPELLS then break end
            local id
            if C_SpellBook and C_SpellBook.GetSpellBookItemInfo then
                local info = C_SpellBook.GetSpellBookItemInfo(index, 0)
                if info and not info.isOffSpec and info.spellID and info.itemType ~= 4 then id = info.spellID end
            elseif GetSpellLink then
                local f = link_fields(GetSpellLink(index, "spell"), "spell")
                id = f and f[1]
            end
            if id and not seen[id] then seen[id] = true; ids[#ids + 1] = id end
        end
    end
    table.sort(ids)
    r.spells = ids
end

function readers.reputations(r)
    local list = {}
    for i = 1, GetNumFactions and GetNumFactions() or 0 do
        local name, _, standing, bmin, bmax, value, _, _, header, _, hasRep = GetFactionInfo(i)
        if name and (not header or hasRep) then
            list[#list + 1] = { faction = name, standing = standing, value = value, min = bmin, max = bmax }
        end
    end
    r.reputations = list
end

-- Recipes of the open trade skill or craft window, kept per profession. Each entry: name, id (the recipe's spell
-- id where the link gives one), item (the made item), difficulty (orange, yellow, green or grey).
local DIFFICULTY = { optimal = "orange", medium = "yellow", easy = "green", trivial = "grey",
    [0] = "orange", [1] = "yellow", [2] = "green", [3] = "grey" }

local function recipe_entry(name, kind, l)
    local spell = link_fields(l, "enchant") or link_fields(l, "spell")
    local item = link_fields(l, "item")
    return { name = name, id = spell and spell[1] or (item and item[1]), item = item and item[1] or nil,
        difficulty = DIFFICULTY[kind] }
end

local function store_recipes(r, profession, out)
    if type(profession) ~= "string" or profession == "" or profession == "UNKNOWN" then return end
    r.recipes = r.recipes or {}
    r.recipes[profession] = { seenAt = time(), entries = out }
end

local function read_recipes(r, profession, count, info, link)
    local out = {}
    for i = 1, count or 0 do
        if #out >= MAX_RECIPES then break end
        if WC.SeenRaw and i <= 3 then WC.SeenRaw("tradeskill", "GetTradeSkillInfo", info(i, true)) end
        local name, kind = info(i)
        if type(name) == "string" and kind ~= "header" and kind ~= "subheader" then
            out[#out + 1] = recipe_entry(name, kind, link and link(i))
        end
    end
    store_recipes(r, profession, out)
end

-- The modern window (C_TradeSkillUI): recipe ids come from the profession, each described by a table.
local function read_modern_recipes(r)
    local T = C_TradeSkillUI
    if not (T and T.GetAllRecipeIDs and T.GetRecipeInfo) then return false end
    if T.IsTradeSkillLinked and T.IsTradeSkillLinked() then return true end
    if T.IsTradeSkillGuild and T.IsTradeSkillGuild() then return true end
    local profession
    if T.GetBaseProfessionInfo then
        local p = T.GetBaseProfessionInfo()
        profession = type(p) == "table" and (p.professionName or p.parentProfessionName) or nil
    end
    if not profession and T.GetTradeSkillLine then profession = T.GetTradeSkillLine() end
    local out = {}
    for _, id in ipairs(T.GetAllRecipeIDs() or {}) do
        if #out >= MAX_RECIPES then break end
        local info = T.GetRecipeInfo(id)
        if WC.SeenRaw and #out < 3 and type(info) == "table" then
            WC.SeenRaw("tradeskill", "C_TradeSkillUI.GetRecipeInfo", id, info.name, info.learned, info.relativeDifficulty, info.difficulty)
        end
        if type(info) == "table" and info.learned ~= false and type(info.name) == "string" then
            local item = info.itemID
            out[#out + 1] = { name = info.name, id = info.recipeID or id, item = item,
                difficulty = DIFFICULTY[info.relativeDifficulty] or DIFFICULTY[info.difficulty] }
        end
    end
    store_recipes(r, profession, out)
    return true
end

function readers.tradeskill(r)
    if GetNumTradeSkills and GetTradeSkillLine then
        if IsTradeSkillLinked and IsTradeSkillLinked() then return end -- someone else's list
        local name = GetTradeSkillLine()
        local n = GetNumTradeSkills() or 0
        if n > 0 or not (C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs) then
            read_recipes(r, name, n,
                function(i, raw)
                    if raw then return GetTradeSkillInfo(i) end
                    local nm, k = GetTradeSkillInfo(i); return nm, k
                end, GetTradeSkillItemLink)
            return
        end
    end
    read_modern_recipes(r)
end

function readers.craft(r)
    local name = GetCraftDisplaySkillLine and GetCraftDisplaySkillLine()
    if (not name or name == "") and GetCraftName then name = GetCraftName() end
    read_recipes(r, name, GetNumCrafts and GetNumCrafts(),
        function(i, raw)
            if raw then return GetCraftInfo(i) end
            local n, _, k = GetCraftInfo(i); return n, k
        end, GetCraftItemLink)
end

-- The order matters little; each part is read on its own so one failing read never costs the rest.
local ORDER = { "identity", "money", "location", "equipment", "bags", "bank", "quests", "completed", "talents",
    "skills", "spells", "reputations", "tradeskill", "craft" }

-- Reads every waiting part now, unless capture is off or the player is in combat.
function WC.CaptureFlush()
    scheduled = false
    timer:SetScript("OnUpdate", nil)
    if not enabled() then dirty = {}; return false end
    if InCombatLockdown and InCombatLockdown() then return false end -- PLAYER_REGEN_ENABLED flushes
    local r = record()
    if not r then return false end
    local any = false
    for _, part in ipairs(ORDER) do
        if dirty[part] then
            dirty[part] = nil
            pcall(readers[part], r)
            any = true
        end
    end
    if any then r.capturedAt = time() end
    return any
end

-- A change waits DELAY seconds (counted by our own OnUpdate, only while something is waiting), so a burst of
-- events is read once.
local function tick(self, elapsed)
    waited = waited + (elapsed or 0)
    if waited < DELAY then return end
    self:SetScript("OnUpdate", nil)
    WC.CaptureFlush()
end

local function schedule()
    if scheduled then return end
    if InCombatLockdown and InCombatLockdown() then return end
    scheduled, waited = true, 0
    timer:SetScript("OnUpdate", tick)
end

-- Marks parts as changed and schedules one coalesced read.
function WC.CaptureMark(...)
    if not enabled() then return end
    for _, part in ipairs({ ... }) do dirty[part] = true end
    schedule()
end

local EVENTS = {
    PLAYER_ENTERING_WORLD = { "identity", "money", "location", "equipment", "bags", "quests", "completed", "talents", "skills", "spells", "reputations" },
    PLAYER_LEVEL_UP = { "identity", "money", "talents", "spells" },
    PLAYER_XP_UPDATE = { "money" },
    PLAYER_MONEY = { "money" },
    ZONE_CHANGED_NEW_AREA = { "location" },
    ZONE_CHANGED = { "location" },
    HEARTHSTONE_BOUND = { "location" },
    PLAYER_EQUIPMENT_CHANGED = { "equipment" },
    BAG_UPDATE_DELAYED = { "bags" },
    QUEST_LOG_UPDATE = { "quests" },
    QUEST_TURNED_IN = { "quests", "completed" },
    SKILL_LINES_CHANGED = { "skills" },
    CHARACTER_POINTS_CHANGED = { "talents" },
    SPELLS_CHANGED = { "spells" },
    LEARNED_SPELL_IN_TAB = { "spells" },
    UPDATE_FACTION = { "reputations" },
    TRADE_SKILL_SHOW = { "tradeskill" },
    TRADE_SKILL_UPDATE = { "tradeskill" },
    TRADE_SKILL_LIST_UPDATE = { "tradeskill" },
    TRADE_SKILL_DATA_SOURCE_CHANGED = { "tradeskill" },
    CRAFT_SHOW = { "craft" },
    CRAFT_UPDATE = { "craft" },
}

-- The windows' update events only count while the window is up.
local WINDOW_PART = { TRADE_SKILL_UPDATE = "tradeskill", TRADE_SKILL_LIST_UPDATE = "tradeskill",
    TRADE_SKILL_DATA_SOURCE_CHANGED = "tradeskill", CRAFT_UPDATE = "craft" }
local windowOpen = {}

local frame = CreateFrame("Frame")
for ev in pairs(EVENTS) do pcall(frame.RegisterEvent, frame, ev) end -- a client without an event just skips it
for _, ev in ipairs({ "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "TRADE_SKILL_CLOSE", "CRAFT_CLOSE", "PLAYER_REGEN_ENABLED" }) do
    pcall(frame.RegisterEvent, frame, ev)
end
frame:SetScript("OnEvent", function(_, event)
    if event == "BANKFRAME_OPENED" then
        bankOpen = true
        WC.CaptureMark("bank")
    elseif event == "BANKFRAME_CLOSED" then
        bankOpen = false
    elseif event == "TRADE_SKILL_CLOSE" then
        windowOpen.tradeskill = false
    elseif event == "CRAFT_CLOSE" then
        windowOpen.craft = false
    elseif event == "PLAYER_REGEN_ENABLED" then
        if next(dirty) then schedule() end
    else
        local part = WINDOW_PART[event]
        if part and not windowOpen[part] then return end
        if event == "TRADE_SKILL_SHOW" then windowOpen.tradeskill = true end
        if event == "CRAFT_SHOW" then windowOpen.craft = true end
        WC.CaptureMark(unpack(EVENTS[event]))
        if event == "BAG_UPDATE_DELAYED" and bankOpen then WC.CaptureMark("bank") end
    end
end)
