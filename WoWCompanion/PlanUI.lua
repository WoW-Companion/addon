-- WoW Companion: draws the plan (see Plan.lua): numbered pins and faint route lines on the world
-- map, the next step on the minimap, and a small step tracker. Plain frames only, nothing secure;
-- every client API is checked before use so a missing one just drops that part of the display.

local WC = WoWCompanion
local L = WC.L

local GOLD = { 1, 0.82, 0 }
local GREY = { 0.7, 0.7, 0.7 }
local NOTCH = { pickup = "!", turnin = "?" } -- objective and travel steps show the number only
-- Badge diameter in map units by the pin size setting; "normal" matches the client's own quest markers (~28).
local PIN_SIZES = { small = 22, normal = 28, large = 36 }
local PIN_ORDER = { "small", "normal", "large" }
WC.PIN_SIZES, WC.PIN_ORDER = PIN_SIZES, PIN_ORDER
local NEXT_LEVEL = 50 -- the next step sits this many levels above the rest of its kind
-- The next step's badge is bigger by the nextGrow setting (1.3), and steps closer than the mergeDistance
-- setting (1.2, in 0-100 map units) share one badge: both are read through WC.Setting, whose defaults are those numbers.
-- Frame levels above the canvas, lowest first: route lines, their arrowheads, then our badges. They sit well
-- above other addons' small map icons (which use the default low levels) but stay below the tags
-- (TAG_LEVEL) and the map's own quest markers.
local LINE_LEVEL, ARROW_LEVEL, PIN_LEVEL = 3000, 3001, 3010
WC.PLAN_LEVELS = { line = LINE_LEVEL, arrow = ARROW_LEVEL, pin = PIN_LEVEL }
local OUTLINE_PAD = 2 -- the outline is 1 px wider each side; the line's width, colour and opacity, and the outline's, are settings
local ARROW_GAP = 2 -- the gap outside the badge ring; the arrowhead size (8 px) is the arrowSize setting
local LONG_SEGMENT = 0.12 -- segments longer than this share of the map width get chevrons
-- A plain round disc the client already ships (the minimap's backdrop); tinted and layered it makes the ring and fill.
-- A white, soft-edged circle: SetVertexColor multiplies, so every tinted badge part needs a white base.
-- (The old minimap-background art is near black, which tinted every badge black and hid the ring.)
local ARRIVE_FLIGHT_ICON = "Interface\\MINIMAP\\TRACKING\\FlightMaster"
local ARRIVE_WALK_ICON = "Interface\\MINIMAP\\TRACKING\\Target"
local DISC = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
WC.DISC = DISC
local TICK = 0.2 -- the tracker and minimap update about 5 times a second
-- Minimap radius in yards by zoom level (outdoors); only used to decide when the pin sits on the edge.
local MINIMAP_YARDS = { [0] = 233, 200, 166, 133, 100, 66 }
local MINIMAP_YARDS_INDOORS = { [0] = 150, 125, 100, 75, 50, 25 }
local MM_RIM = 14 -- the badge centre stays this far inside the minimap edge so the arrow fits outside it
local MM_LIFT = { 8, 8 } -- pixels the badge sits up and right of the true spot, so the NPC icon stays visible
local MM_CENTRE = 7 -- the player's arrow reaches about this far from the minimap centre
local MM_ARROW_SIZE = 10 -- the rim arrow's length in pixels
local MM_ARROW_GAP = 13 -- the edge arrow sits this far from the badge centre, toward the target
local ARRIVE_YARDS = 5 -- pick-ups and turn-ins pulse within this distance

-- Corner tags: a step that sits on one of the client's own quest markers is drawn as a small tag on that
-- marker's top-right corner instead of a full badge that would hide underneath it.
local COINCIDE_RADIUS = 2.5 -- map percent at 1x zoom; shrinks as the map zooms in (markers keep their pixel size)
-- The tag diameter relative to the full badge is the tagScale setting (0.75).
local TAG_OFFSET = 18 -- pixels up and right of the marker centre; the tag's edge clears the glyph centre
local TAG_CHAR_WIDTH = 8 -- pixels per label character, so a merged label widens the tag into a pill
-- The dark green, slightly see-through fill every badge kind uses (map badge, corner tag, minimap badge).
-- The shipped default; the badgeFill and badgeOpacity settings override it (see WC.BadgeFillColor).
WC.BADGE_FILL = { 0.05, 0.22, 0.13, 0.80 }

-- The fill's r, g, b, a from the settings; with nothing saved this is WC.BADGE_FILL.
function WC.BadgeFillColor(kind)
    if kind == "minimap" then
        local c = WC.Setting("minimapFill")
        return c[1], c[2], c[3], WC.Setting("minimapFillOpacity")
    end
    local c = WC.Setting("badgeFill")
    return c[1], c[2], c[3], WC.Setting(kind == "tag" and "tagFillOpacity" or "badgeOpacity")
end

-- Tints a badge's fill with the current setting (called whenever a badge is drawn, so colour changes apply live).
function WC.ApplyBadgeFill(p, kind)
    p.fill:SetVertexColor(WC.BadgeFillColor(kind))
end
local PULSE_SECONDS = { map = 1.2, minimap = 0.8 } -- one pulse at the default speed; the pulseSpeed setting divides it
local TAG_LEVEL = 3500 -- above the client's marker frames, which stay below this on the canvas

-- The player's own arrow is the client's, on the world map's canvas; our layers always draw below it.
local arrowLevel = nil
-- The frame level of the client's player arrow (the group-members pin), or nil when it cannot be found.
function WC.PlayerArrowLevel()
    local wm = WorldMapFrame
    if not (wm and wm.EnumeratePinsByTemplate) then return nil end
    local ok, iter, a, b = pcall(wm.EnumeratePinsByTemplate, wm, "GroupMembersPinTemplate")
    if not ok or type(iter) ~= "function" then return nil end
    local top
    for _, pin in iter, a, b do
        local pk, lv = pcall(function() return pin:GetFrameLevel() end)
        if pk and type(lv) == "number" and (not top or lv > top) then top = lv end
    end
    return top
end
-- A level for one of our layers: base + rel, but shifted down together so the highest layer (the next step's tag)
-- still sits one below the arrow's level when the plain level would reach it. Pure, given the arrow's level.
function WC.LayerLevel(base, rel, arrow)
    local lvl = base + rel
    if arrow and lvl >= arrow then lvl = math.max(0, arrow - 1 - (TAG_LEVEL + NEXT_LEVEL - rel)) end
    return lvl
end
local function layer_level(base, rel) return WC.LayerLevel(base, rel, arrowLevel) end

-- Our pins within about 15 yards of the player (at 1x map zoom; the reach shrinks as the map zooms in, since
-- pins keep their pixel size) shrink and fade so the arrow and what is around it stay readable.
local NEAR_YARDS, NEAR_SCALE, NEAR_ALPHA = 15, 0.6, 0.5
function WC.NearPlayerLook(distYards, zoom)
    if distYards and distYards <= NEAR_YARDS / math.max(1, zoom or 1) then return NEAR_SCALE, NEAR_ALPHA end
    return 1, 1
end

-- Where a route line that starts at the player begins instead: GAP canvas units short of the player, toward the
-- target, so it never crosses the arrow. Returns nil when the target is inside the gap (draw nothing).
local PLAYER_GAP = 14
function WC.LineStartShort(sx, sy, tx, ty, gap)
    local dx, dy = tx - sx, ty - sy
    local len = math.sqrt(dx * dx + dy * dy)
    if len <= gap then return nil end
    return sx + dx / len * gap, sy + dy / len * gap
end

local EMPTY = ""
local pins, lines, arrows = {}, {}, {}
local stepPin = {} -- step.n -> the badge or tag frame drawn for it in the last refresh
local lineLayer, arrowLayer
local nearPins = {} -- the drawn badges and tags with their true spots, for the near-the-player look
local nextLine -- the next-stop line pair and what it needs to follow the player: set by drawNextLine

local function mapShown()
    return WC.plan ~= nil and WC.db.settings.planMap
end

-- Pure badge helpers. A group is { steps = {...}, isNext = bool }.
-- The text in a badge: "4", or "4·5" when steps share a spot (first and last of the group).
-- Only real step numbers are shown: a live step with no route number, or an id-sized number, never is.
function WC.PinLabel(steps)
    local first, last
    for _, s in ipairs(steps) do
        local n = tonumber(s.n)
        if n and not s.synthetic and n >= 1 and n < 100000 and n == math.floor(n) then
            first = first or n
            last = n
        end
    end
    if not first then
        local s = steps[1]
        local name = s and ((s.quest ~= "" and s.quest) or s.label) or ""
        return type(name) == "string" and name:sub(1, 12) or ""
    end
    if first == last then return tostring(first) end
    return first .. "\194\183" .. last
end

-- The small "!" or "?" on the ring for a step kind, or nil for a number-only badge.
function WC.PinNotch(kind)
    return NOTCH[kind]
end

-- The group's cue: the next step's kind when it is in the group, else the first step's.
function WC.PinGroupKind(group)
    for _, s in ipairs(group.steps) do
        if group.next == s then return s.kind end
    end
    return group.steps[1].kind
end

-- The round badge, shared by the map pins and the minimap pin: a glow behind, a gold ring, a dark fill
-- inset by `inset`, the number, and a gold notch (diameter `notch`) at the top right holding the "!" or "?".
function WC.BadgeParts(p, inset, notch, font, notchInset)
    p.glow = p:CreateTexture(nil, "BACKGROUND")
    p.glow:SetTexture(DISC)
    p.glow:SetPoint("CENTER", p, "CENTER", 0, 0)
    p.ring = p:CreateTexture(nil, "BORDER")
    p.ring:SetTexture(DISC)
    p.ring:SetAllPoints()
    p.fill = p:CreateTexture(nil, "ARTWORK")
    p.fill:SetTexture(DISC)
    p.fill:SetPoint("TOPLEFT", p, "TOPLEFT", inset, -inset)
    p.fill:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -inset, inset)
    WC.ApplyBadgeFill(p)
    p.num = p:CreateFontString(nil, "OVERLAY", font)
    p.num:SetPoint("CENTER", p, "CENTER", 0, 0)
    p.notchBg = p:CreateTexture(nil, "OVERLAY")
    p.notchBg:SetTexture(DISC)
    p.notchBg:SetSize(notch, notch)
    p.notchBg:SetPoint("CENTER", p, "TOPRIGHT", -notchInset, -notchInset)
    p.notchBg:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
    p.mark = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    p.mark:SetPoint("CENTER", p.notchBg, "CENTER", 0, 0)
    p.mark:SetTextColor(0.05, 0.04, 0.02)
end

-- Re-insets the dark fill inside the ring (a corner tag has a thinner ring than a full badge).
function WC.SetBadgeInset(p, inset)
    p.fill:ClearAllPoints()
    p.fill:SetPoint("TOPLEFT", p, "TOPLEFT", inset, -inset)
    p.fill:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -inset, inset)
end

-- Tooltip detail: the label without the quest name it repeats, or "" when nothing is left.
-- Strips "<quest>: ", then "Pick up <quest> " or "Turn in <quest> " (plain-text match, so quote
-- and colon characters in names are safe).
function WC.PlanDetail(step)
    local label, quest = step.label or "", step.quest or ""
    if quest ~= "" then
        local function strip(prefix)
            if label:sub(1, #prefix) == prefix then label = label:sub(#prefix + 1) return true end
        end
        if not strip(quest .. ": ") then
            if not strip("Turn in " .. quest .. " ") and not strip("Pick up " .. quest .. " ") then
                if label == "Turn in " .. quest or label == "Pick up " .. quest or label == quest then label = "" end
            end
        end
    end
    return label
end

local function pinFor(i, canvas)
    local p = pins[i]
    if p then return p end
    p = CreateFrame("Button", nil, canvas)
    p.anchor = CreateFrame("Frame", nil, canvas) -- the true spot, which the route lines join
    p.anchor:SetSize(1, 1)
    WC.BadgeParts(p, 3, 12, "GameFontNormal", 4)
    if p.CreateAnimationGroup then
        local ag = p.glow:CreateAnimationGroup()
        ag:SetLooping("BOUNCE")
        local a = ag:CreateAnimation("Alpha")
        a:SetFromAlpha(0.25)
        a:SetToAlpha(0.8)
        a:SetDuration(PULSE_SECONDS.map)
        p.pulse, p.pulseAnim = ag, a
    end
    p:SetScript("OnEnter", function(self)
        local g = self.planGroup
        if not g then return end
        WC.ShowPlanTip(self, "ANCHOR_RIGHT", g)
        WC.HoverEnterBadge(g)
    end)
    p:SetScript("OnLeave", function() GameTooltip:Hide() WC.HoverLeaveBadge() end)
    -- a click selects one step of the badge (the next one when it is in the group, else the first), never the group
    p.selRing = p:CreateTexture(nil, "BACKGROUND")
    p.selRing:SetTexture(DISC)
    p.selRing:SetPoint("TOPLEFT", p, "TOPLEFT", -3, 3)
    p.selRing:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 3, -3)
    p.selRing:SetVertexColor(0.45, 0.7, 1, 1)
    p.selRing:Hide()
    p:SetScript("OnClick", function(self)
        local g = self.planGroup
        if not g or g.ghost or g.arrival or not WC.SelectStep then return end
        WC.SelectStep(g.next or g.steps[1])
    end)
    pins[i] = p
    return p
end

local function hideAll(list)
    for _, o in ipairs(list) do
        if o.anchor then o.anchor:Hide() end
        if o.pulse then o.pulse:Stop() end
        o:Hide()
    end
end

-- Placement maths, pure. x and y are the plan's 0-100 map coordinates, w and h the map canvas size
-- in its own units. A region's anchor offset is multiplied by the region's own scale, so a pin that is
-- counter-scaled by 1/canvasScale must have its offset divided by that same scale; otherwise the
-- position gets scaled a second time and drifts away from the true spot.
function WC.PinOffset(x, y, w, h, pinScale)
    local k = 1 / ((pinScale and pinScale > 0) and pinScale or 1)
    return x / 100 * w * k, -y / 100 * h * k
end

-- A step is drawn only on the map the world map is showing, and only while it is still to do.
function WC.PinWanted(step, mapID, done)
    return step.map == mapID and WC.HasPlace(step) and not (done and done[step.n]) and not WC.StepLocked(step)
end

-- A badge whose every step is approximate is drawn faded (its tooltip says "approx.").
WC.APPROX_ALPHA = 0.6
function WC.GroupApprox(g)
    if not g or not g.steps or #g.steps == 0 then return false end
    for _, s in ipairs(g.steps) do if not s.approx then return false end end
    return true
end

-- Groups the wanted steps of a map into badges, in plan order; steps within the mergeDistance setting of an
-- earlier group's first step join it. group.next is the plan's next step when it is in the group.
function WC.PinGroups(steps, mapID, done, nextStep)
    local groups = {}
    for _, s in ipairs(steps) do
        if WC.PinWanted(s, mapID, done) then
            local home
            for _, g in ipairs(groups) do
                local f = g.steps[1]
                if math.abs(f.x - s.x) < WC.Setting("mergeDistance") and math.abs(f.y - s.y) < WC.Setting("mergeDistance") then home = g break end
            end
            if not home then
                home = { steps = {}, x = s.x, y = s.y }
                groups[#groups + 1] = home
            end
            home.steps[#home.steps + 1] = s
            if s == nextStep or (nextStep and nextStep.live and not s.live and s.n == nextStep.n) then home.next = s end
        end
    end
    for _, g in ipairs(groups) do g.isNext = g.next ~= nil end
    return groups
end

-- Coincidence, pure. markers are { questID, x, y } in 0-100 map units. The radius is COINCIDE_RADIUS
-- divided by the canvas zoom. A group coincides with the nearest marker within the radius, a marker of
-- one of its own quests winning a tie in distance; returns that marker or nil.
function WC.MarkerRadius(canvasScale)
    return COINCIDE_RADIUS / ((canvasScale and canvasScale > 0) and canvasScale or 1)
end

function WC.GroupMarker(group, markers, radius)
    local best, bestD, bestSame
    for _, m in ipairs(markers or {}) do
        for _, s in ipairs(group.steps) do
            local d = math.sqrt((s.x - m.x) ^ 2 + (s.y - m.y) ^ 2)
            if d <= radius then
                local same = (s.questID or 0) > 0 and s.questID == m.questID
                if not best or d < bestD or (d == bestD and same and not bestSame) then
                    best, bestD, bestSame = m, d, same
                end
            end
        end
    end
    return best
end

-- The client's own markers on a map: quests from the quest-on-map API (x and y are 0-1), plus any quest or
-- POI pin the world map is holding when it can enumerate them. Every call is guarded; unknown APIs give {}.
function WC.ClientMarkers(mapID)
    local out = {}
    local q = C_QuestLog and C_QuestLog.GetQuestsOnMap
    if q then
        local ok, list = pcall(q, mapID)
        if ok and type(list) == "table" then
            for _, m in ipairs(list) do
                if type(m.x) == "number" and type(m.y) == "number" then
                    out[#out + 1] = { questID = m.questID or 0, x = m.x * 100, y = m.y * 100 }
                end
            end
        end
    end
    if WorldMapFrame and WorldMapFrame.EnumerateAllPins then
        local ok = pcall(function()
            for pin in WorldMapFrame:EnumerateAllPins() do
                local t = tostring(pin.pinTemplate or "")
                if (t:find("Quest", 1, true) or t:find("POI", 1, true)) and tonumber(pin.normalizedX) and tonumber(pin.normalizedY) then
                    out[#out + 1] = { questID = tonumber(pin.questID) or 0, x = pin.normalizedX * 100, y = pin.normalizedY * 100 }
                end
            end
        end)
        if not ok then return out end
    end
    return out
end

function WC.PinSize(setting, isNext)
    local d = math.floor((PIN_SIZES[setting] or PIN_SIZES.normal) * WC.Setting("badgeScale") + 0.5)
    return isNext and math.floor(d * WC.Setting("nextGrow") + 0.5) or d
end

-- A corner tag's diameter for a full badge of `size`, and its width for `label` (a pill when merged).
function WC.TagDiameter(size)
    return math.floor(size * WC.Setting("tagScale") + 0.5)
end

function WC.TagWidth(d, label)
    return math.max(d, TAG_CHAR_WIDTH * #label + 6)
end

function WC.TagOffset()
    return TAG_OFFSET
end

-- Arrowhead maths, pure. Points are canvas coordinates (y grows upward here; callers flip), radius is the
-- destination badge radius. Returns the direction angle (radians, counter-clockwise from east), the arrowhead
-- tip (stopping gap pixels outside the badge ring) and the segment length; nil for a zero-length segment.
function WC.ArrowPlace(x1, y1, x2, y2, radius, gap)
    local dx, dy = x2 - x1, y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    if len == 0 then return nil end
    local ux, uy = dx / len, dy / len
    local back = (radius or 0) + (gap or ARROW_GAP)
    return (math.atan2 or math.atan)(dy, dx), x2 - ux * back, y2 - uy * back, len
end

-- An arrowhead is two short strokes drawn as client lines (no texture art, which a client may not have). For a head
-- centred on (cx, cy) pointing along angle (radians, counter-clockwise from east, y up) and size pixels long, returns
-- the tip then the two wing ends as x1, y1, x2, y2, x3, y3.
function WC.ArrowheadPoints(cx, cy, angle, size)
    local ux, uy = math.cos(angle), math.sin(angle)
    local half = size / 2
    local tx, ty = cx + ux * half, cy + uy * half
    local bx, by = cx - ux * half, cy - uy * half
    local px, py = -uy * half * 0.8, ux * half * 0.8
    return tx, ty, bx + px, by + py, bx - px, by - py
end

-- How many chevrons a segment gets: none up to LONG_SEGMENT of the map width, one up to twice that, else two.
function WC.ChevronCount(len, mapWidth)
    if not mapWidth or mapWidth <= 0 then return 0 end
    local f = len / mapWidth
    if f <= LONG_SEGMENT then return 0 end
    return f <= 2 * LONG_SEGMENT and 1 or 2
end

-- Fractions along the segment (0 = start, 1 = end) where n chevrons sit, evenly spaced.
function WC.ChevronSpots(n)
    local out = {}
    for i = 1, n do out[i] = i / (n + 1) end
    return out
end

-- Draws one arrowhead (two line pieces, pool slots i and i + 1) on layer, centred on canvas offset (cx, cy) from
-- the layer's top left (y up, so below the top is negative) and pointing along angle.
local function placeArrow(layer, list, i, cx, cy, size, angle, rgba, sub, thickness)
    local tx, ty, x1, y1, x2, y2 = WC.ArrowheadPoints(cx, cy, angle, size)
    local ends = { { x1, y1 }, { x2, y2 } }
    for k = 1, 2 do
        local ln = list[i + k - 1] or layer:CreateLine()
        list[i + k - 1] = ln
        if ln.SetDrawLayer then ln:SetDrawLayer("ARTWORK", sub) end
        ln:SetThickness(thickness)
        ln:SetColorTexture(rgba[1], rgba[2], rgba[3], rgba[4])
        ln:SetStartPoint("TOPLEFT", layer, tx, ty)
        ln:SetEndPoint("TOPLEFT", layer, ends[k][1], ends[k][2])
        ln:Show()
    end
end

-- The steps to draw: all of them, or only the first n undone ones in plan order (n = 5, 10 or "all").
function WC.ShownSteps(steps, done, limit)
    local n = tonumber(limit)
    local anyLocked = false
    for _, s in ipairs(steps) do
        if WC.StepLocked(s) then anyLocked = true break end
    end
    if not n and not anyLocked then return steps end
    local out = {}
    for _, s in ipairs(steps) do
        if not n then
            if not WC.StepLocked(s) then out[#out + 1] = s end
        elseif not (done and done[s.n]) and not WC.StepLocked(s) then
            if #out >= n then break end
            out[#out + 1] = s
        end
    end
    return out
end

-- One line per undone step on the shown map, for /wowc plan debug: number, kind, x/y, badge or tag, level, shown.
function WC.PlanDebugLine(s, p)
    local drawn = p and (p.isTag and "tag" or "badge") or "none"
    local level = p and p.GetFrameLevel and p:GetFrameLevel() or "-"
    local vis = p and p:IsShown() and "yes" or "no"
    return string.format("step %s %s x=%s y=%s %s level=%s shown=%s", tostring(s.n), tostring(s.kind),
        tostring(s.x), tostring(s.y), drawn, tostring(level), vis)
end

function WC.PlanDebug()
    if not WC.plan then return print(L.PLAN_DEBUG_NONE) end
    local mapID = WorldMapFrame and WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
    local lines = {}
    for _, s in ipairs(WC.plan.steps) do
        if WC.PinWanted(s, mapID, WC.plan.done) then lines[#lines + 1] = WC.PlanDebugLine(s, stepPin[s.n]) end
    end
    print(string.format(L.PLAN_DEBUG_HEAD, tostring(mapID), #lines))
    local drawn = 0
    for _, a in ipairs(arrows) do if a:IsShown() then drawn = drawn + 1 end end
    print(string.format(L.PLAN_ARROW_DEBUG, drawn))
    local legacy = "Interface\\Minimap\\ROTATING-MINIMAPARROW"
    local id = GetFileIDFromPath and GetFileIDFromPath(legacy)
    local found = id and tostring(id) or L.PLAN_ARROW_DEBUG_NONE
    print(string.format(L.PLAN_ARROW_DEBUG_LEGACY, legacy, found))
    for _, l in ipairs(lines) do print(l) end
end

-- /wowc plan show <n|all>: limit the map to the next n undone steps.
function WC.SetPlanShow(arg)
    local n = tonumber(arg)
    WC.db.settings.planShow = (n and n >= 1) and math.floor(n) or "all"
    print(string.format(L.PLAN_SHOW_SET, tostring(WC.db.settings.planShow)))
    if WC.SyncOptions then WC.SyncOptions() end
    WC.RefreshPlan()
end

-- The ghost badges: the next locked step of each quest chain on this map, drawn as a hollow, faint ring with a dim
-- number and a tiny lock, so what a turn-in will open is hinted without crowding the route. They reuse the badge
-- frames after the real ones (index first + k). Returns the drawn ghosts as { step, from, pin }.
local GHOST_ALPHA, GHOST_RING = 0.55, 0.5
function WC.DrawGhosts(canvas, mapID, first, w, h, scale, where, spot)
    local drawn = {}
    if not WC.Setting("showUpcoming") or not WC.plan or not WC.plan.hasLocked then return drawn end
    local setting = WC.db.settings.planSize
    local base = (canvas.GetFrameLevel and canvas:GetFrameLevel() or 0)
    local k = 0
    for _, gh in ipairs(WC.GhostSteps(WC.plan.steps, WC.Setting("ghostsPerChain"))) do
        local s = gh.step
        if s.map == mapID and WC.HasPlace(s) then
            k = k + 1
            local p = pinFor(first + k, canvas)
            local size = WC.PinSize(setting, false)
            local ox, oy = WC.PinOffset(s.x, s.y, w, h, scale)
            local a = p.anchor
            a:SetScale(scale)
            a:ClearAllPoints()
            a:SetPoint("CENTER", canvas, "TOPLEFT", ox, oy)
            p:SetScale(scale)
            p:ClearAllPoints()
            p:SetSize(size, size)
            if p.SetFrameLevel then p:SetFrameLevel(layer_level(base, PIN_LEVEL - 1)) end
            p:SetPoint("CENTER", a, "CENTER", 0, 0)
            p.planGroup = { steps = { s }, ghost = true, from = gh.from, total = #WC.plan.steps }
            p.isTag = false
            local rc = WC.Setting("ringColor")
            p.ring:SetVertexColor(rc[1], rc[2], rc[3], GHOST_RING)
            p.fill:Hide() -- hollow
            p.ring:Show()
            if p.icon then p.icon:Hide() end
            p.num:SetText(tostring(s.n))
            p.num:SetTextColor(0.6, 0.6, 0.6)
            p.glow:Hide()
            p.notchBg:Hide()
            p.mark:SetText("")
            if p.pulse then p.pulse:Stop() end
            if not p.lock and p.CreateTexture then
                p.lock = p:CreateTexture(nil, "OVERLAY")
                p.lock:SetTexture("Interface\\PetBattles\\PetBattle-LockIcon")
                p.lock:SetSize(9, 9)
                p.lock:SetPoint("CENTER", p, "TOPRIGHT", -3, -3)
            end
            if p.lock then p.lock:SetVertexColor(0.75, 0.75, 0.75, 0.9) p.lock:Show() end
            if p.SetAlpha then p:SetAlpha(GHOST_ALPHA) end
            a:Show()
            p:Show()
            drawn[#drawn + 1] = { step = s, from = gh.from, pin = p, spot = { ox * scale, oy * scale } }
        end
    end
    return drawn
end

-- The faint dashed route into each ghost, from the turn-in that unlocks it when that is drawn on this map.
-- Dashes are short line pieces (the client draws solid lines only), appended after the real route lines.
local DASHES = 7
function WC.DrawGhostLines(ghosts, canvas, layer, n, lineW, outline, spot, where)
    if not (ghosts and layer and canvas.CreateLine) then return end
    for _, g in ipairs(ghosts) do
        local from = g.from and spot[g.from.n]
        if from then
            local to = g.spot
            for i = 1, DASHES do
                local f1, f2 = (i - 1) / DASHES + 0.02, (i - 0.45) / DASHES
                n = n + 1
                local ln = lines[n] or layer:CreateLine()
                lines[n] = ln
                if ln.SetDrawLayer then ln:SetDrawLayer("ARTWORK", 2) end
                ln:SetThickness(math.max(1, lineW - 1))
                local c = WC.Setting("lineColor")
                ln:SetColorTexture(c[1], c[2], c[3], 0.3)
                ln:SetStartPoint("TOPLEFT", canvas, from[1] + (to[1] - from[1]) * f1, from[2] + (to[2] - from[2]) * f1)
                ln:SetEndPoint("TOPLEFT", canvas, from[1] + (to[1] - from[1]) * f2, from[2] + (to[2] - from[2]) * f2)
                ln:Show()
            end
        end
    end
end

-- Shrinks and fades each drawn pin that sits near the player (see WC.NearPlayerLook); called after a redraw and
-- from the tick, so a pin eases back as the player walks away.
function WC.UpdateNearPlayer(mapID, px, py)
    if #nearPins == 0 then return end
    local w, h = WC.MapYards(WorldMapFrame and WorldMapFrame.GetMapID and WorldMapFrame:GetMapID() or mapID)
    local zoom = WorldMapFrame and WorldMapFrame.GetCanvasScale and WorldMapFrame:GetCanvasScale() or 1
    local here = px ~= nil and mapID ~= nil and WorldMapFrame and WorldMapFrame.GetMapID and WorldMapFrame:GetMapID() == mapID
    for _, np in ipairs(nearPins) do
        local p = np.pin
        local sc, al = 1, 1
        if here and w then
            local d = WC.PlanDistance(px, py, np.x, np.y, w, h)
            sc, al = WC.NearPlayerLook(d, zoom)
        end
        if p.SetScale then p:SetScale(np.scale * sc) end
        if p.SetAlpha then p:SetAlpha(al) end
    end
end

-- Moves the next-stop line's start to the player and shows it, or hides it when the player is not on the shown
-- map. Called from the existing tick (about 5 a second); it only re-anchors two lines.
function WC.UpdateNextLine(mapID, px, py)
    local nl = nextLine
    if not nl then return end
    local on = px ~= nil and mapID == nl.map and mapShown()
    local sx, sy
    if on then
        sx, sy = WC.LineStartShort(px / 100 * nl.w, -py / 100 * nl.h, nl.tx, nl.ty, PLAYER_GAP * nl.scale)
        on = sx ~= nil
    end
    for _, ln in ipairs({ nl.outline, nl.line }) do
        if on then
            ln:SetStartPoint("TOPLEFT", nl.canvas, sx, sy)
            ln:Show()
        else
            ln:Hide()
        end
    end
end

-- The one highlighted line, from the player to the next step, when that step is on the shown map. It is a
-- brighter shade of the route colour (or the player's own pick), a little thicker, and above the other legs.
-- Returns the new count of pooled lines in use.
local function drawNextLine(canvas, mapID, w, h, scale, where, spot, n, lineW, lineA, outline)
    nextLine = nil
    local step = WC.PlanNext()
    local target = step and step.map == mapID and where[step.n]
    if not target then return n end
    local c = WC.NextLineColor()
    local pair = {}
    for k = 1, 2 do
        n = n + 1
        local ln = lines[n] or lineLayer:CreateLine()
        lines[n] = ln
        if ln.SetDrawLayer then ln:SetDrawLayer("ARTWORK", k == 1 and 3 or 4) end
        if k == 1 then
            ln:SetThickness(lineW + OUTLINE_PAD + 2)
            ln:SetColorTexture(outline[1], outline[2], outline[3], outline[4])
        else
            ln:SetThickness(lineW + 1)
            ln:SetColorTexture(c[1], c[2], c[3], math.min(1, math.floor((lineA + 0.2) * 100 + 0.5) / 100))
        end
        ln:SetEndPoint("CENTER", target)
        ln:Hide()
        pair[k] = ln
    end
    nextLine = { outline = pair[1], line = pair[2], canvas = canvas, map = mapID, w = w, h = h, scale = scale,
        tx = spot[step.n][1], ty = spot[step.n][2] }
    local pm, px, py = WC.PlayerPos()
    WC.UpdateNextLine(pm, px, py)
    return n
end

-- The temporary pin for "Show on map" on a place with no plan badge: one pulsing ring and a label on the world map's
-- canvas, our own frames only. It clears when the map closes, after TEMP_SECONDS, or on the next Show on map.
local TEMP_SECONDS = 20
local tempPin, tempShown = nil, nil -- the frame, and { map, x, y, label, token } while one is wanted

local function temp_frame(canvas)
    if tempPin then return tempPin end
    local p = CreateFrame("Frame", nil, canvas)
    p.anchor = CreateFrame("Frame", nil, canvas)
    p.anchor:SetSize(1, 1)
    WC.BadgeParts(p, 3, 12, "GameFontNormal", 4)
    p.fill:Show()
    p.label = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    p.label:SetPoint("TOP", p, "BOTTOM", 0, -2)
    if p.CreateAnimationGroup then
        local ag = p.glow:CreateAnimationGroup()
        ag:SetLooping("BOUNCE")
        local a = ag:CreateAnimation("Alpha")
        a:SetFromAlpha(0.25)
        a:SetToAlpha(0.8)
        a:SetDuration(PULSE_SECONDS.map)
        p.pulse, p.pulseAnim = ag, a
    end
    tempPin = p
    return p
end

local function hide_temp()
    if not tempPin then return end
    if tempPin.pulse then tempPin.pulse:Stop() end
    tempPin.anchor:Hide()
    tempPin:Hide()
end

-- Draws (or hides) the temporary pin for the map the world map is showing.
function WC.DrawTempPin()
    local t = tempShown
    if not t or not (WorldMapFrame and WorldMapFrame.GetCanvas and WorldMapFrame.GetMapID) then hide_temp() return end
    if WorldMapFrame.GetMapID(WorldMapFrame) ~= t.map then hide_temp() return end
    local canvas = WorldMapFrame:GetCanvas()
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    if not w or not h or w <= 0 then hide_temp() return end
    local scale = 1 / ((WorldMapFrame.GetCanvasScale and WorldMapFrame:GetCanvasScale()) or 1)
    local p = temp_frame(canvas)
    local size = WC.PinSize(WC.db.settings.planSize, true)
    local ox, oy = WC.PinOffset(t.x, t.y, w, h, scale)
    p.anchor:SetScale(scale)
    p.anchor:ClearAllPoints()
    p.anchor:SetPoint("CENTER", canvas, "TOPLEFT", ox, oy)
    p.anchor:Show()
    p:SetScale(scale)
    p:SetSize(size, size)
    p:ClearAllPoints()
    p:SetPoint("CENTER", p.anchor, "CENTER", 0, 0)
    if p.SetFrameLevel and canvas.GetFrameLevel then p:SetFrameLevel(canvas:GetFrameLevel() + PIN_LEVEL + NEXT_LEVEL) end
    local rc = WC.Setting("nextRingColor")
    p.ring:SetVertexColor(rc[1], rc[2], rc[3], 1)
    local gc = WC.Setting("glowColor")
    p.glow:SetSize(size * 1.7, size * 1.7)
    p.glow:SetVertexColor(gc[1], gc[2], gc[3], WC.Setting("glowOpacity"))
    p.glow:Show()
    p.num:SetText("")
    p.mark:SetText("")
    p.notchBg:Hide()
    p.label:SetText(WC.SafeText and WC.SafeText(t.label) or t.label)
    if p.pulseAnim then p.pulseAnim:SetDuration(PULSE_SECONDS.map / WC.Setting("pulseSpeed")) end
    if p.pulse then p.pulse:Play() end
    p:Show()
end

function WC.ClearTempPin()
    tempShown = nil
    hide_temp()
end

-- Shows the temporary pin at place ({ map, x, y }) with its label, for TEMP_SECONDS.
function WC.ShowTempPin(place, label)
    local mine = { map = place.map, x = place.x, y = place.y, label = label }
    tempShown = mine
    WC.DrawTempPin()
    if C_Timer and C_Timer.After then
        C_Timer.After(TEMP_SECONDS, function() if tempShown == mine then WC.ClearTempPin() end end)
    end
end

-- The temporary pin the last Show on map drew, or nil (for tests).
function WC.TempPin() return tempShown and tempPin or nil end

-- Another zone's map (the player is somewhere else): the zone's stops are numbered by the plan's own order for the
-- zone, and an arrival marker (flight master or walking icon) is drawn where the player lands. Returns foreign (true
-- on another zone), the arrival marker's key in where/spot/rad or nil, and the chain: the key (a step n) of each badge
-- in order. Without `zones` in the plan (an older one) the chain is empty: badges only, no legs.
function WC.DrawZoneChain(canvas, mapID, groups, used, w, h, scale, base, where, spot, rad)
    local pm = WC.PlayerPos()
    local foreign = pm ~= nil and pm ~= mapID
    local chain = {}
    if not foreign then return false, nil, chain end
    local z = WC.plan.zones and WC.plan.zones[mapID]
    if not z then return true, nil, chain end
    local owner = {}
    for _, g in ipairs(groups) do
        for _, st in ipairs(g.steps) do owner[st.n] = owner[st.n] or g end
    end
    local used_g = {}
    for _, n in ipairs(z.order) do
        local g = owner[n]
        if g and not used_g[g] then
            used_g[g] = true
            chain[#chain + 1] = n
            for _, p in ipairs(pins) do
                if p.planGroup == g and p:IsShown() then p.num:SetText(tostring(#chain)) end
            end
        end
    end
    local a = z.arrival
    if a.map ~= mapID then return true, nil, chain end
    local p = pinFor(used + 1, canvas)
    local size = WC.PinSize(WC.db.settings.planSize, false)
    local ox, oy = WC.PinOffset(a.x, a.y, w, h, scale)
    local an = p.anchor
    an:SetScale(scale)
    an:ClearAllPoints()
    an:SetPoint("CENTER", canvas, "TOPLEFT", ox, oy)
    p:SetScale(scale)
    p:ClearAllPoints()
    p:SetSize(size, size)
    if p.SetFrameLevel then p:SetFrameLevel(layer_level(base, PIN_LEVEL)) end
    p:SetPoint("CENTER", an, "CENTER", 0, 0)
    local label = a.npc and a.name and string.format(L.ARRIVE_AT_NPC, a.name, a.npc)
        or string.format(L.ARRIVE_AT, a.name or a.npc or "?")
    p.planGroup = { steps = {}, arrival = a, arrivalLabel = label }
    p.isTag = false
    p.ring:Hide()
    p.fill:Hide()
    p.glow:Hide()
    p.notchBg:Hide()
    p.mark:SetText("")
    p.num:SetText("")
    if p.pulse then p.pulse:Stop() end
    if p.lock then p.lock:Hide() end
    if p.SetAlpha then p:SetAlpha(1) end
    if not p.icon and p.CreateTexture then
        p.icon = p:CreateTexture(nil, "OVERLAY")
        p.icon:SetAllPoints()
    end
    if p.icon then
        p.icon:SetTexture(a.kind == "walk" and ARRIVE_WALK_ICON or ARRIVE_FLIGHT_ICON)
        p.icon:Show()
    end
    an:Show()
    p:Show()
    where.arrival, spot.arrival, rad.arrival = an, { ox * scale, oy * scale }, size * scale / 2
    return true, "arrival", chain
end

-- Redraws the pins and lines for the map the world map is showing.
function WC.RefreshMapPins()
    nextLine = nil
    nearPins = {}
    arrowLevel = WC.PlayerArrowLevel()
    if WC.RefreshMapPanelSoon then WC.RefreshMapPanelSoon() end -- the side panel follows the map shown and the plan
    hideAll(pins)
    hideAll(lines)
    hideAll(arrows)
    WC.DrawTempPin()
    if not mapShown() or not (WorldMapFrame and WorldMapFrame.GetCanvas and WorldMapFrame.GetMapID) then return end
    local canvas = WorldMapFrame:GetCanvas()
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    if not w or not h or w <= 0 then return end
    local mapID = WorldMapFrame:GetMapID()
    local scale = 1 / ((WorldMapFrame.GetCanvasScale and WorldMapFrame:GetCanvasScale()) or 1)
    local setting = WC.db.settings.planSize
    stepPin = {}
    local shown = WC.ShownSteps(WC.plan.steps, WC.plan.done, WC.db.settings.planShow)
    if #(WC.plan.live or {}) > 0 then
        local withLive = { unpack(shown) }
        for _, st in ipairs(WC.plan.live) do withLive[#withLive + 1] = st end
        shown = withLive
    end
    local extras = WC.LiveTurnInSteps and WC.LiveTurnInSteps() or {}
    if #extras > 0 then
        shown = { unpack(shown) }
        for _, st in ipairs(extras) do shown[#shown + 1] = st end
    end
    local groups = WC.PinGroups(shown, mapID, WC.plan.done, WC.PlanNext())
    local markers = #groups > 0 and WC.ClientMarkers(mapID) or {}
    local radius = WC.MarkerRadius(WorldMapFrame.GetCanvasScale and WorldMapFrame:GetCanvasScale())
    local base = (canvas.GetFrameLevel and canvas:GetFrameLevel() or 0)
    local where, spot, rad = {}, {}, {} -- step.n -> the pin's anchor, its canvas spot and badge radius
    for i, g in ipairs(groups) do
        local p = pinFor(i, canvas)
        p.planGroup = g
        local size = WC.PinSize(setting, g.isNext)
        local marker = WC.GroupMarker(g, markers, radius)
        local ox, oy = WC.PinOffset(g.x, g.y, w, h, scale)
        local a = p.anchor
        a:SetScale(scale)
        a:ClearAllPoints()
        a:SetPoint("CENTER", canvas, "TOPLEFT", ox, oy)
        p:SetScale(scale)
        p:ClearAllPoints()
        local label = WC.PinLabel(g.steps)
        if marker then
            local d = WC.TagDiameter(size)
            p:SetSize(WC.TagWidth(d, label), d)
            if p.SetFrameLevel then p:SetFrameLevel(layer_level(base, TAG_LEVEL + (g.isNext and NEXT_LEVEL or 0))) end
            p:SetPoint("CENTER", a, "CENTER", TAG_OFFSET, TAG_OFFSET)
            WC.SetBadgeInset(p, 1.5)
            if p.num.SetFontObject then p.num:SetFontObject("GameFontNormal") end
            p.notchBg:Hide()
            p.mark:SetText("")
        else
            p:SetSize(size, size)
            if p.SetFrameLevel then p:SetFrameLevel(layer_level(base, PIN_LEVEL + (g.isNext and NEXT_LEVEL or 0))) end
            p:SetPoint("CENTER", a, "CENTER", 0, 0)
            WC.SetBadgeInset(p, 3)
            if p.num.SetFontObject then p.num:SetFontObject("GameFontNormal") end
        end
        p.isTag = marker ~= nil
        p.fill:Show() -- a ghost badge reuses these frames hollow; a real step is solid again
        p.ring:Show()
        if p.icon then p.icon:Hide() end
        local approx = WC.GroupApprox(g)
        if p.SetAlpha then p:SetAlpha(approx and WC.APPROX_ALPHA or 1) end
        if p.lock then p.lock:Hide() end
        local rc = WC.Setting(g.isNext and "nextRingColor" or "ringColor")
        p.ring:SetVertexColor(rc[1], rc[2], rc[3], (marker and WC.Setting("tagRingOpacity") or 1) * (approx and WC.APPROX_ALPHA or 1))
        local nc = WC.Setting("numberColor")
        p.num:SetTextColor(nc[1], nc[2], nc[3])
        local gd = (marker and WC.TagDiameter(size) or size) * 1.7
        local gc = WC.Setting("glowColor")
        p.glow:SetSize(gd, gd)
        p.glow:SetVertexColor(gc[1], gc[2], gc[3], WC.Setting("glowOpacity"))
        if p.pulseAnim then p.pulseAnim:SetDuration(PULSE_SECONDS.map / WC.Setting("pulseSpeed")) end
        p.glow:SetShown(g.isNext or WC.GroupHot(g))
        p.num:SetText(label)
        if not marker then
            local notch = WC.PinNotch(WC.PinGroupKind(g))
            p.mark:SetText(notch or "")
            p.notchBg:SetShown(notch ~= nil)
        end
        a:Show()
        p:Show()
        WC.ApplyBadgeFill(p, marker and "tag" or nil)
        WC.ApplyPinSelection(p)
        if p.pulse and ((g.isNext and WC.Setting("nextPulse")) or WC.GroupHot(g)) then p.pulse:Play() end
        local r = (marker and WC.TagDiameter(size) or size) * scale / 2
        for _, s in ipairs(g.steps) do stepPin[s.n] = p end
        nearPins[#nearPins + 1] = { pin = p, x = g.x, y = g.y, scale = scale }
        for _, s in ipairs(g.steps) do where[s.n], spot[s.n], rad[s.n] = p.anchor, { ox * scale, oy * scale }, r end
    end
    do
        local pm, px, py = WC.PlayerPos()
        WC.UpdateNearPlayer(pm, px, py)
    end
    local ghosts = WC.DrawGhosts(canvas, mapID, #groups, w, h, scale, where, spot)
    local foreign, arrival, chainGroups = WC.DrawZoneChain(canvas, mapID, groups, #groups + #ghosts, w, h, scale, base, where, spot, rad)
    if not WC.db.settings.planLines or not canvas.CreateLine then return end
    if not lineLayer then
        lineLayer = CreateFrame("Frame", nil, canvas)
        lineLayer:SetAllPoints(canvas)
    end
    if lineLayer.SetFrameLevel then lineLayer:SetFrameLevel(layer_level(base, LINE_LEVEL)) end
    lineLayer:Show()
    if not arrowLayer then
        arrowLayer = CreateFrame("Frame", nil, canvas)
        arrowLayer:SetAllPoints(canvas)
    end
    if arrowLayer.SetFrameLevel then arrowLayer:SetFrameLevel(layer_level(base, ARROW_LEVEL)) end
    arrowLayer:Show()
    local wantArrows = WC.db.settings.planArrows
    local lineW, lineA, lineC = WC.Setting("lineWidth"), WC.Setting("lineOpacity"), WC.Setting("lineColor")
    local arrowSize, chevronSize = WC.Setting("arrowSize"), WC.Setting("chevronSize")
    local outC, outA = WC.Setting("outlineColor"), WC.Setting("outlineOpacity")
    local outline = { outC[1], outC[2], outC[3], outA }
    -- Lines join consecutive undone steps (plan order) that are both on this map. Each is a dark outline with
    -- the gold line on top, drawn between the true spots so joints meet with no gap at any zoom.
    local n, na = 0, 0
    local function leg(ka, kb)
        for k = 1, 2 do
            n = n + 1
            local ln = lines[n] or lineLayer:CreateLine()
            lines[n] = ln
            if k == 1 then
                if ln.SetDrawLayer then ln:SetDrawLayer("ARTWORK", 1) end
                ln:SetThickness(lineW + OUTLINE_PAD)
                ln:SetColorTexture(outline[1], outline[2], outline[3], outline[4])
            else
                if ln.SetDrawLayer then ln:SetDrawLayer("ARTWORK", 2) end
                ln:SetThickness(lineW)
                ln:SetColorTexture(lineC[1], lineC[2], lineC[3], lineA)
            end
            ln:SetStartPoint("CENTER", where[ka])
            ln:SetEndPoint("CENTER", where[kb])
            ln:Show()
        end
        if wantArrows and arrowLayer.CreateTexture then
            local a, b = spot[ka], spot[kb]
            -- spots are offsets from the canvas's top left (y up, so negative below it): the maths' own frame
            local ang, tx, ty, len = WC.ArrowPlace(a[1], a[2], b[1], b[2], rad[kb], ARROW_GAP + arrowSize / 2)
            if ang then
                local headC = { lineC[1], lineC[2], lineC[3], 1 }
                local function put(cx, cy, size, sub)
                    placeArrow(arrowLayer, arrows, na + 1, cx, cy, size * scale, ang, outline, sub, (lineW + OUTLINE_PAD + 1) * scale)
                    placeArrow(arrowLayer, arrows, na + 3, cx, cy, size * scale, ang, headC, sub + 1, (lineW + 1) * scale)
                    na = na + 4
                end
                put(tx, ty, arrowSize, 3)
                local chevrons = WC.Setting("planChevrons") and WC.ChevronCount(len, w) or 0
                for _, f in ipairs(WC.ChevronSpots(chevrons)) do
                    put(a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f, chevronSize, 3)
                end
            end
        end
    end
    if foreign then
        -- Another zone: one chain from the arrival marker through the zone's own stop order, never from the player.
        local seq = arrival and { arrival } or {}
        for _, k in ipairs(chainGroups) do seq[#seq + 1] = k end
        for k = 2, #seq do
            if where[seq[k - 1]] ~= where[seq[k]] then leg(seq[k - 1], seq[k]) end
        end
    else
        local prev
        for _, s in ipairs(shown) do
            if not (WC.plan.done and WC.plan.done[s.n]) then
                if WC.HasPlace(s) then
                    if prev and prev.map == mapID and s.map == mapID and where[prev.n] ~= where[s.n] then leg(prev.n, s.n) end
                    prev = s
                end
            end
        end
    end
    if not foreign then n = drawNextLine(canvas, mapID, w, h, scale, where, spot, n, lineW, lineA, outline) end
    WC.DrawGhostLines(ghosts, canvas, lineLayer, n, lineW, outline, spot, where)
end

-- Minimap placement, pure. dist is in yards, bearing in degrees clockwise from north, facing the player's
-- facing in radians (counter-clockwise from north) when Rotate Minimap is on, else nil; radius is the
-- minimap's reach in yards and half its pixel radius. Returns the offset in pixels from the minimap centre of
-- the true spot (x, y), the screen angle in radians, and edge = true when the target is beyond the
-- rim (then x, y is the rim point the badge is clamped to).
function WC.MinimapPlace(dist, bearing, facing, radius, half)
    local angle = math.rad(bearing) + (facing or 0) -- a rotating map turns the target with the player
    local rim = half - MM_RIM
    local reach = dist / radius * (half - 6)
    local edge = reach > rim
    if edge then reach = rim end
    return math.sin(angle) * reach, math.cos(angle) * reach, angle, edge
end

-- Where the badge is drawn relative to the true spot: lifted up and right so the game's own quest-giver
-- icon, which sits on the spot, stays visible; clamped to the rim it has no spot to keep clear.
function WC.MinimapBadgeOffset(edge)
    if edge then return 0, 0 end
    return MM_LIFT[1], MM_LIFT[2]
end

-- Keeps the minimap badge off the player's arrow at the centre: when the badge (lifted off its spot) would cover
-- the centre, it moves out to the rim in the target's direction and counts as an edge pin. Returns x, y, edge.
function WC.MinimapKeepClear(x, y, angle, half, badge, edge)
    if edge then return x, y, edge end
    local cx, cy = x + MM_LIFT[1], y + MM_LIFT[2]
    if math.sqrt(cx * cx + cy * cy) >= badge / 2 + MM_CENTRE then return x, y, false end
    local rim = half - MM_RIM
    return math.sin(angle) * rim, math.cos(angle) * rim, true
end

-- The edge arrow's offset from the badge centre and its texture rotation (the art points up).
function WC.MinimapArrow(angle)
    return math.sin(angle) * MM_ARROW_GAP, math.cos(angle) * MM_ARROW_GAP, -angle
end

-- The subtle pulse shows within ARRIVE_YARDS of a pick-up or turn-in; it never completes a step.
function WC.PinArrived(kind, dist)
    return (kind == "pickup" or kind == "turnin") and dist ~= nil and dist <= ARRIVE_YARDS
end

local function placeMinimap(m, mapID, px, py, step)
    if not (Minimap and mapID == step.map and px and WC.HasPlace(step)) then m:Hide() return end
    local w, h = WC.MapYards(mapID)
    local dist, compass, bearing = WC.PlanDistance(px, py, step.x, step.y, w, h)
    m.tipDist, m.tipDir = dist, compass
    local half = (Minimap:GetWidth() or 140) / 2
    local zoom = Minimap.GetZoom and Minimap:GetZoom() or 0
    local indoors = IsIndoors and IsIndoors()
    local radius = (indoors and MINIMAP_YARDS_INDOORS or MINIMAP_YARDS)[zoom] or (indoors and 100 or MINIMAP_YARDS[3])
    local facing
    if GetCVar and GetCVar("rotateMinimap") == "1" and GetPlayerFacing then facing = GetPlayerFacing() end
    local x, y, angle, edge = WC.MinimapPlace(dist, bearing, facing, radius, half)
    x, y, edge = WC.MinimapKeepClear(x, y, angle, half, WC.Setting("minimapBadgeSize"), edge)
    m:ClearAllPoints()
    m:SetPoint("CENTER", Minimap, "CENTER", x, y)
    local b = m.badge
    local bs = WC.Setting("minimapBadgeSize")
    b:SetSize(bs, bs)
    b.glow:SetSize(bs * 1.6, bs * 1.6)
    local gc, rc = WC.Setting("glowColor"), WC.Setting("nextRingColor")
    b.glow:SetVertexColor(gc[1], gc[2], gc[3], WC.Setting("glowOpacity"))
    b.ring:SetVertexColor(rc[1], rc[2], rc[3], 1)
    local nc = WC.Setting("numberColor")
    b.num:SetTextColor(nc[1], nc[2], nc[3])
    if b.pulseAnim then b.pulseAnim:SetDuration(PULSE_SECONDS.minimap / WC.Setting("pulseSpeed")) end
    WC.ApplyBadgeFill(b, "minimap")
    local ox, oy = WC.MinimapBadgeOffset(edge)
    b:ClearAllPoints()
    b:SetPoint("CENTER", m, "CENTER", ox, oy)
    m.spot:SetShown(not edge)
    local wantRim = edge and WC.Setting("minimapArrow")
    for _, ln in ipairs(m.arrow) do ln:SetShown(wantRim) end
    if wantRim then
        local ax, ay = WC.MinimapArrow(angle)
        local tx, ty, x1, y1, x2, y2 = WC.ArrowheadPoints(ax, ay, (math.atan2 or math.atan)(ay, ax), MM_ARROW_SIZE)
        local ends = { { x1, y1 }, { x2, y2 } }
        local nc2 = WC.NextLineColor()
        for k, ln in ipairs(m.arrow) do
            ln:SetColorTexture(nc2[1], nc2[2], nc2[3], 1)
            ln:SetStartPoint("CENTER", b, tx, ty)
            ln:SetEndPoint("CENTER", b, ends[k][1], ends[k][2])
        end
    end
    b.num:SetText(tostring(step.n))
    local notch = WC.PinNotch(step.kind)
    b.mark:SetText(notch or "")
    b.notchBg:SetShown(notch ~= nil)
    local arrived = (WC.Setting("arrivalPulse") and WC.PinArrived(step.kind, dist)) or WC.StepHot(step) or false
    b.glow:SetShown(arrived)
    if b.pulse then
        if arrived and not b.pulsing then b.pulse:Play() elseif not arrived and b.pulsing then b.pulse:Stop() end
    end
    b.pulsing = arrived
    m:Show()
end

local function tick()
    local f = WC.planTracker
    local step = WC.PlanNext()
    local mapID, px, py = WC.PlayerPos()
    if WC.PlanArrive(mapID) then -- arriving completes a trip with no action
        WC.RefreshPlan()
        return
    end
    if f and f:IsShown() then f.label:SetText(WC.SafeText(WC.PlanText(step, mapID, px, py))) end
    if WC.panel and WC.panel:IsShown() and WC.RefreshNextLine then WC.RefreshNextLine() end
    if WC.UpdateMapPanelHeader then WC.UpdateMapPanelHeader() end
    if WC.HereTick then WC.HereTick(mapID, px, py) end
    WC.UpdateNextLine(mapID, px, py)
    if mapShown() then WC.UpdateNearPlayer(mapID, px, py) end
    local m = WC.planMinimap
    if m then
        if step and mapShown() and WC.Setting("minimapPin") then placeMinimap(m, mapID, px, py, step) else m:Hide() end
    end
end

-- Rings the badge that holds the selected step (the ghost badges never carry a selection).
function WC.ApplyPinSelection(p)
    if not p.selRing then return end
    local g, sel, on = p.planGroup, WC.panelState and WC.panelState.selectedStep, false
    if g and not g.ghost and not g.arrival and sel then
        for _, s in ipairs(g.steps) do if s.n == sel then on = true end end
    end
    p.selRing:SetShown(on)
end

function WC.ApplyMapSelection()
    for _, p in ipairs(pins) do
        if p:IsShown() then WC.ApplyPinSelection(p) end
    end
end

-- Applies the hover pulse to the badges already drawn (world map pins and the minimap badge) without a redraw:
-- a badge whose quest is hovered in the panel glows and pulses; the next step's own glow stays as it was.
function WC.ApplyMapHover()
    for _, p in ipairs(pins) do
        local g = p.planGroup
        if g and p:IsShown() then
            local hot = WC.GroupHot(g)
            p.glow:SetShown(g.isNext or hot)
            if p.pulse then
                if (g.isNext and WC.Setting("nextPulse")) or hot then p.pulse:Play() else p.pulse:Stop() end
            end
        end
    end
    if WC.planMinimap and WC.planMinimap:IsShown() then tick() end
end

-- Redraws everything from the current plan and the settings.
function WC.RefreshPlan()
    local f = WC.planTracker
    if not f then return end
    local on = WC.plan ~= nil and WC.db.settings.planTracker
    if on then
        local bg = WC.Setting("planBgColor")
        f.bg:SetColorTexture(bg[1], bg[2], bg[3], WC.Setting("planBgOpacity"))
        if f.label.SetFont then f.label:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", WC.Setting("planTextSize")) end
        f:Show()
    else
        f:Hide()
    end
    tick()
    WC.RefreshMapPins()
end

function WC.SetPlanSize(size)
    local id = PIN_SIZES[size] and size or "normal"
    WC.db.settings.planSize = id
    local name = L["PLAN_SIZE_" .. id]
    print(string.format(L.PLAN_SIZE_SET, name))
    if WC.SyncOptions then WC.SyncOptions() end
    WC.RefreshPlan()
end

function WC.CyclePlanSize()
    local cur = WC.db.settings.planSize
    for i, id in ipairs(PIN_ORDER) do
        if id == cur then return WC.SetPlanSize(PIN_ORDER[i % #PIN_ORDER + 1]) end
    end
    WC.SetPlanSize("normal")
end

-- /wowc plan toggles the tracker; "map" the pins, "lines" the route lines, "arrows" their arrowheads, "size [small|normal|large]" the pin size.
function WC.TogglePlan(what, arg)
    local s = WC.db.settings
    if what == "map" then
        s.planMap = not s.planMap
        print(s.planMap and L.PLAN_MAP_ON or L.PLAN_MAP_OFF)
    elseif what == "lines" then
        s.planLines = not s.planLines
        print(s.planLines and L.PLAN_LINES_ON or L.PLAN_LINES_OFF)
    elseif what == "arrows" then
        s.planArrows = not s.planArrows
        print(s.planArrows and L.PLAN_ARROWS_ON or L.PLAN_ARROWS_OFF)
    elseif what == "debug" then
        return WC.PlanDebug()
    elseif what == "show" then
        return WC.SetPlanShow(arg)
    elseif what == "size" then
        if PIN_SIZES[arg] then return WC.SetPlanSize(arg) end
        return WC.CyclePlanSize()
    else
        s.planTracker = not s.planTracker
        print(s.planTracker and L.PLAN_TRACKER_ON or L.PLAN_TRACKER_OFF)
    end
    if WC.SyncOptions then WC.SyncOptions() end
    WC.RefreshPlan()
end

function WC.CreatePlanUI()
    local f = CreateFrame("Frame", "WoWCompanionPlanTracker", UIParent)
    f:SetSize(300, 22)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if not WC.db.settings.locked then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        WC.db.planPosition = { point = point, relPoint = relPoint, x = x, y = y }
    end)
    local pos = WC.db.planPosition
    if type(pos) == "table" and pos.point then
        f:SetPoint(pos.point, UIParent, pos.relPoint, tonumber(pos.x) or 0, tonumber(pos.y) or 0)
    else
        f:SetPoint("TOP", UIParent, "TOP", 0, -150)
    end
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints(f)
    f.label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.label:SetPoint("LEFT", f, "LEFT", 6, 0)
    f.label:SetWidth(288)
    f.label:SetJustifyH("LEFT")
    f:Hide()
    WC.planTracker = f

    -- A driver that is always shown, so the minimap pin updates (about 5 times a second) even with the tracker off.
    local d = CreateFrame("Frame", nil, UIParent)
    d.elapsed = 0
    d:SetScript("OnUpdate", function(self, dt)
        self.elapsed = self.elapsed + (dt or 0)
        if self.elapsed < TICK then return end
        self.elapsed = 0
        tick()
    end)
    WC.planDriver = d

    -- The minimap pin: m sits on the true spot; the round badge hangs up and right of it, with a tiny gold tick on the spot.
    local m = CreateFrame("Frame", "WoWCompanionPlanMinimapPin", Minimap)
    m:SetSize(1, 1)
    if m.SetFrameLevel then m:SetFrameLevel(12) end -- above the rim button (level 8), so the badge is never hidden under it
    m.spot = m:CreateTexture(nil, "OVERLAY")
    m.spot:SetSize(3, 3)
    m.spot:SetPoint("CENTER", m, "CENTER", 0, 0)
    m.spot:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
    local b = CreateFrame("Frame", nil, m)
    b:SetSize(WC.Setting("minimapBadgeSize"), WC.Setting("minimapBadgeSize"))
    WC.BadgeParts(b, 2, 9, "GameFontNormalSmall", 3)
    b.glow:SetSize(WC.Setting("minimapBadgeSize") * 1.6, WC.Setting("minimapBadgeSize") * 1.6)
    b.glow:Hide()
    if b.CreateAnimationGroup then
        local ag = b.glow:CreateAnimationGroup()
        ag:SetLooping("BOUNCE")
        local a = ag:CreateAnimation("Alpha")
        a:SetFromAlpha(0.2)
        a:SetToAlpha(0.8)
        a:SetDuration(PULSE_SECONDS.minimap)
        b.pulse, b.pulseAnim = ag, a
    end
    m.badge = b
    -- Mouse-over for the tooltip; clicks still reach the minimap and the pins under the badge.
    b:EnableMouse(true)
    if b.SetPropagateMouseClicks then b:SetPropagateMouseClicks(true) end
    b:SetScript("OnEnter", function(self)
        local st = WC.PlanNext()
        if not st then return end
        WC.ShowPlanTip(self, "ANCHOR_LEFT", { steps = { st }, next = st }, { dist = m.tipDist, dir = m.tipDir })
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    m.arrow = {} -- the rim arrow: two line pieces, no texture art
    for k = 1, 2 do
        local ln = b:CreateLine()
        if ln.SetDrawLayer then ln:SetDrawLayer("OVERLAY", 2) end
        ln:SetThickness(2)
        ln:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
        ln:Hide()
        m.arrow[k] = ln
    end
    m:Hide()
    WC.planMinimap = m

    -- The world map exists from the start; redraw whenever it changes map, size or is opened.
    if WorldMapFrame then
        if hooksecurefunc and WorldMapFrame.OnMapChanged then hooksecurefunc(WorldMapFrame, "OnMapChanged", WC.RefreshMapPins)
        if hooksecurefunc and WorldMapFrame.OnMapChanged then hooksecurefunc(WorldMapFrame, "OnMapChanged", function() if C_Timer and C_Timer.After then C_Timer.After(0, WC.RefreshMapPins) end end) end end
        -- Other addons may raise their pins on a refresh, so draw again (and once more next frame) after it.
        local function again()
            WC.RefreshMapPins()
            if C_Timer and C_Timer.After then C_Timer.After(0, WC.RefreshMapPins) end
        end
        if hooksecurefunc and WorldMapFrame.RefreshAllData then hooksecurefunc(WorldMapFrame, "RefreshAllData", again) end
        if hooksecurefunc and WorldMapFrame.OnCanvasScaleChanged then hooksecurefunc(WorldMapFrame, "OnCanvasScaleChanged", WC.RefreshMapPins) end
        if WorldMapFrame.HookScript then
            WorldMapFrame:HookScript("OnShow", WC.RefreshMapPins)
            WorldMapFrame:HookScript("OnHide", WC.ClearTempPin)
        end
        local canvas = WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas()
        if canvas and canvas.HookScript then canvas:HookScript("OnSizeChanged", WC.RefreshMapPins) end
    end
end
