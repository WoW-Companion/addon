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
    -- Empty fields ("item:2092:::::::10") keep their place: out[i] is the i-th field, nil when empty.
    local i = 0
    for f in (rest .. ":"):gmatch("([^:]*):") do
        i = i + 1
        out[i] = tonumber(f)
    end
    return out
end

-- Which API paths were tried and what each gave, for the "apiProbe" block: a count per path, -1 when the client
-- lacks the API, never a value. Rebuilt by each talents/spells read, so one /reload shows which path works.
local function probe_of(r)
    r.apiProbe = r.apiProbe or {}
    r.apiProbe.seenAt = time()
    return r.apiProbe
end

local STAT_KEYS = {
    ITEM_MOD_AGILITY_SHORT = "agi", ITEM_MOD_STRENGTH_SHORT = "str", ITEM_MOD_STAMINA_SHORT = "sta",
    ITEM_MOD_INTELLECT_SHORT = "int", ITEM_MOD_SPIRIT_SHORT = "spi", RESISTANCE0_NAME = "armor",
}
local statsCache = {}   -- item link -> compact stats map (or false when it has none), for this session
local statsProbe        -- items with stats read since the last reader reset; -1 when the client has no GetItemStats

-- The item's own stats from the read-only GetItemStats (enchants are not in it; the enchant id is kept apart).
local function item_stats(link)
    local getter = (C_Item and C_Item.GetItemStats) or GetItemStats
    if type(getter) ~= "function" then
        statsProbe = -1
        return nil
    end
    if type(link) ~= "string" or link == "" then return nil end
    local cached = statsCache[link]
    if cached == nil then
        local ok, raw = pcall(getter, link)
        cached = false
        if ok and type(raw) == "table" then
            local out, any = {}, false
            for k, v in pairs(raw) do
                v = WC.Clean(v)
                if type(k) == "string" and type(v) == "number" then
                    out[STAT_KEYS[k] or k] = v
                    any = true
                end
            end
            if any then cached = out end
        end
        statsCache[link] = cached
    end
    if cached then
        if statsProbe ~= -1 then statsProbe = (statsProbe or 0) + 1 end
        local copy = {}
        for k, v in pairs(cached) do copy[k] = v end
        return copy
    end
    statsProbe = statsProbe or 0
    return nil
end

local pendingInfo = false -- an item the client had not cached yet; filled when GET_ITEM_INFO_RECEIVED fires

-- What the client says about an item, added to entry e: quality, ilvl, reqLevel, equipLoc from the item info,
-- enchant and suffix from the link's fields (item:id:enchant:gem1:gem2:gem3:gem4:suffix:...).
local function describe(e, link)
    link = WC.Clean(link)
    local f = link_fields(link, "item")
    if f then
        if f[2] and f[2] > 0 then e.enchant = f[2] end
        if f[7] and f[7] ~= 0 then e.suffix = f[7] end
    end
    local getter = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not getter then return end
    local _, _, quality, ilvl, reqLevel, _, _, _, equipLoc = getter(link or e.id)
    if quality == nil and ilvl == nil then
        pendingInfo = true
        return
    end
    e.quality = WC.Clean(quality)
    e.ilvl = WC.Clean(ilvl)
    e.reqLevel = WC.Clean(reqLevel)
    if type(equipLoc) == "string" and equipLoc ~= "" then
        e.equipLoc = WC.Clean(equipLoc)
        e.stats = item_stats(link)
    end
end

local function item_id(link)
    local f = link_fields(WC.Clean(link), "item")
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
    statsProbe = nil
    for slot = 1, SLOTS do
        local id = GetInventoryItemID and GetInventoryItemID("player", slot)
        if id then
            local e = { id = id }
            describe(e, GetInventoryItemLink and GetInventoryItemLink("player", slot))
            eq[slot] = e
        end
    end
    r.equipment = eq
    if statsProbe then probe_of(r).itemStats = statsProbe end
end

-- One container: { size, items = { [slot] = { id, count } } }.
local function read_bag(bag)
    local size
    if C_Container and C_Container.GetContainerNumSlots then size = C_Container.GetContainerNumSlots(bag)
    elseif GetContainerNumSlots then size = GetContainerNumSlots(bag) end
    if not size or size <= 0 then return nil end
    local items = {}
    for slot = 1, size do
        local id, count, link
        if C_Container and C_Container.GetContainerItemInfo then
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info then id, count, link = info.itemID, info.stackCount, info.hyperlink end
        elseif GetContainerItemID then
            id = GetContainerItemID(bag, slot)
            if id and GetContainerItemInfo then
                local _, n, _, _, _, _, l = GetContainerItemInfo(bag, slot) -- icon, count, locked, quality, readable, lootable, link
                count, link = n, l
            end
        end
        if id then
            local e = { id = id, count = count or 1 }
            describe(e, link)
            items[slot] = e
        end
    end
    return { size = size, items = items }
end

local function read_bags(list)
    local out = {}
    for _, bag in ipairs(list) do out[bag] = read_bag(bag) end
    return out
end

function readers.bags(r)
    statsProbe = nil
    r.bags = read_bags(BAGS)
    if statsProbe then probe_of(r).itemStats = statsProbe end
end

function readers.bank(r)
    if not bankOpen then return end -- the last snapshot stays
    r.bank = read_bags(BANK_BAGS)
    r.bankSeenAt = time()
end

-- Calls fn with pcall; its first result, or nil when it is missing or failed.
local function qcall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if ok then return v end
    return nil
end

-- The quest log, read with C_QuestLog first and the legacy globals as a fallback. When no count API exists the
-- field is left alone, so the app does not take "nothing read" for "no quests".
function readers.quests(r)
    local Q = C_QuestLog
    local count, countPath
    if Q and type(Q.GetNumQuestLogEntries) == "function" then
        count, countPath = qcall(Q.GetNumQuestLogEntries), "modern"
    elseif type(GetNumQuestLogEntries) == "function" then
        count, countPath = qcall(GetNumQuestLogEntries), "legacy"
    end
    local probe = probe_of(r)
    if type(count) ~= "number" then
        probe.quests = { count = "none", entries = -1, ready = -1, objectives = -1 }
        return
    end
    local list, ready = {}, 0
    local objPath = -1
    for i = 1, count do
        if #list >= MAX_QUESTS then break end
        local title, level, isHeader, complete, failed, id
        if Q and type(Q.GetInfo) == "function" then
            local info = qcall(Q.GetInfo, i)
            if type(info) == "table" then title, level, isHeader, id = info.title, info.level, info.isHeader, info.questID end
        elseif type(GetQuestLogTitle) == "function" then
            local ok, t, lv, _, header, _, isComplete, _, qid = pcall(GetQuestLogTitle, i)
            if ok then
                title, level, isHeader, id = t, lv, header, qid
                if isComplete == 1 or isComplete == true then complete = true end
                if isComplete == -1 then failed = true end
            end
        end
        if not isHeader and id then
            if Q then
                if qcall(Q.ReadyForTurnIn, id) or qcall(Q.IsComplete, id) then complete = true end
                if qcall(Q.IsFailed, id) then failed = true end
            end
            local q = { id = id, title = title, level = level }
            if complete then q.complete = true; ready = ready + 1 end
            if failed then q.failed = true end
            local objs = {}
            local list_o = Q and qcall(Q.GetQuestObjectives, id)
            if type(list_o) == "table" then
                objPath = "modern"
                for _, ob in ipairs(list_o) do
                    local o = { text = ob.text, done = ob.finished and true or false }
                    if type(ob.numRequired) == "number" and ob.numRequired > 0 then
                        o.have, o.need = ob.numFulfilled or 0, ob.numRequired
                    elseif type(ob.text) == "string" then
                        local have, need = ob.text:match("(%d+)%s*/%s*(%d+)")
                        if have then o.have, o.need = tonumber(have), tonumber(need) end
                    end
                    objs[#objs + 1] = o
                end
            elseif type(GetNumQuestLeaderBoards) == "function" and type(GetQuestLogLeaderBoard) == "function" then
                if objPath == -1 then objPath = "legacy" end
                for j = 1, qcall(GetNumQuestLeaderBoards, i) or 0 do
                    local ok, text, _, done = pcall(GetQuestLogLeaderBoard, j, i)
                    if ok then
                        local o = { text = text, done = done and true or false }
                        if type(text) == "string" then
                            local have, need = text:match("(%d+)%s*/%s*(%d+)")
                            if have then o.have, o.need = tonumber(have), tonumber(need) end
                        end
                        objs[#objs + 1] = o
                    end
                end
            end
            if #objs > 0 then q.objectives = objs end
            list[#list + 1] = q
        end
    end
    probe.quests = { count = countPath, entries = #list, ready = ready, objectives = objPath }
    r.quests = { captured = true, entries = list }
end

-- The game's own quest map points (what its quest POI shows for an active quest), kept per character for quests in
-- the log only. Data only: the three APIs below just READ. The probe says which exist (a count, -1 when missing).
local MAX_POI = 60
local function poi_xy(x, y)
    x, y = tonumber(x), tonumber(y)
    if not x or not y or x < 0 or y < 0 or (x == 0 and y == 0) then return nil end
    return round(math.min(x, 1) * 100, 1), round(math.min(y, 1) * 100, 1)
end

function readers.questpoi(r)
    local Q = C_QuestLog
    local hasMap = Q and type(Q.GetQuestsOnMap) == "function"
    local hasWay = Q and (type(Q.GetNextWaypoint) == "function" or type(Q.GetNextWaypointForMap) == "function")
    local hasLegacy = type(QuestPOIGetIconInfo) == "function"
    local probe = probe_of(r)
    probe.poi = { onMap = hasMap and 0 or -1, waypoint = hasWay and 0 or -1, legacy = hasLegacy and 0 or -1 }
    if not (r.quests and r.quests.captured) then return end -- no log read yet: nothing to prune against
    local inLog = {}
    for _, q in ipairs(r.quests.entries or {}) do inLog[q.id] = true end
    local old = type(r.questPOI) == "table" and r.questPOI or {}
    local out, n, now = {}, 0, time()
    for id, e in pairs(old) do
        if inLog[id] and type(e) == "table" and n < MAX_POI then out[id] = e; n = n + 1 end
    end
    local pmap = WC.PlayerPos and (WC.PlayerPos()) or nil
    local found = {}
    local function put(id, map, x, y, oi)
        x, y = poi_xy(x, y)
        map = tonumber(map)
        if not (id and inLog[id] and x and map) or found[id] then return end
        if not out[id] and n >= MAX_POI then return end
        if not out[id] then n = n + 1 end
        found[id] = true
        out[id] = { map = map, x = x, y = y, seenAt = now, objectiveIndex = tonumber(oi) }
    end
    if hasMap and pmap then
        local list = qcall(Q.GetQuestsOnMap, pmap)
        if type(list) == "table" then
            for _, p in ipairs(list) do
                if type(p) == "table" then put(tonumber(p.questID), pmap, p.x, p.y); probe.poi.onMap = probe.poi.onMap + 1 end
            end
        end
    end
    for _, q in ipairs(r.quests.entries or {}) do
        local id = q.id
        if not found[id] and hasWay then
            local map, x, y
            if type(Q.GetNextWaypoint) == "function" then
                local ok, a, b, c = pcall(Q.GetNextWaypoint, id)
                if ok then map, x, y = a, b, c end
            end
            if type(map) == "table" then map, x, y = map.mapID, map.x, map.y end
            if not map and pmap and type(Q.GetNextWaypointForMap) == "function" then
                local ok, a, b = pcall(Q.GetNextWaypointForMap, id, pmap)
                if ok then
                    if type(a) == "table" then x, y = a.x, a.y else x, y = a, b end
                    map = pmap
                end
            end
            if map then
                put(id, map, x, y)
                if found[id] then probe.poi.waypoint = probe.poi.waypoint + 1 end
            end
        end
        if not found[id] and hasLegacy and pmap then
            local ok, _, x, y, obj = pcall(QuestPOIGetIconInfo, id)
            if ok then
                put(id, pmap, x, y, obj)
                if found[id] then probe.poi.legacy = probe.poi.legacy + 1 end
            end
        end
        -- The client shows no point on this map now: a point we kept for it here is stale.
        if not found[id] and out[id] and pmap and out[id].map == pmap and (hasMap or hasWay or hasLegacy) then
            out[id] = nil
        end
    end
    r.questPOI = out
    -- The live plan follows the point: refresh it now, never letting a failure reach the capture.
    if WC.PlanLiveRefresh then
        local ok, changed = pcall(WC.PlanLiveRefresh)
        if ok and changed and WC.RefreshPlan then pcall(WC.RefreshPlan) end
    end
end

-- The captured map point of a quest in the log: { map, x, y (0-100), seenAt, objectiveIndex } or nil.
function WC.CapturedPOI(questID)
    local r = record()
    local t = r and type(r.questPOI) == "table" and r.questPOI or nil
    local e = t and t[questID]
    return type(e) == "table" and e or nil
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

local MAX_NODES = 200

-- Calls fn; its results when it worked, nil when it is missing or failed.
local function try(fn, ...)
    if type(fn) ~= "function" then return nil end
    local out = { pcall(fn, ...) }
    if not table.remove(out, 1) then return nil end
    return unpack(out, 1, 6)
end

-- Legacy tabs: GetTalentTabInfo is (name, icon, pointsSpent, ...) here; a client that leads with an id gives
-- (id, name, description, icon, pointsSpent, ...), which is told apart by the type of the first return.
local function talents_legacy()
    if not (GetNumTalentTabs and GetTalentTabInfo and GetNumTalents and GetTalentInfo) then return nil end
    local trees = {}
    for t = 1, try(GetNumTalentTabs) or 0 do
        local a, b, c, d, e = try(GetTalentTabInfo, t)
        local name, spent
        if type(a) == "number" then name, spent = b, e else name, spent = a, c end
        local tree = { tree = WC.Clean(name), points = tonumber(WC.Clean(spent)), nodes = {} }
        for i = 1, math.min(try(GetNumTalents, t) or 0, MAX_NODES) do
            local nname, _, _, _, rank, max = try(GetTalentInfo, t, i)
            if nname then tree.nodes[#tree.nodes + 1] = { name = nname, rank = rank or 0, max = max or 0 } end
        end
        trees[#trees + 1] = tree
    end
    return trees
end

-- The talent tree system (C_ClassTalents for the active config, C_Traits for trees, nodes and entries).
local function active_config()
    if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID) then return nil end
    return try(C_ClassTalents.GetActiveConfigID)
end

-- A spell's name: C_Spell.GetSpellName, else C_Spell.GetSpellInfo(...).name, else the global GetSpellInfo.
local function spell_name(id)
    if not id then return nil end
    local C = C_Spell
    local name = C and try(C.GetSpellName, id)
    if name == nil and C and C.GetSpellInfo then
        local info = try(C.GetSpellInfo, id)
        name = type(info) == "table" and info.name or nil
    end
    if name == nil and GetSpellInfo then name = (try(GetSpellInfo, id)) end
    return WC.Clean(name)
end

-- The class tree's name when GetTreeInfo gives none: the specialization's own name, only when the config has one tree.
local function spec_tree_name()
    local S = C_SpecializationInfo
    if not (S and S.GetSpecialization and S.GetSpecializationInfo) then return nil end
    local idx = try(S.GetSpecialization)
    if type(idx) ~= "number" then return nil end
    local _, name = try(S.GetSpecializationInfo, idx)
    return WC.Clean(name)
end

local function talents_traits()
    local T = C_Traits
    if not (T and T.GetConfigInfo and T.GetTreeNodes and T.GetNodeInfo) then return nil end
    local config = active_config()
    if not config then return {} end
    local info = try(T.GetConfigInfo, config)
    local trees = {}
    local treeIDs = type(info) == "table" and info.treeIDs or {}
    for _, treeID in ipairs(treeIDs) do
        local tinfo = T.GetTreeInfo and try(T.GetTreeInfo, config, treeID)
        local tname = type(tinfo) == "table" and WC.Clean(tinfo.name or tinfo.treeName) or nil
        if tname == nil and #treeIDs == 1 then tname = spec_tree_name() end
        local tree = { tree = tname, points = 0, nodes = {} }
        for _, nodeID in ipairs(try(T.GetTreeNodes, treeID) or {}) do
            if #tree.nodes >= MAX_NODES then break end
            local node = try(T.GetNodeInfo, config, nodeID)
            if type(node) == "table" and (node.maxRanks or 0) > 0 then
                local entry = node.activeEntry and node.activeEntry.entryID or (node.entryIDs and node.entryIDs[1])
                local name, spell
                local einfo = entry and T.GetEntryInfo and try(T.GetEntryInfo, config, entry)
                local def = type(einfo) == "table" and einfo.definitionID and T.GetDefinitionInfo and try(T.GetDefinitionInfo, einfo.definitionID)
                if type(def) == "table" then
                    spell = tonumber(WC.Clean(def.spellID))
                    name = WC.Clean(def.overrideName)
                    if name == nil or name == "" then name = spell_name(spell) end
                end
                local rank = tonumber(WC.Clean(node.activeRank)) or 0
                tree.points = tree.points + rank
                local row = { node = tonumber(WC.Clean(nodeID)), entry = tonumber(WC.Clean(entry)), spell = spell,
                    rank = rank, max = tonumber(WC.Clean(node.maxRanks)) or 0,
                    posX = tonumber(WC.Clean(node.posX)), posY = tonumber(WC.Clean(node.posY)) }
                if type(name) == "string" and name ~= "" then row.name = name end
                tree.nodes[#tree.nodes + 1] = row
            end
        end
        trees[#trees + 1] = tree
    end
    return trees
end

-- Another talent API the client may carry: the specialization list (a count only, nothing recorded from it).
local function talents_spec()
    local S = C_SpecializationInfo
    if not (S and S.GetNumSpecializations) then return nil end
    return { n = try(S.GetNumSpecializations) or 0 }
end

-- Unspent talent points: UnitCharacterPoints first, then GetUnspentTalentPoints, then the trait currencies.
local function unspent_points(probe)
    local counts = {}
    probe.points = counts
    local v
    if UnitCharacterPoints then
        v = tonumber(WC.Clean((try(UnitCharacterPoints, "player"))))
        counts.unitCharacterPoints = v and 1 or 0
    else
        counts.unitCharacterPoints = -1
    end
    if v == nil and GetUnspentTalentPoints then
        v = tonumber(WC.Clean((try(GetUnspentTalentPoints))))
        counts.getUnspentTalentPoints = v and 1 or 0
    elseif v == nil then
        counts.getUnspentTalentPoints = -1
    end
    if v == nil then
        local T, config = C_Traits, active_config()
        if T and T.GetTreeCurrencyInfo and T.GetConfigInfo and config then
            local info = try(T.GetConfigInfo, config)
            local total, found = 0, false
            for _, treeID in ipairs(type(info) == "table" and info.treeIDs or {}) do
                for _, cur in ipairs(try(T.GetTreeCurrencyInfo, config, treeID, false) or {}) do
                    local q = tonumber(WC.Clean(cur.quantity))
                    if q then total, found = total + q, true end
                end
            end
            if found then v = total end
            counts.traitCurrency = found and 1 or 0
        else
            counts.traitCurrency = -1
        end
    end
    return v
end

function readers.talents(r)
    local probe = probe_of(r)
    local counts = {}
    probe.talents = counts
    local legacy, traits, spec = talents_legacy(), talents_traits(), talents_spec()
    counts.legacy = legacy and #legacy or -1
    counts.traits = traits and #traits or -1
    counts.specialization = spec and spec.n or -1
    local function nodecount(trees)
        local n = 0
        for _, t in ipairs(trees or {}) do n = n + #t.nodes end
        return n
    end
    counts.legacyNodes = legacy and nodecount(legacy) or -1
    counts.traitsNodes = traits and nodecount(traits) or -1
    local named, withSpell = 0, 0
    for _, t in ipairs(traits or {}) do
        for _, n in ipairs(t.nodes) do
            if n.name then named = named + 1 end
            if n.spell then withSpell = withSpell + 1 end
        end
    end
    counts.named = named
    counts.withSpell = withSpell
    local picked = {}
    if legacy and #legacy > 0 and counts.legacyNodes > 0 then picked = legacy
    elseif traits and #traits > 0 and counts.traitsNodes > 0 then picked = traits end
    counts.used = picked == legacy and #picked > 0 and "legacy" or (#picked > 0 and "traits" or "none")
    r.talents = picked
    local pts = unspent_points(probe)
    if pts then r.talentPoints = pts end
end

-- What the client reports about the character's stats, as it reports it (the numbers its own tooltips use).
-- Every API is looked up at run time and skipped when this client lacks it, and nothing is computed here: a
-- per-point effect is stored only when the client exposes a getter for it.
local STAT_INDEX = { str = 1, agi = 2, sta = 3, int = 4, spi = 5 }
local SPELL_SCHOOLS = { 2, 3, 4, 5, 6, 7 } -- holy, fire, nature, frost, shadow, arcane

-- Calls a client function that may be missing or fail; each result is cleaned, and only numbers are kept.
local function nums(fn, ...)
    if type(fn) ~= "function" then return end
    local out = { pcall(fn, ...) }
    if not table.remove(out, 1) then return end
    for i = 1, #out do
        local v = WC.Clean(out[i])
        out[i] = type(v) == "number" and v == v and v or nil
    end
    return unpack(out, 1, 5)
end

local function put(t, k, v) if v ~= nil then t[k] = v end end

function readers.stats(r)
    local s = { seenAt = time(), level = WC.Clean(UnitLevel and UnitLevel("player")) }
    local stats = {}
    for key, i in pairs(STAT_INDEX) do
        local first, total, pos, neg = nums(UnitStat, "player", i)
        -- The first return on this client is the effective total, so base = total - pos - neg (neg is reported negative).
        local base = total and (total - (pos or 0) - (neg or 0)) or first
        if base or total then stats[key] = { base = base, total = total, pos = pos, neg = neg } end
    end
    s.stats = stats
    put(s, "healthMax", (nums(UnitHealthMax, "player")))
    put(s, "manaMax", (nums(UnitPowerMax, "player", 0)))
    local _, armor = nums(UnitArmor, "player")
    put(s, "armor", armor)
    local schools, best = {}, nil
    for _, school in ipairs(SPELL_SCHOOLS) do
        local v = nums(GetSpellCritChance, school)
        if v then
            schools[school] = v
            best = (best == nil or v > best) and v or best
        end
    end
    if best then s.spellCrit = { max = best, schools = schools } end
    put(s, "meleeCrit", (nums(GetCritChance)))
    put(s, "rangedCrit", (nums(GetRangedCritChance)))
    put(s, "dodge", (nums(GetDodgeChance)))
    put(s, "parry", (nums(GetParryChance)))
    put(s, "block", (nums(GetBlockChance)))
    local base, casting = nums(GetManaRegen)
    if base or casting then s.manaRegen = { base = base, casting = casting } end
    local ab, ap, an = nums(UnitAttackPower, "player")
    if ab then s.attackPower = ab + (ap or 0) + (an or 0) end
    local rb, rp, rn = nums(UnitRangedAttackPower, "player")
    if rb then s.rangedAttackPower = rb + (rp or 0) + (rn or 0) end
    local bonus = {}
    local dmg
    for _, school in ipairs(SPELL_SCHOOLS) do
        local v = nums(GetSpellBonusDamage, school)
        if v and (dmg == nil or v > dmg) then dmg = v end
    end
    put(bonus, "damage", dmg)
    put(bonus, "healing", (nums(GetSpellBonusHealing)))
    if next(bonus) then s.spellBonus = bonus end
    local per = {} -- the client's own per-point effects, only those it exposes
    put(per, "spellCritFromInt", (nums(GetSpellCritChanceFromIntellect, "player")))
    put(per, "critFromAgi", (nums(GetCritChanceFromAgility, "player")))
    put(per, "manaRegenFromSpi", (nums(GetUnitManaRegenRateFromSpirit, "player")))
    put(per, "healthRegenFromSpi", (nums(GetUnitHealthRegenRateFromSpirit, "player")))
    if next(per) then s.perPoint = per end
    r.stats = s
end

-- Every skill line the client lists, in order: { name, header, rank, max }. The modern client's C_SkillInfo
-- returns a table per line; the legacy globals return positional values. Values go through WC.Clean.
local function pick(t, ...)
    for i = 1, select("#", ...) do
        local v = WC.Clean(t[select(i, ...)])
        if v ~= nil then return v end
    end
end

function WC.ReadSkillLines()
    local out = {}
    local S = C_SkillInfo
    if S and S.GetNumSkillLines and S.GetSkillLineInfo then
        local n = WC.Clean(S.GetNumSkillLines())
        if type(n) == "number" and n > 0 then
            for i = 1, n do
                local info = S.GetSkillLineInfo(i)
                if type(info) == "table" then
                    out[#out + 1] = {
                        name = pick(info, "skillName", "skillLineName", "name"),
                        header = pick(info, "isHeader", "header") and true or false,
                        rank = pick(info, "skillRank", "rank") or 0,
                        max = pick(info, "maxSkillRank", "skillMaxRank", "maxRank") or 0,
                    }
                end
            end
            if #out > 0 then return out end
        end
    end
    if GetNumSkillLines and GetSkillLineInfo then
        for i = 1, WC.Clean(GetNumSkillLines()) or 0 do
            local name, header, _, rank, _, _, max = GetSkillLineInfo(i)
            out[#out + 1] = { name = WC.Clean(name), header = WC.Clean(header) and true or false,
                rank = WC.Clean(rank) or 0, max = WC.Clean(max) or 0 }
        end
    end
    return out
end

function readers.skills(r)
    local list, seen = {}, {}
    local group
    local primary = TRADE_SKILLS or "Professions"
    local secondary = SECONDARY_SKILLS or "Secondary Skills"
    for _, line in ipairs(WC.ReadSkillLines()) do
        if line.header then
            group = line.name
        elseif type(line.name) == "string" then
            local s = { name = line.name, rank = line.rank, max = line.max, group = group }
            if group == primary or group == secondary or group == "Professions" or group == "Secondary Skills" then
                s.profession = true
            end
            local prev = seen[line.name]
            if prev then
                -- The client can list a line twice (or under two headers): keep one, with the best rank and cap.
                if (s.rank or 0) > (prev.rank or 0) then prev.rank = s.rank end
                if (s.max or 0) > (prev.max or 0) then prev.max = s.max end
                if s.profession and not prev.profession then prev.profession, prev.group = true, s.group end
            else
                seen[line.name] = s
                list[#list + 1] = s
            end
        end
    end
    r.skills = list
end

-- Spell book item types: Spell 1 is a known spell; future (2), pet action (3) and flyout (4) entries are skipped.
local function spellbook_modern(ids, seen)
    local SC = C_SpellBook
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
    for line = 1, SC.GetNumSpellBookSkillLines() or 0 do
        local li = SC.GetSpellBookSkillLineInfo(line)
        if li and not li.offSpecID then
            local first = li.itemIndexOffset or 0
            for index = first + 1, first + (li.numSpellBookItems or 0) do
                if #ids >= MAX_SPELLS then return end
                local info = SC.GetSpellBookItemInfo(index, bank)
                if info and not info.isOffSpec and info.itemType == 1 then
                    local id = tonumber(WC.Clean(info.spellID))
                    if id and not seen[id] then seen[id] = true; ids[#ids + 1] = id end
                end
            end
        end
    end
end

-- The classic spell book: GetSpellBookItemInfo(i, "spell") gives ("SPELL", id), a table on newer builds.
local function spellbook_classic(ids, seen)
    for tab = 1, try(GetNumSpellTabs) or 0 do
        local _, _, offset, count = try(GetSpellTabInfo, tab)
        for index = (offset or 0) + 1, (offset or 0) + (count or 0) do
            if #ids >= MAX_SPELLS then return end
            local a, b = try(GetSpellBookItemInfo, index, "spell")
            local id
            if type(a) == "table" then
                if a.itemType == 1 then id = a.spellID end
            elseif a == "SPELL" then
                id = b
            end
            id = tonumber(WC.Clean(id))
            if id and not seen[id] then seen[id] = true; ids[#ids + 1] = id end
        end
    end
end

-- The oldest path: the link of each spell book slot.
local function spellbook_links(ids, seen)
    for tab = 1, try(GetNumSpellTabs) or 0 do
        local _, _, offset, count = try(GetSpellTabInfo, tab)
        for index = (offset or 0) + 1, (offset or 0) + (count or 0) do
            if #ids >= MAX_SPELLS then return end
            local f = link_fields(try(GetSpellLink, index, "spell"), "spell")
            local id = f and f[1]
            if id and not seen[id] then seen[id] = true; ids[#ids + 1] = id end
        end
    end
end

function readers.spells(r)
    local probe = probe_of(r)
    local counts = {}
    probe.spells = counts
    local paths = {
        { "modern", C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookSkillLineInfo
            and C_SpellBook.GetSpellBookItemInfo and function(ids, seen) return pcall(spellbook_modern, ids, seen) end },
        { "classic", GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemInfo
            and function(ids, seen) return pcall(spellbook_classic, ids, seen) end },
        { "links", GetNumSpellTabs and GetSpellTabInfo and GetSpellLink
            and function(ids, seen) return pcall(spellbook_links, ids, seen) end },
    }
    local picked
    for _, p in ipairs(paths) do
        if p[2] then
            local ids = {}
            p[2](ids, {})
            counts[p[1]] = #ids
            if not picked and #ids > 0 then picked = ids; counts.used = p[1] end
        else
            counts[p[1]] = -1
        end
    end
    counts.used = counts.used or "none"
    counts.isSpellKnown = (IsSpellKnown or IsPlayerSpell) and 1 or -1 -- present or not; no class id list to try yet
    picked = picked or {}
    table.sort(picked)
    r.spells = picked
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

local MAX_REAGENTS = 8

local function recipe_entry(name, kind, l)
    l = WC.Clean(l)
    local spell = link_fields(l, "enchant") or link_fields(l, "spell")
    local item = link_fields(l, "item")
    return { name = WC.Clean(name), id = spell and spell[1] or (item and item[1]), item = item and item[1] or nil,
        difficulty = DIFFICULTY[WC.Clean(kind)] }
end

-- Classic path: the reagents of one recipe by index, { { item = id, count = n } }, at most MAX_REAGENTS.
local function classic_reagents(i, numFn, infoFn, linkFn)
    if not (numFn and infoFn and linkFn) then return nil end
    local out = {}
    for j = 1, math.min(tonumber(WC.Clean(numFn(i))) or 0, MAX_REAGENTS) do
        local count = WC.Clean(select(3, infoFn(i, j)))
        local id = item_id(WC.Clean(linkFn(i, j)))
        if id then out[#out + 1] = { item = id, count = type(count) == "number" and count or 1 } end
    end
    if #out > 0 then return out end
end

local function store_recipes(r, profession, out)
    if type(profession) ~= "string" or profession == "" or profession == "UNKNOWN" then return end
    r.recipes = r.recipes or {}
    r.recipes[profession] = { seenAt = time(), entries = out }
end

local function read_recipes(r, profession, count, info, link, reagents)
    local out = {}
    for i = 1, count or 0 do
        if #out >= MAX_RECIPES then break end
        if WC.SeenRaw and i <= 3 then WC.SeenRaw("tradeskill", "GetTradeSkillInfo", info(i, true)) end
        local name, kind = info(i)
        if type(name) == "string" and kind ~= "header" and kind ~= "subheader" then
            local e = recipe_entry(name, kind, link and link(i))
            if reagents then
                local ok, list = pcall(reagents, i)
                if ok then e.reagents = list
                elseif WC.SeenError then WC.SeenError("tradeskill", list) end
            end
            if e.item then e.makes = { item = e.item, count = 1 } end
            out[#out + 1] = e
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
    if T.GetBaseProfessionInfo then
        local p = T.GetBaseProfessionInfo()
        if type(p) == "table" then
            local lvl, mx = WC.Clean(p.skillLevel), WC.Clean(p.maxSkillLevel)
            if type(profession) == "string" and type(lvl) == "number" then
                r.skills = r.skills or {}
                local found
                for _, sk in ipairs(r.skills) do if sk.name == profession then found = sk end end
                if not found then
                    found = { name = profession, group = "Professions", profession = true }
                    r.skills[#r.skills + 1] = found
                end
                found.rank = lvl
                if type(mx) == "number" then found.max = mx end
            end
        end
    end
    local out = {}
    for _, id in ipairs(T.GetAllRecipeIDs() or {}) do
        if #out >= MAX_RECIPES then break end
        local info = T.GetRecipeInfo(id)
        if WC.SeenRaw and #out < 3 and type(info) == "table" then
            WC.SeenRaw("tradeskill", "C_TradeSkillUI.GetRecipeInfo", id, info.name, info.learned, info.relativeDifficulty, info.difficulty)
        end
        if type(info) == "table" and info.learned ~= false and type(WC.Clean(info.name)) == "string" then
            local item = WC.Clean(info.itemID)
            local e = { name = WC.Clean(info.name), id = WC.Clean(info.recipeID) or id, item = item,
                difficulty = DIFFICULTY[WC.Clean(info.relativeDifficulty)] or DIFFICULTY[WC.Clean(info.difficulty)] }
            local learnAt = WC.Clean(info.learnedAt or info.skillLineCurrentLevel)
            if type(learnAt) == "number" and learnAt > 0 then e.learnSkill = learnAt end
            if T.GetRecipeSchematic then
                local okS, schem = pcall(T.GetRecipeSchematic, id, false)
                if not okS then
                    if WC.SeenError then WC.SeenError("tradeskill", schem) end
                elseif type(schem) == "table" then
                    local made = schem.outputItemID
                    made = WC.Clean(made)
                    if type(made) == "number" and made > 0 then
                        e.item = e.item or made
                        e.makes = { item = made, count = WC.Clean(schem.quantityMin) or 1 }
                    end
                    local reag = {}
                    for _, slot in ipairs(type(schem.reagentSlotSchematics) == "table" and schem.reagentSlotSchematics or {}) do
                        if #reag >= MAX_REAGENTS then break end
                        local first = type(slot) == "table" and type(slot.reagents) == "table" and slot.reagents[1]
                        local rid = type(first) == "table" and WC.Clean(first.itemID)
                        local cnt = type(slot) == "table" and WC.Clean(slot.quantityRequired)
                        if type(rid) == "number" and rid > 0 then
                            reag[#reag + 1] = { item = rid, count = type(cnt) == "number" and cnt or 1 }
                        end
                    end
                    if #reag > 0 then e.reagents = reag end
                end
            end
            out[#out + 1] = e
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
                end, GetTradeSkillItemLink,
                function(i) return classic_reagents(i, GetTradeSkillNumReagents, GetTradeSkillReagentInfo, GetTradeSkillReagentItemLink) end)
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
        end, GetCraftItemLink,
        function(i) return classic_reagents(i, GetCraftNumReagents, GetCraftReagentInfo, GetCraftReagentItemLink) end)
end

-- The order matters little; each part is read on its own so one failing read never costs the rest.
local ORDER = { "identity", "money", "location", "equipment", "bags", "bank", "quests", "questpoi", "completed", "talents",
    "stats", "skills", "spells", "reputations", "tradeskill", "craft" }

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
            local ok, err = pcall(readers[part], r)
            if not ok and WC.SeenError then WC.SeenError(part, err) end
            any = true
        end
    end
    if any then
        WC.CleanTree(r) -- nothing secret is ever saved, whatever a read returned
        r.capturedAt = time()
    end
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
    PLAYER_ENTERING_WORLD = { "identity", "money", "location", "equipment", "bags", "quests", "questpoi", "completed", "talents", "stats", "skills", "spells", "reputations" },
    PLAYER_LEVEL_UP = { "identity", "money", "talents", "stats", "spells", "skills" },
    PLAYER_XP_UPDATE = { "money" },
    PLAYER_MONEY = { "money" },
    ZONE_CHANGED_NEW_AREA = { "location", "questpoi" },
    ZONE_CHANGED = { "location", "questpoi" },
    HEARTHSTONE_BOUND = { "location" },
    PLAYER_EQUIPMENT_CHANGED = { "equipment", "stats" },
    BAG_UPDATE_DELAYED = { "bags" },
    QUEST_LOG_UPDATE = { "quests", "questpoi" },
    QUEST_ACCEPTED = { "quests", "questpoi" },
    QUEST_REMOVED = { "quests", "questpoi" },
    QUEST_TURNED_IN = { "quests", "completed", "questpoi" },
    SKILL_LINES_CHANGED = { "skills" },
    CHARACTER_POINTS_CHANGED = { "talents", "stats" },
    PLAYER_TALENT_UPDATE = { "talents" },
    SPELLS_CHANGED = { "spells" },
    LEARNED_SPELL_IN_TAB = { "spells" },
    LEARNED_SPELL_IN_SKILL_LINE = { "spells" },
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
for _, ev in ipairs({ "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "TRADE_SKILL_CLOSE", "CRAFT_CLOSE", "PLAYER_REGEN_ENABLED",
    "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", "GET_ITEM_INFO_RECEIVED" }) do
    pcall(frame.RegisterEvent, frame, ev)
end
local RECIPE_DELAY = 1 -- seconds after TRADE_SKILL_SHOW that the recipes are read again (the list can arrive late)
frame:SetScript("OnEvent", function(_, event, a)
    if event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" or event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        if WC.SeenWindowOfType and WC.SeenWindowOfType(a) == "bank" then
            bankOpen = event:find("SHOW") ~= nil
            if bankOpen then WC.CaptureMark("bank") end
        end
    elseif event == "BANKFRAME_OPENED" then
        bankOpen = true
        WC.CaptureMark("bank")
    elseif event == "BANKFRAME_CLOSED" then
        bankOpen = false
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        -- Only when an earlier read found an item uncached; that read set the flag, this one may set it again.
        if pendingInfo then
            pendingInfo = false
            WC.CaptureMark("equipment", "bags")
            if bankOpen then WC.CaptureMark("bank") end
        end
    elseif event == "TRADE_SKILL_CLOSE" then
        windowOpen.tradeskill = false
    elseif event == "CRAFT_CLOSE" then
        windowOpen.craft = false
    elseif event == "PLAYER_REGEN_ENABLED" then
        if next(dirty) then schedule() end
    else
        local part = WINDOW_PART[event]
        if part and not windowOpen[part] then return end
        if event == "TRADE_SKILL_SHOW" then
            windowOpen.tradeskill = true
            if C_Timer and C_Timer.After then
                C_Timer.After(RECIPE_DELAY, function() if windowOpen.tradeskill then WC.CaptureMark("tradeskill") end end)
            end
        end
        if event == "CRAFT_SHOW" then windowOpen.craft = true end
        WC.CaptureMark(unpack(EVENTS[event]))
        if event == "BAG_UPDATE_DELAYED" and bankOpen then WC.CaptureMark("bank") end
    end
end)
