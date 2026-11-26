-- WoW Companion: the advisor's quest route (WoWCompanion_Digest/Plan.lua) as data: parsing, step
-- completion from quest events, and the distance and direction maths. Display only: this file
-- reads the plan table and the quest log, and keeps its own "done" marks in WoWCompanionDB.
-- The drawing is in PlanUI.lua. Format: docs/plan-format.md in the advisor repo.

local WC = WoWCompanion
local L = WC.L

local KINDS = { pickup = true, objective = true, turnin = true, travel = true }
local FALLBACK_YARDS = { 2500, 1670 } -- a zone's size when the client cannot say; distances are then rough
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
local COMPASS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }

local function plain(s)
    return (tostring(s):gsub("|", "||"))
end

function WC.PlanSchemaOK(v)
    return v == 1 or (type(v) == "string" and (v == "1" or v:match("^1%.%d+$") ~= nil))
end

-- A list of positive quest ids from a plan field, or an empty list.
local function id_list(v)
    local out = {}
    if type(v) == "table" then
        for _, x in ipairs(v) do
            local n = tonumber(x)
            if n and n > 0 then out[#out + 1] = n end
        end
    end
    return out
end

local function clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

-- One guided position: text plus an optional map position (a zone-only item has none).
local function guided_spot(o)
    if type(o) ~= "table" or type(o.text) ~= "string" or o.text == "" then return nil end
    local r = { doLine = plain(o.text), zone = type(o.zone) == "string" and plain(o.zone) or nil,
        place = type(o.place) == "string" and o.place ~= "" and plain(o.place) or nil }
    if tonumber(o.map) and tonumber(o.x) and tonumber(o.y) then
        r.map, r.x, r.y = tonumber(o.map), clamp(tonumber(o.x), 0, 100), clamp(tonumber(o.y), 0, 100)
    end
    return r
end

-- The "go and find" fields a plan marks on a quest whose finisher is elsewhere (maybe inside a dungeon):
-- { trip = true, finisher, finisherPlace, instance }. Returns nil when the entry is no trip (an older plan has none).
local function trip_fields(e)
    if type(e) ~= "table" or e.trip ~= true then return nil end
    local function str(v) return type(v) == "string" and v ~= "" and plain(v) or nil end
    return { finisher = str(e.finisher), place = str(e.finisherPlace), instance = str(e.instance) }
end

-- Plan.lua 1.2 per-quest guidance, keyed by quest id: { quest, class, steps = {route step n}, objectives = {spot},
-- turnin = spot or nil, after }. Returns nil when the plan has none (an older plan keeps today's behaviour).
function WC.ParseGuidance(g)
    if type(g) ~= "table" then return nil end
    local out, any = {}, false
    for key, e in pairs(g) do
        local id = tonumber(type(e) == "table" and e.questID or key)
        if id and id > 0 and type(e) == "table" then
            local objs = {}
            for _, o in ipairs(type(e.objectives) == "table" and e.objectives or {}) do
                local spot = guided_spot(o)
                if spot then objs[#objs + 1] = spot end
            end
            out[id] = { questID = id, quest = plain(e.quest or ""), class = e.class == true, steps = id_list(e.steps),
                objectives = objs, turnin = guided_spot(e.turnin),
                after = type(e.after) == "string" and e.after ~= "" and plain(e.after) or nil, trip = trip_fields(e) }
            any = true
        end
    end
    return any and out or nil
end

-- Plan.lua `zones`: per other zone, where the player arrives and the one stop order to follow from there:
-- { [mapID] = { arrival = { kind = "flight"|"walk", npc, name, map, x, y, text }, order = { route step n... } } }.
-- A zone with no usable arrival or order is dropped; nil when the plan has none (an older plan: no legs on other zones).
function WC.ParseZones(z, steps)
    if type(z) ~= "table" then return nil end
    local known = {}
    for _, s in ipairs(steps or {}) do known[s.n] = true end
    local out, any = {}, false
    for key, e in pairs(z) do
        local map = tonumber(key)
        local a = type(e) == "table" and e.arrival
        if map and type(a) == "table" and tonumber(a.x) and tonumber(a.y) then
            local order, seen = {}, {}
            for _, n in ipairs(id_list(e.order) or {}) do
                if known[n] and not seen[n] then seen[n] = true order[#order + 1] = n end
            end
            local function str(v) return type(v) == "string" and v ~= "" and plain(v) or nil end
            local text = str(a.text)
            local tn = tonumber(a.step)
            if not text and tn then
                for _, s in ipairs(steps) do if s.n == tn then text = s.label end end
            end
            out[map] = { order = order, arrival = { kind = a.kind == "walk" and "walk" or "flight", npc = str(a.npc),
                name = str(a.name), map = tonumber(a.map) or map, x = clamp(tonumber(a.x), 0, 100),
                y = clamp(tonumber(a.y), 0, 100), text = text } }
            any = true
        end
    end
    return any and out or nil
end

-- Plan.lua `finishers`: where each logged quest is turned in. Either { [questID] = { spot... } } or a list of
-- { questID, quest, places = { spot... } }; a spot is { npc, map, x, y, place }. Returns { [questID] = { quest, spots } }
-- or nil when the plan has none (an older plan).
function WC.ParseFinishers(list)
    if type(list) ~= "table" then return nil end
    local out, any = {}, false
    local function spots_of(v)
        if type(v) ~= "table" then return {} end
        if tonumber(v.map) then v = { v } end
        local spots = {}
        for _, e in ipairs(v) do
            if type(e) == "table" and tonumber(e.map) and tonumber(e.x) and tonumber(e.y) then
                spots[#spots + 1] = { npc = type(e.npc) == "string" and plain(e.npc) or "", map = tonumber(e.map),
                    x = clamp(tonumber(e.x), 0, 100), y = clamp(tonumber(e.y), 0, 100),
                    place = type(e.place) == "string" and e.place ~= "" and plain(e.place) or nil }
            end
        end
        return spots
    end
    for key, v in pairs(list) do
        local id, name, spots = tonumber(key), "", nil
        if type(v) == "table" and tonumber(v.questID) then
            id, name = tonumber(v.questID), plain(v.quest or "")
            spots = spots_of(v.places or v.spots or v.finishers or v)
        elseif id then
            name = type(v) == "table" and type(v.quest) == "string" and plain(v.quest) or ""
            spots = spots_of(type(v) == "table" and (v.places or v.spots) or v)
        end
        if id and id > 0 and spots and #spots > 0 then
            out[id] = { quest = name, spots = spots, trip = trip_fields(v) }
            any = true
        end
    end
    return any and out or nil
end

-- The quest's trip fields ({ finisher, place, instance }) when the plan marks it a trip, else nil.
local finisher_spots -- defined with the live turn-ins below
local function trip_of(id)
    local p = WC.plan
    if not (p and id) then return nil end
    local g, f = p.guidance and p.guidance[id], p.finishers and p.finishers[id]
    return (g and g.trip) or (f and f.trip) or nil
end

-- "Find <finisher> in <place>" / "inside <instance>" for a trip quest, else nil: the line that replaces "Ready to turn in".
function WC.TripLine(id)
    local t = trip_of(id)
    if not t then return nil end
    local who = t.finisher or L.TRIP_SOMEONE
    if t.instance then return string.format(L.TRIP_INSIDE, who, t.instance) end
    if t.place then return string.format(L.TRIP_IN, who, t.place) end
    return string.format(L.TRIP_FIND, who)
end

-- Plan.lua 1.3 per-NPC "here" blocks: { npc, npcID, map, x, y, place, steps = {n}, can = {text}, quests = { { questID, quest,
-- role, desc, missing = {spot} } }, nearby = { [questID] = guidance } }. nil when the plan has none (an older plan).
function WC.ParseHere(list)
    if type(list) ~= "table" then return nil end
    local out = {}
    for _, b in ipairs(list) do
        if type(b) == "table" and tonumber(b.map) and tonumber(b.x) and tonumber(b.y) then
            local blk = { npc = plain(b.npc or ""), npcID = tonumber(b.npcID), map = tonumber(b.map),
                x = clamp(tonumber(b.x), 0, 100), y = clamp(tonumber(b.y), 0, 100),
                place = type(b.place) == "string" and b.place ~= "" and plain(b.place) or nil,
                steps = id_list(b.steps), can = {}, quests = {}, nearby = {} }
            for key, e in pairs(type(b.nearby) == "table" and b.nearby or {}) do
                local id = tonumber(type(e) == "table" and e.questID or key)
                local g = id and type(e.guidance) == "table" and WC.ParseGuidance({ [id] = e.guidance })
                if g and g[id] then
                    g[id].quest = g[id].quest ~= "" and g[id].quest or plain(e.quest or "")
                    blk.nearby[id] = g[id]
                end
            end
            for _, c in ipairs(type(b.can) == "table" and b.can or {}) do
                if type(c) == "string" then blk.can[#blk.can + 1] = c:lower() end
            end
            for _, q in ipairs(type(b.quests) == "table" and b.quests or {}) do
                local id = type(q) == "table" and tonumber(q.questID)
                if id and id > 0 and (q.role == "turnin" or q.role == "pickup") then
                    local missing = {}
                    for _, m in ipairs(type(q.missing) == "table" and q.missing or {}) do
                        local spot = guided_spot(m)
                        if spot then missing[#missing + 1] = spot end
                    end
                    blk.quests[#blk.quests + 1] = { questID = id, quest = plain(q.quest or ""), role = q.role,
                        desc = type(q.text) == "string" and plain(q.text) or "", missing = missing }
                end
            end
            out[#out + 1] = blk
        end
    end
    return #out > 0 and out or nil
end

-- Optional "later" items: quests with a place that are not route steps yet, { questID, kind = "pickup"|"turnin"|"objective",
-- map, x, y, npc }. An item with no place (x or y below 0, or no map) is dropped. nil when there are none.
function WC.ParseLater(list)
    if type(list) ~= "table" then return nil end
    local out = {}
    for _, it in ipairs(list) do
        local id, x, y = type(it) == "table" and tonumber(it.questID), tonumber(it and it.x), tonumber(it and it.y)
        if id and id > 0 and tonumber(it.map) and x and y and x >= 0 and y >= 0 and x <= 100 and y <= 100 and not (x == 0 and y == 0) then
            local k = it.kind
            out[#out + 1] = { questID = id, kind = (k == "pickup" or k == "turnin" or k == "objective") and k or nil,
                map = tonumber(it.map), x = x, y = y, npc = type(it.npc) == "string" and it.npc ~= "" and plain(it.npc) or nil }
        end
    end
    return #out > 0 and out or nil
end

-- The panel's own plan fields (all optional; an older plan has none): `exit` { label, map, x, y, via }, `trips` an ordered
-- list of { order, map, zone, ready, todo, pickups, questIDs, reason, travel, instance } and `parked` (or a `later` whose
-- items carry a `why`) { questID, quest, why, kind }. Read defensively: a malformed entry is dropped, never an error.
function WC.ParsePanelFields(entry)
    local function str(v) return type(v) == "string" and v ~= "" and plain(v) or nil end
    local exit
    if type(entry.exit) == "table" and str(entry.exit.label) then
        local e = entry.exit
        exit = { label = str(e.label), map = tonumber(e.map), x = tonumber(e.x), y = tonumber(e.y), via = str(e.via) }
    end
    local trips = {}
    for i, t in ipairs(type(entry.trips) == "table" and entry.trips or {}) do
        if type(t) == "table" and (tonumber(t.map) or str(t.zone)) then
            local travel = {}
            if type(t.travel) == "string" then
                travel[1] = plain(t.travel)
            else
                for _, leg in ipairs(type(t.travel) == "table" and t.travel or {}) do
                    local leg_text = type(leg) == "string" and leg or (type(leg) == "table" and (leg.text or leg.label))
                    if type(leg_text) == "string" and leg_text ~= "" then travel[#travel + 1] = plain(leg_text) end
                end
            end
            trips[#trips + 1] = { order = tonumber(t.order) or i, map = tonumber(t.map), zone = str(t.zone),
                ready = math.max(0, math.floor(tonumber(t.ready) or 0)), todo = math.max(0, math.floor(tonumber(t.todo) or 0)),
                pickups = math.max(0, math.floor(tonumber(t.pickups) or 0)), questIDs = id_list(t.questIDs) or {},
                reason = str(t.reason), travel = travel, instance = str(t.instance) }
        end
    end
    table.sort(trips, function(a, b) return a.order < b.order end)
    local parked = {}
    local list = type(entry.parked) == "table" and entry.parked or entry.later
    for _, q in ipairs(type(list) == "table" and list or {}) do
        local id = type(q) == "table" and tonumber(q.questID)
        if id and id > 0 and str(q.why) then
            parked[#parked + 1] = { questID = id, quest = str(q.quest) or "", why = str(q.why), kind = str(q.kind) }
        end
    end
    -- `find`: quests whose next move is a hunt, { questID, quest, hint, zone, map }; a hint or a name is enough.
    local find = {}
    for _, q in ipairs(type(entry.find) == "table" and entry.find or {}) do
        local id = type(q) == "table" and tonumber(q.questID)
        if id and id > 0 and (str(q.hint) or str(q.quest)) then
            find[#find + 1] = { questID = id, quest = str(q.quest) or "", hint = str(q.hint), zone = str(q.zone), map = tonumber(q.map) }
        end
    end
    -- `errands`: stops that are chores, { n = step number and/or questID, kind = train | bank | class | profession }.
    local errands = {}
    for _, e in ipairs(type(entry.errands) == "table" and entry.errands or {}) do
        local kind = type(e) == "table" and str(e.kind or e.type)
        kind = kind and kind:lower()
        if kind and rawget(L, "ERRAND_" .. kind) then
            local n, id = tonumber(e.n or e.step), tonumber(e.questID)
            if n or (id and id > 0) then errands[#errands + 1] = { n = n, questID = id, kind = kind, map = tonumber(e.map) } end
        end
    end
    return exit, #trips > 0 and trips or nil, #parked > 0 and parked or nil, #find > 0 and find or nil, #errands > 0 and errands or nil
end

-- True when a stop has a real place on its map: x and y are numbers, not negative, not both exactly 0 (the plan's
-- "no spot" filler), and it is not flagged unplaced. Never draw a badge, ring, line or minimap pin without it.
function WC.HasPlace(s)
    if type(s) ~= "table" or s.unplaced then return false end
    local x, y = tonumber(s.x), tonumber(s.y)
    if not x or not y or x < 0 or y < 0 then return false end
    return not (x == 0 and y == 0)
end

-- A live extra step or a number that is only an id: never a route step, so never "Step n of N".
function WC.IsSyntheticStep(s)
    local n = type(s) == "table" and tonumber(s.n)
    return type(s) == "table" and (s.synthetic == true or s.live == true and n == nil or (n ~= nil and n >= 100000)) or false
end

-- The valid steps for player in a Plan.lua table, in order; unknown fields are ignored.
-- Returns nil, reason when there is nothing to show ("missing", "schema" or "character").
function WC.ParsePlan(plan, player)
    if type(plan) ~= "table" or next(plan) == nil then return nil, "missing" end
    if not WC.PlanSchemaOK(plan.schema) then return nil, "schema" end
    local chars = plan.characters
    local entry = type(chars) == "table" and (chars[player] or nil)
    if type(chars) == "table" and not entry and type(player) == "string" then
        for name, e in pairs(chars) do
            if type(name) == "string" and name:lower() == player:lower() then entry = e end
        end
    end
    if type(entry) ~= "table" or type(entry.steps) ~= "table" then return nil, "character" end
    local steps = {}
    for _, s in ipairs(entry.steps) do
        if type(s) == "table" and KINDS[s.kind] and tonumber(s.map) and tonumber(s.x) and tonumber(s.y) then
            steps[#steps + 1] = {
                n = #steps + 1, kind = s.kind, questID = tonumber(s.questID) or 0,
                quest = plain(s.quest or ""), label = plain(s.label or ""), approx = s.approx == true,
                map = tonumber(s.map), x = clamp(tonumber(s.x), 0, 100), y = clamp(tonumber(s.y), 0, 100),
                unplaced = s.unplaced == true or tonumber(s.x) < 0 or tonumber(s.y) < 0 or (tonumber(s.x) == 0 and tonumber(s.y) == 0) or nil,
                -- optional, shown in tooltips only when the plan carries them: quest level, class-quest name, NPC level text
                level = tonumber(s.level), class = type(s.class) == "string" and s.class ~= "" and plain(s.class) or nil,
                npcLevel = (type(s.npcLevel) == "string" or type(s.npcLevel) == "number") and plain(tostring(s.npcLevel)) or nil,
                -- Plan.lua 1.1 chain fields: a follow-up is locked until every quest in unlockedBy is turned in;
                -- a turn-in lists what it unlocks. A 1.0 plan has none of them and nothing is ever locked.
                questIDs = id_list(s.questIDs),
                locked = s.locked == true, unlockedBy = id_list(s.unlockedBy), unlocks = id_list(s.unlocks),
                chain = type(s.chain) == "string" and s.chain ~= "" and plain(s.chain) or nil,
                place = type(s.place) == "string" and s.place ~= "" and plain(s.place) or nil, -- 1.3: where the work is done
            }
        end
    end
    if #steps == 0 then return nil, "character" end
    return steps, nil, tonumber(plan.generated) or 0, WC.ParseGuidance(entry.guidance), WC.ParseHere(entry.here), WC.ParseLater(entry.later),
        WC.ParseFinishers(entry.finishers), WC.ParseZones(entry.zones, steps), WC.ParsePanelFields(entry)
end

-- Yards and compass point from (x1,y1) to (x2,y2), both in map percent, on a map w by h yards.
function WC.PlanDistance(x1, y1, x2, y2, w, h)
    local dx, dy = (x2 - x1) * w / 100, (y2 - y1) * h / 100
    local bearing = math.deg(atan2(dx, -dy)) % 360 -- 0 is north, clockwise
    return math.sqrt(dx * dx + dy * dy), COMPASS[math.floor((bearing + 22.5) / 45) % 8 + 1], bearing
end

function WC.MapYards(mapID)
    local w, h
    if C_Map and C_Map.GetMapWorldSize then w, h = C_Map.GetMapWorldSize(mapID) end
    if type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then return w, h end
    return FALLBACK_YARDS[1], FALLBACK_YARDS[2]
end

-- The player's uiMapID and position in map percent, or nil when the client has none (instances, loading).
function WC.PlayerPos()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return end
    local map = C_Map.GetBestMapForUnit("player")
    if not map then return end
    local pos = C_Map.GetPlayerMapPosition(map, "player")
    local x, y
    if pos and pos.GetXY then x, y = pos:GetXY() end
    if not x or (x == 0 and y == 0) then return end
    return map, x * 100, y * 100
end

-- "turnedin", "ready" (objectives finished), "active" (in the log) or "none".
function WC.PlanQuestState(questID)
    local q = C_QuestLog
    if q and q.IsQuestFlaggedCompleted and q.IsQuestFlaggedCompleted(questID) then return "turnedin" end
    if q and q.GetLogIndexForQuestID and q.GetLogIndexForQuestID(questID) then
        if q.IsComplete and q.IsComplete(questID) then return "ready" end
        return "active"
    end
    return "none"
end

-- True when the client offers both quest-log lookups, so "none" really means "not in the log".
local function log_known()
    local q = C_QuestLog
    return q ~= nil and type(q.IsQuestFlaggedCompleted) == "function" and type(q.GetLogIndexForQuestID) == "function"
end

-- The quest's objectives as { text, have, need, finished } (read only), or nil when the client cannot say.
function WC.QuestObjectives(questID)
    local q = C_QuestLog
    if not (q and type(q.GetQuestObjectives) == "function") or not questID or questID <= 0 then return nil end
    local ok, objs = pcall(q.GetQuestObjectives, questID)
    if not ok or type(objs) ~= "table" then return nil end
    local out = {}
    for _, o in ipairs(objs) do
        if type(o) == "table" and type(o.text) == "string" and o.text ~= "" then
            local have, need = tonumber(o.numFulfilled), tonumber(o.numRequired)
            if not need then
                local a, b = o.text:match("(%d+)/(%d+)")
                have, need = tonumber(a), tonumber(b)
            end
            out[#out + 1] = { text = o.text, have = have, need = need, finished = o.finished == true }
        end
    end
    return #out > 0 and out or nil
end

-- The quest's title from the client, or nil.
function WC.QuestTitle(questID)
    local q = C_QuestLog
    if q and type(q.GetTitleForQuestID) == "function" then
        local t = q.GetTitleForQuestID(questID)
        if type(t) == "string" and t ~= "" then return t end
    end
end

-- The objective an objective step is about: the one whose name the label contains, else the only one.
local function objective_for(step, objs)
    local label = (step.label or ""):lower()
    for _, o in ipairs(objs) do
        local name = o.text:gsub("^%d+/%d+%s*", ""):gsub(":?%s*%d+/%d+$", ""):lower()
        if name ~= "" and label:find(name, 1, true) then return o end
    end
    if #objs == 1 then return objs[1] end
end

-- text (a step's label or tooltip detail) with its objective count made live while the quest is in
-- the log; text unchanged otherwise.
function WC.PlanLiveText(step, text)
    if step.kind ~= "objective" or (step.questID or 0) <= 0 or WC.PlanQuestState(step.questID) ~= "active" then return text end
    local objs = WC.QuestObjectives(step.questID)
    local o = objs and objective_for(step, objs)
    if not (o and o.have and o.need) then return text end
    local count = o.have .. "/" .. o.need
    if text:find("%d+/%d+") then return (text:gsub("%d+/%d+", count, 1)) end
    if o.need <= 1 then return text end
    return (text ~= "" and text .. " " or "") .. "(" .. count .. ")"
end

local function charKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "")
end

-- The app writes the plan seconds after the save a /reload makes, so the plan loaded by that reload is one
-- save behind. Compares when the plan was made from (basis.captured, else generated) with the newest save.
WC.PLAN_BEHIND_SECONDS = 30
function WC.ComputePlanBehind(raw, generated)
    local basis = type(raw) == "table" and type(raw.basis) == "table" and raw.basis or nil
    local planAt = basis and tonumber(basis.captured) or nil
    if not planAt or planAt <= 0 then planAt = tonumber(generated) end
    if not planAt or planAt <= 0 then return false end
    local last = WC.OwnCapturedAt and WC.OwnCapturedAt(UnitName("player")) or nil
    local saved = WC.db and tonumber(WC.db.lastSave) or nil
    if saved and (not last or saved > last) then last = saved end
    return last ~= nil and last - planAt > WC.PLAN_BEHIND_SECONDS
end
function WC.PlanBehind() return WC.plan ~= nil and WC.plan.behind == true end
-- The player has seen the line (or asked not to): it never comes back this session.
function WC.DismissPlanLag() WC.lagDismissed = true end

-- Loads the plan for this character and its saved done marks (a new plan starts clean).
function WC.PlanInit()
    local steps, _, generated, guidance, here, later, finishers, zones, exit, trips, parked, find, errands = WC.ParsePlan(WoWCompanionPlan, UnitName("player"))
    WC.plan = nil
    if not steps then return end
    WC.db.plan = type(WC.db.plan) == "table" and WC.db.plan or {}
    local saved = WC.db.plan[charKey()]
    if type(saved) ~= "table" or saved.generated ~= generated or type(saved.done) ~= "table" then
        saved = { generated = generated, done = {} }
        WC.db.plan[charKey()] = saved
    end
    WC.plan = { steps = steps, generated = generated, done = saved.done, open = {}, newAt = {},
        guidance = guidance, here = here, later = later or {}, finishers = finishers, zones = zones, live = {}, liveSig = "",
        exit = exit, trips = trips, parked = parked, find = find, errands = errands }
    for _, st in ipairs(steps) do
        if st.locked then WC.plan.hasLocked = true end
    end
    WC.plan.behind = WC.ComputePlanBehind(WoWCompanionPlan, generated)
    WC.PlanScan()
    WC.PlanUnlockCheck(true)
    WC.PlanLiveRefresh()
end

-- True for a turn-in whose quest is in the log but not complete yet: it is not a place to go.
function WC.StepUnready(step)
    if not step or step.kind ~= "turnin" then return false end
    local ids = step.questIDs and #step.questIDs > 0 and step.questIDs or { step.questID }
    for _, id in ipairs(ids) do
        if (id or 0) > 0 and WC.PlanQuestState(id) == "active" then return true end
    end
    return false
end

-- "n of m done" for the quest's objectives (a merged stop: the first unready quest), or nil when unknown.
function WC.StepAfterText(step)
    local ids = step.questIDs and #step.questIDs > 0 and step.questIDs or { step.questID }
    for _, id in ipairs(ids) do
        if (id or 0) > 0 and WC.PlanQuestState(id) == "active" then
            local objs = WC.QuestObjectives(id)
            if objs then
                local d = 0
                for _, o in ipairs(objs) do
                    if o.finished then d = d + 1 end
                end
                return string.format(L.AFTER_DONE, d, #objs)
            end
            return string.format(L.AFTER_PENDING)
        end
    end
end

-- The first route step not yet done whose quest state allows it, or nil when none is left. A locked
-- follow-up and a turn-in whose quest is not complete yet are skipped.
local function route_next()
    local p = WC.plan
    if not p then return end
    for _, s in ipairs(p.steps) do
        if not p.done[s.n] and not WC.StepLocked(s) and not WC.StepUnready(s) then return s end
    end
end
WC.RouteNext = route_next

-- The step to show now: the live step of the quest being followed (see PlanLiveRefresh), else the route's next step.
function WC.PlanBaseNext()
    local p = WC.plan
    if not p then return end
    return p.liveNow or route_next()
end

-- True when the step's map is the player's map or its parent zone.
local function same_zone(playerMap, stepMap)
    if not (playerMap and stepMap) then return false end
    if playerMap == stepMap then return true end
    local ok, info = pcall(function() return C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(playerMap) end)
    return ok and type(info) == "table" and tonumber(info.parentMapID) == stepMap
end

-- The action part of a travel step ("Turn in Elixir of Pain to Stanley (Hillsbrad Fields)"), from the label after the
-- colon, else from the step's quest; nil when the step is only a trip ("Travel to The Barrens").
local function travel_action(p, step)
    local a = (step.label or ""):match(":%s*(.-)%s*$")
    if not a or a == "" then
        if (step.quest or "") ~= "" then a = "turn in " .. step.quest end
    end
    if not a or a == "" then return nil end
    a = a:sub(1, 1):upper() .. a:sub(2)
    local f = p.finishers and step.questID and p.finishers[step.questID]
    local spot
    for _, sp in ipairs(f and f.spots or {}) do
        if sp.map == step.map then spot = sp break end
    end
    local npc = spot and spot.npc ~= "" and spot.npc or nil
    local place = (spot and spot.place) or step.place
    if npc and not a:find(npc, 1, true) then
        a = a .. " to " .. npc
        if place then a = a .. " (" .. place .. ")" end
    elseif place and not a:find(place, 1, true) then
        a = a .. " (" .. place .. ")"
    end
    return a
end

-- The step as shown when the player stands on its map: a travel step becomes its action; a trip with no action is
-- not shown (it is marked done on arrival). A copy; the plan's own step is untouched.
local function arrived_view(p, step)
    if step.kind ~= "travel" then return step end
    local action = travel_action(p, step)
    if not action then return nil end
    local v = {}
    for k, val in pairs(step) do v[k] = val end
    v.label, v.arrived = action, true
    return v
end

local function lead_step(p, cur)
    local pm = WC.PlayerPos()
    if not pm then return cur end
    if same_zone(pm, cur.map) then return arrived_view(p, cur) or cur end
    local function lead(s)
        local v = arrived_view(p, s)
        if not v then return nil end
        if v == s then
            v = {}
            for k, val in pairs(s) do v[k] = val end
        end
        v.hereFirst, v.skipped = true, cur
        return v
    end
    for _, s in ipairs(p.steps) do
        if (cur.n >= 100000 or s.n > cur.n) and not p.done[s.n] and same_zone(pm, s.map)
            and not WC.StepLocked(s) and not WC.StepUnready(s) then
            local v = lead(s)
            if v then return v end
        end
    end
    -- Work on this map that is not a plan step (a live turn-in, a quest in the log) still comes before another zone.
    local extras = {}
    for _, st in ipairs(p.live or {}) do extras[#extras + 1] = st end
    for _, st in ipairs(WC.LiveTurnInSteps and WC.LiveTurnInSteps() or {}) do extras[#extras + 1] = st end
    for _, s in ipairs(extras) do
        if s ~= cur and not (cur.questID and s.questID == cur.questID) and WC.HasPlace(s) and same_zone(pm, s.map)
            and not (tonumber(s.n) and p.done[s.n]) then
            return lead(s)
        end
    end
    return cur
end

-- The step as the map badge tooltip shows it: a travel step on the player's own map reads as its action. Guarded
-- (ADDON-119): on any failure the plan's own step is shown.
function WC.PlanTipStep(step)
    if not (WC.plan and step and step.kind == "travel") then return step end
    local ok, v = pcall(function()
        local pm = WC.PlayerPos()
        if pm and same_zone(pm, step.map) then return arrived_view(WC.plan, step) end
    end)
    if ok and v then return v end
    return step
end

-- Marks every undone trip step with no action on the player's map as done: arriving completes it. True when any changed.
function WC.PlanArrive(mapID)
    local p = WC.plan
    if not (p and p.done and mapID) then return false end
    local changed = false
    for _, s in ipairs(p.steps) do
        if s.kind == "travel" and not p.done[s.n] and s.map == mapID and not travel_action(p, s) then
            p.done[s.n] = true
            changed = true
        end
    end
    return changed
end

-- What to show now: the base step, or, when the player is already in the zone of a later step, that step (a travel
-- step as its action). Plan order returns once the zone's steps are done or the player leaves.
function WC.PlanNext()
    local p = WC.plan
    if not p then return end
    local cur = WC.PlanBaseNext()
    if not cur then return end
    local ok, v = pcall(lead_step, p, cur) -- ADDON-119's live-path rule: a failure here shows the plan's own step
    if ok and v then return v end
    return cur
end

-- ---------------------------------------------------------------- chains: locked steps, unlocks, "New"

WC.NEW_SECONDS = 10 -- how long a freshly unlocked step carries its "New" tag

local function now()
    return GetTime and GetTime() or os.time()
end

-- True when quest id is turned in: the client says so, or the plan's own turn-in step for it is marked done.
local function quest_turned_in(p, id)
    if WC.PlanQuestState(id) == "turnedin" then return true end
    for _, s in ipairs(p.steps) do
        if s.kind == "turnin" and s.questID == id and p.done[s.n] then return true end
    end
    return false
end

-- True while a follow-up step waits on a turn-in that is not done. Derived from the quest state every time,
-- so un-marking or re-doing a turn-in locks the step again with no extra bookkeeping.
function WC.StepLocked(step)
    local p = WC.plan
    if not (p and step and step.locked) or #step.unlockedBy == 0 then return false end
    if (step.questID or 0) > 0 then
        local st = WC.PlanQuestState(step.questID)
        if st ~= "none" then return false end -- already in the log or done: it is plainly available
    end
    for _, id in ipairs(step.unlockedBy) do
        if not quest_turned_in(p, id) then return true end
    end
    return false
end

-- The chain a locked step belongs to: its named chain, else the first locked quest it hangs from.
local function chain_key(step, byQuest)
    if step.chain then return "c:" .. step.chain end
    local cur = step
    for _ = 1, 12 do
        local parent = byQuest[cur.unlockedBy[1] or 0]
        if not parent or parent == cur then break end
        cur = parent
    end
    return "q:" .. tostring(cur.questID)
end

-- The locked follow-ups to show as ghosts: the pick-up of the next `perChain` locked quests of each chain, in plan
-- order. Returns { { step = pickup, from = the turn-in step that unlocks it or nil }, ... }.
function WC.GhostSteps(steps, perChain)
    perChain = math.max(0, tonumber(perChain) or 1)
    local byQuest, locked = {}, {}
    for _, s in ipairs(steps or {}) do
        if s.kind == "pickup" and WC.StepLocked(s) then
            locked[#locked + 1] = s
            byQuest[s.questID] = byQuest[s.questID] or s
        end
    end
    local out, seen = {}, {}
    for _, s in ipairs(locked) do
        local key = chain_key(s, byQuest)
        seen[key] = (seen[key] or 0) + 1
        if seen[key] <= perChain then
            local from
            for _, t in ipairs(steps) do
                if t.kind == "turnin" and not WC.plan.done[t.n] and t.questID == s.unlockedBy[1] then from = t break end
            end
            out[#out + 1] = { step = s, from = from }
        end
    end
    return out
end

-- Notes which locked steps have just opened (every unlocker done) and which locked again. With initial set it only
-- records the state, so a /reload does not tag everything "New". Returns the newly opened steps.
function WC.PlanUnlockCheck(initial)
    local p = WC.plan
    if not p or not p.hasLocked then return {} end
    local opened = {}
    p.open, p.newAt = p.open or {}, p.newAt or {}
    for _, s in ipairs(p.steps) do
        if s.locked then
            if not WC.StepLocked(s) then
                if not p.open[s.n] then
                    p.open[s.n] = true
                    if not initial then
                        p.newAt[s.n] = now()
                        opened[#opened + 1] = s
                    end
                end
            else
                p.open[s.n], p.newAt[s.n] = nil, nil
            end
        end
    end
    return opened
end

-- True while a step carries the "New" tag: unlocked in the last NEW_SECONDS and not hovered yet.
function WC.StepIsNew(step)
    local p = WC.plan
    local at = p and step and p.newAt and p.newAt[step.n]
    return at ~= nil and WC.Setting("showNew") and now() - at < WC.NEW_SECONDS
end

-- True when any step of the quest is "New" (the digest panel's rows are keyed by quest).
function WC.QuestIsNew(questID)
    local p = WC.plan
    if not p or not questID then return false end
    for _, s in ipairs(p.steps) do
        if s.questID == questID and WC.StepIsNew(s) then return true end
    end
    return false
end

-- Hovering a tagged entry dismisses its tag. Returns whether one was cleared.
function WC.ClearNew(questID)
    local p = WC.plan
    local hit = false
    if p and p.newAt then
        for _, s in ipairs(p.steps) do
            if s.questID == questID and p.newAt[s.n] then p.newAt[s.n] = nil hit = true end
        end
    end
    return hit
end

-- What a turn-in unlocks, for its "then:" line: { title, who, here } for the first still-locked follow-up, or nil.
function WC.ThenInfo(questID)
    local p = WC.plan
    if not p or not p.hasLocked or (questID or 0) <= 0 then return nil end
    local turnin
    for _, s in ipairs(p.steps) do
        if s.kind == "turnin" and s.questID == questID then turnin = s break end
    end
    for _, s in ipairs(p.steps) do
        if s.kind == "pickup" and s.locked and WC.StepLocked(s) then
            for _, id in ipairs(s.unlockedBy) do
                if id == questID then
                    local title = (s.questID or 0) > 0 and WC.QuestTitle(s.questID) or nil
                    title = title or (s.quest ~= "" and s.quest) or s.label or ""
                    local who = WC.PlanDetail(s):gsub("^[Ff]rom%s+", "")
                    local here = turnin ~= nil and turnin.map == s.map and math.abs(turnin.x - s.x) <= 3 and math.abs(turnin.y - s.y) <= 3
                    return { title = title, who = who ~= "" and who or nil, here = here, step = s, from = turnin }
                end
            end
        end
    end
end

-- "then: <Quest> (from <npc>, here)", or nil when nothing waits on this quest (or the lines are switched off).
function WC.ThenLine(questID)
    if not WC.Setting("showThen") then return nil end
    local info = WC.ThenInfo(questID)
    if not info then return nil end
    if info.who then
        return string.format(info.here and L.THEN_LINE_HERE or L.THEN_LINE_FROM, info.title, info.who)
    end
    return string.format(L.THEN_LINE, info.title)
end

-- The step number shown in "Step 12/22": the step's own number once a plan has locked steps (so every view
-- agrees on it), else the count of done steps plus one.
function WC.StepNumber(step)
    local done, total = WC.PlanCounts()
    if step and step.n and step.n < 100000 then return step.n end
    return math.min(done + 1, total)
end

function WC.PlanCounts()
    local p = WC.plan
    if not p then return 0, 0 end
    local n = 0
    for _ in pairs(p.done) do n = n + 1 end
    return n, #p.steps
end

-- True when every quest a turn-in step serves is turned in (a merged stop lists them in questIDs).
function WC.StepTurnedIn(step)
    local ids = step.questIDs and #step.questIDs > 0 and step.questIDs or { step.questID }
    for _, id in ipairs(ids) do
        if WC.PlanQuestState(id) ~= "turnedin" then return false end
    end
    return true
end

-- The quest ids a step carries (a merged stop lists them in questIDs).
local function step_ids(s)
    if s.questIDs and #s.questIDs > 0 then return s.questIDs end
    return { s.questID }
end

-- A travel step that carries quest(s) is finished once each is turned in, or gone from the log (abandoned) when
-- the log is known; keep is a quest just accepted.
local function travel_done(s, known, keep)
    for _, id in ipairs(step_ids(s)) do
        if id and id > 0 then
            local st = WC.PlanQuestState(id)
            if not (st == "turnedin" or (known and st == "none" and id ~= keep)) then return false end
        end
    end
    return true
end

local function mark(step)
    if WC.plan.done[step.n] then return false end
    WC.plan.done[step.n] = true
    return true
end

-- Marks the steps the quest log shows as done, and clears the pick-up and objective marks of a
-- quest that is neither in the log nor completed (abandoned); a turned-in quest stays done.
-- keep is a quest id whose marks are left alone (it was just accepted). Returns whether anything changed.
function WC.PlanScan(keep)
    local p = WC.plan
    if not p then return false end
    local changed = false
    local known = log_known()
    for _, s in ipairs(p.steps) do
        if s.kind == "travel" then
            if (s.questID or 0) > 0 or (s.questIDs and #s.questIDs > 0) then
                local ok, done = pcall(travel_done, s, known, keep) -- ADDON-119's live-path rule
                if ok then
                    if done and not p.done[s.n] then changed = mark(s) or changed
                    elseif not done and p.done[s.n] then p.done[s.n] = nil changed = true end
                end
            end
        elseif s.questID > 0 then
            local st = WC.PlanQuestState(s.questID)
            if not p.done[s.n] then
                local done = (s.kind == "pickup" and st ~= "none")
                    or (s.kind == "objective" and (st == "ready" or st == "turnedin"))
                    or (s.kind == "turnin" and WC.StepTurnedIn(s))
                if done then changed = mark(s) or changed end
            elseif known and st == "none" and (s.kind == "pickup" or s.kind == "objective") and s.questID ~= keep then
                p.done[s.n] = nil
                changed = true
            end
        end
    end
    return changed
end

-- ---------------------------------------------------------------- live guidance (Plan.lua 1.2)

local function step_has_quest(s, id)
    if s.questID == id then return true end
    for _, q in ipairs(s.questIDs or {}) do
        if q == id then return true end
    end
    return false
end

-- A quest just accepted becomes the one the panel follows when the plan lists it and it is a class quest or the
-- plan's current step. Any other listed quest still gets its pin; a quest the plan does not list is ignored.
function WC.PlanFollowAccepted(id)
    local p = WC.plan
    local g = p and p.guidance and p.guidance[id]
    if not g then return end
    local cur = route_next()
    if g.class or (cur and step_has_quest(cur, id)) then p.focus = id end
end

-- Runs a live-guidance read so an unexpected data shape never raises a Lua error in front of the player: on error
-- the fallback value is returned (the static plan view) and the error is recorded once per distinct message.
local liveErrSeen = {}
local function guarded(kind, fn, fallback, ...)
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
    local msg = tostring(a)
    if not liveErrSeen[msg] then
        liveErrSeen[msg] = true
        if WC.SeenError then pcall(WC.SeenError, "live", kind .. ": " .. msg) end
    end
    if type(fallback) == "function" then return fallback() end
    return fallback
end

-- Which of the quest's guided objectives are still open, matched to the client's objectives by position when the
-- counts agree, else by text. An unknown objective counts as open.
local function open_objective(g, qid)
    local live = WC.QuestObjectives(qid)
    local done = 0
    for i, o in ipairs(g.objectives) do
        local fin = false
        if live then
            local m = nil
            if #live == #g.objectives then m = live[i] end
            if type(m) ~= "table" then
                m = nil
                for _, lo in ipairs(live) do
                    local name = type(lo) == "table" and type(lo.text) == "string" and lo.text:gsub("^%d+/%d+%s*", ""):gsub(":?%s*%d+/%d+$", ""):lower()
                    if name and name ~= "" and o.doLine:lower():find(name, 1, true) then m = lo break end
                end
            end
            fin = type(m) == "table" and m.finished == true
        end
        if not fin then return o, done, #g.objectives end
        done = done + 1
    end
end

-- The step a guided quest in the log shows: its first open objective, or its turn-in once they are done. nil when
-- the guidance has nothing for the state. n is the route step it belongs to, so "Step n/N" stays on the route.
local function live_step(p, g, state)
    local spot, kind, done, total
    if state == "ready" then
        spot, kind = g.turnin, "turnin"
    else
        spot, done, total = open_objective(g, g.questID)
        kind = "objective"
    end
    if not spot then return nil end
    local approx
    if not WC.HasPlace(spot) then
        -- No known position: use the game's own quest map point when it is on the map the player is on.
        local poi = WC.CapturedPOI and WC.CapturedPOI(g.questID)
        local pmap = WC.PlayerPos and (WC.PlayerPos())
        if poi and pmap and poi.map == pmap then
            spot = { doLine = spot.doLine, place = spot.place, map = poi.map, x = poi.x, y = poi.y }
            approx = true
        end
    end
    local n
    for _, sn in ipairs(g.steps) do
        local rs = p.steps[sn]
        if rs and not p.done[sn] and (rs.kind == "turnin") == (kind == "turnin") then n = sn break end
    end
    return { n = n or (100000 + g.questID), synthetic = n == nil or nil, kind = kind, questID = g.questID, questIDs = {}, quest = g.quest, label = spot.doLine,
        approx = approx or false, map = spot.map, x = spot.x, y = spot.y, unlockedBy = {}, unlocks = {}, live = true,
        place = spot.place, doneCount = done, totalCount = total,
        unplaced = not WC.HasPlace(spot) or nil }
end

-- Rebuilds the live steps from the quest log and the plan's guidance: nothing is stored, so a reload gives the same
-- view. Returns whether what the panel shows changed.
local function live_refresh()
    local p = WC.plan
    if not p then return false end
    local live, ids = {}, {}
    for id in pairs(p.guidance or {}) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local state = WC.PlanQuestState(id)
        if state == "active" or state == "ready" then
            local st = live_step(p, p.guidance[id], state)
            if st then live[#live + 1] = st end
        end
    end
    local byQuest = {}
    for _, st in ipairs(live) do byQuest[st.questID] = st end
    if p.focus and not byQuest[p.focus] then p.focus = nil end
    local cur = route_next()
    local now = p.focus and byQuest[p.focus]
    if not now and cur then
        for _, st in ipairs(live) do
            if step_has_quest(cur, st.questID) then now = st break end
        end
    end
    local sig = {}
    for _, st in ipairs(live) do
        sig[#sig + 1] = st.questID .. ":" .. st.kind .. ":" .. st.label .. ":" .. tostring(st.n) .. ":" .. tostring(st.map) .. "," .. tostring(st.x) .. "," .. tostring(st.y)
    end
    sig = table.concat(sig, "|") .. "#" .. tostring(now and now.questID)
    local changed = sig ~= p.liveSig
    p.live, p.liveNow, p.liveSig = live, now, sig
    return changed
end

function WC.PlanLiveRefresh()
    return guarded("refresh", live_refresh, function()
        local p = WC.plan
        if p then p.live, p.liveNow, p.liveSig = {}, nil, nil end
        return false
    end)
end

-- True when the plan carries guidance, so the panel follows the quest log.
function WC.PlanFollowing()
    return WC.plan ~= nil and WC.plan.guidance ~= nil
end

-- Quest events advance the route with no /reload. QUEST_ACCEPTED carries (logIndex, questID) in
-- classic clients and (questID) alone elsewhere; every event also rescans the log.
function WC.PlanOnQuestEvent(event, a, b)
    if WC.ObserveQuestEvent then WC.ObserveQuestEvent(event, a, b) end
    local p = WC.plan
    if not p then return end
    local changed = false
    local id = tonumber(event == "QUEST_ACCEPTED" and (b or a) or a)
    if id and event == "QUEST_ACCEPTED" then WC.PlanFollowAccepted(id) end
    if id and (event == "QUEST_ACCEPTED" or event == "QUEST_TURNED_IN") then
        for _, s in ipairs(p.steps) do
            if s.questID == id and (event == "QUEST_ACCEPTED" and s.kind == "pickup"
                or event == "QUEST_TURNED_IN" and (not s.questIDs or #s.questIDs == 0 or s.kind ~= "turnin")) then
                changed = mark(s) or changed
            end
        end
    end
    changed = WC.PlanScan(event == "QUEST_ACCEPTED" and id or nil) or changed
    changed = WC.PlanLiveRefresh() or changed
    -- A turn-in (or a rescan that finds one) may open follow-ups: they turn solid, pulse once and carry "New".
    local opened = WC.PlanUnlockCheck()
    if #opened > 0 then
        changed = true
        local quests = {}
        for _, s in ipairs(opened) do
            if (s.questID or 0) > 0 then quests[s.questID] = true end
        end
        if next(quests) and WC.PulseQuests then WC.PulseQuests(quests, 3) end
        if C_Timer and C_Timer.After then
            C_Timer.After(WC.NEW_SECONDS + 0.5, function()
                if WC.db and WC.RefreshPlan then WC.RefreshPlan() end
                if WC.Refresh and WC.panel and WC.panel:IsShown() then WC.Refresh() end
            end)
        end
    end
    if changed and WC.RefreshPlan then WC.RefreshPlan() end
end

-- Redraws the digest panel and tracker when either is on screen, so live lines stay current.
local function refresh_panel()
    local f = WC.panel
    if WC.Refresh and f and (f:IsShown() or (WC.db.settings and WC.db.settings.tracker)) then WC.Refresh() end
end

-- Everything that follows the quest log and talents: plan marks, the map, the panel.
function WC.LiveUpdate(event, a, b)
    if event ~= "ZONE_CHANGED" and event ~= "ZONE_CHANGED_INDOORS" and event ~= "ZONE_CHANGED_NEW_AREA"
        and event ~= "PLAYER_ENTERING_WORLD" then
        WC.PlanOnQuestEvent(event, a, b)
    elseif WC.plan then -- a zone change: arriving completes a trip with no action, and HERE is rebuilt for the new zone
        local map = WC.PlayerPos and WC.PlayerPos()
        pcall(function()
            if map then WC.PlanArrive(map) end
            WC.PlanScan()
        end)
    end
    refresh_panel()
    if WC.RefreshMapPanelSoon then WC.RefreshMapPanelSoon() end
end

WC.LIVE_THROTTLE = 0.5 -- seconds; QUEST_LOG_UPDATE fires in bursts (looting), so it is coalesced

-- Runs LiveUpdate for a QUEST_LOG_UPDATE at most once per LIVE_THROTTLE seconds. Without a client
-- timer it runs at once.
local pending = false
function WC.LiveUpdateSoon(event)
    if not (C_Timer and C_Timer.After) then return WC.LiveUpdate(event) end
    if pending then return end
    pending = true
    C_Timer.After(WC.LIVE_THROTTLE, function()
        pending = false
        if WC.db then WC.LiveUpdate(event) end
    end)
end

-- The tracker's text: step count and label, then distance and direction from the player.
function WC.PlanText(step, mapID, px, py)
    local done, total = WC.PlanCounts()
    if not step then return string.format(L.PLAN_DONE, total) end
    local text = string.format(L.PLAN_STEP, WC.StepNumber(step), total, WC.PlanLiveText(step, step.label))
    if mapID == step.map and px then
        local d, dir = WC.PlanDistance(px, py, step.x, step.y, WC.MapYards(mapID))
        return text .. string.format(L.PLAN_DISTANCE, math.floor(d + 0.5), dir)
    end
    return text .. L.PLAN_ELSEWHERE
end

-- The panel header's next-step line: "Step 1/20 · label · 125 yd W". Empty when there is no plan.
function WC.NextStepLine(step, mapID, px, py)
    local done, total = WC.PlanCounts()
    if total == 0 then return "" end
    if not step then return string.format(L.PLAN_DONE, total) end
    local label = WC.PlanLiveText(step, step.label)
    local text = string.format(L.NEXT_STEP_LINE, WC.StepNumber(step), total, label)
    if step.hereFirst then
        text = string.format(L.HERE_FIRST, WC.StepNumber(step), total) .. " · " .. label
        local sk = step.skipped and WC.PlaceName(nil, step.skipped.map)
        if sk then text = text .. " · " .. string.format(L.HERE_FIRST_SKIPPED, sk) end
    end
    local place = step.place and WC.PlaceName(step.place, step.map)
    if place and not label:find(place, 1, true) then text = text .. string.format(L.NEXT_STEP_PLACE, place) end
    if mapID == step.map and px then
        local d, dir = WC.PlanDistance(px, py, step.x, step.y, WC.MapYards(mapID))
        text = text .. string.format(L.PLAN_DISTANCE, math.floor(d + 0.5), dir)
    else
        text = text .. L.PLAN_ELSEWHERE
    end
    if step.totalCount and step.totalCount > 1 and step.doneCount then
        text = text .. string.format(L.NEXT_STEP_PROGRESS, step.doneCount, step.totalCount)
    end
    return text
end

-- The "next step only" rows: the digest's quest entry for the next step's quest with its objective rows, nothing else.
function WC.NextStepRows(rows, step)
    local out, on = {}, false
    local id = step and step.questID
    if not id or id <= 0 then return out end
    for _, r in ipairs(rows) do
        if r.kind == "quest" then
            if on then break end
            on = r.quest == id
            if on then out[#out + 1] = r end
        elseif on and (r.kind == "obj" or r.kind == "status") then
            out[#out + 1] = r
        elseif on then
            break
        end
    end
    return out
end

-- The rows a view shows: all of them, the compact cut, or the next step's entry.
function WC.ViewRows(mode, rows, expanded, step)
    if mode == "compact" then return WC.CompactRows(rows, expanded) end
    if mode == "next" then return WC.NextStepRows(rows, step) end
    return rows
end

-- ---------------------------------------------------------------- the "Here" card (Plan.lua 1.3)

WC.HERE_YARDS = 40 -- how close to an NPC's spot the card shows
WC.HERE_THROTTLE = 1 -- seconds between distance checks while walking

local function item_name(text)
    return (text:gsub("%s*%(%d+/%d+%)%s*$", ""):gsub("^%d+/%d+%s*", ""))
end

-- The items of a here-quest still open: matched by name against the quest log's finished objectives; with no
-- log objectives to compare, every item counts as open.
local function open_items(q)
    local live = WC.QuestObjectives(q.questID)
    local out = {}
    for _, m in ipairs(q.missing) do
        local fin = false
        local name = item_name(m.doLine):gsub("^%a+ ", ""):lower()
        for _, lo in ipairs(live or {}) do
            local ln = lo.text:gsub("^%d+/%d+%s*", ""):gsub(":?%s*%d+/%d+$", ""):lower()
            if lo.finished and ln ~= "" and (ln:find(name, 1, true) or name:find(ln, 1, true)) then fin = true break end
        end
        if not fin then out[#out + 1] = m end
    end
    return out
end

-- The nearest "here" block within HERE_YARDS of the player on this map, or nil.
function WC.HereBlock(mapID, px, py)
    local p = WC.plan
    if not (p and p.here and mapID and px) then return nil end
    local best, bestD
    for _, b in ipairs(p.here) do
        if b.map == mapID then
            local d = WC.PlanDistance(px, py, b.x, b.y, WC.MapYards(mapID))
            if d <= WC.HERE_YARDS and (not bestD or d < bestD) then best, bestD = b, d end
        end
    end
    return best, bestD
end

local function pickup_fits(p, id)
    local lvl = UnitLevel and tonumber(UnitLevel("player"))
    for _, s in ipairs(p.steps) do
        if s.questID == id and s.kind == "pickup" and s.level and lvl and s.level > lvl then return false end
    end
    return true
end

-- The route step of this kind for the quest, not yet done: later than the current step it is a "while you're here".
local function later_step(p, id, kind)
    local cur = route_next()
    for _, s in ipairs(p.steps) do
        if s.questID == id and s.kind == kind and not p.done[s.n] and cur and s.n > cur.n then return s end
    end
end

-- True when the player stands within HERE_YARDS of a trip quest's finisher (on the finisher's own map).
function WC.TripNear(id, mapID, px, py)
    local p = WC.plan
    if not (p and mapID and px) then return false end
    local spots = finisher_spots(p, id)
    for _, sp in ipairs(spots) do
        if sp.map == mapID and WC.PlanDistance(px, py, sp.x, sp.y, WC.MapYards(mapID)) <= WC.HERE_YARDS then return true end
    end
    return false
end

-- The card for where the player stands: { title, lines = { text }, key } or nil. Lines come from the live quest log.
function WC.HereCard(mapID, px, py)
    local p = WC.plan
    local b = WC.HereBlock(mapID, px, py)
    if not b then return nil end
    local lines, whileHere = {}, {}
    for _, q in ipairs(b.quests) do
        local state = WC.PlanQuestState(q.questID)
        local title = q.quest ~= "" and q.quest or (WC.QuestTitle(q.questID) or "?")
        if q.role == "turnin" and state == "ready" and trip_of(q.questID) and not WC.TripNear(q.questID, mapID, px, py) then
            -- a trip's finisher is elsewhere: not a turn-in line here
        elseif q.role == "turnin" and state == "ready" then
            local later = later_step(p, q.questID, "turnin")
            if later then
                whileHere[#whileHere + 1] = string.format(L.HERE_WHILE, later.n, string.format(L.HERE_TURNIN_LC, title))
            else
                lines[#lines + 1] = string.format(L.HERE_TURNIN, title)
            end
        elseif q.role == "turnin" and state == "active" then
            local need = {}
            for _, m in ipairs(open_items(q)) do
                need[#need + 1] = item_name(m.doLine) .. ((m.place or m.zone) and (" (" .. (m.place and WC.PlaceName(m.place, m.map) or m.zone) .. ")") or "")
            end
            if #need > 0 then
                lines[#lines + 1] = string.format(L.HERE_TURNIN_NEED, title, table.concat(need, ", "))
            else
                lines[#lines + 1] = string.format(L.HERE_TURNIN, title)
            end
        elseif q.role == "pickup" and state == "none" and pickup_fits(p, q.questID) then
            local later = later_step(p, q.questID, "pickup")
            if later then
                whileHere[#whileHere + 1] = string.format(L.HERE_WHILE, later.n, string.format(L.HERE_PICKUP_LC, title))
            else
                lines[#lines + 1] = string.format(L.HERE_PICKUP, title)
            end
        end
    end
    local trains, vendor = false, false
    for _, c in ipairs(b.can) do
        if c == "train" then trains = true elseif c == "buy and sell" or c == "repair" then vendor = true end
    end
    if trains then lines[#lines + 1] = L.HERE_TRAIN end
    if vendor then lines[#lines + 1] = L.HERE_VENDOR end
    for _, w in ipairs(whileHere) do lines[#lines + 1] = w end
    if #lines == 0 then return nil end
    return { title = b.npc ~= "" and b.npc or (b.place and WC.PlaceName(b.place, b.map) or "?"), lines = lines, key = b.npc .. "#" .. table.concat(lines, "|") }
end

-- Quests in the log that the route does not list but the plan has guidance for (its own, or a nearby block's):
-- { { questID, quest, line, spot } }, each with what to do next (its first open objective, or its turn-in).
local function also_doing()
    local p = WC.plan
    local out = {}
    if not p then return out end
    local pool = {}
    for id, g in pairs(p.guidance or {}) do pool[id] = g end
    for _, b in ipairs(p.here or {}) do
        for id, g in pairs(b.nearby) do pool[id] = pool[id] or g end
    end
    local ids = {}
    for id in pairs(pool) do ids[#ids + 1] = id end
    table.sort(ids)
    local cur = WC.PlanNext() -- the headline step's quest is never repeated below it
    for _, id in ipairs(ids) do
        local listed = false
        for _, s in ipairs(p.steps) do
            if step_has_quest(s, id) then listed = true break end
        end
        local state = WC.PlanQuestState(id)
        if not listed and not (cur and step_has_quest(cur, id)) and (state == "active" or state == "ready") then
            local g = pool[id]
            local spot
            if state == "ready" then spot = g.turnin else spot = open_objective(g, id) end
            if spot then
                local name = g.quest ~= "" and g.quest or (WC.QuestTitle(id) or "?")
                out[#out + 1] = { questID = id, quest = name, line = spot.doLine, spot = spot, ready = state == "ready" }
            end
        end
    end
    return out
end
function WC.AlsoDoing()
    return guarded("also", also_doing, function() return {} end)
end

-- ---------------------------------------------------------------- live turn-ins (read from the log, no reload)

WC.TURNIN_YARDS = 300 -- a ready quest's finisher this close on the same continent still counts as "here"
WC.PLAN_STALE_SECONDS = 1800 -- a plan older than this may be out of step with the log

-- True when the quest is in the log and ready to hand in: ReadyForTurnIn, then IsComplete, then the legacy flag.
local function log_ready(id)
    local q = C_QuestLog
    if not q then return false end
    if q.IsQuestFlaggedCompleted and q.IsQuestFlaggedCompleted(id) then return false end
    if q.GetLogIndexForQuestID and not q.GetLogIndexForQuestID(id) then return false end
    if q.ReadyForTurnIn and q.ReadyForTurnIn(id) then return true end
    if q.IsComplete and q.IsComplete(id) then return true end
    local idx = q.GetLogIndexForQuestID and q.GetLogIndexForQuestID(id)
    if idx and GetQuestLogTitle then
        local ok, _, _, _, header, _, isComplete = pcall(GetQuestLogTitle, idx)
        return ok and not header and (isComplete == 1 or isComplete == true)
    end
    return false
end

-- The quest ids in the log that are ready, sorted. Walks the log when the client lists it, else the plan's own ids.
local function ready_ids(p)
    local seen, ids = {}, {}
    local function add(id)
        if id and id > 0 and not seen[id] and log_ready(id) then seen[id] = true ids[#ids + 1] = id end
    end
    local q = C_QuestLog
    if q and q.GetNumQuestLogEntries and q.GetInfo then
        for i = 1, (q.GetNumQuestLogEntries()) or 0 do
            local info = q.GetInfo(i)
            if type(info) == "table" and not info.isHeader then add(tonumber(info.questID)) end
        end
    end
    for id in pairs(p.finishers or {}) do add(id) end
    for _, s in ipairs(p.steps) do
        if s.kind == "turnin" then
            add(s.questID)
            for _, id in ipairs(s.questIDs or {}) do add(id) end
        end
    end
    for id in pairs(p.guidance or {}) do add(id) end
    table.sort(ids)
    return ids
end

-- Where a quest is handed in: the plan's finishers row, else (an older plan) its own turn-in steps, guidance and
-- here blocks. { { npc, map, x, y, place } } or {}.
function finisher_spots(p, id)
    local f = p.finishers and p.finishers[id]
    if f then return f.spots, f.quest end
    local spots, name = {}, ""
    for _, s in ipairs(p.steps) do
        if s.kind == "turnin" and (s.questID == id or step_has_quest(s, id)) then
            spots[#spots + 1] = { npc = s.label:match("^Turn in .- to (.+)$") or "", map = s.map, x = s.x, y = s.y, place = s.place }
            if name == "" then name = s.quest end
        end
    end
    local g = p.guidance and p.guidance[id]
    if g and g.turnin then
        spots[#spots + 1] = { npc = "", map = g.turnin.map, x = g.turnin.x, y = g.turnin.y, place = g.turnin.place }
        if name == "" then name = g.quest end
    end
    for _, b in ipairs(p.here or {}) do
        for _, hq in ipairs(b.quests) do
            if hq.questID == id and hq.role == "turnin" then
                spots[#spots + 1] = { npc = b.npc, map = b.map, x = b.x, y = b.y, place = b.place }
                if name == "" then name = hq.quest end
            end
        end
    end
    return spots, name
end

-- Yards from the player to a spot: on the same map straight, on another map of the same continent through world
-- positions; nil when the two cannot be compared.
local function spot_yards(mapID, px, py, spot)
    if spot.map == mapID then return (WC.PlanDistance(px, py, spot.x, spot.y, WC.MapYards(mapID))) end
    if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
    local ok, c1, w1, c2, w2 = pcall(function()
        local a, wa = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(px / 100, py / 100))
        local b, wb = C_Map.GetWorldPosFromMapPos(spot.map, CreateVector2D(spot.x / 100, spot.y / 100))
        return a, wa, b, wb
    end)
    if not (ok and c1 and c1 == c2 and w1 and w2 and w1.GetXY and w2.GetXY) then return nil end
    local ax, ay = w1:GetXY()
    local bx, by = w2:GetXY()
    return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

-- Ready quests whose finisher is here (the player's map, or within TURNIN_YARDS on the continent), nearest first:
-- { { questID, quest, spot, yards } }. Live extras: they are not plan steps and change no counter.
function WC.LiveTurnIns(mapID, px, py)
    local p = WC.plan
    local out = {}
    if not (p and mapID and px) then return out end
    for _, id in ipairs(ready_ids(p)) do
        local spots, name = finisher_spots(p, id)
        local best, bestD
        for _, sp in ipairs(spots) do
            local d = spot_yards(mapID, px, py, sp)
            local reach = trip_of(id) and WC.HERE_YARDS or WC.TURNIN_YARDS -- a trip's finisher counts only when the player is at it
            if d and (sp.map == mapID or d <= reach) and (not bestD or d < bestD) and (reach ~= WC.HERE_YARDS or (sp.map == mapID and d <= reach)) then best, bestD = sp, d end
        end
        if best then
            local title = (name and name ~= "" and name) or WC.QuestTitle(id) or "?"
            out[#out + 1] = { questID = id, quest = title, spot = best, yards = bestD }
        end
    end
    table.sort(out, function(a, b) if a.yards ~= b.yards then return a.yards < b.yards end return a.questID < b.questID end)
    return out
end

-- ---------------------------------------------------------------- live training offers

-- Copper as "1g 2s 3c", zero parts left out; "" for nothing.
function WC.CopperText(c)
    c = math.floor(tonumber(c) or 0)
    if c <= 0 then return "" end
    local parts = {}
    if c >= 10000 then parts[#parts + 1] = math.floor(c / 10000) .. "g" end
    if c % 10000 >= 100 then parts[#parts + 1] = math.floor(c % 10000 / 100) .. "s" end
    if c % 100 > 0 then parts[#parts + 1] = (c % 100) .. "c" end
    return table.concat(parts, " ")
end

local function train_spot(line, sp)
    local map = tonumber(sp.map) or tonumber(line.map)
    local x = tonumber(sp.x) or tonumber(line.x)
    local y = tonumber(sp.y) or tonumber(line.y)
    local npc = sp.npc or line.npc
    return { map = map, x = x, y = y, npc = type(npc) == "string" and npc or "" }
end

-- The digest's training offers that carry the live fields (a spell `state`, with `requires`, `level`, `cost`) and
-- are open to buy now: not known, the prerequisite known (or none), the level reached. Grouped by trainer, the
-- one beside the player first. An older digest without the fields gives nothing.
-- { { spot, offers = { { id, name, cost } }, total, here } }
function WC.TrainableNow(mapID, px, py)
    local d = WoWCompanionDigest
    local out = {}
    if type(d) ~= "table" or type(d.sections) ~= "table" then return out end
    local me = UnitName and UnitName("player")
    if me and type(d.character) == "string" and d.character ~= me then return out end
    local lvl = UnitLevel and tonumber(UnitLevel("player"))
    local byKey, order = {}, {}
    for _, section in ipairs(d.sections) do
        if section.id == "next_quests" and type(section.lines) == "table" then
            for _, line in ipairs(section.lines) do
                if type(line) == "table" and line.kind == "training" and type(line.spells) == "table" then
                    for _, sp in ipairs(line.spells) do
                        local id = type(sp) == "table" and tonumber(sp.id)
                        local need = id and tonumber(sp.requires)
                        local at = id and tonumber(sp.level)
                        if id and type(sp.state) == "string" and not WC.SpellKnown(id) and (not need or WC.SpellKnown(need))
                            and (not at or (lvl and at <= lvl)) then
                            local spot = train_spot(line, sp)
                            local key = spot.npc .. "#" .. tostring(spot.map)
                            local g = byKey[key]
                            if not g then
                                g = { spot = spot, offers = {}, total = 0 }
                                byKey[key] = g
                                order[#order + 1] = g
                            end
                            local o = { id = id, name = WC.SpellLabel(sp), cost = math.max(0, tonumber(sp.cost) or 0) }
                            g.offers[#g.offers + 1] = o
                            g.total = g.total + o.cost
                        end
                    end
                end
            end
        end
    end
    for _, g in ipairs(order) do
        local sp = g.spot
        local yards
        if mapID and px and sp.map and sp.x and sp.y then yards = spot_yards(mapID, px, py, sp) end
        g.here = yards ~= nil and sp.map == mapID and yards <= WC.HERE_YARDS
        out[#out + 1] = g
    end
    table.sort(out, function(a, b)
        if a.here ~= b.here then return a.here end
        return a.spot.npc < b.spot.npc
    end)
    return out
end

-- Panel rows for the groups: "Here: train ..." beside the trainer, else "Train now: ..., at NPC (x, y)"; gold, on top.
local function train_rows(mapID, px, py)
    local rows = {}
    for _, g in ipairs(WC.TrainableNow(mapID, px, py)) do
        local names = {}
        for i, o in ipairs(g.offers) do names[i] = o.name end
        local list = table.concat(names, ", ")
        local cost = WC.CopperText(g.total)
        if cost ~= "" then list = list .. ", " .. cost end
        local sp = g.spot
        local text
        if g.here then
            text = string.format(L.HERE_TRAIN_NOW, list)
        elseif sp.npc ~= "" and sp.x and sp.y then
            text = string.format(L.TRAIN_NOW_AT, list, sp.npc, math.floor(sp.x + 0.5), math.floor(sp.y + 0.5))
        else
            text = string.format(L.TRAIN_NOW, list)
        end
        rows[#rows + 1] = { kind = "line", color = WC.COLORS.gold, text = text }
    end
    return rows
end
function WC.TrainRows(mapID, px, py)
    return guarded("train", train_rows, function() return {} end, mapID, px, py)
end

-- Map badges for those turn-ins: synthetic steps shaped like the live steps, so the map draws them the same way.
function WC.LiveTurnInSteps()
    local out = {}
    if not (WC.plan and WC.PlayerPos) then return out end
    local mapID, px, py = WC.PlayerPos()
    local have = {}
    for _, st in ipairs(WC.plan.live or {}) do have[st.questID] = true end
    for _, t in ipairs(WC.LiveTurnIns(mapID, px, py)) do
        if not have[t.questID] and t.spot.map == mapID then
            out[#out + 1] = { n = 200000 + t.questID, synthetic = true, kind = "turnin", questID = t.questID, questIDs = {},
                quest = t.quest, label = string.format(L.HERE_TURNIN, t.quest), approx = false, map = t.spot.map, x = t.spot.x,
                y = t.spot.y, unlockedBy = {}, unlocks = {}, live = true, place = t.spot.place }
        end
    end
    return out
end

-- "Plan from 4:38 PM; /reload to refresh it" once the plan is old and the live log disagrees with it, else nil.
-- Latched: once shown it stays the one line for this session, and nothing ever asks for or triggers a reload.
function WC.StaleNote(mapID)
    local p = WC.plan
    if not p then return nil end
    if p.behind then -- the one line: the 30-minute stale note never joins it
        if WC.lagDismissed then return nil end
        return L.PLAN_LAG_NOTE
    end
    if WC.staleNoted then return WC.staleNoted end
    if not (p.generated and p.generated > 0 and time() - p.generated > WC.PLAN_STALE_SECONDS) then return nil end
    local differs = false
    for _, id in ipairs(ready_ids(p)) do
        local listed = false
        for _, s in ipairs(p.steps) do
            if s.kind == "turnin" and step_has_quest(s, id) then listed = true break end
        end
        if not listed then differs = true break end
    end
    local cur = WC.PlanNext()
    if not differs and cur and mapID and cur.map and cur.map ~= mapID then differs = true end
    if not differs then return nil end
    WC.staleNoted = string.format(L.PLAN_STALE_NOTE, WC.FormatClock(p.generated))
    return WC.staleNoted
end

-- ---------------------------------------------------------------- "Also doing": near quests, a cap, the rest grouped

WC.ALSO_DOING_MAX = 3 -- the default for the alsoDoingMax setting

local function map_info(id)
    local ok, info = pcall(function() return C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(id) end)
    if ok and type(info) == "table" then return info end
end
local function good_name(info)
    return info and type(info.name) == "string" and info.name ~= "" and not info.name:match("^map %d+$") and info.name or nil
end
local function map_name(id)
    return good_name(map_info(id))
end

-- A label safe to show: never "map 310". A missing label or a raw "map N" is resolved through the client's map
-- (pcall-guarded): the map's own name, else its parent's name plus "(instance)", else "Unknown place".
-- `place` is the label from the plan, `mapID` the map it belongs to (read from "map N" when not given).
function WC.PlaceName(place, mapID)
    if type(place) == "string" and place ~= "" and not place:match("^%s*[Mm]ap %d+%s*$") then return place end
    local id = tonumber(mapID) or (type(place) == "string" and tonumber(place:match("^%s*[Mm]ap (%d+)%s*$"))) or nil
    if id then
        local info = map_info(id)
        local name = good_name(info)
        if name then return name end
        local parent = info and tonumber(info.parentMapID)
        if parent and parent > 0 then
            local pn = map_name(parent)
            if pn then return pn .. L.PLACE_INSTANCE end
        end
    end
    return L.PLACE_UNKNOWN
end

-- The row text for a quest in a list: ready ones get a gold "?" turn-in marker (the map's glyph) before the name.
function WC.ReadyMark(text) return L.READY_MARK .. text end

-- The place a quest's next spot belongs to, for grouping: its zone, else its map's name, else its place.
local function entry_zone(a)
    local sp = a.spot
    if sp.zone then return sp.zone end
    if sp.map or sp.place then return WC.PlaceName(sp.place, sp.map) end
    return L.ALSO_ELSEWHERE
end

-- Yards to an entry when it is near the player (same map, or within TURNIN_YARDS on the continent); an unplaced
-- objective is near only while the player is in its zone. nil when not near.
local function entry_near(a, mapID, px, py)
    local sp = a.spot
    if not (mapID and px) then return nil end
    if sp.map and sp.x then
        local d = spot_yards(mapID, px, py, sp)
        if d and (sp.map == mapID or d <= WC.TURNIN_YARDS) then return d end
        return nil
    end
    if sp.zone then
        local here = map_name(mapID)
        if not here and GetZoneText then here = GetZoneText() end
        if here and here:lower() == sp.zone:lower() then return WC.TURNIN_YARDS end
    end
    return nil
end

local function char_record()
    if not (WC.db and UnitName and GetRealmName) then return nil end
    local name = UnitName("player")
    if type(name) ~= "string" or name == "" then return nil end
    if type(WC.db.characters) ~= "table" then WC.db.characters = {} end
    local key = (GetRealmName() or "") .. ":" .. name
    if type(WC.db.characters[key]) ~= "table" then WC.db.characters[key] = {} end
    return WC.db.characters[key]
end

-- The expanded "rest of the log" view, remembered per character; collapsed by default.
function WC.AlsoExpanded()
    local r = char_record()
    return r ~= nil and r.alsoExpanded == true
end
function WC.ToggleAlsoExpanded()
    local r = char_record()
    if not r then return false end
    r.alsoExpanded = (not r.alsoExpanded) or nil
    return r.alsoExpanded == true
end

local function also_max()
    local n = WC.Setting and tonumber(WC.Setting("alsoDoingMax"))
    if not n then n = WC.ALSO_DOING_MAX end
    return math.max(0, math.min(10, math.floor(n)))
end

-- Splits the "Also doing" list: { near = shown rows (ready first, nearest first, capped), rest = every other entry }.
function WC.AlsoDoingSplit(mapID, px, py)
    local near, rest = {}, {}
    for _, a in ipairs(WC.AlsoDoing()) do
        local d = entry_near(a, mapID, px, py)
        if d then a.yards = d near[#near + 1] = a else rest[#rest + 1] = a end
    end
    table.sort(near, function(a, b)
        if a.ready ~= b.ready then return a.ready end
        if a.yards ~= b.yards then return a.yards < b.yards end
        return a.questID < b.questID
    end)
    local max, shown = also_max(), {}
    for i, a in ipairs(near) do
        if i <= max then shown[#shown + 1] = a else rest[#rest + 1] = a end
    end
    return { near = shown, rest = rest }
end

local function also_line(a, mapID, px, py)
    local t = string.format(L.ALSO_DOING_LINE, a.quest, a.line)
    if a.spot.map and a.spot.map == mapID and px and a.spot.x then
        local d, dir = WC.PlanDistance(px, py, a.spot.x, a.spot.y, WC.MapYards(mapID))
        t = t .. string.format(L.PLAN_DISTANCE, math.floor(d + 0.5), dir)
    end
    return t
end

-- A quest's row: ready ones in the user's ready colour with the turn-in marker.
local function quest_row(a, indent, t)
    if not a.ready then return { kind = "line", indent = indent, text = t } end
    local color = WC.Setting("readyColor")
    return { kind = "line", indent = indent, text = WC.ReadyMark(t), color = color }
end

local function also_rows(mapID, px, py)
    local sp = WC.AlsoDoingSplit(mapID, px, py)
    local rows = {}
    if #sp.near == 0 and #sp.rest == 0 then return rows end
    if #sp.near > 0 then
        rows[#rows + 1] = { kind = "line", text = L.ALSO_DOING, color = WC.COLORS.gold }
        for _, a in ipairs(sp.near) do
            rows[#rows + 1] = quest_row(a, 1, also_line(a, mapID, px, py))
        end
    end
    if #sp.rest == 0 then return rows end
    -- the rest, grouped by place; places with the most ready turn-ins first, ready turn-ins first inside each
    local groups, order, ready = {}, {}, 0
    for _, a in ipairs(sp.rest) do
        local z = entry_zone(a)
        local g = groups[z]
        if not g then g = { zone = z, ready = 0, list = {} } groups[z] = g order[#order + 1] = g end
        g.list[#g.list + 1] = a
        if a.ready then g.ready = g.ready + 1 ready = ready + 1 end
    end
    table.sort(order, function(a, b)
        if a.ready ~= b.ready then return a.ready > b.ready end
        if #a.list ~= #b.list then return #a.list > #b.list end
        return a.zone < b.zone
    end)
    local summary = string.format(L.ALSO_MORE, #sp.rest)
    if ready > 0 then
        local names = {}
        for _, g in ipairs(order) do
            if g.ready > 0 and #names < 3 then names[#names + 1] = g.ready .. " " .. g.zone end
        end
        summary = summary .. string.format(L.ALSO_MORE_READY, ready, table.concat(names, ", "))
    end
    local open = WC.AlsoExpanded()
    rows[#rows + 1] = { kind = "line", text = summary .. (open and L.ALSO_HIDE or ""), color = WC.COLORS.dim,
        click = function() WC.ToggleAlsoExpanded() if WC.Refresh then WC.Refresh() end end }
    if open then
        for _, g in ipairs(order) do
            table.sort(g.list, function(a, b)
                if a.ready ~= b.ready then return a.ready end
                return a.questID < b.questID
            end)
            rows[#rows + 1] = { kind = "line", indent = 1, text = (g.ready > 0 and string.format(L.ALSO_ZONE_READY, g.zone, #g.list, g.ready) or string.format(L.ALSO_ZONE, g.zone, #g.list)), color = WC.COLORS.gold }
            for _, a in ipairs(g.list) do
                local t = a.ready and string.format(L.ALSO_READY_LINE, a.quest) or string.format(L.ALSO_DOING_LINE, a.quest, a.line)
                rows[#rows + 1] = quest_row(a, 2, t)
            end
        end
    end
    return rows
end
function WC.AlsoDoingRows(mapID, px, py)
    return guarded("also", also_rows, function() return {} end, mapID, px, py)
end

-- Panel rows for the card and the "Also doing" section, to sit above the digest rows. Plain rows, data only.
local function here_rows(mapID, px, py)
    local rows = WC.TrainRows(mapID, px, py)
    for _, t in ipairs(WC.LiveTurnIns(mapID, px, py)) do
        local who = t.spot.npc ~= "" and (t.quest .. ": " .. t.spot.npc) or t.quest
        rows[#rows + 1] = { kind = "line", color = WC.COLORS.gold,
            text = string.format(L.HERE_LIVE_TURNIN, who, math.floor(t.spot.x + 0.5), math.floor(t.spot.y + 0.5)) }
    end
    local card = WC.HereCard(mapID, px, py)
    if card then
        rows[#rows + 1] = { kind = "line", text = string.format(L.HERE_TITLE, card.title), color = WC.COLORS.gold }
        for _, t in ipairs(card.lines) do rows[#rows + 1] = { kind = "line", indent = 1, text = t } end
    end
    for _, r in ipairs(WC.AlsoDoingRows(mapID, px, py)) do rows[#rows + 1] = r end
    local note = WC.StaleNote(mapID)
    if note then rows[#rows + 1] = { kind = "line", text = note, color = WC.COLORS.dim } end
    return rows
end
function WC.HereRows(mapID, px, py)
    return guarded("rows", here_rows, function() return {} end, mapID, px, py)
end

-- Called from the 0.2 s tick: checks the card at most once a second and redraws the panel only when it changed.
local function here_tick(mapID, px, py)
    local p = WC.plan
    if not p or not p.here then return end
    local t = now()
    if p.hereAt and t - p.hereAt < WC.HERE_THROTTLE then return end
    p.hereAt = t
    local card = WC.HereCard(mapID, px, py)
    local key = card and card.key or ""
    if key == p.hereKey then return end
    p.hereKey = key
    if WC.Refresh and WC.panel and WC.panel:IsShown() then WC.Refresh() end
end
function WC.HereTick(mapID, px, py)
    return guarded("tick", here_tick, nil, mapID, px, py)
end

local TRAIN_EVENTS = { SPELLS_CHANGED = true, LEARNED_SPELL_IN_TAB = true }
local ZONE_EVENTS = { ZONE_CHANGED = true, ZONE_CHANGED_INDOORS = true, ZONE_CHANGED_NEW_AREA = true, PLAYER_ENTERING_WORLD = true }
local events = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_LOGOUT", "QUEST_ACCEPTED", "QUEST_LOG_UPDATE", "QUEST_TURNED_IN", "QUEST_REMOVED",
    "PLAYER_LEVEL_UP", "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB", "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED",
    "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do pcall(events.RegisterEvent, events, e) end
events:SetScript("OnEvent", function(_, event, a, b)
    if not WC.db then return end
    if event == "PLAYER_LOGOUT" then
        WC.db.lastSave = time()
    elseif event == "PLAYER_LOGIN" then
        WC.PlanInit()
        if WC.RefreshPlan then WC.RefreshPlan() end
        refresh_panel()
    elseif TRAIN_EVENTS[event] then
        if not (InCombatLockdown and InCombatLockdown()) then WC.LiveUpdateSoon(event) end
    elseif event == "QUEST_LOG_UPDATE" or ZONE_EVENTS[event] then
        WC.LiveUpdateSoon(event)
    else
        WC.LiveUpdate(event, a, b)
    end
end)
