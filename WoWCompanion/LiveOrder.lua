-- WoW Companion: NOW and HERE follow the player. The stops on the player's map are re-ordered from where the player
-- stands (nearest available stop first, then nearest neighbour with a 2-opt pass), never breaking the plan's
-- dependencies. Display only: it reads the plan and the player's position and moves nothing in the plan itself.

local WC = WoWCompanion
local L = WC.L

WC.LIVE_TURNIN_YARDS = 250 -- a ready turn-in this close always comes first
WC.LIVE_ORDER_MOVE = 200 -- the player moved this far: order again
WC.LIVE_ORDER_SECONDS = 2 -- seconds between two re-orders
WC.FLIGHT_MIN_YARDS = 1500 -- a hint only for a stop farther than this
WC.FLIGHT_MIN_SAVING = 500 -- and only when the flight saves at least this much walking
WC.LEG_RIDE_YARDS = 800 -- a leg between two stops longer than this gets a connector line
WC.REROUTE_YARDS = 1000 -- farther than this from the plan's start: the order is ours, not the app's

local function yards(ax, ay, bx, by, w, h)
    local dx, dy = (ax - bx) * w / 100, (ay - by) * h / 100
    return math.sqrt(dx * dx + dy * dy)
end
WC.LiveYards = yards

-- Pure. items = { { x, y, deps = { item index... }, turnin = true for a ready turn-in, blocked = true for a stop
-- that cannot be done yet } } in map percent on a w by h yard map; returns the item indexes in the order to visit
-- them from (px, py). The first is the nearest available item (every dependency visited); a ready turn-in within
-- LIVE_TURNIN_YARDS comes first whenever one is available; then nearest neighbour, then a 2-opt pass that keeps
-- every dependency and the pinned lead.
function WC.LiveOrder(items, px, py, w, h)
    local n = #items
    local placed, order = {}, {}
    local function available(i)
        for _, d in ipairs(items[i].deps or {}) do
            if d ~= i and items[d] and not placed[d] then return false end
        end
        return true
    end
    local cx, cy = px, py
    local pinned, leading = 0, true
    while #order < n do
        local pool
        for _, pass in ipairs({ "open", "unblocked", "any" }) do -- cycles and blocked stops still get placed, last
            local list = {}
            for i = 1, n do
                local it = items[i]
                if not placed[i] and (pass == "any" or not it.blocked) and (pass ~= "open" or available(i)) then list[#list + 1] = i end
            end
            if #list > 0 then pool = list break end
        end
        local best, bd, prio
        for _, i in ipairs(pool) do
            local d = yards(cx, cy, items[i].x, items[i].y, w, h)
            local p = items[i].turnin and not items[i].blocked and d <= WC.LIVE_TURNIN_YARDS
            if not best or (p and not prio) or (p == prio and d < bd) then best, bd, prio = i, d, p end
        end
        placed[best] = true
        order[#order + 1] = best
        if leading and (#order == 1 or prio) then pinned = #order else leading = false end
        cx, cy = items[best].x, items[best].y
    end
    -- 2-opt over the unpinned tail of the open path, accepting only a shorter order that still honours the dependencies.
    local function valid(seq)
        local at = {}
        for pos, i in ipairs(seq) do at[i] = pos end
        local sawBlocked
        for pos, i in ipairs(seq) do
            if items[i].blocked then sawBlocked = true elseif sawBlocked then return false end
            for _, d in ipairs(items[i].deps or {}) do
                if d ~= i and at[d] and at[d] > pos then return false end
            end
        end
        return true
    end
    local function length(seq)
        local total, x, y = 0, px, py
        for _, i in ipairs(seq) do
            total = total + yards(x, y, items[i].x, items[i].y, w, h)
            x, y = items[i].x, items[i].y
        end
        return total
    end
    if n - pinned >= 2 and valid(order) then
        local best = length(order)
        local improved, rounds = true, 0
        while improved and rounds < 20 do
            improved, rounds = false, rounds + 1
            for i = pinned + 1, n - 1 do
                for j = i + 1, n do
                    local trial = {}
                    for k = 1, n do trial[k] = order[k] end
                    for k = i, j do trial[k] = order[i + j - k] end
                    if valid(trial) then
                        local len = length(trial)
                        if len < best - 0.5 then order, best, improved = trial, len, true end
                    end
                end
            end
        end
    end
    return order
end

-- Pure. Should the order be made again? st = { map, px, py, at, sig } from the last time (nil: never).
function WC.LiveGate(st, now, mapID, px, py, sig, inCombat, w, h)
    if inCombat then return false end
    if not st or st.map ~= mapID then return true end
    if now - st.at < WC.LIVE_ORDER_SECONDS then return false end
    if st.sig ~= sig then return true end
    return yards(st.px, st.py, px, py, w, h) > WC.LIVE_ORDER_MOVE
end

local RANK = { pickup = 1, objective = 2, turnin = 3 }

local function group_key(g)
    local parts = {}
    for _, s in ipairs(g.steps) do parts[#parts + 1] = tostring(s.n) end
    return table.concat(parts, ",")
end

-- The dependencies of each group: a step's own `after` (route step numbers) when the plan carries them, else a turn-in
-- waits on its quest's undone pickup and objectives, and an objective on its pickup. Returns deps[groupIndex] = { indexes }.
local function group_deps(groups)
    local owner = {}
    for gi, g in ipairs(groups) do for _, s in ipairs(g.steps) do owner[s.n] = gi end end
    local plan = WC.plan
    local deps = {}
    for gi, g in ipairs(groups) do
        local list, seen = {}, {}
        local function add(target)
            if target and target ~= gi and not seen[target] then seen[target] = true list[#list + 1] = target end
        end
        for _, s in ipairs(g.steps) do
            if type(s.after) == "table" and #s.after > 0 then
                for _, n in ipairs(s.after) do add(owner[n]) end
            elseif RANK[s.kind] and (s.questID or 0) > 0 then
                for _, t in ipairs(plan and plan.steps or {}) do
                    if t.questID == s.questID and RANK[t.kind] and RANK[t.kind] < RANK[s.kind] and not plan.done[t.n] then add(owner[t.n]) end
                end
            end
        end
        deps[gi] = list
    end
    -- A pickup and a turn-in at one NPC share a badge (a group cannot be split): if that group and another wait on each
    -- other, the group holding the pickup goes first.
    for gi, g in ipairs(groups) do
        local hasPickup = false
        for _, s in ipairs(g.steps) do if s.kind == "pickup" then hasPickup = true end end
        if hasPickup then
            local keep = {}
            for _, d in ipairs(deps[gi]) do
                local mutual = false
                for _, back in ipairs(deps[d]) do if back == gi then mutual = true end end
                if not mutual then keep[#keep + 1] = d end
            end
            deps[gi] = keep
        end
    end
    return deps
end

local function ready_turnin(g)
    for _, s in ipairs(g.steps) do
        if s.kind == "turnin" then
            local ids = s.questIDs and #s.questIDs > 0 and s.questIDs or { s.questID }
            for _, id in ipairs(ids) do if (id or 0) > 0 and WC.PlanQuestState(id) == "ready" then return true end end
        end
    end
    return false
end

local function all_unready(g)
    for _, s in ipairs(g.steps) do if not WC.StepUnready(s) then return false end end
    return true
end

local function now_clock()
    return GetTime and GetTime() or os.time()
end

-- Pure. The quests a badge group serves, one { id, step } each, in step order. A quest listed twice (a live turn-in for
-- a quest the plan already lists here) is the same quest and appears once.
function WC.GroupItems(group)
    local items, listed = {}, {}
    for _, st in ipairs(group.steps) do
        local ids = st.questIDs and #st.questIDs > 0 and st.questIDs or { st.questID }
        for _, id in ipairs(ids) do
            if not listed[id] then
                listed[id] = true
                items[#items + 1] = { id = id, step = st }
            end
        end
    end
    return items
end

-- Pure. Numbers every actionable step of the groups, in their (live) order, 1, 2, 3...: one number per step, so a stop
-- that merges quests reads "4·5". Sets each group's steps.liveLabel and returns { byStep = { [step] = n }, count = n }.
-- The map badge, tooltip and panel all read these numbers, so they cannot disagree.
function WC.LiveNumber(groups)
    local byStep, n = {}, 0
    for _, g in ipairs(groups) do
        local first, last
        for _, it in ipairs(WC.GroupItems(g)) do
            if not byStep[it.step] then
                n = n + 1
                byStep[it.step] = n
            end
            first = first or byStep[it.step]
            last = byStep[it.step]
        end
        if first then
            g.steps.liveLabel = first == last and tostring(first) or (first .. "\194\183" .. last)
            g.steps.liveNums = byStep
        end
    end
    return { byStep = byStep, count = n }
end

-- Pure. A plan's `after` (plan step numbers) as live numbers for the step numbered `own`: a step already done is
-- dropped, a step with no live number is dropped, and so is any number not smaller than `own` (a step never waits on
-- itself or on something later). `nums` is a LiveNumber result (nil: no live order, plan numbers stand).
function WC.LiveAfter(after, plan, nums, own)
    local out, seen = {}, {}
    for _, n in ipairs(after or {}) do
        if not (plan and plan.done and plan.done[n]) then
            local live = n
            if nums then
                live = nil
                for _, st in ipairs(plan and plan.steps or {}) do
                    if st.n == n then live = nums.byStep[st] break end
                end
            end
            if live and (not own or live < own) and not seen[live] then
                seen[live] = true
                out[#out + 1] = live
            end
        end
    end
    table.sort(out)
    return out
end

-- Puts the badge groups of the player's own map in live order and marks the first one NOW. `groups` is a PinGroups
-- result; returns the same list, re-ordered, with each numbered badge relabelled to its place in the order
-- (steps.liveLabel). With no position, or on another map than the player's, the plan's order stands.
function WC.LiveGroups(groups, mapID, px, py, now)
    local plan = WC.plan
    if WC.Setting("planLive") == false then WC.liveState = nil return groups end
    if not plan or #groups == 0 or not (mapID and px and py) then return groups end
    local pm = WC.PlayerPos and WC.PlayerPos()
    if pm ~= mapID then return groups end
    now = now or now_clock()
    local w, h = WC.MapYards(mapID)
    local keys, parts = {}, {}
    for i, g in ipairs(groups) do
        keys[i] = group_key(g)
        parts[i] = keys[i] .. (ready_turnin(g) and "!" or "") .. (all_unready(g) and "?" or "")
    end
    local sig = table.concat(parts, ";")
    local st = WC.liveState
    local combat = InCombatLockdown and InCombatLockdown() or false
    if WC.LiveGate(st, now, mapID, px, py, sig, combat, w, h) then
        local deps = group_deps(groups)
        local items = {}
        for i, g in ipairs(groups) do
            items[i] = { x = g.x, y = g.y, deps = deps[i], turnin = ready_turnin(g), blocked = all_unready(g) }
        end
        local order = WC.LiveOrder(items, px, py, w, h)
        local list = {}
        for pos, i in ipairs(order) do list[pos] = keys[i] end
        local was = st and st.map == mapID and table.concat(st.order, "|") or nil
        st = { map = mapID, px = px, py = py, at = now, sig = sig, order = list, runs = ((st and st.runs) or 0) + 1 }
        WC.liveState = st
        if was and was ~= table.concat(list, "|") then WC.liveChanged = true end
    end
    if not st or st.map ~= mapID then return groups end
    local rank = {}
    for pos, k in ipairs(st.order) do rank[k] = pos end
    local sorted = {}
    for i, g in ipairs(groups) do sorted[i] = { g = g, r = rank[keys[i]] or (1000 + i) } end
    table.sort(sorted, function(a, b) return a.r < b.r end)
    local out, hadNext = {}, false
    for i, e in ipairs(sorted) do out[i] = e.g if e.g.isNext then hadNext = true end end
    out.nums = WC.LiveNumber(out)
    st.now, st.nowGroup = nil, nil
    local first = out[1]
    if first and not all_unready(first) then
        local step = first.steps[1]
        for _, s in ipairs(first.steps) do if not WC.StepUnready(s) then step = s break end end
        st.now, st.nowGroup = step, first
        if hadNext then -- the plan's NOW is on this map: the first live stop takes the mark
            for _, g in ipairs(out) do g.next, g.isNext = nil, false end
            first.next, first.isNext = step, true
        end
    end
    return out
end

-- The step to show as NOW: the live first stop when the plan's own NOW is on the player's map, else `cur` unchanged.
function WC.LiveNowStep(cur)
    local st, p = WC.liveState, WC.plan
    local s = st and st.now
    if not (s and cur and p) or cur.map ~= st.map or cur.kind == "travel" or cur.unplaced then return cur end
    if s == cur or p.done[s.n] or WC.StepLocked(s) or WC.StepUnready(s) or (WC.StepDismissed and WC.StepDismissed(s)) then return cur end
    for _, x in ipairs(st.nowGroup and st.nowGroup.steps or {}) do if x == cur then return cur end end
    return s
end

-- Called on the tick: keeps the order current for the player's map and redraws the map when it changed.
function WC.LiveRefresh(mapID, px, py)
    if not (WC.plan and mapID and px and WC.MapBadgeGroups) then return end
    pcall(WC.MapBadgeGroups, mapID, px, py)
    if WC.liveChanged then
        WC.liveChanged = nil
        if WC.RefreshMapPins then pcall(WC.RefreshMapPins) end
    end
end

-- Pure. The plan's known flight masters on this map (a list of { name, map, x, y }), a stop, and the player: the flight
-- { from, to, yards, dir } (the flight masters' names, then the walk from the landing to the stop) when the stop is
-- farther than FLIGHT_MIN_YARDS and flying saves real walking; else nil.
function WC.FlightLeg(flights, mapID, px, py, target, w, h)
    if type(flights) ~= "table" or not (px and target and target.x) then return nil end
    local direct = yards(px, py, target.x, target.y, w, h)
    if direct <= WC.FLIGHT_MIN_YARDS then return nil end
    local from, to, fd, td
    for _, f in ipairs(flights) do
        if f.map == mapID and f.known ~= false then
            local a, b = yards(px, py, f.x, f.y, w, h), yards(target.x, target.y, f.x, f.y, w, h)
            if not fd or a < fd then from, fd = f, a end
            if not td or b < td then to, td = f, b end
        end
    end
    if not from or not to or from == to or from.name == to.name then return nil end
    if fd + td > direct - WC.FLIGHT_MIN_SAVING then return nil end
    local d, dir = WC.PlanDistance(to.x, to.y, target.x, target.y, w, h)
    return { from = from.name, to = to.name, yards = math.floor(d + 0.5), dir = dir }
end

-- A hint "Fly A to B, then N yd D" for the NOW stop, or nil.
function WC.FlightHint(flights, mapID, px, py, target, w, h)
    local f = WC.FlightLeg(flights, mapID, px, py, target, w, h)
    return f and string.format(L.FLIGHT_HINT, f.from, f.to, f.yards, f.dir) or nil
end

-- True when the player is on the plan's start map and farther than REROUTE_YARDS from where the app drew the plan.
function WC.PlanRerouted(mapID, px, py)
    local s = WC.plan and WC.plan.start
    if not (s and mapID and px and s.map == mapID) then return false end
    local w, h = WC.MapYards(mapID)
    return yards(px, py, s.x, s.y, w, h) > WC.REROUTE_YARDS
end
