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
    if not (UnitGUID and UnitExists) then return nil end
    local unit, id
    for _, u in ipairs({ "npc", "target" }) do -- some clients leave "npc" empty while a window is open
        if WC.Clean(UnitExists(u)) then
            id = npc_id(WC.Clean(UnitGUID(u)))
            if id then unit = u break end
        end
    end
    if not id then return nil end
    local g = { id = id }
    local name = WC.Clean(UnitName and UnitName(unit))
    if type(name) == "string" and name ~= "" then g.name = name end
    g.map, g.x, g.y = here()
    if UnitReaction then g.reaction = WC.Clean(UnitReaction("player", unit)) end
    if UnitFactionGroup then g.faction = WC.Clean(UnitFactionGroup(unit)) end
    return g
end

local function fill_npc(rec, g)
    rec.npc, rec.name, rec.map, rec.x, rec.y = g.id, g.name, g.map, g.x, g.y
    rec.reaction, rec.faction = g.reaction, g.faction
    rec.t = time()
end

-- Replaces the record for this npc (the list stays oldest first) and drops the oldest beyond the cap.
local function put(list, rec, cap)
    WC.CleanTree(rec)
    for i, r in ipairs(list) do
        if type(r) == "table" and r.npc == rec.npc then table.remove(list, i) break end
    end
    list[#list + 1] = rec
    trim(list, cap)
end

-- Raw samples: the first RAW_PER_KIND return tuples of each window kind per session are kept, length-capped, under
-- observed.raw.<kind>, so the real client's return order can be verified from a saved file.
local RAW_PER_KIND, RAW_VALUES, RAW_TEXT, RAW_TABLE = 3, 12, 60, 200
local ERR_KEEP, ERR_TEXT = 5, 120
local rawCount = {}

-- A table return as sorted "key=value" text.
local function table_text(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    local out = {}
    for _, k in ipairs(keys) do
        local v = t[k]
        if v == nil then v = t[tonumber(k)] end
        out[#out + 1] = k .. "=" .. tostring(WC.Clean(v))
    end
    return table.concat(out, " "):sub(1, RAW_TABLE)
end

-- A window read that raised an error: kind, time and the message (capped); the last ERR_KEEP are kept under
-- observed.raw.errors, so a read that fails silently can be seen in the saved file.
function WC.SeenError(kind, msg)
    if not on() then return end
    local o = store()
    if not o then return end
    if type(o.raw) ~= "table" then o.raw = {} end
    if type(o.raw.errors) ~= "table" then o.raw.errors = {} end
    o.raw.errors[#o.raw.errors + 1] = { kind = kind, t = time(), msg = tostring(msg):sub(1, ERR_TEXT) }
    trim(o.raw.errors, ERR_KEEP)
end
function WC.SeenRaw(kind, call, ...)
    if not on() then return end
    if (rawCount[kind] or 0) >= RAW_PER_KIND then return end
    local o = store()
    if not o then return end
    rawCount[kind] = (rawCount[kind] or 0) + 1
    if type(o.raw) ~= "table" then o.raw = {} end
    if type(o.raw[kind]) ~= "table" then o.raw[kind] = {} end
    local vals = {}
    for i = 1, math.min(select("#", ...), RAW_VALUES) do
        local v = select(i, ...)
        if type(v) ~= "table" then
            local c = WC.Clean(v)
            if c == nil and v ~= nil then v = "(secret)" else v = c end
        end
        local t = type(v)
        if t == "string" then v = v:sub(1, RAW_TEXT)
        elseif t == "table" then v = table_text(v)
        elseif t ~= "number" and t ~= "boolean" then v = tostring(v) end
        vals[i] = v
    end
    o.raw[kind][#o.raw[kind] + 1] = { call = call, n = select("#", ...), t = time(), vals = vals }
    trim(o.raw[kind], RAW_PER_KIND)
end

local AVAILABILITY = { available = true, unavailable = true, used = true }

-- Sorts one trainer service's returns by type, not by position: a number is an icon, a string that is one of the
-- availability words is the availability, any other string is the rank text. Whatever order the client gives them in.
function WC.SeenClassifyService(...)
    local name, rank, state, icon
    for i = 1, select("#", ...) do
        local v = WC.Clean(select(i, ...))
        if type(v) == "string" and v ~= "" then
            if i == 1 then name = v
            elseif AVAILABILITY[v] then state = state or v
            else rank = rank or v end
        elseif type(v) == "number" and not icon then
            icon = v
        end
    end
    return name, rank, state, icon
end

-- Trainer window: every offer with its cost, level and skill gate and availability.
function WC.SeenReadTrainer()
    if not (on() and GetNumTrainerServices) then return false end
    local g = talking_to()
    if not g then return false end
    local list = section("trainers")
    if not list then return false end
    local rec = { offers = {} }
    fill_npc(rec, g)
    for i = 1, math.min(GetNumTrainerServices() or 0, WC.SEEN_OFFER_CAP) do
        WC.SeenRaw("trainer", "GetTrainerServiceInfo", GetTrainerServiceInfo(i))
        local name, rank, state, icon = WC.SeenClassifyService(GetTrainerServiceInfo(i))
        if name then
            local o = { name = name, rank = rank, state = state, icon = icon }
            if GetTrainerServiceCost then
                local cost = GetTrainerServiceCost(i)
                if type(cost) == "number" then o.cost = cost end
            end
            if GetTrainerServiceLevelReq then
                local lvl = GetTrainerServiceLevelReq(i)
                if type(lvl) == "number" and lvl > 0 then o.level = lvl end
            end
            if GetTrainerServiceSkillReq then
                local skill, level = GetTrainerServiceSkillReq(i)
                if type(skill) == "string" and skill ~= "" then
                    o.skill = skill
                    if type(level) == "number" then o.skillLevel = level end
                end
            end
            if GetTrainerServiceItemLink then
                local ok, l = pcall(GetTrainerServiceItemLink, i)
                if not ok then WC.SeenError("trainer", l) l = nil end
                WC.SeenRaw("trainerlink", "GetTrainerServiceItemLink", l)
                if type(l) == "number" then o.spell = l else o.spell = spell_id(l) or item_id(l) end
            end
            rec.offers[#rec.offers + 1] = o
        end
    end
    put(list, rec, WC.SEEN_TRAINER_CAP)
    return true
end

-- Merchant window: the stock with prices; one record per vendor, overwritten each time. This client's merchant
-- frame is the modern one, so C_MerchantFrame.GetNumItems/GetItemInfo are used when present (GetItemInfo returns a
-- table: name, texture, price, stackCount, numAvailable, hasExtendedCost, ...); otherwise the global tuple
-- GetMerchantItemInfo (name, texture, price, quantity, numAvailable, isUsable, extendedCost). The vendor is always
-- saved, whatever fails; every item is read on its own, and every page (the API is index-based).
local function merchant_count()
    if C_MerchantFrame and C_MerchantFrame.GetNumItems then return C_MerchantFrame.GetNumItems() end
    if GetMerchantNumItems then return GetMerchantNumItems() end
    error("no merchant item count API")
end

-- The extra costs of one merchant item, { { id = item id, count = n } or { currency = currency id, count = n } }
-- (at most COST_SLOTS), or nil when the client gives none. A failing read is recorded and costs only this list.
local COST_SLOTS = 8
local function merchant_costs(i)
    if not (GetMerchantItemCostInfo and GetMerchantItemCostItem) then return nil end
    local ok, n = pcall(GetMerchantItemCostInfo, i)
    if not ok then WC.SeenError("merchant", n) return nil end
    local out = {}
    for j = 1, math.min(tonumber(WC.Clean(n)) or 0, COST_SLOTS) do
        local okj, _, value, link = pcall(GetMerchantItemCostItem, i, j)
        if not okj then WC.SeenError("merchant", value) break end
        value, link = WC.Clean(value), WC.Clean(link)
        if type(link) == "string" and type(value) == "number" then
            local cur = tonumber(link:match("currency:(%d+)"))
            local item = item_id(link)
            if cur then out[#out + 1] = { currency = cur, count = value }
            elseif item then out[#out + 1] = { id = item, count = value } end
        end
    end
    if #out > 0 then return out end
end

local function merchant_item(i)
    local price, qty, avail, ext, id
    local info
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        info = C_MerchantFrame.GetItemInfo(i)
        WC.SeenRaw("merchant", "C_MerchantFrame.GetItemInfo", info)
    elseif GetMerchantItemInfo then
        info = { GetMerchantItemInfo(i) }
        WC.SeenRaw("merchant", "GetMerchantItemInfo", (table.unpack or unpack)(info, 1, 12))
    else
        error("no merchant item info API")
    end
    if type(info) ~= "table" then error("merchant item info is " .. type(info)) end
    if info.price ~= nil or info.name ~= nil or info.stackCount ~= nil then
        price, qty, avail, ext = info.price, info.stackCount, info.numAvailable, info.hasExtendedCost
        id = tonumber(WC.Clean(info.itemID)) or item_id(WC.Clean(info.itemLink))
    else
        price, qty, avail, ext = info[3], info[4], info[5], info[7]
    end
    price, qty, avail, ext = WC.Clean(price), WC.Clean(qty), WC.Clean(avail), WC.Clean(ext)
    if GetMerchantItemID then -- the item id directly, preferred
        local ok, direct = pcall(GetMerchantItemID, i)
        direct = ok and tonumber(WC.Clean(direct)) or nil
        if direct and direct > 0 then id = direct end
    end
    if not id then
        local link
        if GetMerchantItemLink then link = GetMerchantItemLink(i)
        elseif C_MerchantFrame and C_MerchantFrame.GetItemLink then link = C_MerchantFrame.GetItemLink(i) end
        id = item_id(WC.Clean(link))
    end
    if not id then return nil end
    local it = { id = id }
    if type(price) == "number" then it.price = price end
    if type(qty) == "number" then it.stack = qty end
    if type(avail) == "number" and avail >= 0 then it.limited = avail end
    if ext then it.ext = merchant_costs(i) or true end
    return it
end

function WC.SeenReadMerchant()
    if not on() then return false end
    local g = talking_to()
    if not g then WC.SeenError("merchant", "no npc to attribute the vendor to") return false end
    local list = section("vendors")
    if not list then return false end
    local rec = { items = {} }
    fill_npc(rec, g)
    local okN, n = pcall(merchant_count)
    if not okN then WC.SeenError("merchant", n) n = 0 end
    for i = 1, math.min(tonumber(n) or 0, WC.SEEN_OFFER_CAP) do
        local ok, it = pcall(merchant_item, i)
        if not ok then WC.SeenError("merchant", it)
        elseif it then rec.items[#rec.items + 1] = it end
    end
    put(list, rec, WC.SEEN_VENDOR_CAP)
    return true
end

WC.SEEN_FLIGHT_CAP = 300 -- flight masters kept

-- Taxi window: only the flight master (npc, name, where), never the node list.
function WC.SeenReadFlight()
    if not on() then return false end
    local g = talking_to()
    if not g then WC.SeenError("taxi", "no npc to attribute the flight master to") return false end
    local list = section("flightmasters")
    if not list then return false end
    local rec = {}
    fill_npc(rec, g)
    put(list, rec, WC.SEEN_FLIGHT_CAP)
    return true
end

WC.SEEN_NODE_CAP = 80 -- known flight points kept per character

-- Flight path states: Enum.FlightPathState at runtime when the client has it, else its documented numbers
-- (0 current, 1 reachable, 2 unreachable). Classic's TaxiNodeGetType says "CURRENT", "REACHABLE", "DISTANT", "NONE".
local function node_state(v)
    v = WC.Clean(v)
    if type(v) == "string" then
        v = v:lower()
        if v == "current" or v == "reachable" then return v end
        return nil
    end
    if type(v) ~= "number" then return nil end
    local E = Enum and Enum.FlightPathState
    if type(E) == "table" then
        if v == E.Current then return "current" end
        if v == E.Reachable then return "reachable" end
        return nil
    end
    if v == 0 then return "current" elseif v == 1 then return "reachable" end
end

local function node_xy(x, y)
    x, y = WC.Clean(x), WC.Clean(y)
    if type(x) == "number" and type(y) == "number" then return round1(x * 100), round1(y * 100) end
end

-- The nodes the open taxi map shows, as { id, name, map, x, y, state }: the modern C_TaxiMap list when the client
-- has it, else the classic Taxi* calls. Only the learned ones ("current" and "reachable") are kept.
local function read_nodes(map)
    local out = {}
    local function add(id, name, x, y, st)
        st = node_state(st)
        name = WC.Clean(name)
        if not st or type(name) ~= "string" or name == "" or #out >= WC.SEEN_NODE_CAP then return end
        x, y = node_xy(x, y)
        out[#out + 1] = { id = WC.Clean(id), name = name, map = map, x = x, y = y, state = st }
    end
    if C_TaxiMap and C_TaxiMap.GetAllTaxiNodes and map then
        local list = C_TaxiMap.GetAllTaxiNodes(map)
        if type(list) == "table" then
            for _, n in ipairs(list) do
                if type(n) == "table" then
                    local pos = n.position
                    local px, py
                    if type(pos) == "table" then
                        px, py = pos.x, pos.y
                        if px == nil and pos.GetXY then px, py = pos:GetXY() end
                    end
                    add(n.nodeID, n.name, px, py, n.state)
                end
            end
        end
    elseif NumTaxiNodes and TaxiNodeName and TaxiNodeGetType then
        for i = 1, math.min(tonumber(NumTaxiNodes()) or 0, 200) do
            local x, y
            if TaxiNodePosition then x, y = TaxiNodePosition(i) end
            add(i, TaxiNodeName(i), x, y, TaxiNodeGetType(i))
        end
    end
    return out
end

-- Taxi window, second part: the character's known flight points, under characters[<key>].flightPoints.
function WC.SeenReadFlightPoints()
    if not (WC.db and WC.Setting("recordCharacter") == true and UnitName and GetRealmName) then return false end
    local name, realm = UnitName("player"), GetRealmName()
    if type(name) ~= "string" or name == "" then return false end
    local map = here()
    local nodes = read_nodes(map)
    if #nodes == 0 then return false end
    if type(WC.db.characters) ~= "table" then WC.db.characters = {} end
    local key = (realm or "") .. ":" .. name
    if type(WC.db.characters[key]) ~= "table" then WC.db.characters[key] = {} end
    local fp = { seenAt = time(), nodes = nodes }
    WC.CleanTree(fp)
    WC.db.characters[key].flightPoints = fp
    return true
end

local function skill_rank(kind)
    if not (GetNumSkillLines and GetSkillLineInfo) then return nil end
    for i = 1, GetNumSkillLines() or 0 do
        local name, header, _, rank = GetSkillLineInfo(i)
        name, rank = WC.Clean(name), WC.Clean(rank)
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
                local name = WC.Clean(GetSpellInfo(v))
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
        local n = WC.Clean(UnitName and UnitName("target"))
        if type(n) == "string" and n ~= "" then source = n end
    end
    local items = {}
    for i = 1, GetNumLootItems() or 0 do
        local id = item_id(WC.Clean(GetLootSlotLink(i)))
        if id then
            local count = 1
            if GetLootSlotInfo then
                local q = WC.Clean(select(3, GetLootSlotInfo(i)))
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

local READ = { trainer = "SeenReadTrainer", merchant = "SeenReadMerchant", taxi = "SeenReadFlight" }
local EXTRA = { taxi = "SeenReadFlightPoints" } -- a second read of the same window
local OPEN_DELAY, UPDATE_DELAY = 0.5, 1.5 -- seconds after a window opens or updates that its data is read
local gen = {}          -- window name -> counter; a newer schedule replaces an older one (debounce)

local function read(win)
    if not open[win] then return end
    if InCombatLockdown and InCombatLockdown() then pending[win] = true; return end
    pending[win] = nil
    local ok, err = pcall(WC[READ[win]])
    if not ok then WC.SeenError(win, err) end
    if EXTRA[win] then
        ok, err = pcall(WC[EXTRA[win]])
        if not ok then WC.SeenError(win, err) end
    end
end

-- Reads the window after a short delay (the lists can be empty or partial when the event fires). Repeated
-- schedules cause one read; without C_Timer the read happens at once.
local function schedule(win, delay)
    if not (C_Timer and C_Timer.After) then read(win) return end
    gen[win] = (gen[win] or 0) + 1
    local mine = gen[win]
    C_Timer.After(delay, function() if gen[win] == mine then read(win) end end)
end

-- A window opens once, whichever event says so first; a repeat while it is up counts as an update.
-- (a stale "open" from a missed close expires after DOUBLE_FIRE seconds, so the next real open is read).
local DOUBLE_FIRE = 1
local function open_window(win)
    local now = time()
    local who = tostring(WC.Clean(UnitGUID and UnitGUID("npc")))
    if open[win] and open[win].who == who and now - open[win].at < DOUBLE_FIRE then return end
    open[win] = { at = now, who = who }
    schedule(win, OPEN_DELAY)
end

local function update_window(win)
    if open[win] then schedule(win, UPDATE_DELAY) end
end

local function close_window(win)
    open[win], pending[win] = nil, nil
    gen[win] = (gen[win] or 0) + 1
end

-- PLAYER_INTERACTION_MANAGER_FRAME_SHOW/HIDE carry an Enum.PlayerInteractionType: the enum at runtime when the
-- client has it, else the documented numbers.
local TYPE_WINDOW = { { "Merchant", 5, "merchant" }, { "Vendor", 12, "merchant" }, { "Trainer", 7, "trainer" },
    { "Banker", 8, "bank" }, { "QuestGiver", 4, "quest" }, { "TaxiNode", 6, "taxi" } }
function WC.SeenWindowOfType(t)
    t = WC.Clean(t)
    if type(t) ~= "number" then return nil end
    local E = Enum and Enum.PlayerInteractionType
    for _, row in ipairs(TYPE_WINDOW) do
        local v = type(E) == "table" and tonumber(E[row[1]]) or row[2]
        if v == t then return row[3] end
    end
end

local frame = CreateFrame("Frame")
for _, ev in ipairs({ "TRAINER_SHOW", "TRAINER_UPDATE", "TRAINER_CLOSED", "MERCHANT_SHOW", "MERCHANT_UPDATE",
    "MERCHANT_CLOSED", "TAXIMAP_OPENED", "TAXIMAP_CLOSED", "PLAYER_INTERACTION_MANAGER_FRAME_SHOW",
    "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", "LOOT_OPENED", "QUEST_DETAIL", "UNIT_SPELLCAST_SUCCEEDED",
    "UNIT_SPELLCAST_CHANNEL_START", "PLAYER_REGEN_ENABLED" }) do
    pcall(frame.RegisterEvent, frame, ev) -- a client without an event just skips it
end
-- A client with no MERCHANT_SHOW event: read when the merchant frame is shown instead (a read-only hook).
if not pcall(frame.RegisterEvent, frame, "MERCHANT_SHOW") and MerchantFrame and MerchantFrame.HookScript then
    pcall(MerchantFrame.HookScript, MerchantFrame, "OnShow", function() open_window("merchant") end)
    pcall(MerchantFrame.HookScript, MerchantFrame, "OnHide", function() close_window("merchant") end)
end
frame:SetScript("OnEvent", function(_, event, a, ...)
    if event == "TRAINER_SHOW" then open_window("trainer")
    elseif event == "TRAINER_UPDATE" then update_window("trainer")
    elseif event == "TRAINER_CLOSED" then close_window("trainer")
    elseif event == "MERCHANT_SHOW" then open_window("merchant")
    elseif event == "MERCHANT_UPDATE" then update_window("merchant")
    elseif event == "MERCHANT_CLOSED" then close_window("merchant")
    elseif event == "TAXIMAP_OPENED" then open_window("taxi")
    elseif event == "TAXIMAP_CLOSED" then close_window("taxi")
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" or event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        local win = WC.SeenWindowOfType(a)
        if win == "quest" then
            if event:find("SHOW") then pcall(WC.SeenQuestGiver) end
        elseif win and READ[win] then
            if event:find("SHOW") then open_window(win) else close_window(win) end
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        for win in pairs(pending) do read(win) end
    elseif event == "LOOT_OPENED" then pcall(WC.SeenLoot)
    elseif event == "QUEST_DETAIL" then pcall(WC.SeenQuestGiver)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" or event == "UNIT_SPELLCAST_CHANNEL_START" then
        pcall(WC.SeenCast, a, ...)
    end
end)
