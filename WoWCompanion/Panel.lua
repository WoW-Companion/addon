-- WoW Companion: the movable advice panel.

local WC = WoWCompanion
local L = WC.L

local FULL_HEIGHT, COMPACT_MIN = 320, 150
local WIDTH_MARGIN = 48 -- the panel is this much wider than its text column; the width is the panelWidth setting (340)
local function panel_width() return WC.Setting("panelWidth") end
local function content_width() return panel_width() - WIDTH_MARGIN end
local SCROLL_TOP = 44 -- the scroll area's offset from the frame's top; the other edges follow the padding setting
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
    local hc = WC.Setting("headerColor")
    f.title:SetTextColor(hc[1], hc[2], hc[3])
    f.title:ClearAllPoints()
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -8)
    f.step:ClearAllPoints()
    f.step:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -26)
    f.header:ClearAllPoints()
    f.header:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(pad + 2), -26)
    f.scroll:ClearAllPoints()
    f.scroll:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -SCROLL_TOP)
    f.scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(pad + 18), pad)
end

-- Which sections are temporarily expanded in compact mode.
WC.view = { expanded = {} }

function WC.CreatePanel()
    -- A light, translucent frame: a thin border and a dark wash instead of the dialog template.
    local f = CreateFrame("Frame", "WoWCompanionPanel", UIParent, "BackdropTemplate")
    f:SetSize(panel_width(), FULL_HEIGHT)
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

    f.close = CreateFrame("Button", "WoWCompanionPanelClose", f, "UIPanelCloseButton")
    f.close:SetSize(20, 20)
    f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    f.close:SetScript("OnClick", function() f:Hide() end)

    f.scroll = CreateFrame("ScrollFrame", "WoWCompanionPanelScroll", f, "UIPanelScrollFrameTemplate")
    f.content = CreateFrame("Frame", nil, f.scroll)
    f.content:SetSize(content_width(), 1)
    f.scroll:SetScrollChild(f.content)

    f.rows = {}

    -- The compact toggle: a small text button beside the close button.
    local c = CreateFrame("Button", "WoWCompanionCompactButton", f)
    c:SetSize(56, 16)
    c:SetPoint("TOPRIGHT", f, "TOPRIGHT", -24, -6)
    c.label = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    c.label:SetPoint("RIGHT", c, "RIGHT", 0, 0)
    c.label:SetJustifyH("RIGHT")
    shadow(c.label)
    c:SetScript("OnClick", function() WC.SetCompact(not WC.db.settings.compact) end)
    c.SetText = function(self, t) self.label:SetText(t) end
    c.GetText = function(self) return self.label:GetText() end
    c:SetText(L.COMPACT)
    f.compactButton = c

    -- The gear: opens the options window.
    local g = CreateFrame("Button", "WoWCompanionGearButton", f)
    g:SetSize(16, 16)
    g:SetPoint("TOPRIGHT", f, "TOPRIGHT", -82, -6)
    g.icon = g:CreateTexture(nil, "ARTWORK")
    g.icon:SetAllPoints()
    g.icon:SetTexture("Interface\\Buttons\\UI-OptionsButton")
    g:SetScript("OnClick", function() WC.OpenOptions() end)
    g:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(L.OPEN_GEAR_TIP)
        GameTooltip:Show()
    end)
    g:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.gear = g

    f:SetScript("OnHide", function() WC.view.expanded = {} end)

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

-- Returns the pooled row button at index i, creating it on first use.
local function get_row(f, i)
    local row = f.rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, f.content)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.toggle = row:CreateTexture(nil, "ARTWORK") -- the collapse button
    row.toggle:SetSize(12, 12)
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
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(row.link)
    GameTooltip:Show()
end

local function toggle_section(id)
    if WC.db.settings.compact then
        WC.view.expanded[id] = (not WC.view.expanded[id]) or nil
        WC.Refresh()
        return
    end
    WC.db.collapsed = type(WC.db.collapsed) == "table" and WC.db.collapsed or {}
    WC.db.collapsed[id] = (not WC.db.collapsed[id]) or nil
    WC.Refresh()
end

-- A quest's own collapse state, kept with the section ones (its id starts with "q").
local function toggle_quest(id)
    WC.db.collapsed = type(WC.db.collapsed) == "table" and WC.db.collapsed or {}
    WC.db.collapsed[id] = (not WC.db.collapsed[id]) or nil
    WC.Refresh()
end

-- Right-click on a digest line: queues its templated question exactly like /ask.
-- The text only leaves the game through SavedVariables, and the overlay answers it.
function WC.FillAsk(row)
    local q = WC.AskTemplate(row)
    if q then WC.Ask(q:sub(1, WC.MAX_ASK_LEN)) end
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
        WC.CapturedAt(ForeverScribeDB, player, GetRealmName and GetRealmName()))
    WC.StyleText(f.step)
    f.title:SetText(meta and string.format(L.PANEL_TITLE, L.ADDON_NAME, meta.name) or L.ADDON_NAME)
    f.header:SetText(meta and meta.advice or header)
    local done, total = WC.PlanCounts()
    f.step:SetText(total > 0 and string.format(L.STEP_COUNT, math.min(done + 1, total), total) or "")
    local compact = WC.db.settings.compact
    if compact then rows = WC.CompactRows(rows, WC.view.expanded) end
    f.compactButton:SetText(compact and L.FULL or L.COMPACT)

    local y = 0
    for i, r in ipairs(rows) do
        local row = get_row(f, i)
        row:Show()
        WC.StyleText(row.label)
        WC.StyleText(row.right, -1)
        local x = layout_row(row, r)
        row.label:SetText(r.text)
        row.label:SetTextColor(unpack(r.color or WC.COLORS.white))
        row.right:SetText(r.right or "")
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
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, -y)
        row:SetSize(content_width(), h)
        y = y + h + math.max(0, WC.Setting("lineSpacing") - (r.kind == "obj" and 1 or 0))
        row.link = (r.item and "item:" .. r.item) or (r.spell and "spell:" .. r.spell) or nil
        row.sectionId = r.id
        local interactive = row.link ~= nil or r.kind == "header" or r.kind == "quest" or r.ask ~= nil
        row:EnableMouse(interactive)
        row:SetScript("OnEnter", row.link and show_tooltip or nil)
        row:SetScript("OnLeave", row.link and function() GameTooltip:Hide() end or nil)
        row.ask = r.ask
        row:SetScript("OnClick", function(self, button)
            if button == "RightButton" then
                WC.FillAsk(self)
            elseif r.kind == "header" then
                toggle_section(r.id)
            elseif r.kind == "quest" then
                toggle_quest(r.id)
            end
        end)
    end
    for i = #rows + 1, #f.rows do f.rows[i]:Hide() end
    f.plain = WC.RowsText(rows)
    f.content:SetHeight(y)
    f:SetSize(panel_width(), compact and math.max(COMPACT_MIN, math.min(FULL_HEIGHT, SCROLL_TOP + WC.Setting("padding") + y)) or FULL_HEIGHT)
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
