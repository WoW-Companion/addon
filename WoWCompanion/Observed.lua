-- WoW Companion: a small log of the player's own quest events (accepted, turned in, abandoned) with where they
-- happened, kept in WoWCompanionDB.observed. Plain data in our own SavedVariables: it leaves the game only when the
-- client saves (a /reload, logout or quit), and the addon never asks for one. The overlay reads it at each natural
-- save to route quests the plan did not know and to learn which turn-ins unlock which quests.
-- Format: { version = 2, events = { { t, ev, questID, character, map, x, y, npc?, offPlan? }, ... } }, oldest first.

local WC = WoWCompanion
local L = WC.L

WC.OBSERVED_CAP = 400 -- events kept; the oldest are dropped first
WC.OBSERVED_VERSION = 2
local REMOVED_WAIT = 1 -- seconds a removed quest waits to tell a turn-in from an abandon

local turned = {}      -- quest id -> true for turn-ins seen this session (a removal right after one is not an abandon)
local unplanned = {}   -- quest id -> true for quests accepted this session that the plan does not hold

local function store()
    local db = WC.db
    if not db then return nil end
    local o = db.observed
    if type(o) ~= "table" or type(o.events) ~= "table" then
        o = { version = WC.OBSERVED_VERSION, events = {} }
        db.observed = o
    end
    o.version = WC.OBSERVED_VERSION
    return o
end

local function round1(v)
    return math.floor(v * 10 + 0.5) / 10
end

-- Appends one event (when the log is on) and drops the oldest beyond the cap. Returns the event or nil.
function WC.ObservedAdd(ev, questID, offPlan, where)
    if not WC.Setting("keepObserved") then return nil end
    local o = store()
    if not o or not questID or questID <= 0 then return nil end
    local e = { t = time(), ev = ev, questID = questID, character = WC.Clean(UnitName and UnitName("player")) or "" }
    local map, x, y
    if where then map, x, y = where.map, where.x, where.y elseif WC.PlayerPos then map, x, y = WC.PlayerPos() end
    if map and x and y then e.map, e.x, e.y = map, round1(x), round1(y) end
    if ev == "accepted" then
        if UnitName and UnitExists and UnitExists("npc") then
            local name = WC.Clean(UnitName("npc"))
            if type(name) == "string" and name ~= "" then e.npc = name end
        end
        if WC.SeenGiverFor then WC.SeenGiverFor(e) end
        if offPlan then e.offPlan = true end
    end
    WC.CleanTree(e)
    o.events[#o.events + 1] = e
    while #o.events > WC.OBSERVED_CAP do table.remove(o.events, 1) end
    return e
end

-- True when the plan holds the quest anywhere: a step, a trip, a find entry or a parked (LATER) one.
local function in_plan(id)
    local p = WC.plan
    if not p then return false end
    for _, s in ipairs(p.steps or {}) do
        if s.questID == id then return true end
        for _, q in ipairs(s.questIDs or {}) do if q == id then return true end end
    end
    for _, t in ipairs(p.trips or {}) do
        for _, q in ipairs(t.questIDs or {}) do if q == id then return true end end
    end
    for _, k in ipairs(p.find or {}) do if k.questID == id then return true end end
    for _, k in ipairs(p.parked or {}) do if k.questID == id then return true end end
    for _, k in ipairs(p.later or {}) do if k.questID == id then return true end end
    return false
end

-- When the plan's save was taken: the save it was made from, else when it was generated. nil when unknown.
function WC.PlanSaveTime()
    local raw = WoWCompanionPlan
    local basis = type(raw) == "table" and type(raw.basis) == "table" and raw.basis or nil
    local at = basis and tonumber(basis.captured)
    if not at or at <= 0 then at = WC.plan and tonumber(WC.plan.generated) end
    return at and at > 0 and at or nil
end

-- Quest events feed the log. QUEST_REMOVED fires for abandons and for turn-ins alike, so it waits a moment and
-- only counts as an abandon when no turn-in arrived and the quest is not flagged complete.
function WC.ObserveQuestEvent(event, a, b)
    if not WC.db then return end
    if event == "QUEST_ACCEPTED" then
        local id = tonumber(b or a)
        if not id then return end
        turned[id] = nil
        local off = WC.plan ~= nil and not in_plan(id)
        if off then unplanned[id] = true end
        WC.ObservedAdd("accepted", id, off)
    elseif event == "QUEST_TURNED_IN" then
        local id = tonumber(a)
        if not id then return end
        turned[id] = true
        unplanned[id] = nil
        WC.ObservedAdd("turnedin", id)
    elseif event == "QUEST_REMOVED" then
        local id = tonumber(a)
        if not id then return end
        local map, x, y
        if WC.PlayerPos then map, x, y = WC.PlayerPos() end
        local function decide()
            if turned[id] then return end
            if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(id) then return end
            unplanned[id] = nil
            WC.ObservedAdd("abandoned", id, false, { map = map, x = x, y = y })
        end
        if C_Timer and C_Timer.After then C_Timer.After(REMOVED_WAIT, decide) else decide() end
    end
end

-- The quests accepted outside the plan that are still open: replays the log and this session's accepts, drops
-- anything the plan now holds (the overlay routed it) or that left the quest log. Oldest first:
-- { { id, title, new } }; new is true when the quest was accepted after the plan's save (or when that is unknown).
function WC.UnplannedQuests()
    local ids, order, at = {}, {}, {}
    local function add(id)
        if not ids[id] then ids[id] = true order[#order + 1] = id end
    end
    local o = WC.db and type(WC.db.observed) == "table" and WC.db.observed.events or {}
    local me = UnitName and UnitName("player")
    for _, e in ipairs(o) do
        if type(e) == "table" and (e.character == nil or e.character == "" or e.character == me) then
            if e.ev == "accepted" and e.offPlan then add(e.questID) at[e.questID] = tonumber(e.t)
            elseif e.ev == "turnedin" or e.ev == "abandoned" then ids[e.questID] = nil end
        end
    end
    for id in pairs(unplanned) do add(id) end
    local saved = WC.PlanSaveTime()
    local out = {}
    for _, id in ipairs(order) do
        if ids[id] and not in_plan(id) then
            local st = WC.PlanQuestState(id)
            if st == "active" or st == "ready" then
                local title = WC.QuestTitle and WC.QuestTitle(id)
                if title then
                    local new = not (saved and at[id] and at[id] <= saved)
                    out[#out + 1] = { id = id, title = title, new = new }
                    if not new and (WC.plan.trips or WC.plan.parked) then
                        WC.planGaps = WC.planGaps or {}
                        WC.planGaps[id] = title -- a plan with trips places every logged quest: shown by /wowc plan debug
                    end
                end
            end
        end
    end
    return out
end
