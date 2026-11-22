-- WoW Companion: draws the plan (see Plan.lua): numbered pins and faint route lines on the world
-- map, the next step on the minimap, and a small step tracker. Plain frames only, nothing secure;
-- every client API is checked before use so a missing one just drops that part of the display.

local WC = WoWCompanion
local L = WC.L

local GOLD = { 1, 0.82, 0 }
local NOTCH = { pickup = "!", turnin = "?" } -- objective and travel steps show the number only
-- Badge diameter in map units by the pin size setting; "normal" matches the client's own quest markers (~28).
local PIN_SIZES = { small = 22, normal = 28, large = 36 }
local PIN_ORDER = { "small", "normal", "large" }
WC.PIN_SIZES, WC.PIN_ORDER = PIN_SIZES, PIN_ORDER
local NEXT_GROW = 1.3 -- the next step's badge is this much bigger
local MERGE_DISTANCE = 1.2 -- steps closer than this (0-100 map units) share one badge
-- Frame levels above the canvas: our lines, then our badges. Kept low and fixed so we sit over the
-- terrain and mob dots but stay below the map's own quest markers and their click areas.
local LINE_LEVEL, PIN_LEVEL = 5, 6
-- A plain round disc the client already ships (the minimap's backdrop); tinted and layered it makes the ring and fill.
local DISC = "Interface\\Minimap\\UI-Minimap-Background"
local TICK = 0.2 -- the tracker and minimap update about 5 times a second
-- Minimap radius in yards by zoom level (outdoors); only used to decide when the pin sits on the edge.
local MINIMAP_YARDS = { [0] = 233, 200, 166, 133, 100, 66 }
local MINIMAP_YARDS_INDOORS = { [0] = 150, 125, 100, 75, 50, 25 }
local MM_BADGE = 17 -- minimap badge diameter in pixels
local MM_RIM = 14 -- the badge centre stays this far inside the minimap edge so the arrow fits outside it
local MM_LIFT = { 8, 8 } -- pixels the badge sits up and right of the true spot, so the NPC icon stays visible
local MM_ARROW_GAP = 13 -- the edge arrow sits this far from the badge centre, toward the target
local ARRIVE_YARDS = 5 -- pick-ups and turn-ins pulse within this distance
local MINIMAP_ARROW = "Interface\\Minimap\\ROTATING-MINIMAPARROW"

-- Corner tags: a step that sits on one of the client's own quest markers is drawn as a small tag on that
-- marker's top-right corner instead of a full badge that would hide underneath it.
local COINCIDE_RADIUS = 2.5 -- map percent at 1x zoom; shrinks as the map zooms in (markers keep their pixel size)
local TAG_SCALE = 0.45 -- tag diameter relative to the full badge
local TAG_OFFSET = 16 -- pixels up and right of the marker centre, clear of its glyph
local TAG_LEVEL = 2500 -- above the client's marker frames, which stay below this on the canvas

local EMPTY = ""
local pins, lines = {}, {}

local function mapShown()
    return WC.plan ~= nil and WC.db.settings.planMap
end

-- Pure badge helpers. A group is { steps = {...}, isNext = bool }.
-- The text in a badge: "4", or "4·5" when steps share a spot (first and last of the group).
function WC.PinLabel(steps)
    local first, last = steps[1].n, steps[#steps].n
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
    p.fill:SetVertexColor(0.05, 0.04, 0.02, 0.95)
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
        a:SetDuration(1.2)
        p.pulse = ag
    end
    p:SetScript("OnEnter", function(self)
        local g = self.planGroup
        if not g then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        for _, s in ipairs(g.steps) do
            GameTooltip:AddLine(string.format(L.PLAN_PIN_LINE, tostring(s.n), s.label), GOLD[1], GOLD[2], GOLD[3])
            if s.quest ~= "" then GameTooltip:AddLine(s.quest, 1, 1, 1) end
            GameTooltip:AddLine(L["PLAN_KIND_" .. s.kind] or s.kind, 0.7, 0.7, 0.7)
        end
        GameTooltip:Show()
    end)
    p:SetScript("OnLeave", function() GameTooltip:Hide() end)
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
    return step.map == mapID and not (done and done[step.n])
end

-- Groups the wanted steps of a map into badges, in plan order; steps within MERGE_DISTANCE of an
-- earlier group's first step join it. group.next is the plan's next step when it is in the group.
function WC.PinGroups(steps, mapID, done, nextStep)
    local groups = {}
    for _, s in ipairs(steps) do
        if WC.PinWanted(s, mapID, done) then
            local home
            for _, g in ipairs(groups) do
                local f = g.steps[1]
                if math.abs(f.x - s.x) < MERGE_DISTANCE and math.abs(f.y - s.y) < MERGE_DISTANCE then home = g break end
            end
            if not home then
                home = { steps = {}, x = s.x, y = s.y }
                groups[#groups + 1] = home
            end
            home.steps[#home.steps + 1] = s
            if s == nextStep then home.next = s end
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
    local d = PIN_SIZES[setting] or PIN_SIZES.normal
    return isNext and math.floor(d * NEXT_GROW + 0.5) or d
end

-- Redraws the pins and lines for the map the world map is showing.
function WC.RefreshMapPins()
    hideAll(pins)
    hideAll(lines)
    if not mapShown() or not (WorldMapFrame and WorldMapFrame.GetCanvas and WorldMapFrame.GetMapID) then return end
    local canvas = WorldMapFrame:GetCanvas()
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    if not w or not h or w <= 0 then return end
    local mapID = WorldMapFrame:GetMapID()
    local scale = 1 / ((WorldMapFrame.GetCanvasScale and WorldMapFrame:GetCanvasScale()) or 1)
    local setting = WC.db.settings.planSize
    local groups = WC.PinGroups(WC.plan.steps, mapID, WC.plan.done, WC.PlanNext())
    local markers = #groups > 0 and WC.ClientMarkers(mapID) or {}
    local radius = WC.MarkerRadius(WorldMapFrame.GetCanvasScale and WorldMapFrame:GetCanvasScale())
    local base = (canvas.GetFrameLevel and canvas:GetFrameLevel() or 0)
    local where = {} -- step.n -> the pin showing it
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
            local d = math.floor(size * TAG_SCALE + 0.5)
            p:SetSize(math.max(d, 5 * #label), d)
            if p.SetFrameLevel then p:SetFrameLevel(base + TAG_LEVEL + (g.isNext and 1 or 0)) end
            p:SetPoint("CENTER", a, "CENTER", TAG_OFFSET, TAG_OFFSET)
            WC.SetBadgeInset(p, 1.5)
            if p.num.SetFontObject then p.num:SetFontObject("GameFontNormalSmall") end
            p.notchBg:Hide()
            p.mark:SetText("")
        else
            p:SetSize(size, size)
            if p.SetFrameLevel then p:SetFrameLevel(base + PIN_LEVEL + (g.isNext and 1 or 0)) end
            p:SetPoint("CENTER", a, "CENTER", 0, 0)
            WC.SetBadgeInset(p, 3)
            if p.num.SetFontObject then p.num:SetFontObject("GameFontNormal") end
        end
        p.isTag = marker ~= nil
        if g.isNext then p.ring:SetVertexColor(1, 0.95, 0.6, 1) else p.ring:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1) end
        p.glow:SetSize(size * (marker and TAG_SCALE or 1) * 1.7, size * (marker and TAG_SCALE or 1) * 1.7)
        p.glow:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.5)
        p.glow:SetShown(g.isNext)
        p.num:SetText(label)
        if not marker then
            local notch = WC.PinNotch(WC.PinGroupKind(g))
            p.mark:SetText(notch or "")
            p.notchBg:SetShown(notch ~= nil)
        end
        a:Show()
        p:Show()
        if g.isNext and p.pulse then p.pulse:Play() end
        for _, s in ipairs(g.steps) do where[s.n] = p.anchor end
    end
    if not WC.db.settings.planLines or not canvas.CreateLine then return end
    -- Lines join consecutive undone steps (plan order) that are both on this map, under the badges.
    local prev, n = nil, 0
    for _, s in ipairs(WC.plan.steps) do
        if not (WC.plan.done and WC.plan.done[s.n]) then
            if prev and prev.map == mapID and s.map == mapID and where[prev.n] ~= where[s.n] then
                n = n + 1
                local ln = lines[n] or canvas:CreateLine()
                lines[n] = ln
                if ln.SetDrawLayer then ln:SetDrawLayer("ARTWORK", 7) end
                ln:SetThickness(2.5)
                ln:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.6)
                ln:SetStartPoint("CENTER", where[prev.n])
                ln:SetEndPoint("CENTER", where[s.n])
                ln:Show()
            end
            prev = s
        end
    end
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

-- The edge arrow's offset from the badge centre and its texture rotation (the art points up).
function WC.MinimapArrow(angle)
    return math.sin(angle) * MM_ARROW_GAP, math.cos(angle) * MM_ARROW_GAP, -angle
end

-- The subtle pulse shows within ARRIVE_YARDS of a pick-up or turn-in; it never completes a step.
function WC.PinArrived(kind, dist)
    return (kind == "pickup" or kind == "turnin") and dist ~= nil and dist <= ARRIVE_YARDS
end

local function placeMinimap(m, mapID, px, py, step)
    if not (Minimap and mapID == step.map and px) then m:Hide() return end
    local w, h = WC.MapYards(mapID)
    local dist, _, bearing = WC.PlanDistance(px, py, step.x, step.y, w, h)
    local half = (Minimap:GetWidth() or 140) / 2
    local zoom = Minimap.GetZoom and Minimap:GetZoom() or 0
    local indoors = IsIndoors and IsIndoors()
    local radius = (indoors and MINIMAP_YARDS_INDOORS or MINIMAP_YARDS)[zoom] or (indoors and 100 or MINIMAP_YARDS[3])
    local facing
    if GetCVar and GetCVar("rotateMinimap") == "1" and GetPlayerFacing then facing = GetPlayerFacing() end
    local x, y, angle, edge = WC.MinimapPlace(dist, bearing, facing, radius, half)
    m:ClearAllPoints()
    m:SetPoint("CENTER", Minimap, "CENTER", x, y)
    local b = m.badge
    local ox, oy = WC.MinimapBadgeOffset(edge)
    b:ClearAllPoints()
    b:SetPoint("CENTER", m, "CENTER", ox, oy)
    m.spot:SetShown(not edge)
    m.arrow:SetShown(edge)
    if edge then
        local ax, ay, rot = WC.MinimapArrow(angle)
        m.arrow:ClearAllPoints()
        m.arrow:SetPoint("CENTER", b, "CENTER", ax, ay)
        if m.arrow.SetRotation then m.arrow:SetRotation(rot) end
    end
    b.num:SetText(tostring(step.n))
    local notch = WC.PinNotch(step.kind)
    b.mark:SetText(notch or "")
    b.notchBg:SetShown(notch ~= nil)
    local arrived = WC.PinArrived(step.kind, dist)
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
    if step and step.kind == "travel" and mapID == step.map and WC.plan.done then
        WC.plan.done[step.n] = true -- arriving completes a travel stop
        WC.RefreshPlan()
        return
    end
    if f and f:IsShown() then f.label:SetText(WC.PlanText(step, mapID, px, py)) end
    local m = WC.planMinimap
    if m then
        if step and mapShown() then placeMinimap(m, mapID, px, py, step) else m:Hide() end
    end
end

-- Redraws everything from the current plan and the settings.
function WC.RefreshPlan()
    local f = WC.planTracker
    if not f then return end
    local on = WC.plan ~= nil and WC.db.settings.planTracker
    if on then
        WC.StyleText(f.label)
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
    if WC.settingsFrame then WC.settingsFrame.sync() end
    WC.RefreshPlan()
end

function WC.CyclePlanSize()
    local cur = WC.db.settings.planSize
    for i, id in ipairs(PIN_ORDER) do
        if id == cur then return WC.SetPlanSize(PIN_ORDER[i % #PIN_ORDER + 1]) end
    end
    WC.SetPlanSize("normal")
end

-- /wowc plan toggles the tracker; "map" the pins, "lines" the route lines, "size [small|normal|large]" the pin size.
function WC.TogglePlan(what, arg)
    local s = WC.db.settings
    if what == "map" then
        s.planMap = not s.planMap
        print(s.planMap and L.PLAN_MAP_ON or L.PLAN_MAP_OFF)
    elseif what == "lines" then
        s.planLines = not s.planLines
        print(s.planLines and L.PLAN_LINES_ON or L.PLAN_LINES_OFF)
    elseif what == "size" then
        if PIN_SIZES[arg] then return WC.SetPlanSize(arg) end
        return WC.CyclePlanSize()
    else
        s.planTracker = not s.planTracker
        print(s.planTracker and L.PLAN_TRACKER_ON or L.PLAN_TRACKER_OFF)
    end
    if WC.settingsFrame then WC.settingsFrame.sync() end
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
    f.bg:SetColorTexture(0, 0, 0, 0.5)
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
    m.spot = m:CreateTexture(nil, "OVERLAY")
    m.spot:SetSize(3, 3)
    m.spot:SetPoint("CENTER", m, "CENTER", 0, 0)
    m.spot:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
    local b = CreateFrame("Frame", nil, m)
    b:SetSize(MM_BADGE, MM_BADGE)
    WC.BadgeParts(b, 2, 9, "GameFontNormalSmall", 3)
    b.ring:SetVertexColor(1, 0.95, 0.6, 1)
    b.glow:SetSize(MM_BADGE * 1.6, MM_BADGE * 1.6)
    b.glow:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.6)
    b.glow:Hide()
    if b.CreateAnimationGroup then
        local ag = b.glow:CreateAnimationGroup()
        ag:SetLooping("BOUNCE")
        local a = ag:CreateAnimation("Alpha")
        a:SetFromAlpha(0.2)
        a:SetToAlpha(0.8)
        a:SetDuration(0.8)
        b.pulse = ag
    end
    m.badge = b
    m.arrow = b:CreateTexture(nil, "OVERLAY")
    m.arrow:SetSize(10, 10)
    m.arrow:SetTexture(MINIMAP_ARROW)
    m.arrow:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
    m:Hide()
    WC.planMinimap = m

    -- The world map exists from the start; redraw whenever it changes map, size or is opened.
    if WorldMapFrame then
        if hooksecurefunc and WorldMapFrame.OnMapChanged then hooksecurefunc(WorldMapFrame, "OnMapChanged", WC.RefreshMapPins) end
        if hooksecurefunc and WorldMapFrame.OnCanvasScaleChanged then hooksecurefunc(WorldMapFrame, "OnCanvasScaleChanged", WC.RefreshMapPins) end
        if WorldMapFrame.HookScript then WorldMapFrame:HookScript("OnShow", WC.RefreshMapPins) end
        local canvas = WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas()
        if canvas and canvas.HookScript then canvas:HookScript("OnSizeChanged", WC.RefreshMapPins) end
    end
end
