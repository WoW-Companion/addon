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
local MINIMAP_ARROW = "Interface\\Minimap\\ROTATING-MINIMAPARROW"

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

local function pinFor(i, canvas)
    local p = pins[i]
    if p then return p end
    p = CreateFrame("Button", nil, canvas)
    p.glow = p:CreateTexture(nil, "BACKGROUND")
    p.glow:SetTexture(DISC)
    p.glow:SetPoint("CENTER", p, "CENTER", 0, 0)
    p.ring = p:CreateTexture(nil, "BORDER")
    p.ring:SetTexture(DISC)
    p.ring:SetAllPoints()
    p.fill = p:CreateTexture(nil, "ARTWORK")
    p.fill:SetTexture(DISC)
    p.fill:SetPoint("TOPLEFT", p, "TOPLEFT", 3, -3)
    p.fill:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -3, 3)
    p.fill:SetVertexColor(0.05, 0.04, 0.02, 0.95)
    p.num = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    p.num:SetPoint("CENTER", p, "CENTER", 0, 0)
    p.notchBg = p:CreateTexture(nil, "OVERLAY")
    p.notchBg:SetTexture(DISC)
    p.notchBg:SetSize(12, 12)
    p.notchBg:SetPoint("CENTER", p, "TOPRIGHT", -4, -4)
    p.notchBg:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
    p.mark = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    p.mark:SetPoint("CENTER", p.notchBg, "CENTER", 0, 0)
    p.mark:SetTextColor(0.05, 0.04, 0.02)
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
    local base = (canvas.GetFrameLevel and canvas:GetFrameLevel() or 0)
    local where = {} -- step.n -> the pin showing it
    for i, g in ipairs(groups) do
        local p = pinFor(i, canvas)
        p.planGroup = g
        local size = WC.PinSize(setting, g.isNext)
        p:SetSize(size, size)
        p:SetScale(scale)
        if p.SetFrameLevel then p:SetFrameLevel(base + PIN_LEVEL + (g.isNext and 1 or 0)) end
        p:ClearAllPoints()
        local ox, oy = WC.PinOffset(g.x, g.y, w, h, scale)
        p:SetPoint("CENTER", canvas, "TOPLEFT", ox, oy)
        if g.isNext then p.ring:SetVertexColor(1, 0.95, 0.6, 1) else p.ring:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1) end
        p.glow:SetSize(size * 1.7, size * 1.7)
        p.glow:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.5)
        p.glow:SetShown(g.isNext)
        p.num:SetText(WC.PinLabel(g.steps))
        local notch = WC.PinNotch(WC.PinGroupKind(g))
        p.mark:SetText(notch or "")
        p.notchBg:SetShown(notch ~= nil)
        p:Show()
        if g.isNext and p.pulse then p.pulse:Play() end
        for _, s in ipairs(g.steps) do where[s.n] = p end
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

local function placeMinimap(m, mapID, px, py, step)
    if not (Minimap and mapID == step.map and px) then m:Hide() return end
    local w, h = WC.MapYards(mapID)
    local dist, _, bearing = WC.PlanDistance(px, py, step.x, step.y, w, h)
    local half = (Minimap:GetWidth() or 140) / 2
    local zoom = Minimap.GetZoom and Minimap:GetZoom() or 0
    local radius = MINIMAP_YARDS[zoom] or MINIMAP_YARDS[3]
    local angle = math.rad(bearing)
    if GetCVar and GetCVar("rotateMinimap") == "1" and GetPlayerFacing and GetPlayerFacing() then
        angle = angle + GetPlayerFacing() -- the map turns with the player
    end
    local reach = math.min(dist / radius, 1) * (half - 6)
    m:ClearAllPoints()
    m:SetPoint("CENTER", Minimap, "CENTER", math.sin(angle) * reach, math.cos(angle) * reach)
    local edge = dist > radius
    m.dot:SetShown(not edge)
    m.arrow:SetShown(edge)
    if edge and m.arrow.SetRotation then m.arrow:SetRotation(-angle) end -- the arrow art points up
    m.num:SetText(edge and EMPTY or tostring(step.n))
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
    f.elapsed = 0
    f:SetScript("OnUpdate", function(self, dt)
        self.elapsed = self.elapsed + (dt or 0)
        if self.elapsed < TICK then return end
        self.elapsed = 0
        tick()
    end)
    f:Hide()
    WC.planTracker = f

    local m = CreateFrame("Frame", "WoWCompanionPlanMinimapPin", Minimap)
    m:SetSize(14, 14)
    m.dot = m:CreateTexture(nil, "BACKGROUND")
    m.dot:SetAllPoints()
    m.dot:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.9)
    m.arrow = m:CreateTexture(nil, "ARTWORK")
    m.arrow:SetAllPoints()
    m.arrow:SetTexture(MINIMAP_ARROW)
    m.num = m:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    m.num:SetPoint("CENTER", m, "CENTER", 0, 0)
    m:Hide()
    WC.planMinimap = m

    -- The world map exists from the start; redraw whenever it changes map, size or is opened.
    if WorldMapFrame then
        if hooksecurefunc and WorldMapFrame.OnMapChanged then hooksecurefunc(WorldMapFrame, "OnMapChanged", WC.RefreshMapPins) end
        if WorldMapFrame.HookScript then WorldMapFrame:HookScript("OnShow", WC.RefreshMapPins) end
        local canvas = WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas()
        if canvas and canvas.HookScript then canvas:HookScript("OnSizeChanged", WC.RefreshMapPins) end
    end
end
