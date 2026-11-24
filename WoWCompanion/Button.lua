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

-- Sets the round button's pressed look: on while the plan is up in the side panel (or, with no side panel in this
-- client, while the plan shows on the map).
function WC.RefreshMapTab()
    local r = WC.mapRound
    if not r then return end
    local on
    if QuestMapFrame then on = WC.panelState.selected == true else on = WC.PlanShownOnMap() end
    if r.checkedTex then r.checkedTex:SetShown(on and true or false) end
end

-- A click on the round map button: left shows or hides the plan in the side panel (the client's quest-pane frame),
-- shift-left shows or hides the plan on the map, right opens the options window. A client without the quest-pane
-- frame has no side panel: left flips the plan on the map.
function WC.MapButtonClick(button, shift)
    if button == "RightButton" then
        WC.OpenOptions()
    elseif shift or not QuestMapFrame then
        WC.TogglePlan("map")
        if WC.UpdateMapPanelHeader then WC.UpdateMapPanelHeader() end
    else
        WC.ToggleMapPanel()
    end
    WC.RefreshMapTab()
end

local function shift_down() return IsShiftKeyDown and IsShiftKeyDown() or false end

-- A frame's geometry number, or nil when the client has not laid it out (a getter that returns nothing is "unknown",
-- never 0, and never an argument-less tonumber call).
function WC.GeoNum(f, method)
    if type(f) ~= "table" or type(f[method]) ~= "function" then return nil end
    local ok, v = pcall(f[method], f)
    if not ok then return nil end
    return tonumber(v)
end

-- ---------------------------------------------------------------- round map button (the client's own map)
-- The map control is always this round button, in the column of round buttons at the
-- map's top-left edge, below every one already there. Those are read as rectangles only (about 32 x 32, near the
-- container's top-left corner); no name, global or library of theirs is used, and no frame of theirs is touched.

WC.ROUND_SIZE, WC.ROUND_X, WC.ROUND_Y0, WC.ROUND_PITCH = 32, 3, 3, 32
WC.ROUND_NEAR = 40 -- a round button counts as in the column when its left edge is within this of the corner

-- The frame the round buttons are stacked on: the map's canvas container (or the map itself).
function WC.RoundParent()
    local map = WorldMapFrame
    if not map then return nil end
    if type(map.GetCanvasContainer) == "function" then
        local ok, c = pcall(map.GetCanvasContainer, map)
        if ok and type(c) == "table" then return c end
    end
    return (type(map.ScrollContainer) == "table" and map.ScrollContainer) or map
end

-- Pure: the first free slot below the occupied ones. rects: { x, y, w, h } measured from the container's top-left corner,
-- y going down. Returns x, y (down from the corner), and the slot number (1 = the top).
function WC.RoundSlot(rects)
    local y = WC.ROUND_Y0
    for _, r in ipairs(rects) do
        local bottom = r.y + r.h
        if bottom > y then y = bottom end
    end
    local slot = math.floor((y - WC.ROUND_Y0) / WC.ROUND_PITCH + 0.5) + 1
    return WC.ROUND_X, y, slot
end

-- The shown round-button-sized frames in the corner column of the container and of the map, as rectangles.
function WC.ScanRoundColumn()
    local parent = WC.RoundParent()
    if not parent then return {} end
    local cl, ct = WC.GeoNum(parent, "GetLeft"), WC.GeoNum(parent, "GetTop")
    if not (cl and ct) then return {} end
    local rects, seen = {}, {}
    for _, owner in ipairs({ parent, WorldMapFrame }) do
        if type(owner) == "table" and owner.GetChildren and not seen[owner] then
            seen[owner] = true
            for _, c in ipairs({ owner:GetChildren() }) do
                if type(c) == "table" and c ~= WC.mapRound and c ~= WC.mapPanel and not seen[c]
                    and c.IsShown and c:IsShown() then
                    seen[c] = true
                    local l, t, w, h = WC.GeoNum(c, "GetLeft"), WC.GeoNum(c, "GetTop"), WC.GeoNum(c, "GetWidth"), WC.GeoNum(c, "GetHeight")
                    if l and t and w and h and math.abs(w - WC.ROUND_SIZE) <= 4 and math.abs(h - WC.ROUND_SIZE) <= 4
                        and l - cl >= -2 and l - cl <= WC.ROUND_NEAR and ct - t >= -2 then
                        rects[#rects + 1] = { x = l - cl, y = ct - t, w = w, h = h }
                    end
                end
            end
        end
    end
    -- the client's own pin button leads the column: found by its mixin's load function, wherever it hangs
    local pinMixin = type(WorldMapTrackingPinButtonMixin) == "table" and WorldMapTrackingPinButtonMixin.OnLoad or nil
    if pinMixin and type(WorldMapFrame) == "table" and type(WorldMapFrame.overlayFrames) == "table" then
        for _, f in ipairs(WorldMapFrame.overlayFrames) do
            if type(f) == "table" and f.OnLoad == pinMixin and not seen[f] and f ~= WC.mapRound and f.IsShown and f:IsShown() then
                seen[f] = true
                local l, t, w, h = WC.GeoNum(f, "GetLeft"), WC.GeoNum(f, "GetTop"), WC.GeoNum(f, "GetWidth"), WC.GeoNum(f, "GetHeight")
                if l and t and w and h then rects[#rects + 1] = { x = l - cl, y = ct - t, w = w, h = h } end
            end
        end
    end
    return rects
end

local function round_sig(rects)
    local parts = {}
    for _, r in ipairs(rects) do parts[#parts + 1] = string.format("%d,%d", r.x + 0.5, r.y + 0.5) end
    table.sort(parts)
    return table.concat(parts, ";")
end

-- Pure: the vertical offset (down, in pixels; may be negative to move up) saved by a drag, kept inside the container.
function WC.RoundOffset(saved, baseY, containerH)
    local off = tonumber(saved) or 0
    local h = tonumber(containerH)
    if not h or h <= 0 then return off end
    return math.min(h - WC.ROUND_SIZE - baseY, math.max(-baseY, off))
end

local function round_tooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    for _, line in ipairs({ WC.L.ADDON_NAME, WC.L.TIP_MAP_ROUND, WC.L.TIP_MAP_SHIFT, WC.L.TIP_MAP_RIGHT, WC.L.TIP_MAP_DRAG }) do GameTooltip:AddLine(line) end
    if WC.panelState.wantOpen or WC.panelState.wantClose then GameTooltip:AddLine(WC.L.TIP_MAP_DEFERRED) end
    GameTooltip:Show()
end

local function create_round_button()
    local parent = WC.RoundParent()
    if WC.mapRound or not parent or type(CreateFrame) ~= "function" then return WC.mapRound end
    local ok, b = pcall(CreateFrame, "Button", "WoWCompanionMapRoundButton", WorldMapFrame) -- on the map itself, like the client's own buttons
    if not ok or type(b) ~= "table" then return nil end
    b:SetSize(WC.ROUND_SIZE, WC.ROUND_SIZE)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.back = b:CreateTexture(nil, "BACKGROUND") -- the client's own round-button art
    b.back:SetSize(20, 20)
    b.back:SetPoint("TOPLEFT", b, "TOPLEFT", 7, -5)
    b.back:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(17, 17)
    b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", 8, -6)
    b.icon:SetTexture(WC.ICON)
    b.border = b:CreateTexture(nil, "OVERLAY")
    b.border:SetSize(54, 54)
    b.border:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    b.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    if b.SetHighlightTexture then b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight") end
    b.checkedTex = b:CreateTexture(nil, "HIGHLIGHT")
    b.checkedTex:SetAllPoints(b.back)
    b.checkedTex:SetColorTexture(1, 1, 1, 0.25)
    b.checkedTex:Hide()
    b:SetScript("OnMouseDown", function(self) self.icon:SetPoint("TOPLEFT", self, "TOPLEFT", 9, -7) end) -- pushed
    b:SetScript("OnMouseUp", function(self) self.icon:SetPoint("TOPLEFT", self, "TOPLEFT", 8, -6) end)
    b:SetScript("OnClick", function(_, button) WC.MapButtonClick(button, shift_down()) end)
    b:SetScript("OnEnter", round_tooltip)
    b:SetScript("OnLeave", hide_tooltip)
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", function(self)
        if not shift_down() then return end
        self:SetScript("OnUpdate", function()
            local _, cy = GetCursorPosition()
            WC.SetRoundFromCursor(cy)
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    WC.mapRound = b
    return b
end

-- Moves the round button so its middle sits at the cursor's height; the offset from its slot is saved. Returns it.
function WC.SetRoundFromCursor(cursorY)
    local parent, b = WC.RoundParent(), WC.mapRound
    local top = WC.GeoNum(parent, "GetTop")
    if not (b and top and tonumber(cursorY)) then return nil end
    local scale = parent.GetEffectiveScale and parent:GetEffectiveScale() or 1
    if not scale or scale <= 0 then return nil end
    local base = WC.roundBase or WC.ROUND_Y0
    local y = top - cursorY / scale - WC.ROUND_SIZE / 2 -- the wanted top edge, down from the corner
    local off = math.floor(WC.RoundOffset(y - base, base, WC.GeoNum(parent, "GetHeight")) + 0.5)
    WC.SetSetting("mapRoundY", off)
    WC.PlaceRoundButton()
    return off
end

function WC.RaiseRoundButton()
    local b, parent = WC.mapRound, WC.RoundParent()
    if not b then return end
    local map = WorldMapFrame
    if b.SetFrameStrata then pcall(b.SetFrameStrata, b, "HIGH") end -- the client's map buttons' strata
    local top = 0
    for _, f in ipairs({ map, parent, map and map.BorderFrame, map and map.ScrollContainer }) do
        if type(f) == "table" and f.GetFrameLevel then
            local ok, l = pcall(f.GetFrameLevel, f)
            if ok and tonumber(l) and l > top then top = l end
        end
    end
    if b.SetFrameLevel then b:SetFrameLevel(top + 10) end
end

-- Shows the round button in the column's first free slot (plus the player's saved vertical offset).
function WC.PlaceRoundButton()
    local parent = WC.RoundParent()
    local b = create_round_button()
    if not (b and parent) then return end
    if b.GetParent and b:GetParent() ~= WorldMapFrame then b:SetParent(WorldMapFrame) end
    WC.RaiseRoundButton()
    local rects = WC.ScanRoundColumn()
    local x, y, slot = WC.RoundSlot(rects)
    WC.roundBase, WC.roundSig = y, round_sig(rects)
    local off = WC.RoundOffset(WC.Setting("mapRoundY"), y, WC.GeoNum(parent, "GetHeight"))
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -(y + off))
    b:SetShown(WC.Setting("mapButton") ~= false)
    WC.roundPlace = { x = x, y = y + off, slot = slot, occupied = rects }
    WC.RefreshMapTab()
end

function WC.HideRoundButton()
    if WC.mapRound and WC.mapRound.Hide then WC.mapRound:Hide() end
    WC.roundPlace = nil
end

-- Places again now and once more shortly after, for buttons that move after us; the probe is refreshed each time.
function WC.ReplaceMapControl()
    WC.PlaceMapTab()
    WC.RecordMapGeometry()
    if C_Timer and C_Timer.After then
        C_Timer.After(0.2, function() WC.PlaceMapTab(); WC.RecordMapGeometry() end)
    end
end

-- Places the round button (a failure never propagates; the error is recorded once as data) and fits the plan.
function WC.PlaceMapTab()
    if not WC.mapRound then return end
    local ok, err = pcall(function()
        WC.mapControl = "round"
        WC.PlaceRoundButton()
        if WC.PlaceMapPanel then WC.PlaceMapPanel() end
    end)
    if ok or WC.placeErrorSeen then return end
    WC.placeErrorSeen = true
    local db = WC.db or WoWCompanionDB
    if type(db) ~= "table" then return end
    if type(db.observed) ~= "table" then db.observed = {} end
    db.observed.placeError = tostring(err):sub(1, 300)
end

-- Places now, and once more on the next frame (geometry may not exist yet when the map or log has just been shown).
function WC.PlaceMapTabSoon()
    WC.PlaceMapTab()
    if C_Timer and C_Timer.After then C_Timer.After(0, WC.PlaceMapTab) end
end

WC.ROUND_SCAN_EVERY = 0.5

-- Every 0.5 s while the map is shown: re-place only when the round column changed (or the button was hidden).
function WC.WatchRoundColumn(elapsed)
    WC.columnClock = (WC.columnClock or 0) + (tonumber(elapsed) or 0)
    if WC.columnClock < WC.ROUND_SCAN_EVERY then return false end
    WC.columnClock = 0
    local r = WC.mapRound
    if not r then return false end
    if WC.roundSig and WC.roundSig ~= round_sig(WC.ScanRoundColumn()) then
        WC.PlaceMapTab() -- a round button above ours appeared or went away
        return true
    end
    if WC.Setting("mapButton") ~= false and not r:IsShown() then WC.PlaceMapTab() return true end
    return false
end

function WC.ResetMapTabPosition()
    WC.SetSetting("mapRoundY", WC.DEF_OF["mapRoundY"].default)
    if WC.PlaceMapTab then WC.PlaceMapTab() end
end

-- The round map button, on the map frame, shown whenever the map is, in every size and pane state. The plan's side
-- panel hangs on the client's quest-pane frame when this client has one.
function WC.CreateMapButton()
    local map = WorldMapFrame
    if not map or WC.mapRound then return end
    if not create_round_button() then return end
    local col = QuestMapFrame
    if col and col.HookScript then
        col:HookScript("OnShow", function() WC.PlaceMapTabSoon(); WC.RefreshMapTab(); WC.ReplaceMapControl() end)
        col:HookScript("OnHide", function() WC.ReplaceMapControl() end)
        col:HookScript("OnSizeChanged", WC.ReplaceMapControl)
    end
    if map.HookScript then
        map:HookScript("OnShow", function()
            WC.PlaceMapTabSoon(); WC.ApplyMapTabState(); WC.RefreshMapTab(); WC.RecordMapGeometry()
            if C_Timer and C_Timer.After then -- again once the client has laid the map out
                C_Timer.After(0.2, function() WC.PlaceMapTab(); WC.RecordMapGeometry() end)
                C_Timer.After(0.5, function() WC.PlaceMapTab(); WC.RecordMapGeometry() end)
            end
        end)
        map:HookScript("OnSizeChanged", WC.ReplaceMapControl)
        map:HookScript("OnUpdate", function(_, elapsed) WC.WatchRoundColumn(elapsed) end)
        map:HookScript("OnHide", function() WC.ClearSelectedStep() end) -- the selection ends with the map
    end
    if hooksecurefunc and type(map.OnMapChanged) == "function" and not WC.mapChangedHooked then
        WC.mapChangedHooked = pcall(hooksecurefunc, map, "OnMapChanged", WC.ReplaceMapControl)
    end
    if col and WC.HookDisplayMode then WC.HookDisplayMode(col) end
    WC.InitMapPanel()
    WC.RefreshMapTab()
end

-- The client changes its quest-log display mode through SetDisplayMode: place again then.
function WC.HookDisplayMode(column)
    if type(column) == "table" and type(column.SetDisplayMode) == "function" and hooksecurefunc and not WC.displayModeHooked then
        WC.displayModeHooked = true
        pcall(hooksecurefunc, column, "SetDisplayMode", function() WC.PlaceMapTabSoon() end)
    end
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
    if WC.mapRound then WC.mapRound:SetShown(WC.Setting("mapButton") ~= false) end
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
