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
    WC.plan = { steps = steps, generated = generated, done = saved.done }
    WC.PlanScan()
end

-- The first step not yet done, or nil when the route is finished.
function WC.PlanNext()
    local p = WC.plan
    if not p then return end
    for _, s in ipairs(p.steps) do
        if not p.done[s.n] then return s end
    end
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
    local text = string.format(L.PLAN_STEP, math.min(done + 1, total), total, WC.PlanLiveText(step, step.label))
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
    local text = string.format(L.NEXT_STEP_LINE, math.min(done + 1, total), total, WC.PlanLiveText(step, step.label))
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
