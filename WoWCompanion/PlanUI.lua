-- WoW Companion: draws the plan (see Plan.lua): numbered pins and faint route lines on the world
-- map, the next step on the minimap, and a small step tracker. Plain frames only, nothing secure;
-- every client API is checked before use so a missing one just drops that part of the display.

local WC = WoWCompanion
local L = WC.L

local GOLD = { 1, 0.82, 0 }
local KIND_MARK = { pickup = "!", objective = "x", turnin = "?", travel = ">" }
local PIN_SIZE, NEXT_SIZE = 16, 22
local TICK = 0.2 -- the tracker and minimap update about 5 times a second
-- Minimap radius in yards by zoom level (outdoors); only used to decide when the pin sits on the edge.
local MINIMAP_YARDS = { [0] = 233, 200, 166, 133, 100, 66 }
local MINIMAP_ARROW = "Interface\\Minimap\\ROTATING-MINIMAPARROW"

local EMPTY = ""
local pins, lines = {}, {}

local function mapShown()
    return WC.plan ~= nil and WC.db.settings.planMap
end

local function pinFor(i, canvas)
    local p = pins[i]
    if p then return p end
    p = CreateFrame("Button", nil, canvas)
    p:SetSize(PIN_SIZE, PIN_SIZE)
    p.border = p:CreateTexture(nil, "BACKGROUND")
    p.border:SetAllPoints()
    p.fill = p:CreateTexture(nil, "BORDER")
    p.fill:SetPoint("TOPLEFT", p, "TOPLEFT", 1, -1)
    p.fill:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -1, 1)
    p.num = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    p.num:SetPoint("CENTER", p, "CENTER", 0, 0)
    p.mark = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    p.mark:SetPoint("BOTTOMLEFT", p, "TOPRIGHT", -3, -3)
    p:SetScript("OnEnter", function(self)
        local s = self.planStep
        if not s then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(string.format(L.PLAN_PIN_LINE, s.n, s.quest ~= "" and s.quest or s.label), GOLD[1], GOLD[2], GOLD[3])
        if s.quest ~= "" then GameTooltip:AddLine(s.label, 1, 1, 1) end
        GameTooltip:Show()
    end)
    p:SetScript("OnLeave", function() GameTooltip:Hide() end)
    pins[i] = p
    return p
end

local function hideAll(list)
    for _, o in ipairs(list) do o:Hide() end
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
    local nextStep, shown, prev = WC.PlanNext(), 0, nil
    for _, s in ipairs(WC.plan.steps) do
        if s.map == mapID and not WC.plan.done[s.n] then
            shown = shown + 1
            local isNext = nextStep == s
            local p = pinFor(shown, canvas)
            p.planStep = s
            local size = isNext and NEXT_SIZE or PIN_SIZE
            p:SetSize(size, size)
            p:SetScale(scale)
            p:ClearAllPoints()
            p:SetPoint("CENTER", canvas, "TOPLEFT", s.x / 100 * w, -s.y / 100 * h)
            if isNext then p.border:SetColorTexture(1, 1, 1, 1) else p.border:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.9) end
            p.fill:SetColorTexture(0.08, 0.06, 0, 0.85)
            p.num:SetText(tostring(s.n))
            p.mark:SetText(KIND_MARK[s.kind] or "")
            p:Show()
            if prev and canvas.CreateLine then
                local ln = lines[shown - 1] or canvas:CreateLine()
                lines[shown - 1] = ln
                ln:SetThickness(1.5)
                ln:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.35)
                ln:SetStartPoint("CENTER", pins[shown - 1])
                ln:SetEndPoint("CENTER", p)
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

-- /wowc plan toggles the tracker, /wowc plan map the pins; each says what it did.
function WC.TogglePlan(map)
    local s = WC.db.settings
    if map then
        s.planMap = not s.planMap
        print(s.planMap and L.PLAN_MAP_ON or L.PLAN_MAP_OFF)
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
