-- WoW Companion: the movable advice panel.

local WC = WoWCompanion
local L = WC.L

local FULL_HEIGHT, COMPACT_MIN = 320, 150
local SCROLL_TOP, SCROLL_BOTTOM = 50, 12 -- the scroll area's offsets from the frame's top and bottom

-- Which sections are temporarily expanded in compact mode.
WC.view = { expanded = {} }

function WC.CreatePanel()
    local f = CreateFrame("Frame", "WoWCompanionPanel", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(340, FULL_HEIGHT)
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

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOP", f, "TOP", 0, -5)
    f.title:SetText(L.ADDON_NAME)

    f.header = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.header:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -28)
    f.header:SetWidth(300)
    f.header:SetJustifyH("LEFT")

    local function button(name, label, w, x, y, fn)
        local b = CreateFrame("Button", name, f, "UIPanelButtonTemplate")
        b:SetSize(w, 22)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
        b:SetText(label)
        b:SetScript("OnClick", fn)
        return b
    end

    f.scroll = CreateFrame("ScrollFrame", "WoWCompanionPanelScroll", f, "UIPanelScrollFrameTemplate")
    f.scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -SCROLL_TOP)
    f.scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -32, SCROLL_BOTTOM)
    f.content = CreateFrame("Frame", nil, f.scroll)
    f.content:SetSize(290, 1)
    f.scroll:SetScrollChild(f.content)

    f.rows = {}

    f.compactButton = button("WoWCompanionCompactButton", L.COMPACT, 60, 8, -3, function()
        WC.SetCompact(not WC.db.settings.compact)
    end)
    f.compactButton:SetHeight(18)

    f:SetScript("OnHide", function() WC.view.expanded = {} end)

    f:SetScript("OnShow", function() WC.Refresh() end)
    WC.panel = f
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
    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.label:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.label:SetWidth(290)
    WC.StyleText(row.label)
    row.label:SetJustifyH("LEFT")
    f.rows[i] = row
    return row
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
    WC.StyleText(f.title)
    WC.StyleText(f.header)
    local collapsed = type(WC.db.collapsed) == "table" and WC.db.collapsed or {}
    local player = UnitName("player")
    local show = WC.db.settings.show
    local header, rows = WC.RenderDigest(WoWCompanionDigest, time(), player, collapsed, show,
        WC.CapturedAt(ForeverScribeDB, player, GetRealmName and GetRealmName()))
    f.header:SetText(header)
    local compact = WC.db.settings.compact
    if compact then rows = WC.CompactRows(rows, WC.view.expanded) end
    f.compactButton:SetText(compact and L.FULL or L.COMPACT)

    local y = 0
    for i, r in ipairs(rows) do
        local row = get_row(f, i)
        row:Show()
        WC.StyleText(row.label)
        row.label:SetText(r.text)
        local h = (row.label.GetStringHeight and row.label:GetStringHeight()) or WC.LINE_HEIGHT
        h = math.max(WC.LINE_HEIGHT * WC.FONT_SIZES[WC.db.settings.fontSize] / WC.FONT_SIZES.normal, h)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, -y)
        row:SetSize(290, h)
        y = y + h
        row.link = (r.item and "item:" .. r.item) or (r.spell and "spell:" .. r.spell) or nil
        row.sectionId = r.id
        local interactive = row.link ~= nil or r.kind == "header" or r.ask ~= nil
        row:EnableMouse(interactive)
        row:SetScript("OnEnter", row.link and show_tooltip or nil)
        row:SetScript("OnLeave", row.link and function() GameTooltip:Hide() end or nil)
        row.ask = r.ask
        row:SetScript("OnClick", function(self, button)
            if button == "RightButton" then
                WC.FillAsk(self)
            elseif r.kind == "header" then
                toggle_section(r.id)
            end
        end)
    end
    for i = #rows + 1, #f.rows do f.rows[i]:Hide() end
    f.plain = WC.RowsText(rows)
    f.content:SetHeight(y)
    f:SetSize(340, compact and math.max(COMPACT_MIN, math.min(FULL_HEIGHT, SCROLL_TOP + SCROLL_BOTTOM + y)) or FULL_HEIGHT)
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
