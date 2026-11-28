-- WoW Companion: the panel's plan layout. NOW (the map's current badge), HERE (the run on this map, numbered as the
-- map's badges are), TRIPS (the other zones, one collapsible row each) and LATER (parked quests). Display only: it
-- reads the plan and the quest log. HERE is built from the same badge groups the world map draws (WC.MapBadgeGroups),
-- so the two always agree; it is rebuilt from live quest state on every panel refresh. Each quest appears once.

local WC = WoWCompanion
local L = WC.L

WC.view = WC.view or {}
WC.view.tripOpen = WC.view.tripOpen or {}
WC.view.laterOpen = false

-- ---------------------------------------------------------------- the player's plan preferences, quest levels, hiding

-- The character's plan preferences, saved with its record in the SavedVariables: { levelReach, hidden, includeElite }.
-- The app reads them on its next save. nil when there is no saved table or no character yet; `create` makes the record.
local DEFAULT_REACH = 3
function WC.PlanPrefs(create)
    local db = WC.db
    if not (db and UnitName and GetRealmName) then return nil end
    local name, realm = UnitName("player"), GetRealmName()
    if type(name) ~= "string" or name == "" then return nil end
    local key = (realm or "") .. ":" .. name
    local rec = type(db.characters) == "table" and db.characters[key] or nil
    if type(rec) ~= "table" then
        if not create then return nil end
        if type(db.characters) ~= "table" then db.characters = {} end
        rec = { name = name, realm = realm }
        db.characters[key] = rec
    end
    local pp = rec.planPrefs
    if type(pp) ~= "table" then
        if not create then return nil end
        pp = { levelReach = DEFAULT_REACH, hidden = {}, includeElite = false }
        rec.planPrefs = pp
    end
    if type(pp.hidden) ~= "table" then pp.hidden = {} end
    return pp
end

-- The reach in levels (0-10) or nil for no limit, from the Settings row; the elite switch likewise.
function WC.PlanReach()
    local v = WC.Setting("planReach")
    if v == "all" or tonumber(v) == nil or tonumber(v) > 10 then return nil end
    return tonumber(v)
end

-- Mirrors the two Settings rows into planPrefs (only once there are prefs to keep, or a non-default choice to record).
function WC.SyncPlanPrefs()
    if not WC.db then return end
    local reach, elite = WC.PlanReach() or -1, WC.Setting("planElite") == true
    local pp = WC.PlanPrefs(false)
    if not pp and reach == DEFAULT_REACH and not elite then return end
    pp = pp or WC.PlanPrefs(true)
    if not pp then return end
    if pp.levelReach ~= reach or pp.includeElite ~= elite then pp.updated = time and time() or nil end
    pp.levelReach, pp.includeElite = reach, elite
end

function WC.QuestHidden(id)
    local pp = id and WC.PlanPrefs(false)
    return pp ~= nil and pp.hidden[id] == true
end

-- The plan's own entry for a quest: a step, a find or a parked line (level, diff, elite), or nil.
local function plan_entry(id)
    local p = WC.plan
    if not (p and id and id > 0) then return nil end
    for _, s in ipairs(p.steps) do
        if s.level then
            if s.questID == id then return s end
            for _, qid in ipairs(s.questIDs or {}) do if qid == id then return s end end
        end
    end
    for _, q in ipairs(p.find or {}) do if q.questID == id and q.level then return q end end
    for _, q in ipairs(p.parked or {}) do if q.questID == id and q.level then return q end end
end

-- A quest's level: the plan's, else the live quest log's. Second return: the plan's diff (quest level minus yours) or nil.
function WC.PlanQuestLevel(id)
    local e = plan_entry(id)
    if e then return e.level, e.diff end
    return WC.QuestLevel and WC.QuestLevel(id) or nil, nil
end

-- The colour of a level: from the plan's diff when it has one, else the game's own bands against your level.
function WC.LevelColor(level, diff)
    if diff then return WC.DifficultyColor(level, level - diff) end
    return WC.DifficultyColor(level)
end

local function hex(c)
    return string.format("|cff%02x%02x%02x", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

-- A level tag ("[38] ") in the neutral colour, by an inline colour escape, so a green "ready" row keeps its level plain.
function WC.NeutralTag(tag)
    return hex(WC.COLORS.white) .. (tag:gsub("%s+$", "")) .. "|r "
end

-- "[38] " for a quest row, or "" when levels are off or unknown. A ready turn-in's level is neutral (inline colour), so
-- the row's own colour (green) is left to say "ready".
function WC.LevelTag(id, neutral)
    if not WC.Setting("showLevels") then return "" end
    local level = id and WC.PlanQuestLevel(id)
    if not (level and level > 0) then return "" end
    local tag = string.format("[%d]", math.floor(level))
    if neutral then return WC.NeutralTag(tag) end
    return tag .. " "
end

-- True when a quest is further above the player than the reach allows (in the log or not, as the app parks it), or is
-- elite while elite quests are off (never one already in the log). A turned-in quest is never dropped.
local function out_of_reach(id, level, elite)
    if not id or id <= 0 then return false end
    local state = WC.PlanQuestState(id)
    if state == "turnedin" then return false end
    if state == "none" and elite and not WC.Setting("planElite") then return true end
    local reach, mine = WC.PlanReach(), UnitLevel and UnitLevel("player")
    return reach ~= nil and level ~= nil and mine ~= nil and level > mine + reach
end
function WC.QuestOutOfReach(id)
    local e = plan_entry(id)
    return e ~= nil and out_of_reach(id, e.level, e.elite)
end

-- True when a plan step is not wanted on the plan: its quest is hidden, or out of reach. Never errors (live path).
function WC.StepDismissed(step)
    local ok, v = pcall(function()
        if type(step) ~= "table" then return false end
        local ids = (step.questIDs and #step.questIDs > 0) and step.questIDs or { step.questID }
        local any
        for _, id in ipairs(ids) do
            id = tonumber(id)
            if id and id > 0 then
                if not (WC.QuestHidden(id) or out_of_reach(id, step.level, step.elite)) then return false end
                any = true
            end
        end
        return any == true
    end)
    return ok and v or false
end

-- A redraw of everything the plan touches: panel, map badges, map side panel.
local function redraw()
    if WC.ApplySettings then WC.ApplySettings() elseif WC.Refresh then WC.Refresh() end
end

function WC.HideQuest(id)
    id = tonumber(id)
    if not (id and id > 0) then return false end
    local pp = WC.PlanPrefs(true)
    if not pp then return false end
    pp.hidden[id] = true
    pp.updated = time and time() or nil
    redraw()
    return true
end

function WC.UnhideQuest(id)
    local pp = WC.PlanPrefs(false)
    if not (pp and pp.hidden[id]) then return false end
    pp.hidden[id] = nil
    pp.updated = time and time() or nil
    redraw()
    return true
end

function WC.UnhideAll()
    local pp = WC.PlanPrefs(false)
    if not pp then return end
    pp.hidden = {}
    pp.updated = time and time() or nil
    redraw()
end

-- The hidden quests as { id, name }, in quest id order.
function WC.HiddenQuests()
    local pp, out = WC.PlanPrefs(false), {}
    for id in pairs(pp and pp.hidden or {}) do
        local name = WC.QuestTitle(id)
        if not name and WC.plan then
            for _, s in ipairs(WC.plan.steps) do if s.questID == id and s.quest ~= "" then name = s.quest break end end
            for _, q in ipairs(WC.plan.parked or {}) do if q.questID == id and q.quest ~= "" then name = name or q.quest end end
            for _, q in ipairs(WC.plan.find or {}) do if q.questID == id and q.quest ~= "" then name = name or q.quest end end
        end
        out[#out + 1] = { id = id, name = name or L.QUEST_UNKNOWN:format(id) }
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

-- True while the saved choices are newer than the plan the app wrote ("Applies fully after your next save").
function WC.PlanPrefsPending()
    local pp = WC.PlanPrefs(false)
    return pp ~= nil and pp.updated ~= nil and (not WC.plan or (WC.plan.generated or 0) < pp.updated)
end

local function guarded(fn, fallback, ...)
    local ok, a = pcall(fn, ...)
    if ok then return a end
    return fallback
end

local function ids_of(step)
    if step.questIDs and #step.questIDs > 0 then return step.questIDs end
    return { step.questID }
end

local function yards_between(mapID, a, b)
    local w, h = WC.MapYards(mapID)
    return (WC.PlanDistance(a.x, a.y, b.x, b.y, w, h))
end

local function zone_name(mapID)
    local n = mapID and WC.PlaceName(nil, mapID)
    if n and n ~= L.PLACE_UNKNOWN then return n end
    return L.PANEL_THIS_ZONE
end

local function trip_zone(t)
    return t.zone or zone_name(t.map)
end

local function errand_of(plan, step)
    if step.errand and rawget(L, "ERRAND_" .. step.errand) then return step.errand end
    for _, e in ipairs(plan and plan.errands or {}) do
        if (e.n and e.n == step.n) or (e.questID and not e.n and e.questID == step.questID) then return e.kind end
    end
end

-- A merged stop's turn-in line: "Turn in Quest (Giver)" from the step's "Turn in Quest to Giver".
local function merged_text(step, id)
    local title = WC.QuestTitle(id)
    local label = step.label or ""
    if #ids_of(step) > 1 then
        local npc = label:match(" to ([^()]+)$")
        local name = title or L.QUEST_UNKNOWN:format(id)
        local verb = step.kind == "turnin" and (L.PANEL_TURNIN .. " ") or ""
        return npc and string.format("%s%s (%s)", verb, name, npc) or (verb .. name)
    end
    local quest, npc = label:match("^(.-) to ([^()]+)$")
    if step.kind == "turnin" and quest then return string.format("%s (%s)", quest, npc) end
    return label ~= "" and label or (step.quest or "")
end

-- The label a panel row leads with: the badge's step number(s), or nothing. A step with no number (a live turn-in) has
-- only the map badge's cut-short name for a label, which the panel never shows: its text already names the quest.
local function panel_label(steps)
    local l = WC.PinLabel(steps)
    return l:match("^%d") and l or ""
end

-- " in <place>" for a row's text, unless the text already names the place ("somewhere in Stranglethorn Vale").
local function in_place(text, place)
    if not place or place == "" then return text end
    if tostring(text):lower():find(tostring(place):lower(), 1, true) then return text end
    return text .. string.format(L.PANEL_IN_PLACE, place)
end

local function labelled(fmt, label, text)
    if label == "" then return text end
    return string.format(fmt, label, text)
end

-- A stop as a row: its badge label and its text (a travel step on the player's own map reads as its action). A stop
-- that merges several quests also lists each one in `items` ({ id, step, text }), so each is named with its own state.
local function stop_of(group, nums)
    local s = group.steps[1]
    local view = WC.PlanTipStep(s) or s
    local text = WC.PlanLiveText(view, view.label ~= "" and view.label or (s.quest or ""))
    local items = WC.GroupItems(group) -- a live turn-in step for a quest the plan already lists here is the same quest
    local stop = { label = WC.PinLabel(group.steps), plabel = panel_label(group.steps), text = text, step = s, group = group, x = group.x, y = group.y,
        isNext = group.isNext == true }
    for _, st in ipairs(group.steps) do stop.errand = stop.errand or errand_of(WC.plan, st) end
    if #items > 1 then
        for _, it in ipairs(items) do
            local st = it.step
            it.num = nums and nums.byStep[st] or nil
            local pn = tonumber(st.n)
            if not nums and pn and not st.synthetic and pn >= 1 and pn < 100000 and pn == math.floor(pn) then it.num = pn end -- no live order: the plan's number
            local live = WC.PlanLiveText(st, st.label ~= "" and st.label or (st.quest or ""))
            if st.kind == "turnin" then live = merged_text(st, it.id) end
            it.text = live
        end
        stop.items = items
        stop.text = items[1].text
    end
    return stop
end

-- What a step waits on, in live numbers: its plan `after` (else, for a turn-in, the quest's open objective steps),
-- a step already done dropped, never itself or a later number. Else, for a turn-in, the first unmet objective.
local function waits_on(id, step, nums)
    local plan = WC.plan
    local list = {}
    if step and type(step.after) == "table" then
        for _, n in ipairs(step.after) do list[#list + 1] = n end
    elseif step == nil or step.kind == "turnin" then
        for _, st in ipairs(plan and plan.steps or {}) do
            if st.kind == "objective" and st.questID == id and not plan.done[st.n] and tonumber(st.n) then list[#list + 1] = st.n end
        end
    end
    if #list > 0 then
        local own = step and (nums and nums.byStep[step] or (not nums and tonumber(step.n))) or nil
        local live = WC.LiveAfter(list, plan, nums, own)
        if #live == 0 then return nil end
        local text = {}
        for _, n in ipairs(live) do text[#text + 1] = tostring(n) end
        return string.format(#live == 1 and L.PANEL_AFTER_STEP or L.PANEL_AFTER_STEPS, table.concat(text, ", "))
    end
    if step and step.kind ~= "turnin" then return nil end
    for _, o in ipairs(WC.QuestObjectives and WC.QuestObjectives(id) or {}) do
        if not o.finished and o.text then return string.format(L.PANEL_AFTER_OBJ, (o.text:gsub("^%d+/%d+%s*", ""))) end
    end
end

-- The dim connector between two stops when the leg is worth a line: a zone change (boat), a known flight that saves
-- real walking, or a long ride. a and b are { map, x, y }; nil for a short leg or a stop with no spot.
local function leg_text(a, b)
    if not (a and b and a.x and b.x and a.map and b.map) then return nil end
    if a.map ~= b.map then
        return string.format(L.LEG_BOAT, zone_name(a.map), zone_name(b.map))
    end
    local w, h = WC.MapYards(a.map)
    local flight = WC.FlightLeg(WC.plan and WC.plan.flights, a.map, a.x, a.y, b, w, h)
    if flight then return string.format(L.LEG_FLY, flight.from, flight.to, flight.yards) end
    local d, dir = WC.PlanDistance(a.x, a.y, b.x, b.y, w, h)
    if d <= WC.LEG_RIDE_YARDS then return nil end
    local rounded = math.floor(d / 100 + 0.5) * 100
    local text = tostring(rounded):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return string.format(L.LEG_RIDE, text, dir)
end
WC.LegText = leg_text

-- The sections for the player at mapID, px, py. nil when there is no plan. Pure over live state: call it any time.
--  now   = { text, label, step, travel = true when it is a promoted trip leg }
--  here  = { zone, stops = { {label, text, step, yards} }, yards, exit, done }
--  trips = { { key, zone, map, head, reason, quests = { {id, text, ready} }, travel = {text}, trip } }
--  later = { { id, text } }
function WC.PanelSections(mapID, px, py)
    local p = WC.plan
    if not p then return nil end
    local cur = mapID == nil and guarded(WC.PlanNext, nil) or nil
    local hereMap = mapID or (cur and cur.map)
    local groups = hereMap and guarded(WC.MapBadgeGroups, {}, hereMap, px, py) or {} -- in the live order for the player's map
    cur = cur or guarded(WC.PlanNext, nil)
    local nums = groups.nums
    -- Steps with no spot on the map are numbered too, after every placed stop, in plan order.
    local function unplaced_here(st)
        return st.unplaced and st.kind ~= "travel" and not p.done[st.n] and (st.map == hereMap or st.map == 0) and not WC.StepDismissed(st)
    end
    local unplacedNum = {}
    local nextNum = nums and nums.count or 0
    for _, st in ipairs(p.steps) do
        if unplaced_here(st) then
            if nums then
                nextNum = nextNum + 1
                nums.byStep[st] = nextNum
                nums.count = nextNum
                unplacedNum[st] = tostring(nextNum)
            elseif tonumber(st.n) and st.n >= 1 and st.n < 100000 then
                unplacedNum[st] = tostring(st.n)
            end
        end
    end
    local seen = {}
    local function note(step)
        for _, id in ipairs(ids_of(step)) do if (id or 0) > 0 then seen[id] = true end end
    end
    local S = { here = { zone = zone_name(hereMap), stops = {}, yards = 0, exit = p.exit and p.exit.label or nil, done = false },
        trips = {}, later = {}, seen = seen, mapID = hereMap, nums = nums }

    -- NOW: the current step with its badge label, distance and direction.
    if cur then
        local label, steps
        for _, g in ipairs(groups) do if g.isNext then label, steps = WC.PinLabel(g.steps), g.steps end end
        label = label or WC.PinLabel({ cur })
        local plabel = cur.unplaced and (unplacedNum[cur] or "") or panel_label(steps or { cur })
        local view = cur.kind == "travel" and WC.PlanTipStep(cur) or cur
        local text = WC.PlanLiveText(view, view.label or "")
        local where
        if cur.unplaced then -- no spot to walk to: say where the work is done
            where = in_place(text, cur.place):sub(#text + 1)
            if unplacedNum[cur] then where = where .. L.PANEL_NO_SPOT end
        elseif hereMap == cur.map and px then
            local d, dir = WC.PlanDistance(px, py, cur.x, cur.y, WC.MapYards(hereMap))
            where = string.format(L.PLAN_DISTANCE, math.floor(d + 0.5), dir)
        else
            where = L.PLAN_ELSEWHERE
        end
        local hint
        if not cur.unplaced and hereMap == cur.map and px and cur.kind ~= "travel" then
            local w, h = WC.MapYards(hereMap)
            hint = WC.FlightHint(p.flights, hereMap, px, py, cur, w, h)
        end
        S.now = { label = label, plabel = plabel, text = text, where = where, step = cur, hint = hint, steps = steps }
        note(cur)
    end

    -- HERE: every other badge on this map, in the map's order, with the walk length from NOW through the last.
    local prev = S.now and S.now.step and hereMap == S.now.step.map and S.now.step or (px and { x = px, y = py }) or nil
    -- A stop is NOW's when one of its steps is the current step (or repeats it): it is never listed twice.
    local function is_now(g)
        if not cur then return false end
        for _, s in ipairs(g.steps) do
            if s.n == cur.n or (s.questID == cur.questID and s.kind == cur.kind and (cur.questID or 0) > 0) then return true end
        end
        return false
    end
    local legPrev = S.now and S.now.step and S.now.step.map == hereMap and not S.now.step.unplaced and S.now.step or nil
    for _, g in ipairs(groups) do
        if not g.isNext and not is_now(g) then
            local stop = stop_of(g, nums)
            stop.map = hereMap
            stop.leg = leg_text(legPrev, stop)
            legPrev = stop
            if prev and prev.x then stop.yards = yards_between(hereMap, prev, stop) S.here.yards = S.here.yards + stop.yards end
            prev = stop
            S.here.stops[#S.here.stops + 1] = stop
            for _, s in ipairs(g.steps) do note(s) end
        end
    end
    -- Steps with no spot on the map (an errand "in Undercity") have no badge: each is a plain HERE row on its own map.
    for _, s in ipairs(p.steps) do
        if unplaced_here(s) and not (cur and cur.n == s.n) then
            local stop = { label = unplacedNum[s] or "", plabel = unplacedNum[s] or "", step = s, group = { steps = { s } }, errand = errand_of(p, s),
                text = s.label ~= "" and s.label or (s.quest or "") }
            stop.text = in_place(stop.text, s.place) .. (unplacedNum[s] and L.PANEL_NO_SPOT or "")
            S.here.stops[#S.here.stops + 1] = stop
            note(s)
        end
    end
    local nowOnHere = false
    for _, g in ipairs(groups) do if g.isNext or is_now(g) then nowOnHere = true end end
    S.here.done = #S.here.stops == 0 and not nowOnHere

    -- FIND: quests that are a hunt, each with the plan's hint. Never unplanned; each quest has this one home.
    S.find = {}
    for _, q in ipairs(p.find or {}) do
        if not seen[q.questID] and WC.PlanQuestState(q.questID) ~= "turnedin" and not WC.QuestHidden(q.questID)
            and not (q.level and WC.QuestOutOfReach(q.questID)) then
            seen[q.questID] = true
            local name = q.quest ~= "" and q.quest or (WC.QuestTitle(q.questID) or L.QUEST_UNKNOWN:format(q.questID))
            local text = q.hint and string.format(L.FIND_LINE, name, q.hint) or string.format(L.FIND_LINE_NOHINT, name)
            local zone = q.zone or (q.map and WC.PlaceName(nil, q.map) ~= L.PLACE_UNKNOWN and WC.PlaceName(nil, q.map)) or nil
            if zone then text = string.format(L.FIND_ZONE, text, zone) end
            S.find[#S.find + 1] = { id = q.questID, name = name, text = text }
        end
    end

    -- TRIPS: each quest once, ready counted from the live log when the plan lists the quests.
    local firstTrip
    for i, t in ipairs(p.trips or {}) do
        local quests, ready = {}, 0
        for _, id in ipairs(t.questIDs or {}) do
            if not seen[id] and not WC.QuestHidden(id) and not WC.QuestOutOfReach(id) then
                seen[id] = true
                local state = WC.PlanQuestState(id)
                if state ~= "turnedin" then
                    local title = WC.QuestTitle(id)
                    if not title then
                        for _, s in ipairs(p.steps) do if s.questID == id and s.quest ~= "" then title = s.quest break end end
                    end
                    quests[#quests + 1] = { id = id, name = title or L.QUEST_UNKNOWN:format(id), ready = state == "ready" }
                    if state == "ready" then ready = ready + 1 end
                end
            end
        end
        local count = #t.questIDs > 0 and #quests or (t.ready + t.todo + t.pickups)
        if #t.questIDs == 0 then ready = t.ready end
        if count > 0 or #t.questIDs == 0 then
            local zone = trip_zone(t)
            local head = string.format(count == 1 and L.TRIP_HEAD_ONE or L.TRIP_HEAD, zone, count)
            if ready > 0 then head = head .. string.format(L.TRIP_HEAD_READY, ready) end
            local trip = { key = (t.map or zone) .. ":" .. i, zone = zone, map = t.map, head = head, reason = t.reason,
                quests = quests, travel = t.travel or {}, instance = t.instance }
            S.trips[#S.trips + 1] = trip
            firstTrip = firstTrip or trip
        end
    end

    -- Zone done: the first trip's travel legs become NOW.
    if S.here.done and not S.now and p.exit and p.exit.label and p.exit.label ~= "" and (firstTrip or #p.steps == 0) then
        S.now = { label = "", text = p.exit.label, where = "", travel = true }
    end
    if S.here.done and firstTrip then
        S.here.next = firstTrip.zone
        local nowHere = S.now and S.now.step and S.now.step.unplaced and (S.now.step.map == hereMap or S.now.step.map == 0)
        if #firstTrip.travel > 0 and not nowHere then
            S.now = { label = "", text = table.concat(firstTrip.travel, " > "), where = "", travel = true, step = S.now and S.now.step }
        end
    end

    -- LATER: parked quests not shown anywhere above.
    S.hidden = WC.HiddenQuests()
    for _, q in ipairs(p.parked or {}) do
        if not seen[q.questID] and not WC.QuestHidden(q.questID) then
            seen[q.questID] = true
            S.later[#S.later + 1] = { id = q.questID, text = string.format(L.LATER_LINE, q.quest ~= "" and q.quest or (WC.QuestTitle(q.questID) or L.QUEST_UNKNOWN:format(q.questID)), q.why) }
        end
    end
    -- LATER, too: a quest in the log that the reach dropped from the plan above. Display only; the game is never touched.
    local mine = UnitLevel and UnitLevel("player")
    local function reach_later(id, level, name)
        local r = WC.PlanReach()
        if not (id and id > 0 and level and mine and r and not seen[id] and not WC.QuestHidden(id)) then return end
        local st = WC.PlanQuestState(id)
        if (st ~= "active" and st ~= "ready") or not WC.QuestOutOfReach(id) then return end
        seen[id] = true
        local nm = (name and name ~= "") and name or WC.QuestTitle(id) or L.QUEST_UNKNOWN:format(id)
        local why = string.format(L.LATER_REACH, r, math.floor(level))
        S.later[#S.later + 1] = { id = id, name = nm, text = WC.LevelTag(id) .. string.format(L.LATER_LINE, nm, why) }
    end
    for _, st in ipairs(p.steps) do
        for _, id in ipairs(ids_of(st)) do reach_later(tonumber(id), st.level, st.quest) end
    end
    for _, q in ipairs(p.find or {}) do reach_later(q.questID, q.level, q.quest) end
    return S
end

-- The right-click menu on a quest row: "Hide from plan" and "Open details" (the card the right-click opened before).
-- Our own two buttons in one small frame; nothing protected, and the quest in the game is never touched.
function WC.HideRowMenu()
    if WC.rowMenu then WC.rowMenu:Hide() end
end

function WC.ShowRowMenu(row)
    local m = WC.rowMenu
    if not m then
        m = CreateFrame("Frame", "WoWCompanionRowMenu", UIParent, "BackdropTemplate")
        m:SetSize(130, 48)
        if m.SetFrameStrata then m:SetFrameStrata("DIALOG") end
        if m.SetBackdrop then
            m:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
            m:SetBackdropColor(0, 0, 0, 0.9)
            m:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)
        end
        m:EnableMouse(true)
        local function leave() if not m:IsMouseOver() then m:Hide() end end
        m:SetScript("OnLeave", leave)
        local function item(i, text, onclick)
            local b = CreateFrame("Button", nil, m)
            b:SetSize(122, 20)
            b:SetPoint("TOPLEFT", m, "TOPLEFT", 4, -4 - (i - 1) * 20)
            b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            b.label:SetPoint("LEFT", b, "LEFT", 4, 0)
            b.label:SetText(text)
            b:SetScript("OnClick", function() m:Hide() onclick() end)
            b:SetScript("OnLeave", leave)
            return b
        end
        m.hide = item(1, L.HIDE_FROM_PLAN, function() if m.questID then WC.HideQuest(m.questID) end end)
        m.card = item(2, L.MENU_OPEN_CARD, function() if m.entry then WC.EntryClick(m.entry, "RightButton") end end)
        WC.rowMenu = m
    end
    m.questID, m.entry = row.hideId, row.entry
    m:ClearAllPoints()
    m:SetPoint("TOPLEFT", row, "BOTTOMLEFT", 16, 0)
    m:Show()
end

-- True when a trip or LATER section is open: remembered while the session runs.
local function toggle(tbl, key)
    tbl[key] = (not tbl[key]) or nil
    if WC.Refresh then WC.Refresh() end
end

-- Switches the world map to a trip's zone: the map's public SetMapID and the panel show, nothing protected.
function WC.ShowTripOnMap(trip)
    if not (trip and trip.map and WorldMapFrame) then return false end
    if WorldMapFrame.SetMapID then pcall(WorldMapFrame.SetMapID, WorldMapFrame, trip.map) end
    if type(ShowUIPanel) == "function" then pcall(ShowUIPanel, WorldMapFrame) elseif WorldMapFrame.Show then WorldMapFrame:Show() end
    return true
end

-- The ready turn-ins, the trainer and the vendor doable at the player's spot, none already a HERE stop. Plain rows.
local function action_rows(S, mapID, px, py)
    local rows = {}
    for _, r in ipairs(WC.TrainRows(mapID, px, py)) do rows[#rows + 1] = r end
    for _, t in ipairs(WC.LiveTurnIns(mapID, px, py)) do
        if not S.seen[t.questID] and not WC.QuestHidden(t.questID) then
            S.seen[t.questID] = true
            local who = t.spot.npc ~= "" and (t.quest .. ": " .. t.spot.npc) or t.quest
            rows[#rows + 1] = { kind = "line", color = WC.COLORS.gold,
                text = string.format(L.HERE_LIVE_TURNIN, who, math.floor(t.spot.x + 0.5), math.floor(t.spot.y + 0.5)) }
        end
    end
    local b = WC.HereBlock(mapID, px, py)
    for _, c in ipairs(b and b.can or {}) do
        if c == "train" then rows[#rows + 1] = { kind = "line", text = L.HERE_TRAIN }
        elseif c == "buy and sell" or c == "repair" then rows[#rows + 1] = { kind = "line", text = L.HERE_VENDOR } end
    end
    return rows
end

local function now_text(S)
    local n = S.now
    if n.travel then return string.format(L.PANEL_NOW_TRAVEL, n.text) end
    local text = n.text
    local kind = n.step and errand_of(WC.plan, n.step)
    local errandName = kind and L["ERRAND_" .. kind]
    if errandName then text = string.format(L.ERRAND_ROW, text, string.format(L.ERRAND_TAG, errandName)) end
    return labelled(L.PANEL_NOW_LINE, n.plabel or n.label, text) .. n.where
end

local function stop_text(stop)
    local text = labelled(L.PANEL_STOP_LINE, stop.plabel, stop.text)
    local errandName = stop.errand and L["ERRAND_" .. stop.errand]
    if errandName then
        text = string.format(L.ERRAND_ROW, text, string.format(L.ERRAND_TAG, errandName))
    end
    return text
end

-- Dim "While you're here" sub-lines for the errands riding on a stop's steps.
local function chore_rows(out, steps, indent)
    for _, e in ipairs(WC.ChoresFor(steps)) do
        out[#out + 1] = { kind = "status", indent = indent, text = WC.ChoreText(e), color = WC.COLORS.dim }
    end
end

local function header(id, text, click)
    local color = WC.Setting("sectionColor")
    local tip = (id == "panel_now" or id == "panel_here" or id == "panel_trips") and L.PANEL_SECTIONS_TIP or nil
    return { kind = "header", id = id, title = text, text = text, color = color, click = click, tip = tip }
end

-- The digest's own line for a quest (its next_quests entry), so a row can open the same card as before; nil when none.
local function digest_line(id)
    local e = WC.EntryFor and WC.EntryFor(WoWCompanionDigest, UnitName("player"))
    for _, sec in ipairs(type(e) == "table" and type(e.sections) == "table" and e.sections or {}) do
        if sec.id == "next_quests" then
            for _, line in ipairs(type(sec.lines) == "table" and sec.lines or {}) do
                if tonumber(line.quest) == id then return line end
            end
        end
    end
end

-- Gives a quest row the entry, group and question of the quest's card, so hover, click and the card work on it.
local function with_card(row, id, title, verbFirst)
    if not (id and id > 0 and WC.QuestEntryRows) then return row end
    local line = digest_line(id) or { kind = "progress", title = title }
    local rows = guarded(WC.QuestEntryRows, nil, line, id, {}, UnitLevel and UnitLevel("player") or nil, verbFirst and { verbFirst = true } or nil)
    local head = rows and rows[1]
    if head then
        row.entry, row.group, row.ask, row.quest = head.entry, head.group, head.ask, id
        row.color = row.color or head.color -- the quest's difficulty colour, as the old list had
        if row.useHead then
            row.text = head.text -- the verb-first title: "[38] Kill X", or a ready turn-in's neutral level then "ready" in green
        elseif not tostring(row.text or ""):find("^%s*%[%d+%]") and not tostring(row.text or ""):find("^|c") then
            local ready = WC.PlanQuestState(id) == "ready"
            row.text = WC.LevelTag(id, ready) .. tostring(row.text or "")
            if not row.color and not ready then
                local lv, df = WC.PlanQuestLevel(id)
                if lv and df and WC.Setting("colorByDifficulty") then row.color = WC.LevelColor(lv, df) end
            end
        end
        row.hideId = id
    end
    return row, rows
end

-- Adds a quest row, then (for a quest in the log) its objective rows, so the quest's lines light together on hover.
local function add_quest(out, row, id, title, step, nums)
    local r, rows = with_card(row, id, title, true)
    out[#out + 1] = r
    local state = id and id > 0 and WC.PlanQuestState(id)
    local planAfter = step and step.kind ~= "turnin" and type(step.after) == "table" and #step.after > 0
    if planAfter then
        local wait = waits_on(id, step, nums)
        if wait then out[#out + 1] = { kind = "status", indent = (r.indent or 0) + 1, text = wait, color = WC.COLORS.dim, group = r.group } end
    end
    if step and step.kind == "turnin" then
        -- a turn-in never repeats the objectives' progress (it is shown where the work is): ready says nothing, else what it waits on
        local wait = state == "active" and waits_on(id, step, nums) or nil
        if wait then out[#out + 1] = { kind = "status", indent = (r.indent or 0) + 1, text = wait, color = WC.COLORS.dim, group = r.group } end
    elseif rows and (state == "active" or state == "ready") then
        for i = 2, #rows do
            if rows[i].kind == "obj" then
                rows[i].indent = (r.indent or 0) + 1
                out[#out + 1] = rows[i]
            end
        end
    end
end

-- The rows of the four sections, to sit above the other digest rows.
function WC.PanelSectionRows(S, mapID, px, py)
    local rows = {}
    if not S then return rows end
    rows[#rows + 1] = header("panel_now", L.PANEL_NOW)
    if S.now then
        local id = S.now.step and (S.now.step.questID or 0) > 0 and S.now.step.questID or nil
        add_quest(rows, { kind = "line", text = now_text(S), color = WC.COLORS.gold }, id, S.now.step and S.now.step.quest, S.now.step, S.nums)
        if S.now.step then chore_rows(rows, S.now.steps or { S.now.step }, 1) end
        if S.now.hint then rows[#rows + 1] = { kind = "line", indent = 1, text = S.now.hint, color = WC.COLORS.dim } end
    else
        rows[#rows + 1] = { kind = "line", text = L.PANEL_NOTHING_NOW }
    end
    local h = S.here
    if S.here.done and h.next then
        rows[#rows + 1] = header("panel_here", string.format(L.PANEL_ZONE_DONE, h.zone, h.next))
    else
        local title
        if #h.stops == 0 then
            title = string.format(L.PANEL_HERE_NONE, h.zone)
        else
            local far = h.yards > 0 and string.format(L.PANEL_HERE_YARDS, math.floor(h.yards + 0.5)) or ""
            title = string.format(#h.stops == 1 and L.PANEL_HERE_ONE or L.PANEL_HERE, h.zone, #h.stops, far)
        end
        rows[#rows + 1] = header("panel_here", title)
    end
    for _, stop in ipairs(h.stops) do
        if stop.leg then rows[#rows + 1] = { kind = "line", indent = 1, text = stop.leg, color = WC.COLORS.dim, connector = true } end
        if stop.items then
            for i, it in ipairs(stop.items) do
                local ready = it.step.kind == "turnin" and WC.PlanQuestState(it.id) == "ready"
                -- the first line leads with the stop's badge ("4·5"); each further quest leads with its own number
                local label = i == 1 and stop.plabel or (it.num and tostring(it.num) or "")
                local text = labelled(L.PANEL_STOP_LINE, label, it.text)
                add_quest(rows, { kind = "line", indent = i == 1 and 1 or 2, text = text,
                    color = ready and WC.Setting("readyColor") or nil }, it.id > 0 and it.id or nil, it.step.quest, it.step, S.nums)
            end
        else
            add_quest(rows, { kind = "line", indent = 1, text = stop_text(stop) },
                (stop.step.questID or 0) > 0 and stop.step.questID or nil, stop.step.quest, stop.step, S.nums)
        end
        chore_rows(rows, stop.group and stop.group.steps or { stop.step }, 2)
    end
    if h.exit and #h.stops + (S.now and 1 or 0) > 0 then
        rows[#rows + 1] = { kind = "line", indent = 1, text = string.format(L.PANEL_THEN, h.exit), color = WC.COLORS.dim }
    end
    for _, r in ipairs(guarded(action_rows, {}, S, mapID, px, py)) do rows[#rows + 1] = r end
    if #(S.find or {}) > 0 then
        rows[#rows + 1] = header("panel_find", string.format(L.PANEL_FIND, #S.find))
        for _, q in ipairs(S.find) do
            rows[#rows + 1] = with_card({ kind = "line", indent = 1, text = q.text, color = WC.COLORS.gold }, q.id, q.name)
        end
    end
    if #S.trips > 0 then
        rows[#rows + 1] = header("panel_trips", string.format(L.PANEL_TRIPS, #S.trips))
        for _, t in ipairs(S.trips) do
            local open = WC.view.tripOpen[t.key] == true
            rows[#rows + 1] = { kind = "line", indent = 1, text = string.format(open and L.OPEN_SECTION or L.CLOSED_SECTION, t.head),
                click = function() toggle(WC.view.tripOpen, t.key) end }
            if open then
                if t.reason then rows[#rows + 1] = { kind = "line", indent = 2, text = t.reason, color = WC.COLORS.dim } end
                for _, q in ipairs(t.quests) do
                    add_quest(rows, { kind = "line", indent = 2, useHead = true, text = q.ready and WC.ReadyMark(q.name) or q.name,
                        color = q.ready and WC.Setting("readyColor") or nil }, q.id, q.name)
                end
                for _, leg in ipairs(t.travel) do
                    rows[#rows + 1] = { kind = "line", indent = 2, text = string.format(L.PANEL_TRAVEL, leg), color = WC.COLORS.dim }
                end
                if t.map then
                    rows[#rows + 1] = { kind = "line", indent = 2, text = L.CARD_SHOW_MAP, color = WC.COLORS.gold, click = function() WC.ShowTripOnMap(t) end }
                end
            end
        end
    end
    local hidden = S.hidden or {}
    if #S.later + #hidden > 0 then
        local open = WC.view.laterOpen == true
        rows[#rows + 1] = header("panel_later", string.format(open and L.OPEN_SECTION or L.CLOSED_SECTION, string.format(L.PANEL_LATER, #S.later + #hidden)),
            function() WC.view.laterOpen = not WC.view.laterOpen if WC.Refresh then WC.Refresh() end end)
        if open then
            for _, q in ipairs(S.later) do rows[#rows + 1] = with_card({ kind = "line", indent = 1, text = q.text }, q.id, q.name) end
            if #hidden > 0 then
                rows[#rows + 1] = { kind = "line", indent = 1, text = string.format(L.PANEL_HIDDEN, #hidden), color = WC.COLORS.dim }
                for _, h in ipairs(hidden) do
                    local id = h.id
                    rows[#rows + 1] = { kind = "line", indent = 2, text = WC.LevelTag(id) .. h.name .. L.UNHIDE_SUFFIX, color = WC.COLORS.gold,
                        unhideId = id, click = function() WC.UnhideQuest(id) end }
                end
            end
        end
    end
    return rows
end

local function is_bank_note(text)
    text = tostring(text or ""):lower()
    return text:find("bank", 1, true) ~= nil and text:find("captured", 1, true) ~= nil
end

-- True when the player stands where a bank is: a here block that lists one, or a plan errand for the bank on this map.
local function at_bank(S, mapID, px, py)
    local b = WC.HereBlock and WC.HereBlock(mapID, px, py)
    for _, c in ipairs(b and b.can or {}) do
        if c:find("bank", 1, true) then return true end
    end
    for _, stop in ipairs(S and S.here and S.here.stops or {}) do if stop.errand == "bank" then return true end end
    if S and S.now and S.now.step and errand_of(WC.plan, S.now.step) == "bank" then return true end
    return false
end

-- "Bank not captured" is a passive note; in a city with a bank it becomes an errand row of the plan sections. Returns the
-- rows without the note and the errand row (nil when the note stays or is absent).
function WC.BankErrand(rows, S, mapID, px, py)
    local found
    for _, r in ipairs(rows) do if r.kind ~= "header" and is_bank_note(r.text) then found = true end end
    if not (found and S and at_bank(S, mapID, px, py)) then return rows, nil end
    local out = {}
    for _, r in ipairs(rows) do
        if not (r.kind ~= "header" and is_bank_note(r.text)) then out[#out + 1] = r end
    end
    -- a Notes header left with nothing under it goes too
    local clean = {}
    for i, r in ipairs(out) do
        local nxt = out[i + 1]
        if not (r.kind == "header" and r.id == "notes" and (not nxt or nxt.kind == "header")) then clean[#clean + 1] = r end
    end
    return clean, { kind = "line", indent = 1, text = string.format(L.ERRAND_ROW, L.BANK_ERRAND, string.format(L.ERRAND_TAG, L.ERRAND_bank)), color = WC.COLORS.gold }
end

-- The collapsed panel's lines: NOW and the next two HERE stops, as plain text lines.
function WC.PanelPeekLines(S)
    local out = {}
    if not (S and S.now) then return out end
    out[1] = now_text(S)
    for i = 1, math.min(2, #S.here.stops) do out[#out + 1] = stop_text(S.here.stops[i]) end
    return out
end

-- Drops the digest's old "Next quests" section (its header and lines) from the rows: the plan sections replace it.
function WC.DropNextQuests(rows)
    local out, skip = {}, false
    for _, r in ipairs(rows) do
        if r.kind == "header" then skip = r.id == "next_quests" end
        if not skip then out[#out + 1] = r end
    end
    return out
end

-- True when the quest log holds a quest no section of the plan knows: only then is the plan really one save behind.
function WC.PlanLacksLive()
    local p = WC.plan
    local q = C_QuestLog
    if not (p and q and q.GetNumQuestLogEntries and q.GetInfo) then return false end
    local known = {}
    local function add(id) if id then known[id] = true end end
    for _, s in ipairs(p.steps) do for _, id in ipairs(ids_of(s)) do add(id) end end
    for _, t in ipairs(p.trips or {}) do for _, id in ipairs(t.questIDs) do add(id) end end
    for _, k in ipairs(p.parked or {}) do add(k.questID) end
    for id in pairs(p.guidance or {}) do add(id) end
    for id in pairs(p.finishers or {}) do add(id) end
    for _, it in ipairs(p.later or {}) do add(it.questID) end
    for i = 1, (q.GetNumQuestLogEntries()) or 0 do
        local info = q.GetInfo(i)
        if type(info) == "table" and not info.isHeader then
            local id = tonumber(info.questID)
            if id and id > 0 and not known[id] then return true end
        end
    end
    return false
end
