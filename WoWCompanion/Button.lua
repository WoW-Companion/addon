-- WoW Companion: a button that toggles the panel. A plain-frame button sits on the minimap rim (draggable,
-- lockable) and the addon compartment entry is kept as well when the client has one; each has its own setting.

local WC = WoWCompanion

-- A rolled map: reads clearly at 20 px and fits a route-planning addon. The TOCs use the same icon.
WC.ICON = "Interface\\Icons\\INV_Misc_Map_01"

-- The ring other minimap buttons sit on: the minimap's half-width plus a few pixels, so the button's centre rides
-- the minimap's outer edge. Square corners use the client's own shape convention (GetMinimapShape), clamped to
-- the square's edge the way other buttons do it.
WC.MINIMAP_RING_GAP = 5
WC.MINIMAP_DEFAULT_WIDTH = 140
local CORNER_ROUNDING = 10
-- Per shape, which quadrants are round: { bottom-right, bottom-left, top-right, top-left }.
WC.MINIMAP_SHAPES = {
    ROUND = { true, true, true, true }, SQUARE = { false, false, false, false },
    ["CORNER-TOPLEFT"] = { false, false, false, true }, ["CORNER-TOPRIGHT"] = { false, false, true, false },
    ["CORNER-BOTTOMLEFT"] = { false, true, false, false }, ["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
    ["SIDE-LEFT"] = { false, true, false, true }, ["SIDE-RIGHT"] = { true, false, true, false },
    ["SIDE-TOP"] = { false, false, true, true }, ["SIDE-BOTTOM"] = { true, true, false, false },
    ["TRICORNER-TOPLEFT"] = { false, true, true, true }, ["TRICORNER-TOPRIGHT"] = { true, false, true, true },
    ["TRICORNER-BOTTOMLEFT"] = { true, true, false, true }, ["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
}

function WC.MinimapRingRadius(width)
    return (tonumber(width) and width > 0 and width or WC.MINIMAP_DEFAULT_WIDTH) / 2 + WC.MINIMAP_RING_GAP
end

-- The button's offset from the minimap centre for an angle in degrees, the minimap's width and its shape name.
function WC.MinimapOffset(angle, width, shape)
    local a = math.rad(angle)
    local c, s = math.cos(a), math.sin(a)
    local r = WC.MinimapRingRadius(width)
    local quads = WC.MINIMAP_SHAPES[shape or "ROUND"] or WC.MINIMAP_SHAPES.ROUND
    local q = 1
    if c < 0 then q = q + 1 end
    if s > 0 then q = q + 2 end
    if quads[q] then return c * r, s * r end
    local diag = math.sqrt(2 * r * r) - CORNER_ROUNDING
    return math.max(-r, math.min(c * diag, r)), math.max(-r, math.min(s * diag, r))
end

-- Angle in degrees from the minimap centre (mx, my) to the cursor (cx, cy), given the minimap's scale.
function WC.MinimapAngle(cx, cy, mx, my, scale)
    local atan2 = math.atan2 or math.atan
    return math.deg(atan2(cy / scale - my, cx / scale - mx))
end

-- The tooltip's lines from plain values: info = { digest, db, player, now }.
function WC.TooltipLines(info)
    local L = WC.L
    local out = { L.ADDON_NAME }
    local d = WC.EntryFor(info.digest, info.player)
    local gen = type(d) == "table" and tonumber(d.generated)
    out[#out + 1] = gen and string.format(L.TIP_DIGEST, WC.FormatClock(gen), WC.FormatAge(math.max(0, info.now - gen))) or L.TIP_DIGEST_NONE
    if type(d) == "table" and gen and WC.DigestOutdated(d, info.now, info.captured) then out[#out + 1] = L.TIP_OUT_OF_DATE end
    out[#out + 1] = string.format(L.TIP_QUEUED, WC.Unanswered(info.db))
    out[#out + 1] = L.TIP_CLICK
    out[#out + 1] = L.TIP_CLICK_RIGHT
    out[#out + 1] = L.TIP_CLICK_SHIFT
    if info.minimap then out[#out + 1] = L.TIP_CLICK_DRAG end
    return out
end

-- Display only: fills the game tooltip next to the button.
local function show_tooltip(owner)
    local lines = WC.TooltipLines({ digest = WoWCompanionDigest, db = WC.db or {}, player = UnitName("player"), now = time(),
        captured = WC.OwnCapturedAt(UnitName("player")), minimap = owner == WC.minimapButton })
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    for _, line in ipairs(lines) do GameTooltip:AddLine(line) end
    GameTooltip:Show()
end

local function hide_tooltip() GameTooltip:Hide() end

-- A click on the minimap button or the compartment entry: right opens the options window, shift-left shows or
-- hides the plan on the map, any other click toggles the panel.
function WC.ButtonClick(button, shift)
    if button == "RightButton" then
        WC.OpenOptions()
    elseif shift then
        WC.TogglePlan("map")
    else
        WC.TogglePanel()
    end
end

-- Is the plan shown on the map right now? (The eye in the side panel and shift-click on the tab flip it.)
function WC.PlanShownOnMap()
    return WC.db and WC.db.settings and WC.db.settings.planMap and true or false
end

-- Sets the tab's pressed (checked) look: selected while its panel is up (a tab), or plan-on-map (the plain edge
-- button, which has no panel). The client's tab method when it has one, else a texture.
function WC.RefreshMapTab()
    local b = WC.mapButton
    if not b then return end
    local on
    if WC.mapButtonMode == "tab" then on = WC.panelState.selected == true else on = WC.PlanShownOnMap() end
    if b.SetChecked then b:SetChecked(on) end
    if b.checkedTex then b.checkedTex:SetShown(on) end
end

-- A click on the world map tab: left selects (or deselects) the plan in the side panel, shift-left shows or hides
-- the plan on the map, right opens the options window. The plain edge button has no panel: left flips the plan.
function WC.MapButtonClick(button, shift)
    if button == "RightButton" then
        WC.OpenOptions()
    elseif shift or WC.mapButtonMode ~= "tab" then
        WC.TogglePlan("map")
        if WC.UpdateMapPanelHeader then WC.UpdateMapPanelHeader() end
    else
        WC.ToggleMapPanel()
    end
    WC.RefreshMapTab()
end

local function shift_down() return IsShiftKeyDown and IsShiftKeyDown() or false end

local function show_map_tooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    for _, line in ipairs({ WC.L.ADDON_NAME, WC.L.TIP_MAP_LEFT, WC.L.TIP_MAP_SHIFT, WC.L.TIP_MAP_RIGHT }) do GameTooltip:AddLine(line) end
    if WC.MapTabAlone() then GameTooltip:AddLine(WC.L.TIP_MAP_DRAG) end
    GameTooltip:Show()
end

-- The client's own large side-tab template (the one its Quests / Map legend tabs use) and the frame that
-- parents that tab column.
WC.MAP_TAB_TEMPLATE = "QuestLogTabButtonTemplate"
WC.MAP_TAB_SIZE, WC.MAP_TAB_GAP = 44, 3
WC.MAP_TAB_DEFAULT_X, WC.MAP_TAB_DEFAULT_Y = -2, -100

-- The client's own side tabs (each a field of the quest-map frame), in the order they stack.
WC.CLIENT_TAB_FIELDS = { "QuestsTab", "EventsTab", "MapLegendTab" }

-- Pure: the lowest shown tab of a list of { frame =, bottom = } candidates (screen units, y up), or nil.
function WC.LowestTab(cands)
    local low
    for _, c in ipairs(cands) do
        if not low or c.bottom < low.bottom then low = c end
    end
    return low and low.frame or nil
end

-- The lowest shown tab among the client's own (named by WC.CLIENT_TAB_FIELDS). Never another addon's frame.
function WC.FindClientTab(parent)
    local cands = {}
    for _, name in ipairs(WC.CLIENT_TAB_FIELDS) do
        local t = parent[name]
        if type(t) == "table" and t ~= WC.mapButton and t.IsShown and t:IsShown() and t.GetBottom then
            local bt = t:GetBottom()
            if bt then cands[#cands + 1] = { frame = t, bottom = bt } end
        end
    end
    if #cands == 0 and parent.GetChildren then
        -- the client moved or renamed its tab fields: take its own shown check buttons of tab size, never ours or
        -- another addon's (those carry a name of their own)
        for _, t in ipairs({ parent:GetChildren() }) do
            local nm = type(t) == "table" and t.GetName and t:GetName() or nil
            local w, h = t.GetWidth and t:GetWidth() or 0, t.GetHeight and t:GetHeight() or 0
            if t ~= WC.mapButton and t ~= WC.mapPanel and t.GetObjectType and t:GetObjectType() == "CheckButton" and (nm == nil or not nm:find("^WoWCompanion"))
                and t.IsShown and t:IsShown() and t.GetBottom and t:GetBottom() and w > 0 and w <= 80 and h > 0 and h <= 80 then
                cands[#cands + 1] = { frame = t, bottom = t:GetBottom() }
            end
        end
    end
    return WC.LowestTab(cands)
end

-- The tab's art regions (the template's own textures): the ones that must stay inside its frame.
WC.MAP_TAB_ART_FIELDS = { "Background", "Border", "SelectedTexture", "Icon" }
WC.MAP_TAB_ICON_FRACTION = 0.6

function WC.MapTabArt(b)
    local out = {}
    for _, name in ipairs(WC.MAP_TAB_ART_FIELDS) do
        if type(b[name]) == "table" then out[#out + 1] = { field = name, region = b[name] } end
    end
    if b.icon and b.icon ~= b.Icon then out[#out + 1] = { field = "icon", region = b.icon } end
    if b.GetHighlightTexture then
        local h = b:GetHighlightTexture()
        if type(h) == "table" then out[#out + 1] = { field = "Highlight", region = h } end
    end
    return out
end

-- Keeps every texture of the tab inside its frame: the frame-sized art fills the frame exactly, the icon is a
-- fraction of it, centred. Only the client's own textures; nothing is drawn outside the bounds.
function WC.FitMapTabArt(b)
    local w, h = b:GetSize()
    for _, a in ipairs(WC.MapTabArt(b)) do
        local r = a.region
        r:ClearAllPoints()
        if a.field == "Icon" or a.field == "icon" then
            r:SetSize(math.floor(w * WC.MAP_TAB_ICON_FRACTION), math.floor(h * WC.MAP_TAB_ICON_FRACTION))
            r:SetPoint("CENTER", b, "CENTER", 0, 0)
        else
            r:SetAllPoints(b)
        end
    end
end

-- Pure: the tab's vertical offset (negative, down from the frame's top) for a saved value (0 = none), the frame's
-- height and the tab's height. The default is the middle of the frame's lower half; the result stays inside the frame.
function WC.MapTabOffset(saved, frameH, tabH)
    if not (type(frameH) == "number" and frameH > 0) then return WC.MAP_TAB_DEFAULT_Y end
    local y = tonumber(saved)
    if not y or y == 0 then y = -frameH * 0.75 end
    return math.min(0, math.max(-(frameH - (tabH or 0)), y))
end

-- True when none of the client's own tabs is shown, so our tab stands alone on the frame's left edge.
function WC.MapTabAlone()
    return WC.mapButtonMode == "tab" and WC.mapButtonParent ~= nil and WC.FindClientTab(WC.mapButtonParent) == nil
end

-- Anchors the tab directly below the lowest client tab, at that tab's size, so a map addon that moves the client's
-- tabs carries ours along. With every client tab hidden it sits on the frame's left edge at the saved (or default)
-- height, at 44 x 44. Re-run on map show and mode change.
function WC.PlaceMapTab()
    local b, parent = WC.mapButton, WC.mapButtonParent
    if not b or WC.mapButtonMode ~= "tab" or not parent then return end
    local low = WC.FindClientTab(parent)
    b:ClearAllPoints()
    if low then
        local w, h = low.GetWidth and low:GetWidth() or 0, low.GetHeight and low:GetHeight() or 0
        if w > 0 and h > 0 then b:SetSize(w, h) end
        b:SetPoint("TOP", low, "BOTTOM", 0, -WC.MAP_TAB_GAP) -- centred under it, so the two share one column
    else
        b:SetSize(WC.MAP_TAB_SIZE, WC.MAP_TAB_SIZE)
        local fh = parent.GetHeight and parent:GetHeight() or 0
        local y = WC.MapTabOffset(WC.Setting("mapTabY"), fh, WC.MAP_TAB_SIZE)
        b:SetPoint("TOPRIGHT", parent, "TOPLEFT", WC.MAP_TAB_DEFAULT_X, y)
    end
    WC.FitMapTabArt(b)
    if WC.PlaceMapPanel then WC.PlaceMapPanel() end
    if WC.HookClientTabs then WC.HookClientTabs() end
end

-- Moves the lone tab so its middle sits at the cursor's height (screen y, as GetCursorPosition gives it); the
-- offset is clamped to the frame and saved. Returns the saved offset, or nil when the tab is not alone.
function WC.SetMapTabFromCursor(cursorY)
    local parent = WC.mapButtonParent
    if not (WC.MapTabAlone() and parent and parent.GetTop and tonumber(cursorY)) then return nil end
    local top = parent:GetTop()
    local scale = parent.GetEffectiveScale and parent:GetEffectiveScale() or 1
    if not tonumber(top) or not scale or scale <= 0 then return nil end
    local fh = parent.GetHeight and parent:GetHeight() or 0
    local y = cursorY / scale - top + WC.MAP_TAB_SIZE / 2 -- the tab's top edge
    y = math.floor(WC.MapTabOffset(y == 0 and -0.01 or y, fh, WC.MAP_TAB_SIZE) + 0.5)
    if y == 0 then y = -1 end -- 0 means "default", so a tab flush with the top saves as 1 below it
    WC.SetSetting("mapTabY", y)
    WC.PlaceMapTab()
    return y
end

function WC.ResetMapTabPosition()
    WC.SetSetting("mapTabY", WC.DEF_OF["mapTabY"].default)
    if WC.PlaceMapTab then WC.PlaceMapTab() end
end

-- One square side tab in the world map's tab column, built from the client's own side-tab template. A client without
-- the template or the column keeps the plain button on the map frame's own edge.
function WC.CreateMapButton()
    local map = WorldMapFrame
    if not map or WC.mapButton then return end
    local b
    local column = QuestMapFrame
    if column and type(CreateFrame) == "function" then
        local ok, frame = pcall(CreateFrame, "CheckButton", "WoWCompanionMapTab", column, WC.MAP_TAB_TEMPLATE) -- the client's own tabs are check buttons
        if ok and type(frame) == "table" then b, WC.mapButtonMode, WC.mapButtonParent = frame, "tab", column end
    end
    if not b then
        local ok, frame = pcall(CreateFrame, "Button", "WoWCompanionMapButton", map)
        if not ok then return end
        b = frame
        b:SetPoint("TOPRIGHT", map, "TOPRIGHT", -8, -110)
        b:SetSize(31, 31)
        WC.mapButtonMode = "edge"
        b.back = b:CreateTexture(nil, "BACKGROUND")
        b.back:SetSize(20, 20)
        b.back:SetPoint("TOPLEFT", b, "TOPLEFT", 7, -5)
        b.back:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
        b.border = b:CreateTexture(nil, "OVERLAY")
        b.border:SetSize(53, 53)
        b.border:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
        b.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
        b.checkedTex = b:CreateTexture(nil, "OVERLAY")
        b.checkedTex:SetAllPoints()
        b.checkedTex:SetColorTexture(1, 1, 1, 0.25)
    else
        b:SetSize(WC.MAP_TAB_SIZE, WC.MAP_TAB_SIZE)
    end
    if b.SetFrameStrata then b:SetFrameStrata("HIGH") end
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    -- the template's own icon region when it has one, else ours
    local own = b.Icon
    b.icon = own or b:CreateTexture(nil, "ARTWORK")
    if not own then -- the template's icon keeps its own size and place, so the frame matches its siblings
        if b.icon.SetSize then b.icon:SetSize(26, 26) end
        b.icon:SetPoint("CENTER", b, "CENTER", 0, 0)
    end
    b.icon:SetTexture(WC.ICON)
    if WC.mapButtonMode == "edge" and b.SetHighlightTexture then b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square") end
    b:SetScript("OnClick", function(_, button) WC.MapButtonClick(button, shift_down()) end)
    if WC.mapButtonMode == "tab" then
        b:RegisterForDrag("LeftButton")
        b:SetScript("OnDragStart", function(self)
            if not (shift_down() and WC.MapTabAlone()) then return end
            self:SetScript("OnUpdate", function()
                local _, cy = GetCursorPosition()
                WC.SetMapTabFromCursor(cy)
            end)
        end)
        b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    end
    b:SetScript("OnEnter", show_map_tooltip)
    b:SetScript("OnLeave", hide_tooltip)
    WC.mapButton = b
    if WC.mapButtonMode == "tab" then
        if column.HookScript then column:HookScript("OnShow", function() WC.PlaceMapTab(); WC.RefreshMapTab() end) end
        if column.HookScript then column:HookScript("OnSizeChanged", WC.PlaceMapTab) end
        if map.HookScript then map:HookScript("OnShow", function()
            WC.PlaceMapTab(); WC.ApplyMapTabState(); WC.RefreshMapTab(); WC.RecordMapGeometry()
            if C_Timer and C_Timer.After then -- again once the client has laid the map out
                C_Timer.After(0.5, function() WC.PlaceMapTab(); WC.RecordMapGeometry() end)
            end
        end) end
        if map.HookScript then map:HookScript("OnSizeChanged", WC.PlaceMapTab) end
        if map.HookScript then map:HookScript("OnHide", function() WC.ClearSelectedStep() end) end -- the selection ends with the map
        WC.PlaceMapTab()
        if C_Timer and C_Timer.After then C_Timer.After(0, WC.PlaceMapTab) end -- once the client has laid its tabs out
        WC.InitMapPanel()
    end
    WC.RefreshMapTab()
end

function WC.PlaceMinimapButton()
    local b = WC.minimapButton
    if not b then return end
    local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
    local x, y = WC.MinimapOffset(WC.db.settings.minimap.angle, Minimap:GetWidth(), shape)
    b:ClearAllPoints()
    b:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function create_minimap_button()
    local b = CreateFrame("Button", "WoWCompanionMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameLevel(8) -- below the plan's minimap badge (12), so the badge is never hidden under it
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b.back = b:CreateTexture(nil, "BACKGROUND")
    b.back:SetSize(20, 20)
    b.back:SetPoint("TOPLEFT", b, "TOPLEFT", 7, -5)
    b.back:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(17, 17)
    b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", 8, -6)
    b.icon:SetTexture(WC.ICON)
    b.border = b:CreateTexture(nil, "OVERLAY")
    b.border:SetSize(53, 53)
    b.border:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    b.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    b:SetScript("OnClick", function(_, button) WC.ButtonClick(button, shift_down()) end)
    b:SetScript("OnEnter", show_tooltip)
    b:SetScript("OnLeave", hide_tooltip)
    b:SetScript("OnDragStart", function(self)
        if WC.db.settings.minimap.locked then return end
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            WC.db.settings.minimap.angle = WC.MinimapAngle(cx, cy, mx, my, Minimap:GetEffectiveScale())
            WC.PlaceMinimapButton()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    -- Another addon may resize the minimap; the ring follows.
    if Minimap.HookScript then Minimap:HookScript("OnSizeChanged", WC.PlaceMinimapButton) end
    WC.minimapButton = b
    WC.PlaceMinimapButton()
end

-- The compartment entry's description; kept so it can be removed and added again from the options.
local function compartment_info()
    return {
        text = WC.L.ADDON_NAME,
        icon = WC.ICON,
        notCheckable = true,
        func = function(_, data) WC.ButtonClick(type(data) == "table" and data.buttonName or nil, shift_down()) end,
        funcOnEnter = show_tooltip,
        funcOnLeave = hide_tooltip,
    }
end

-- Shows or hides each button to match its setting. The compartment entry is registered or removed; a client that
-- cannot remove an entry keeps it until the next /reload.
function WC.ApplyButtons()
    local s = WC.db.settings.minimap
    local b = WC.minimapButton
    if b then b:SetShown(s.show ~= false) end
    if WC.mapButton then WC.mapButton:SetShown(WC.Setting("mapButton") ~= false) end
    local comp = AddonCompartmentFrame
    if comp and comp.RegisterAddon then
        if s.compartment ~= false and not WC.compartmentInfo then
            WC.compartmentInfo = compartment_info()
            comp:RegisterAddon(WC.compartmentInfo)
        elseif s.compartment == false and WC.compartmentInfo then
            if comp.UnregisterAddon then comp:UnregisterAddon(WC.compartmentInfo) end
            WC.compartmentInfo = nil
        end
    end
end

function WC.CreateButton()
    if Minimap then create_minimap_button() end
    WC.CreateMapButton()
    WC.buttonMode = (AddonCompartmentFrame and AddonCompartmentFrame.RegisterAddon) and "compartment" or "minimap"
    WC.ApplyButtons()
end
