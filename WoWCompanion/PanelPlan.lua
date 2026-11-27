-- WoW Companion: the panel's plan layout. NOW (the map's current badge), HERE (the run on this map, numbered as the
-- map's badges are), TRIPS (the other zones, one collapsible row each) and LATER (parked quests). Display only: it
-- reads the plan and the quest log. HERE is built from the same badge groups the world map draws (WC.MapBadgeGroups),
-- so the two always agree; it is rebuilt from live quest state on every panel refresh. Each quest appears once.

local WC = WoWCompanion
local L = WC.L

WC.view = WC.view or {}
WC.view.tripOpen = WC.view.tripOpen or {}
WC.view.laterOpen = false

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

local function labelled(fmt, label, text)
    if label == "" then return text end
    return string.format(fmt, label, text)
end

-- A stop as a row: its badge label and its text (a travel step on the player's own map reads as its action). A stop
-- that merges several quests also lists each one in `items` ({ id, step, text }), so each is named with its own state.
local function stop_of(group)
    local s = group.steps[1]
    local view = WC.PlanTipStep(s) or s
    local text = WC.PlanLiveText(view, view.label ~= "" and view.label or (s.quest or ""))
    local items, listed = {}, {}
    for _, st in ipairs(group.steps) do
        for _, id in ipairs(ids_of(st)) do
            if not listed[id] then -- a live turn-in step for a quest the plan already lists here is the same quest
                listed[id] = true
                items[#items + 1] = { id = id, step = st }
            end
        end
    end
    local stop = { label = WC.PinLabel(group.steps), plabel = panel_label(group.steps), text = text, step = s, group = group, x = group.x, y = group.y,
        isNext = group.isNext == true }
    for _, st in ipairs(group.steps) do stop.errand = stop.errand or errand_of(WC.plan, st) end
    if #items > 1 then
        for _, it in ipairs(items) do
            local st = it.step
            local live = WC.PlanLiveText(st, st.label ~= "" and st.label or (st.quest or ""))
            if st.kind == "turnin" then live = merged_text(st, it.id) end
            it.text = live
        end
        stop.items = items
        stop.text = items[1].text
    end
    return stop
end

-- What a not-ready turn-in waits on: the plan's open objective steps ("after step 1"), else the first unmet objective.
local function waits_on(id)
    local steps = {}
    for _, st in ipairs(WC.plan and WC.plan.steps or {}) do
        if st.kind == "objective" and st.questID == id and not WC.plan.done[st.n] and tonumber(st.n) then
            steps[#steps + 1] = tostring(st.n)
        end
    end
    if #steps > 0 then return string.format(#steps == 1 and L.PANEL_AFTER_STEP or L.PANEL_AFTER_STEPS, table.concat(steps, ", ")) end
    for _, o in ipairs(WC.QuestObjectives and WC.QuestObjectives(id) or {}) do
        if not o.finished and o.text then return string.format(L.PANEL_AFTER_OBJ, (o.text:gsub("^%d+/%d+%s*", ""))) end
    end
end

-- The sections for the player at mapID, px, py. nil when there is no plan. Pure over live state: call it any time.
--  now   = { text, label, step, travel = true when it is a promoted trip leg }
--  here  = { zone, stops = { {label, text, step, yards} }, yards, exit, done }
--  trips = { { key, zone, map, head, reason, quests = { {id, text, ready} }, travel = {text}, trip } }
--  later = { { id, text } }
function WC.PanelSections(mapID, px, py)
    local p = WC.plan
    if not p then return nil end
    local cur = guarded(WC.PlanNext, nil)
    local hereMap = mapID or (cur and cur.map)
    local groups = hereMap and guarded(WC.MapBadgeGroups, {}, hereMap) or {}
    local seen = {}
    local function note(step)
        for _, id in ipairs(ids_of(step)) do if (id or 0) > 0 then seen[id] = true end end
    end
    local S = { here = { zone = zone_name(hereMap), stops = {}, yards = 0, exit = p.exit and p.exit.label or nil, done = false },
        trips = {}, later = {}, seen = seen, mapID = hereMap }

    -- NOW: the current step with its badge label, distance and direction.
    if cur then
        local label, steps
        for _, g in ipairs(groups) do if g.isNext then label, steps = WC.PinLabel(g.steps), g.steps end end
        label = label or WC.PinLabel({ cur })
        local plabel = cur.unplaced and "" or panel_label(steps or { cur })
        local view = cur.kind == "travel" and WC.PlanTipStep(cur) or cur
        local text = WC.PlanLiveText(view, view.label or "")
        local where
        if cur.unplaced then -- no spot to walk to: say where the work is done
            where = cur.place and string.format(L.PANEL_IN_PLACE, cur.place) or ""
        elseif hereMap == cur.map and px then
            local d, dir = WC.PlanDistance(px, py, cur.x, cur.y, WC.MapYards(hereMap))
            where = string.format(L.PLAN_DISTANCE, math.floor(d + 0.5), dir)
        else
            where = L.PLAN_ELSEWHERE
        end
        S.now = { label = label, plabel = plabel, text = text, where = where, step = cur }
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
    for _, g in ipairs(groups) do
        if not g.isNext and not is_now(g) then
            local stop = stop_of(g)
            if prev and prev.x then stop.yards = yards_between(hereMap, prev, stop) S.here.yards = S.here.yards + stop.yards end
            prev = stop
            S.here.stops[#S.here.stops + 1] = stop
            for _, s in ipairs(g.steps) do note(s) end
        end
    end
    -- Steps with no spot on the map (an errand "in Undercity") have no badge: each is a plain HERE row on its own map.
    for _, s in ipairs(p.steps) do
        if s.unplaced and s.kind ~= "travel" and not p.done[s.n] and (s.map == hereMap or s.map == 0) and not (cur and cur.n == s.n) then
            local stop = { label = "", plabel = "", step = s, group = { steps = { s } }, errand = errand_of(p, s),
                text = s.label ~= "" and s.label or (s.quest or "") }
            if s.place then stop.text = stop.text .. string.format(L.PANEL_IN_PLACE, s.place) end
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
        if not seen[q.questID] and WC.PlanQuestState(q.questID) ~= "turnedin" then
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
            if not seen[id] then
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
    for _, q in ipairs(p.parked or {}) do
        if not seen[q.questID] then
            seen[q.questID] = true
            S.later[#S.later + 1] = { id = q.questID, text = string.format(L.LATER_LINE, q.quest ~= "" and q.quest or (WC.QuestTitle(q.questID) or L.QUEST_UNKNOWN:format(q.questID)), q.why) }
        end
    end
    return S
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
        if not S.seen[t.questID] then
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

local function header(id, text, click)
    local color = WC.Setting("sectionColor")
    return { kind = "header", id = id, title = text, text = text, color = color, click = click }
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
        if row.useHead then row.text = head.text end -- the verb-first title (a ready turn-in: no level, "ready" in green)
    end
    return row, rows
end

-- Adds a quest row, then (for a quest in the log) its objective rows, so the quest's lines light together on hover.
local function add_quest(out, row, id, title, step)
    local r, rows = with_card(row, id, title, true)
    out[#out + 1] = r
    local state = id and id > 0 and WC.PlanQuestState(id)
    if step and step.kind == "turnin" then
        -- a turn-in never repeats the objectives' progress (it is shown where the work is): ready says nothing, else what it waits on
        local wait = state == "active" and waits_on(id) or nil
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
        add_quest(rows, { kind = "line", text = now_text(S), color = WC.COLORS.gold }, id, S.now.step and S.now.step.quest, S.now.step)
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
            title = string.format(#h.stops == 1 and L.PANEL_HERE_ONE or L.PANEL_HERE, h.zone, #h.stops)
            if h.yards > 0 then title = title .. string.format(L.PANEL_HERE_YARDS, math.floor(h.yards + 0.5)) end
        end
        rows[#rows + 1] = header("panel_here", title)
    end
    for _, stop in ipairs(h.stops) do
        if stop.items then
            for i, it in ipairs(stop.items) do
                local ready = it.step.kind == "turnin" and WC.PlanQuestState(it.id) == "ready"
                local text = i == 1 and labelled(L.PANEL_STOP_LINE, stop.plabel, it.text) or it.text
                add_quest(rows, { kind = "line", indent = i == 1 and 1 or 2, text = text,
                    color = ready and WC.Setting("readyColor") or nil }, it.id > 0 and it.id or nil, it.step.quest, it.step)
            end
        else
            add_quest(rows, { kind = "line", indent = 1, text = stop_text(stop) },
                (stop.step.questID or 0) > 0 and stop.step.questID or nil, stop.step.quest, stop.step)
        end
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
    if #S.later > 0 then
        local open = WC.view.laterOpen == true
        rows[#rows + 1] = header("panel_later", string.format(open and L.OPEN_SECTION or L.CLOSED_SECTION, string.format(L.PANEL_LATER, #S.later)),
            function() WC.view.laterOpen = not WC.view.laterOpen if WC.Refresh then WC.Refresh() end end)
        if open then
            for _, q in ipairs(S.later) do rows[#rows + 1] = with_card({ kind = "line", indent = 1, text = q.text }, q.id, q.name) end
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
