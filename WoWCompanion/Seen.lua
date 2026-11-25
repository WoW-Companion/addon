-- WoW Companion: remembers what the player sees, in WoWCompanionDB.observed (format: docs/observed-format.md):
-- trainer offers, vendor stock, what gathering and fishing yield where, and who gives quests. Strictly read-only:
-- only the client's read APIs are called (each is on tests/guard.lua's allowlist), nothing is bought, learned,
-- clicked or sent, and no tooltip is scanned. Data leaves the game only when the client saves; we never ask for it.
-- Everything is bounded (caps below, oldest dropped) and waits for the player to be out of combat.

local WC = WoWCompanion

WC.SEEN_TRAINER_CAP = 300   -- trainers kept
WC.SEEN_VENDOR_CAP = 300    -- vendors kept
WC.SEEN_GATHER_CAP = 2000   -- aggregate gathering rows kept
WC.SEEN_OFFER_CAP = 200     -- offers or items kept per trainer or vendor
WC.SEEN_ITEM_CAP = 40       -- distinct items kept per gathering row
local CELL = 5              -- a gathering cell is 5% of the map square
local GIVER_KEEP = 120      -- seconds a quest giver seen at QUEST_DETAIL still counts at QUEST_ACCEPTED
local WINDOWS = { herb = 20, mine = 20, skin = 20, fish = 45 } -- seconds a gathering cast waits for its loot

-- The gathering casts, by spell id (every rank) and by the English spell name as a fallback.
local KIND_BY_SPELL = {}
for kind, ids in pairs({
    herb = { 2366, 2368, 3570, 11993, 28695, 50300 },
    mine = { 2575, 2576, 3564, 10248, 29354, 50310 },
    skin = { 8613, 8617, 8618, 10768, 32678, 50305 },
    fish = { 7620, 7731, 7732, 18248, 33095, 51294 },
}) do for _, id in ipairs(ids) do KIND_BY_SPELL[id] = kind end end
local KIND_BY_NAME = { ["Herb Gathering"] = "herb", Mining = "mine", Skinning = "skin", Fishing = "fish" }
local SKILL_NAME = { herb = "Herbalism", mine = "Mining", skin = "Skinning", fish = "Fishing" }

local cast          -- { kind, t }: the player's own gathering cast waiting for loot
local giver         -- { id, name, map, x, y, t }: the last quest giver whose dialog opened
local open = {}     -- window name -> true while the trainer or merchant window is up
local pending = {}  -- window name -> true: opened in combat, read when combat ends

local function round1(v) return math.floor(v * 10 + 0.5) / 10 end

local function store()
    local o = WC.db and WC.db.observed
    if type(o) ~= "table" then
        if not WC.db then return nil end
        o = { version = WC.OBSERVED_VERSION, events = {} }
        WC.db.observed = o
    end
    if type(o.events) ~= "table" then o.events = {} end
    o.version = WC.OBSERVED_VERSION
    return o
end

local function on()
    return WC.db ~= nil and WC.Setting("keepObserved") == true
end

local function section(name)
    local o = store()
    if not o then return nil end
    if type(o[name]) ~= "table" then o[name] = {} end
    return o[name]
end

local function trim(list, cap)
    while #list > cap do table.remove(list, 1) end
end

-- npc id from a creature GUID ("Creature-0-realm-instance-zone-npcid-spawn").
local function npc_id(guid)
    if type(guid) ~= "string" then return nil end
    return tonumber(guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
end

local function item_id(link)
    if type(link) ~= "string" then return nil end
    return tonumber(link:match("item:(%d+)"))
end

local function spell_id(link)
    if type(link) ~= "string" then return nil end
    return tonumber(link:match("spell:(%d+)") or link:match("enchant:(%d+)"))
end

local function here()
    local map, x, y
    if WC.PlayerPos then map, x, y = WC.PlayerPos() end
    if map and x and y then return map, round1(x), round1(y) end
    return map
end

-- Who the player is talking to (the "npc" unit): { id, name, map, x, y, reaction, faction } or nil.
local function talking_to()
    if not (UnitGUID and UnitExists and UnitExists("npc")) then return nil end
    local id = npc_id(UnitGUID("npc"))
    if not id then return nil end
    local g = { id = id }
    local name = UnitName and UnitName("npc")
    if type(name) == "string" and name ~= "" then g.name = name end
    g.map, g.x, g.y = here()
    if UnitReaction then g.reaction = UnitReaction("player", "npc") end
    if UnitFactionGroup then g.faction = UnitFactionGroup("npc") end
    return g
end

local function fill_npc(rec, g)
    rec.npc, rec.name, rec.map, rec.x, rec.y = g.id, g.name, g.map, g.x, g.y
    rec.reaction, rec.faction = g.reaction, g.faction
    rec.t = time()
end

-- Replaces the record for this npc (the list stays oldest first) and drops the oldest beyond the cap.
local function put(list, rec, cap)
    for i, r in ipairs(list) do
        if type(r) == "table" and r.npc == rec.npc then table.remove(list, i) break end
    end
    list[#list + 1] = rec
    trim(list, cap)
end

-- Trainer window: every offer with its cost, skill gate and availability.
function WC.SeenReadTrainer()
    if not (on() and GetNumTrainerServices) then return false end
    local g = talking_to()
    if not g then return false end
    local list = section("trainers")
    if not list then return false end
    local rec = { offers = {} }
    fill_npc(rec, g)
    for i = 1, math.min(GetNumTrainerServices() or 0, WC.SEEN_OFFER_CAP) do
        local name, sub, state = GetTrainerServiceInfo(i)
        if type(name) == "string" and name ~= "" then
            local o = { name = name, state = state }
            if type(sub) == "string" and sub ~= "" then o.rank = sub end
            if GetTrainerServiceCost then o.cost = (GetTrainerServiceCost(i)) end
            if GetTrainerServiceSkillReq then
                local skill, level = GetTrainerServiceSkillReq(i)
                if skill then o.skill, o.skillLevel = skill, level end
            end
            if GetTrainerServiceItemLink then o.spell = spell_id(GetTrainerServiceItemLink(i)) or item_id(GetTrainerServiceItemLink(i)) end
            rec.offers[#rec.offers + 1] = o
        end
    end
    put(list, rec, WC.SEEN_TRAINER_CAP)
    return true
end

-- Merchant window: the stock with prices; one record per vendor, overwritten each time.
function WC.SeenReadMerchant()
    if not (on() and GetMerchantNumItems) then return false end
    local g = talking_to()
    if not g then return false end
    local list = section("vendors")
    if not list then return false end
    local rec = { items = {} }
    fill_npc(rec, g)
    for i = 1, math.min(GetMerchantNumItems() or 0, WC.SEEN_OFFER_CAP) do
        local _, _, price, qty, avail, _, ext = GetMerchantItemInfo(i)
        local id = GetMerchantItemLink and item_id(GetMerchantItemLink(i))
        if id then
            local it = { id = id, price = price, stack = qty }
            if type(avail) == "number" and avail >= 0 then it.limited = avail end
            if ext then it.ext = true end
            rec.items[#rec.items + 1] = it
        end
    end
    put(list, rec, WC.SEEN_VENDOR_CAP)
    return true
end

local function skill_rank(kind)
    if not (GetNumSkillLines and GetSkillLineInfo) then return nil end
    for i = 1, GetNumSkillLines() or 0 do
        local name, header, _, rank = GetSkillLineInfo(i)
        if not header and name == SKILL_NAME[kind] then return rank end
    end
end

-- A gathering or fishing cast by the player starts the clock for the loot that follows.
function WC.SeenCast(unit, ...)
    if unit ~= "player" or not on() then return end
    local kind
    for _, v in ipairs({ ... }) do
        if type(v) == "number" and KIND_BY_SPELL[v] then kind = KIND_BY_SPELL[v] break end
    end
    if not kind and GetSpellInfo then
        for _, v in ipairs({ ... }) do
            if type(v) == "number" then
                local name = GetSpellInfo(v)
                kind = name and KIND_BY_NAME[name]
            elseif type(v) == "string" then
                kind = KIND_BY_NAME[v]
            end
            if kind then break end
        end
    end
    if kind then cast = { kind = kind, t = time() } end
end

-- Loot that opens right after the cast is aggregated per (kind, source, map, cell); any other loot is ignored.
function WC.SeenLoot()
    local c = cast
    cast = nil
    if not (c and on()) then return false end
    if time() - c.t > WINDOWS[c.kind] then return false end
    if InCombatLockdown and InCombatLockdown() then return false end
    if not (GetNumLootItems and GetLootSlotLink) then return false end
    local map, x, y = here()
    if not (map and x and y) then return false end
    local source
    if c.kind == "skin" and UnitExists and UnitExists("target") then
        local n = UnitName and UnitName("target")
        if type(n) == "string" and n ~= "" then source = n end
    end
    local items = {}
    for i = 1, GetNumLootItems() or 0 do
        local id = item_id(GetLootSlotLink(i))
        if id then
            local count = 1
            if GetLootSlotInfo then
                local q = select(3, GetLootSlotInfo(i))
                if type(q) == "number" and q > 0 then count = q end
            end
            items[#items + 1] = { id = id, count = count }
        end
    end
    if #items == 0 then return false end
    local list = section("gathering")
    if not list then return false end
    local cx, cy = math.floor(x / CELL), math.floor(y / CELL)
    local row
    for i, r in ipairs(list) do
        if type(r) == "table" and r.kind == c.kind and r.source == source and r.map == map and r.cx == cx and r.cy == cy then
            row = table.remove(list, i)
            break
        end
    end
    local skill = skill_rank(c.kind)
    if not row then row = { kind = c.kind, source = source, map = map, cx = cx, cy = cy, n = 0, items = {} } end
    row.n = row.n + 1
    row.t = time()
    if skill then
        row.skillMin = math.min(row.skillMin or skill, skill)
        row.skillMax = math.max(row.skillMax or skill, skill)
    end
    for _, it in ipairs(items) do
        local slot = row.items[it.id]
        if not slot and WC.SEEN_ITEM_CAP > 0 then
            local n = 0
            for _ in pairs(row.items) do n = n + 1 end
            if n < WC.SEEN_ITEM_CAP then slot = { count = 0, n = 0 }; row.items[it.id] = slot end
        end
        if slot then slot.count, slot.n = slot.count + it.count, slot.n + 1 end
    end
    list[#list + 1] = row
    trim(list, WC.SEEN_GATHER_CAP)
    return true
end

-- The quest giver whose dialog just opened; QUEST_ACCEPTED may arrive after the window has closed.
function WC.SeenQuestGiver()
    if not on() then return end
    local g = talking_to()
    if g then g.t = time(); giver = g end
end

-- Called by the quest log for an accepted event: gives the giver's id and position (the cache or the open dialog).
function WC.SeenGiverFor(e)
    if not on() then return end
    local g = talking_to()
    if not g and giver and time() - giver.t <= GIVER_KEEP then g = giver end
    if not g then return end
    e.npcId = g.id
    if g.name and not e.npc then e.npc = g.name end
    if g.map then e.npcMap = g.map end
    if g.x and g.y then e.npcX, e.npcY = g.x, g.y end
    giver = nil
end

local READ = { trainer = "SeenReadTrainer", merchant = "SeenReadMerchant" }
local function read(win)
    if not open[win] then return end
    if InCombatLockdown and InCombatLockdown() then pending[win] = true; return end
    pending[win] = nil
    pcall(WC[READ[win]])
end

local frame = CreateFrame("Frame")
for _, ev in ipairs({ "TRAINER_SHOW", "TRAINER_UPDATE", "TRAINER_CLOSED", "MERCHANT_SHOW", "MERCHANT_UPDATE",
    "MERCHANT_CLOSED", "LOOT_OPENED", "QUEST_DETAIL", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_CHANNEL_START",
    "PLAYER_REGEN_ENABLED" }) do
    pcall(frame.RegisterEvent, frame, ev) -- a client without an event just skips it
end
frame:SetScript("OnEvent", function(_, event, a, ...)
    if event == "TRAINER_SHOW" then open.trainer = true; read("trainer")
    elseif event == "TRAINER_UPDATE" then read("trainer")
    elseif event == "TRAINER_CLOSED" then open.trainer, pending.trainer = nil, nil
    elseif event == "MERCHANT_SHOW" then open.merchant = true; read("merchant")
    elseif event == "MERCHANT_UPDATE" then read("merchant")
    elseif event == "MERCHANT_CLOSED" then open.merchant, pending.merchant = nil, nil
    elseif event == "PLAYER_REGEN_ENABLED" then
        for win in pairs(pending) do read(win) end
    elseif event == "LOOT_OPENED" then pcall(WC.SeenLoot)
    elseif event == "QUEST_DETAIL" then pcall(WC.SeenQuestGiver)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" or event == "UNIT_SPELLCAST_CHANNEL_START" then
        pcall(WC.SeenCast, a, ...)
    end
end)
