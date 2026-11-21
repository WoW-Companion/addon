-- WoW Companion: the movable advice panel.

local WC = WoWCompanion

function WC.CreatePanel()
    local f = CreateFrame("Frame", "WoWCompanionPanel", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(340, 320)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
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
    f.title:SetText("WoW Companion")

    f.header = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.header:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -28)
    f.header:SetWidth(300)
    f.header:SetJustifyH("LEFT")

    -- Ask box: text goes only into the SavedVariables queue (see WC.SubmitAsk).
    f.askBox = CreateFrame("EditBox", "WoWCompanionAskBox", f, "InputBoxTemplate")
    f.askBox:SetSize(236, 20)
    f.askBox:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -50)
    f.askBox:SetAutoFocus(false)
    f.askBox:SetMaxLetters(WC.MAX_ASK_LEN)
    f.askBox:SetScript("OnEnterPressed", function() WC.SubmitFromBox() end)
    f.askBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    f.askButton = CreateFrame("Button", "WoWCompanionAskButton", f, "UIPanelButtonTemplate")
    f.askButton:SetSize(54, 22)
    f.askButton:SetPoint("LEFT", f.askBox, "RIGHT", 6, 0)
    f.askButton:SetText("Ask")
    f.askButton:SetScript("OnClick", function() WC.SubmitFromBox() end)

    f.askHint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.askHint:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -74)
    f.askHint:SetWidth(310)
    f.askHint:SetJustifyH("LEFT")
    f.askHint:SetText(WC.ASK_HINT)

    f.scroll = CreateFrame("ScrollFrame", "WoWCompanionPanelScroll", f, "UIPanelScrollFrameTemplate")
    f.scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -104)
    f.scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -32, 12)
    f.content = CreateFrame("Frame", nil, f.scroll)
    f.content:SetSize(290, 1)
    f.scroll:SetScrollChild(f.content)

    f.rows = {}

    f:SetScript("OnShow", function()
        WC.LoadAnswers()
        WC.Refresh()
    end)
    WC.panel = f
    WC.Refresh()
    f:Hide()
end

WC.ASK_HINT = "Your AI client answers after /reload; /reload again to see the answer."

-- Queues the box's text exactly like /ask, then clears the box. Empty input is ignored.
function WC.SubmitFromBox()
    local f = WC.panel
    if not f then return end
    if WC.SubmitAsk(f.askBox:GetText()) then
        f.askBox:SetText("")
        WC.Refresh()
    end
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
    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.label:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.label:SetWidth(290)
    row.label:SetJustifyH("LEFT")
    f.rows[i] = row
    return row
end

-- Display only: shows the item's tooltip while the mouse is over the row.
local function show_item_tooltip(row)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink("item:" .. row.itemId)
    GameTooltip:Show()
end

local function toggle_section(id)
    WC.db.collapsed = type(WC.db.collapsed) == "table" and WC.db.collapsed or {}
    WC.db.collapsed[id] = (not WC.db.collapsed[id]) or nil
    WC.Refresh()
end

-- Re-reads the global digest table (data only) and redraws the panel.
function WC.Refresh()
    local f = WC.panel
    if not f then return end
    local collapsed = type(WC.db.collapsed) == "table" and WC.db.collapsed or {}
    local header, rows = WC.RenderDigest(WoWCompanionDigest, time(), UnitName("player"), collapsed)
    f.header:SetText(header)
    local items, note = WC.MatchAnswers(WC.db, WoWCompanionAnswers)
    for _, r in ipairs(WC.RenderAsks(items, note, time(), collapsed)) do rows[#rows + 1] = r end

    local y = 0
    for i, r in ipairs(rows) do
        local row = get_row(f, i)
        row:Show()
        row.label:SetText(r.text)
        local h = (row.label.GetStringHeight and row.label:GetStringHeight()) or WC.LINE_HEIGHT
        h = math.max(WC.LINE_HEIGHT, h)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, -y)
        row:SetSize(290, h)
        y = y + h
        row.itemId = r.item
        row.sectionId = r.id
        local interactive = r.item ~= nil or r.kind == "header"
        row:EnableMouse(interactive)
        row:SetScript("OnEnter", r.item and show_item_tooltip or nil)
        row:SetScript("OnLeave", r.item and function() GameTooltip:Hide() end or nil)
        row:SetScript("OnClick", r.kind == "header" and function() toggle_section(r.id) end or nil)
    end
    for i = #rows + 1, #f.rows do f.rows[i]:Hide() end
    f.plain = WC.RowsText(rows)
    f.content:SetHeight(y)
    f.scrollRange = math.max(0, y - f.scroll:GetHeight())
    f.scroll:UpdateScrollChildRect()
end

-- Restores the default position and expands every section.
function WC.ResetPanel()
    local f = WC.panel
    if not f then return end
    WC.db.position, WC.db.collapsed = nil, nil
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    WC.Refresh()
end
