-- WoW Companion: the movable advice panel.

local WC = WoWCompanion
local L = WC.L

local FULL_HEIGHT, COMPACT_MIN = 320, 150
local SCROLL_TOP = 44 -- the scroll area's offset from the frame's top; the other edges follow the padding setting
local WIDTH_MARGIN = 48 -- the panel is this much wider than its text column; the width is the panelWidth setting (340)
local function panel_width() return WC.Setting("panelWidth") end
local function content_width() return panel_width() - WIDTH_MARGIN end

-- Manual size: the grip sets panelSizeMode to "manual" and saves panelWidth and panelHeight; right-click is Auto again.
-- Bounds: width is the slider's range; height runs from the title, step line and two rows up to 90% of the screen.
local WIDTH_MIN, WIDTH_MAX, SCREEN_FRACTION = 280, 520, 0.9

function WC.PanelHeightBounds()
    local f = WC.panel
    local pad = WC.Setting("padding")
    local lo = math.ceil(((f and f.scrollTop) or SCROLL_TOP) + pad + 2 * WC.LINE_HEIGHT)
    local screen = (UIParent and UIParent.GetHeight and UIParent:GetHeight()) or 0
    if not screen or screen <= 0 then screen = (GetScreenHeight and GetScreenHeight()) or 1000 end
    local scale = (f and f.GetScale and f:GetScale()) or 1
    if not scale or scale <= 0 then scale = 1 end
    return lo, math.max(lo, math.floor(screen * SCREEN_FRACTION / scale))
end

-- The width and height inside the bounds.
function WC.ClampPanelSize(w, h)
    local lo, hi = WC.PanelHeightBounds()
    return math.max(WIDTH_MIN, math.min(WIDTH_MAX, w)), math.max(lo, math.min(hi, h))
end

-- The size the panel takes: the saved size in Manual; in Auto the width setting, the full height or (compact) the fit.
function WC.PanelSize(fit)
    local w = panel_width()
    if WC.Setting("panelSizeMode") == "manual" then
        local _, h = WC.ClampPanelSize(w, WC.Setting("panelHeight"))
        return w, h
    end
    return w, fit or FULL_HEIGHT
end

-- The grip's tooltip: { text, gold } lines.
function WC.GripTipLines()
    local out = { { L["GRIP_TIP_" .. WC.Setting("panelSizeMode")], true } }
    if WC.Setting("locked") then
        out[#out + 1] = { L.GRIP_TIP_LOCKED, false }
    else
        out[#out + 1] = { L.GRIP_TIP_DRAG, false }
        out[#out + 1] = { L.GRIP_TIP_RESET, false }
    end
    return out
end

-- Starts a drag-resize from the bottom-right corner. Refused while locked or in combat.
function WC.StartPanelSizing()
    local f = WC.panel
    if not f or f.sizing or WC.Setting("locked") or WC.inCombat or (InCombatLockdown and InCombatLockdown()) then return false end
    local lo, hi = WC.PanelHeightBounds()
    if f.SetResizable then f:SetResizable(true) end
    if f.SetResizeBounds then f:SetResizeBounds(WIDTH_MIN, lo, WIDTH_MAX, hi)
    else
        if f.SetMinResize then f:SetMinResize(WIDTH_MIN, lo) end
        if f.SetMaxResize then f:SetMaxResize(WIDTH_MAX, hi) end
    end
    f.sizing = true
    f:StartSizing("BOTTOMRIGHT")
    return true
end

-- Ends a drag-resize (also on combat) and saves the size: Manual, with the width in the panelWidth setting.
function WC.StopPanelSizing()
    local f = WC.panel
    if not f or not f.sizing then return end
    f.sizing = false
    f:StopMovingOrSizing()
    local w, h = WC.ClampPanelSize(f:GetWidth(), f:GetHeight())
    local point, _, relPoint, x, y = f:GetPoint()
    if point then WC.db.position = { point = point, relPoint = relPoint, x = x, y = y } end
    WC.db.settings.panelSizeMode = "manual"
    WC.db.settings.panelHeight = WC.Repair(WC.DEF_OF.panelHeight, h)
    WC.SetSetting("panelWidth", w)
end

-- Right-click on the grip: Automatic size again; the width stays.
function WC.ResetPanelSize()
    WC.SetSetting("panelSizeMode", "auto")
end

-- While dragging, the width follows the cursor live: the text wraps at the new width as it moves.
local function sizing_changed(f, w)
    if not f.sizing then return end
    w = math.max(WIDTH_MIN, math.min(WIDTH_MAX, math.floor((w or 0) / 10 + 0.5) * 10))
    if w ~= WC.db.settings.panelWidth then
        WC.db.settings.panelWidth = w
        if WC.SyncOptions then WC.SyncOptions() end
        WC.Refresh()
    end
end
local STEP, TITLE_X, RIGHT_W = 16, 32, 64 -- indent step; where a quest title starts; width kept for a right-aligned note

-- Text shadow so lines read over the world.
local function shadow(fs)
    if fs.SetShadowOffset then fs:SetShadowOffset(1, -1) end
    if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 1) end
end

-- Applies the look settings (background, border, header colour, padding) to the panel; called on every redraw.
function WC.ApplyPanelLook()
    local f = WC.panel
    if not f then return end
    local pad = WC.Setting("padding")
    if f.SetBackdropColor then
        local bg = WC.Setting("bgColor")
        f:SetBackdropColor(bg[1], bg[2], bg[3], WC.Setting("bgOpacity"))
        local bc = WC.Setting("borderColor")
        f:SetBackdropBorderColor(bc[1], bc[2], bc[3], WC.Setting("borderShow") and WC.Setting("borderOpacity") or 0)
    end
    if f.grip then f.grip:SetShown(not WC.Setting("locked")) end
    local hc = WC.Setting("headerColor")
    f.title:SetTextColor(hc[1], hc[2], hc[3])
    f.title:ClearAllPoints()
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -8)
    WC.LayoutPanelHeader()
end

-- Header controls, right to left: close, view button (sized to its label), gear. Their click areas never overlap.
function WC.LayoutHeaderButtons()
    local f = WC.panel
    if not f or not f.close or not f.compactButton or not f.gear then return end
    local c, g = f.compactButton, f.gear
    local label = c.label
    local w = label and ((label.GetStringWidth and label:GetStringWidth()) or 0) or 0
    if not w or w <= 0 then w = #(label and label:GetText() or "") * 6 end
    c:SetSize(math.ceil(w) + 4, 16)
    c:ClearAllPoints()
    c:SetPoint("RIGHT", f.close, "LEFT", -2, 0)
    g:ClearAllPoints()
    g:SetPoint("RIGHT", c, "LEFT", -6, 0)
    g:SetFrameLevel(f:GetFrameLevel() + 5)
end

-- Places the next-step line under the title (it wraps), the advice time under it and the scroll area below both.
-- The scroll area's offset from the frame's top is kept in f.scrollTop.
function WC.LayoutPanelHeader()
    local f = WC.panel
    if not f then return end
    WC.LayoutHeaderButtons()
    local pad = WC.Setting("padding")
    local text = f.step:GetText()
    f.step:ClearAllPoints()
    f.step:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -26)
    f.step:SetWidth(panel_width() - 2 * pad - 24)
    local h1 = 0
    if text and text ~= "" then
        h1 = (f.step.GetStringHeight and f.step:GetStringHeight()) or WC.LINE_HEIGHT
        if not h1 or h1 <= 0 then h1 = WC.LINE_HEIGHT end
        h1 = h1 + 2
    end
    f.header:ClearAllPoints()
    f.header:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(pad + 2), -(26 + h1))
    f.headerTip:ClearAllPoints()
    f.headerTip:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(pad + 2), -(26 + h1))
    f.headerTip:SetSize(math.max(60, (f.header.GetStringWidth and f.header:GetStringWidth()) or 160), WC.LINE_HEIGHT)
    -- the to-do chips sit under the advice time; the scroll area starts below them
    local chipH = f.chipH or 0
    WC.PlaceChips(f, pad, SCROLL_TOP + h1 - 2)
    f.scrollTop = SCROLL_TOP + h1 + (chipH > 0 and chipH + 4 or 0)
    f.scroll:ClearAllPoints()
    f.scroll:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -f.scrollTop)
    f.scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(pad + 18), pad)
end

-- The pooled chip button at index i.
local function get_chip(f, i)
    f.chipButtons = f.chipButtons or {}
    local b = f.chipButtons[i]
    if b then return b end
    b = CreateFrame("Button", nil, f)
    b:SetSize(WC.CHIP_SIZE, WC.CHIP_SIZE)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(0, 0, 0, 0.6)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.glow = b:CreateTexture(nil, "OVERLAY") -- the "something new" highlight
    b.glow:SetPoint("TOPLEFT", b, "TOPLEFT", -2, 2)
    b.glow:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 2, -2)
    b.glow:SetColorTexture(1, 0.82, 0, 1)
    b.glow:SetAlpha(0)
    b.count = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall") -- the badge in the corner
    b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 3, -2)
    shadow(b.count)
    b:SetScript("OnEnter", function(self)
        WC.ChipHovered(self.chip.kind)
        WC.StyleChip(self)
        WC.TipOpen(GameTooltip, self, "ANCHOR_BOTTOM")
        for _, l in ipairs(WC.ChipTipLines(self.chip)) do WC.TipLine(GameTooltip, l.text, l.color) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self) WC.OpenCard(self.chip.entry) end) -- either mouse button
    f.chipButtons[i] = b
    return b
end

-- The glow of a chip: pulsing while new and recent, steady until hovered, else off.
function WC.StyleChip(b)
    local kind = b.chip and b.chip.kind
    if kind and WC.ChipNew(kind) then
        b:SetScript("OnUpdate", function(self)
            local t = WC.Now()
            if WC.ChipPulsing(self.chip.kind, t) then
                self.glow:SetAlpha(0.35 + 0.35 * math.sin(t * 5))
            elseif WC.ChipNew(self.chip.kind) then
                self.glow:SetAlpha(0.6)
            else
                self.glow:SetAlpha(0)
                self:SetScript("OnUpdate", nil)
            end
        end)
        b.glow:SetAlpha(0.6)
    else
        b:SetScript("OnUpdate", nil)
        b.glow:SetAlpha(0)
    end
end

-- Lays the chip buttons out (wrapping at the panel width) from the chip list the last Refresh set.
function WC.PlaceChips(f, pad, top)
    local chips = f.chipList or {}
    f.chipButtons = f.chipButtons or {}
    local pos = f.chipPos or {}
    for i, c in ipairs(chips) do
        local b = get_chip(f, i)
        b.chip = c
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", f, "TOPLEFT", pad + pos[i].x, -(top + pos[i].y))
        b.icon:SetTexture(c.icon)
        b.count:SetText(not c.noBadge and tostring(c.count) or nil)
        b:Show()
        WC.StyleChip(b)
    end
    for i = #chips + 1, #f.chipButtons do f.chipButtons[i]:Hide(); f.chipButtons[i].chip = nil end
end

-- Takes the chips from a render: notes counts that went up, filters by the settings, and sizes the row.
function WC.SetChips(f, all)
    if all then WC.ChipsNote(all) end
    f.chipList = WC.VisibleChips(all)
    f.chipEntries = {}
    for _, c in ipairs(f.chipList) do f.chipEntries[c.entry.key] = c.entry end
    f.chipPos, f.chipH = WC.ChipLayout(#f.chipList, panel_width() - 2 * WC.Setting("padding") - 24)
end

-- Sets the next-step line from the plan and where the player stands. Re-lays the header only when the text changed,
-- so movement (every tick) costs one string comparison.
function WC.RefreshNextLine()
    local f = WC.panel
    if not f then return end
    local mapID, px, py
    if WC.PlayerPos then mapID, px, py = WC.PlayerPos() end
    local text = WC.NextStepLine(WC.PlanNext(), mapID, px, py)
    if f.step:GetText() == text then return end
    f.step:SetText(WC.SafeText(text))
    WC.LayoutPanelHeader()
    if f:IsShown() and WC.view.mode == "next" then WC.Refresh() end
end

-- Which sections are temporarily expanded in compact mode.
WC.view = { expanded = {} }

function WC.CreatePanel()
    -- A light, translucent frame: a thin border and a dark wash instead of the dialog template.
    local f = CreateFrame("Frame", "WoWCompanionPanel", UIParent, "BackdropTemplate")
    f:SetSize(WC.PanelSize())
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    end
    f:SetScale(WC.db.settings.scale)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if not WC.db.settings.locked then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        WC.db.position = { point = point, relPoint = relPoint, x = x, y = y }
    end)

    local pos = WC.db.position
    if pos then
        f:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal") -- gold
    f.title:SetText(L.ADDON_NAME)
    shadow(f.title)

    f.step = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.step:SetTextColor(unpack(WC.COLORS.grey))
    shadow(f.step)

    f.header = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") -- the advice time, dim, right-aligned
    f.header:SetJustifyH("RIGHT")
    f.header:SetTextColor(unpack(WC.COLORS.dim))
    shadow(f.header)

    -- the advice time explains itself when it has gone amber
    f.headerTip = CreateFrame("Frame", "WoWCompanionPanelHeaderTip", f)
    f.headerTip:EnableMouse(true)
    f.headerTip:SetScript("OnEnter", function(self)
        if not f.stale then return end
        WC.TipOpen(GameTooltip, self, "ANCHOR_BOTTOM")
        WC.TipLine(GameTooltip, L.STALE_TIP, 1, 1, 1)
        GameTooltip:Show()
    end)
    f.headerTip:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.close = CreateFrame("Button", "WoWCompanionPanelClose", f, "UIPanelCloseButton")
    f.close:SetSize(20, 20)
    f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    f.close:SetScript("OnClick", function() f:Hide() end)

    f.scroll = CreateFrame("ScrollFrame", "WoWCompanionPanelScroll", f, "UIPanelScrollFrameTemplate")
    f.content = CreateFrame("Frame", nil, f.scroll)
    f.content:SetSize(content_width(), 1)
    f.scroll:SetScrollChild(f.content)

    f.rows = {}

    -- The resize grip: the chat frame's size-grabber in the bottom-right corner.
    local grip = CreateFrame("Button", "WoWCompanionPanelGrip", f)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    grip:SetFrameLevel(f:GetFrameLevel() + 5)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    grip:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then WC.StartPanelSizing() end
    end)
    grip:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then WC.StopPanelSizing() elseif button == "RightButton" then WC.ResetPanelSize() end
    end)
    grip:SetScript("OnEnter", function(self)
        WC.TipOpen(GameTooltip, self, "ANCHOR_TOP")
        for _, l in ipairs(WC.GripTipLines()) do
            if l[2] then WC.TipLine(GameTooltip, l[1], 1, 0.82, 0) else WC.TipLine(GameTooltip, l[1], 1, 1, 1) end
        end
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.grip = grip
    f:SetScript("OnSizeChanged", function(self, w) sizing_changed(self, w) end)

    -- The compact toggle: a small text button beside the close button.
    local c = CreateFrame("Button", "WoWCompanionCompactButton", f)
    c:SetSize(40, 16)
    c:SetPoint("RIGHT", f.close, "LEFT", -2, 0)
    c.label = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    c.label:SetPoint("RIGHT", c, "RIGHT", 0, 0)
    c.label:SetJustifyH("RIGHT")
    shadow(c.label)
    c:SetScript("OnClick", function() WC.SetSetting("view", WC.NextView(WC.ViewMode())) end)
    c:SetScript("OnEnter", function(self)
        WC.TipOpen(GameTooltip, self, "ANCHOR_BOTTOM")
        for _, l in ipairs(WC.ViewTipLines(WC.ViewMode())) do
            if l[2] then WC.TipLine(GameTooltip, l[1], 1, 0.82, 0) else WC.TipLine(GameTooltip, l[1], 1, 1, 1) end
        end
        GameTooltip:Show()
    end)
    c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    c.SetText = function(self, t) self.label:SetText(t); WC.LayoutHeaderButtons() end
    c.GetText = function(self) return self.label:GetText() end
    c:SetText(L.COMPACT)
    f.compactButton = c

    -- The gear: opens the options window.
    local g = CreateFrame("Button", "WoWCompanionGearButton", f)
    g:SetSize(16, 16)
    g:SetPoint("RIGHT", c, "LEFT", -6, 0)
    g:SetFrameLevel(f:GetFrameLevel() + 5)
    g.icon = g:CreateTexture(nil, "ARTWORK")
    g.icon:SetAllPoints()
    g.icon:SetTexture("Interface\\Buttons\\UI-OptionsButton")
    g:SetScript("OnClick", function() WC.OpenOptions() end)
    g:SetScript("OnEnter", function(self)
        WC.TipOpen(GameTooltip, self, "ANCHOR_BOTTOM")
        WC.TipLine(GameTooltip, L.OPEN_GEAR_TIP, 1, 1, 1)
        GameTooltip:Show()
    end)
    g:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.gear = g
    WC.LayoutHeaderButtons()

    f:SetScript("OnHide", function()
        WC.view.expanded = {}
        WC.hover = { groups = {}, quests = {}, source = nil }
        if WC.ApplyMapHover then WC.ApplyMapHover() end
        if WC.CloseCard then WC.CloseCard() end
    end)

    f:SetScript("OnShow", function() WC.Refresh() end)
    WC.panel = f
    WC.ApplyPanelLook()
    WC.Refresh()
    f:Hide()
end

function WC.ShowPanel()
    local f = WC.panel
    if not f then return end
    if f:IsShown() then WC.Refresh() else f:Show() end
end

function WC.TogglePanel()
    local f = WC.panel
    if not f then return end
    if f:IsShown() then f:Hide() else f:Show() end
end

local toggle_quest -- defined below; the row buttons call it

-- Returns the pooled row button at index i, creating it on first use.
local function get_row(f, i)
    local row = f.rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, f.content)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.hl = row:CreateTexture(nil, "BACKGROUND") -- the hover bar behind the entry's rows
    row.hl:SetPoint("TOPLEFT", row, "TOPLEFT", -2, 1)
    row.hl:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 2, -1)
    row.hl:Hide()
    row.toggle = row:CreateTexture(nil, "ARTWORK") -- the collapse button
    row.toggle:SetSize(12, 12)
    -- The +/- square collapses a quest; the rest of the title row opens it (left-click) or its card (right-click).
    row.tbtn = CreateFrame("Button", nil, row)
    row.tbtn:SetSize(14, 14)
    row.tbtn:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.tbtn:SetScript("OnClick", function() if row.sectionId then toggle_quest(row.sectionId) end end)
    row.tbtn:Hide()
    row.icon = row:CreateTexture(nil, "ARTWORK") -- the state icon
    row.icon:SetSize(16, 16)
    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.label:SetJustifyH("LEFT")
    shadow(row.label)
    row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.right:SetJustifyH("RIGHT")
    shadow(row.right)
    f.rows[i] = row
    return row
end

-- Places one row's pieces and returns the x its text starts at.
local function layout_row(row, r)
    local x = (r.indent or 0) * STEP
    row.toggle:ClearAllPoints()
    row.icon:ClearAllPoints()
    row.toggle:Hide()
    row.icon:Hide()
    row.tbtn:SetShown(r.kind == "quest")
    if r.kind == "quest" then
        row.toggle:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -1)
        row.toggle:SetTexture(r.closed and WC.ICONS.closed or WC.ICONS.open)
        row.toggle:Show()
        x = TITLE_X
        if r.icon then
            row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 14, 0)
            row.icon:SetTexture(r.icon)
            row.icon:Show()
        end
    elseif r.icon then
        row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", x, 0)
        row.icon:SetTexture(r.icon)
        row.icon:Show()
        x = x + 18
    end
    return x
end

-- Display only: shows the item's or spell's tooltip while the mouse is over the row.
local function show_tooltip(row)
    WC.TipOpen(GameTooltip, row, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(row.link)
    GameTooltip:Show()
end

local function toggle_section(id)
    if WC.ViewMode() == "compact" then
        WC.view.expanded[id] = (not WC.view.expanded[id]) or nil
        WC.Refresh()
        return
    end
    WC.db.collapsed = type(WC.db.collapsed) == "table" and WC.db.collapsed or {}
    if WC.DefaultClosed(id) then -- closed unless explicitly opened (false)
        if WC.db.collapsed[id] == false then WC.db.collapsed[id] = nil else WC.db.collapsed[id] = false end
    else
        WC.db.collapsed[id] = (not WC.db.collapsed[id]) or nil
    end
    WC.Refresh()
end

-- A quest's own collapse state, kept with the section ones (its id starts with "q").
function toggle_quest(id)
    WC.db.collapsed = type(WC.db.collapsed) == "table" and WC.db.collapsed or {}
    WC.db.collapsed[id] = (not WC.db.collapsed[id]) or nil
    WC.Refresh()
end

-- Re-reads the global digest table (data only) and redraws the panel.
function WC.Refresh()
    WC.RefreshTracker()
    local f = WC.panel
    if not f then return end
    WC.ApplyPanelLook()
    f.content:SetWidth(content_width())
    WC.StyleText(f.title)
    WC.StyleText(f.header)
    local collapsed = type(WC.db.collapsed) == "table" and WC.db.collapsed or {}
    local player = UnitName("player")
    local show = WC.db.settings.show
    local header, rows, meta = WC.RenderDigest(WoWCompanionDigest, time(), player, collapsed, show,
        WC.OwnCapturedAt(player))
    WC.StyleText(f.step)
    WC.SetChips(f, meta and meta.chips)
    f.title:SetText(meta and string.format(L.PANEL_TITLE, L.ADDON_NAME, meta.name) or L.ADDON_NAME)
    local advice = meta and meta.advice or header
    if meta and WC.PlanFollowing() and WC.plan.generated > 0 then
        advice = string.format(L.ADVICE_FOLLOWING, WC.FormatClock(WC.plan.generated))
    end
    f.header:SetText(WC.SafeText(advice))
    f.stale = meta and meta.stale or false
    local hc = f.stale and WC.COLORS.amber or WC.COLORS.dim
    f.header:SetTextColor(hc[1], hc[2], hc[3])
    local mode = WC.ViewMode()
    WC.view.mode = mode
    local mapID, px, py
    if WC.PlayerPos then mapID, px, py = WC.PlayerPos() end
    f.step:SetText(WC.SafeText(WC.NextStepLine(WC.PlanNext(), mapID, px, py)))
    WC.LayoutPanelHeader()
    rows = WC.ViewRows(mode, rows, WC.view.expanded, WC.PlanNext())
    if WC.HereRows and WC.plan then -- the "Here" card and "Also doing" sit above the digest rows
        local extra = WC.HereRows(mapID, px, py)
        for i, r in ipairs(extra) do table.insert(rows, i, r) end
    end
    local compact = mode ~= "full"
    f.compactButton:SetText(WC.ViewButtonLabel(mode))

    local y = 0
    local entries = {} -- group key -> its entry, so every row of an entry opens the same card
    for i, r in ipairs(rows) do
        local row = get_row(f, i)
        row:Show()
        WC.StyleText(row.label)
        WC.StyleText(row.right, -1)
        local x = layout_row(row, r)
        row.label:SetText(WC.SafeText(r.text))
        if row.label.SetMaxLines then row.label:SetMaxLines((r.kind == "line" or r.why) and 2 or 0) end -- a note wraps to 2 lines; its card shows all
        row.baseColor = r.color or WC.COLORS.white
        row.right:SetText(WC.SafeText(r.right or ""))
        row.right:SetTextColor(unpack(WC.COLORS.dim))
        -- The text wraps at the panel width; it is never cut.
        row.label:SetWidth(content_width() - x - (r.right and RIGHT_W or 0))
        row.label:ClearAllPoints()
        row.label:SetPoint("TOPLEFT", row, "TOPLEFT", x, 0)
        row.right:ClearAllPoints()
        row.right:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
        row.right:SetWidth(RIGHT_W)
        local h = (row.label.GetStringHeight and row.label:GetStringHeight()) or WC.LINE_HEIGHT
        h = math.max(WC.LINE_HEIGHT * WC.FONT_SIZES[WC.db.settings.fontSize] / WC.FONT_SIZES.normal, h)
        if r.kind == "header" and i > 1 then y = y + 4 end -- a little air above each section
        row.top, row.hh = y, h
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, -y)
        row:SetSize(content_width(), h)
        y = y + h + math.max(0, WC.Setting("lineSpacing") - (r.kind == "obj" and 1 or 0))
        row.link = (r.item and "item:" .. r.item) or (r.spell and "spell:" .. r.spell) or nil
        row.sectionId = r.id
        if r.entry then entries[r.group] = r.entry end
        row.entry, row.group, row.quest = r.entry or (r.group and entries[r.group]) or nil, r.group, r.quest
        local interactive = row.link ~= nil or r.kind == "header" or row.entry ~= nil or r.ask ~= nil
        row:EnableMouse(interactive)
        row:SetScript("OnEnter", function(self)
            if self.link then show_tooltip(self) end
            if self.group then WC.HoverEnterRow(self) end
            if self.quest and WC.ClearNew and WC.ClearNew(self.quest) then WC.Refresh() end -- hovering dismisses "New"
        end)
        row:SetScript("OnLeave", function(self)
            if self.link then GameTooltip:Hide() end
            if self.group then WC.HoverLeaveRow() end
        end)
        row.ask = r.ask
        row:SetScript("OnClick", function(self, button)
            if r.kind == "header" then
                if button ~= "RightButton" then toggle_section(r.id) end
            elseif self.entry then
                WC.EntryClick(self.entry, button)
            end
        end)
        WC.ApplyRowHover(row)
    end
    for i = #rows + 1, #f.rows do f.rows[i]:Hide() end
    f.plain = WC.RowsText(rows)
    WC.HoverCheck()
    if WC.RefreshCard then WC.RefreshCard() end
    f.content:SetHeight(y)
    if not f.sizing then -- the client sizes the frame itself while the grip is held
        f:SetSize(WC.PanelSize(compact and math.max(COMPACT_MIN, math.min(FULL_HEIGHT, f.scrollTop + WC.Setting("padding") + y)) or FULL_HEIGHT))
    end
    f.scrollRange = math.max(0, y - f.scroll:GetHeight())
    f.scroll:UpdateScrollChildRect()
end

-- Restores the default position and expands every section.
function WC.ResetPanel()
    local f = WC.panel
    if not f then return end
    WC.db.position, WC.db.collapsed, WC.view.expanded = nil, nil, {}
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    WC.Refresh()
end
