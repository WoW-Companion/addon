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
                -- optional, shown in tooltips only when the plan carries them: quest level, class-quest name, NPC level text
                level = tonumber(s.level), class = type(s.class) == "string" and s.class ~= "" and plain(s.class) or nil,
                npcLevel = (type(s.npcLevel) == "string" or type(s.npcLevel) == "number") and plain(tostring(s.npcLevel)) or nil,
                -- Plan.lua 1.1 chain fields: a follow-up is locked until every quest in unlockedBy is turned in;
                -- a turn-in lists what it unlocks. A 1.0 plan has none of them and nothing is ever locked.
                locked = s.locked == true, unlockedBy = id_list(s.unlockedBy), unlocks = id_list(s.unlocks),
                chain = type(s.chain) == "string" and s.chain ~= "" and plain(s.chain) or nil,
            }
        end
    end
    if #steps == 0 then return nil, "character" end
    return steps, nil, tonumber(plan.generated) or 0
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

-- Loads the plan for this character and its saved done marks (a new plan starts clean).
function WC.PlanInit()
    local steps, _, generated = WC.ParsePlan(WoWCompanionPlan, UnitName("player"))
    WC.plan = nil
    if not steps then return end
    WC.db.plan = type(WC.db.plan) == "table" and WC.db.plan or {}
    local saved = WC.db.plan[charKey()]
    if type(saved) ~= "table" or saved.generated ~= generated or type(saved.done) ~= "table" then
        saved = { generated = generated, done = {} }
        WC.db.plan[charKey()] = saved
    end
    WC.plan = { steps = steps, generated = generated, done = saved.done, open = {}, newAt = {} }
    for _, st in ipairs(steps) do
        if st.locked then WC.plan.hasLocked = true end
    end
    WC.PlanScan()
    WC.PlanUnlockCheck(true)
end

-- The first step not yet done, or nil when the route is finished.
function WC.PlanNext()
    local p = WC.plan
    if not p then return end
    for _, s in ipairs(p.steps) do
        if not p.done[s.n] and not WC.StepLocked(s) then return s end
    end
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
    if WC.plan and WC.plan.hasLocked and step then return step.n end
    return math.min(done + 1, total)
end

function WC.PlanCounts()
    local p = WC.plan
    if not p then return 0, 0 end
    local n = 0
    for _ in pairs(p.done) do n = n + 1 end
    return n, #p.steps
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
        if s.questID > 0 then
            local st = WC.PlanQuestState(s.questID)
            if not p.done[s.n] then
                local done = (s.kind == "pickup" and st ~= "none")
                    or (s.kind == "objective" and (st == "ready" or st == "turnedin"))
                    or (s.kind == "turnin" and st == "turnedin")
                if done then changed = mark(s) or changed end
            elseif known and st == "none" and (s.kind == "pickup" or s.kind == "objective") and s.questID ~= keep then
                p.done[s.n] = nil
                changed = true
            end
        end
    end
    return changed
end

-- Quest events advance the route with no /reload. QUEST_ACCEPTED carries (logIndex, questID) in
-- classic clients and (questID) alone elsewhere; every event also rescans the log.
function WC.PlanOnQuestEvent(event, a, b)
    if WC.ObserveQuestEvent then WC.ObserveQuestEvent(event, a, b) end
    local p = WC.plan
    if not p then return end
    local changed = false
    local id = tonumber(event == "QUEST_ACCEPTED" and (b or a) or a)
    if id and (event == "QUEST_ACCEPTED" or event == "QUEST_TURNED_IN") then
        for _, s in ipairs(p.steps) do
            if s.questID == id and (event == "QUEST_TURNED_IN" or s.kind == "pickup") then changed = mark(s) or changed end
        end
    end
    changed = WC.PlanScan(event == "QUEST_ACCEPTED" and id or nil) or changed
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
    WC.PlanOnQuestEvent(event, a, b)
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
    local text = string.format(L.NEXT_STEP_LINE, WC.StepNumber(step), total, WC.PlanLiveText(step, step.label))
    if mapID == step.map and px then
        local d, dir = WC.PlanDistance(px, py, step.x, step.y, WC.MapYards(mapID))
        return text .. string.format(L.PLAN_DISTANCE, math.floor(d + 0.5), dir)
    end
    return text .. L.PLAN_ELSEWHERE
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

local events = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "QUEST_ACCEPTED", "QUEST_LOG_UPDATE", "QUEST_TURNED_IN", "QUEST_REMOVED",
    "PLAYER_LEVEL_UP", "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED" }) do events:RegisterEvent(e) end
events:SetScript("OnEvent", function(_, event, a, b)
    if not WC.db then return end
    if event == "PLAYER_LOGIN" then
        WC.PlanInit()
        if WC.RefreshPlan then WC.RefreshPlan() end
        refresh_panel()
    elseif event == "QUEST_LOG_UPDATE" then
        WC.LiveUpdateSoon(event)
    else
        WC.LiveUpdate(event, a, b)
    end
end)
