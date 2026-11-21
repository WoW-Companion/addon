-- WoW Companion: the movable advice panel.

local WC = WoWCompanion
local L = WC.L

local FULL_HEIGHT, COMPACT_MIN = 320, 150

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
    f.askButton:SetText(L.ASK)
    f.askButton:SetScript("OnClick", function() WC.SubmitFromBox() end)

    f.askHint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.askHint:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -74)
    f.askHint:SetWidth(250)
    f.askHint:SetJustifyH("LEFT")
    f.askHint:SetText(WC.ASK_HINT)

    local function button(name, label, w, x, y, fn)
        local b = CreateFrame("Button", name, f, "UIPanelButtonTemplate")
        b:SetSize(w, 22)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
        b:SetText(label)
        b:SetScript("OnClick", fn)
        return b
    end
    -- History controls: all of them only change what the panel shows or this character's saved list.
    f.histButton = button("WoWCompanionHistoryButton", L.HISTORY, 64, 264, -70, function()
        WC.ShowHistory(not WC.view.history, false)
    end)
    f.prevButton = button("WoWCompanionHistoryPrev", L.PREV, 50, 14, -98, function() WC.HistoryPage(-1) end)
    f.nextButton = button("WoWCompanionHistoryNext", L.NEXT, 50, 68, -98, function() WC.HistoryPage(1) end)
    f.clearButton = button("WoWCompanionHistoryClear", L.CLEAR, 50, 122, -98, function() WC.RequestClearHistory() end)
    f.reaskButton = button("WoWCompanionHistoryReask", L.REASK, 64, 176, -98, function() WC.ReaskSelected() end)
    f.confirmButton = button("WoWCompanionHistoryConfirm", L.CONFIRM, 64, 14, -98, function() WC.ConfirmClearHistory() end)
    f.cancelButton = button("WoWCompanionHistoryCancel", L.CANCEL, 64, 82, -98, function() WC.CancelClearHistory() end)

    -- Read-only view of the selected answer: select the text and copy it with Ctrl+C.
    f.copyBox = CreateFrame("EditBox", "WoWCompanionCopyBox", f, "InputBoxTemplate")
    f.copyBox:SetSize(300, 20)
    f.copyBox:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 20, 14)
    f.copyBox:SetAutoFocus(false)
    f.copyBox:SetScript("OnTextChanged", function(self, user)
        if user then self:SetText(self.copyText or "") end
    end)
    f.copyBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.copyBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)

    -- Read-only view of the selected question, above the answer box, for copying.
    f.questionBox = CreateFrame("EditBox", "WoWCompanionQuestionBox", f, "InputBoxTemplate")
    f.questionBox:SetSize(300, 20)
    f.questionBox:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 20, 38)
    f.questionBox:SetAutoFocus(false)
    f.questionBox:SetScript("OnTextChanged", function(self, user)
        if user then self:SetText(self.copyText or "") end
    end)
    f.questionBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.questionBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)

    f.scroll = CreateFrame("ScrollFrame", "WoWCompanionPanelScroll", f, "UIPanelScrollFrameTemplate")
    f.scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -104)
    f.scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -32, 12)
    f.content = CreateFrame("Frame", f.scroll)
    f.content:SetSize(290, 1)
    f.scroll:SetScrollChild(f.content)

    f.rows = {}

    f.compactButton = button("WoWCompanionCompactButton", L.COMPACT, 60, 8, -3, function()
        WC.SetCompact(not WC.db.settings.compact)
    end)
    f.compactButton:SetHeight(18)

    -- Keyboard handling exists only in the history view, and a key we do not use is passed on.
    f:SetScript("OnKeyDown", function(self, key)
        self:SetPropagateKeyboardInput(not WC.HistoryKey(key))
    end)
    f:SetScript("OnHide", function() WC.view.expanded = {} end)

    f:SetScript("OnShow", function()
        WC.LoadAnswers()
        WC.Refresh()
    end)
    WC.panel = f
    WC.Refresh()
    f:Hide()
end

WC.ASK_HINT = L.ASK_HINT

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
    row = CreateFrame("Button", f.content)
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
    if WC.db.settings.compact and not WC.view.history then
        WC.view.expanded[id] = (not WC.view.expanded[id]) or nil
        WC.Refresh()
        return
    end
    WC.db.collapsed = type(WC.db.collapsed) == "table" and WC.db.collapsed or {}
    WC.db.collapsed[id] = (not WC.db.collapsed[id]) or nil
    WC.Refresh()
end

local function set_shown(b, v) if v then b:Show() else b:Hide() end end

-- Shows the history controls only in the history view; entry is the selected one, if any.
-- Hidden sections (settings) free their space: the rows below move up.
function WC.UpdateHistoryUI(f, entry)
    local on, confirming = WC.view.history, WC.view.confirming
    local ask, hist = WC.SectionShown("ask"), WC.SectionShown("history")
    set_shown(f.askBox, ask)
    set_shown(f.askButton, ask)
    set_shown(f.askHint, ask)
    set_shown(f.histButton, hist)
    f.histButton:SetPoint("TOPLEFT", f, "TOPLEFT", 264, ask and -70 or -46)
    local rowY = ask and -98 or -46
    local top = ask and (on and -126 or -104) or (hist and (on and -74 or -72) or -50)
    for _, b in ipairs({ { f.prevButton, 14 }, { f.nextButton, 68 }, { f.clearButton, 122 },
                         { f.confirmButton, 14 }, { f.cancelButton, 82 } }) do
        b[1]:SetPoint("TOPLEFT", f, "TOPLEFT", b[2], rowY)
    end
    set_shown(f.prevButton, on and entry and not confirming)
    set_shown(f.nextButton, on and entry and not confirming)
    set_shown(f.clearButton, on and entry and not confirming)
    set_shown(f.confirmButton, on and confirming)
    set_shown(f.cancelButton, on and confirming)
    set_shown(f.reaskButton, on and entry and not confirming)
    set_shown(f.copyBox, on and entry)
    set_shown(f.questionBox, on and entry)
    f.histButton:SetText(on and L.BACK or L.HISTORY)
    f.scrollTop, f.scrollBottom = -top, (on and entry) and 64 or 12
    f.scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 14, top)
    f.scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -32, f.scrollBottom)
    f:EnableKeyboard(on and true or false)
    f.copyBox.copyText = entry and WC.HistoryCopyText(entry) or ""
    f.copyBox:SetText(f.copyBox.copyText)
    f.questionBox.copyText = entry and tostring(entry.question or "") or ""
    f.questionBox:SetText(f.questionBox.copyText)
end

-- Right-click on a digest line: puts a template question in the Ask box and focuses it.
-- Display only: nothing is queued until the player presses Enter or Ask.
function WC.FillAsk(row)
    local f = WC.panel
    local q = f and WC.AskTemplate(row)
    if not q or not f.askBox:IsShown() then return end
    f.askBox:SetText(q:sub(1, WC.MAX_ASK_LEN))
    f.askBox:SetFocus()
end

-- Re-reads the global digest table (data only) and redraws the panel.
function WC.Refresh()
    WC.RefreshTracker()
    local f = WC.panel
    if not f then return end
    WC.StyleText(f.title)
    WC.StyleText(f.header)
    WC.StyleText(f.askHint, -2)
    local collapsed = type(WC.db.collapsed) == "table" and WC.db.collapsed or {}
    local player = UnitName("player")
    local show = WC.db.settings.show
    if not WC.SectionShown("history") then WC.view.history = false end
    local header, rows = WC.RenderDigest(WoWCompanionDigest, time(), player, collapsed, show,
        WC.CapturedAt(ForeverScribeDB, player, GetRealmName and GetRealmName()))
    f.header:SetText(header)
    local items, note = WC.MatchAnswers(WC.db, WoWCompanionAnswers)
    if WC.view.history then
        local list = WC.HistoryList(WC.db, player)
        local index = #list > 0 and WC.HistoryIndex(#list) or 0
        WC.view.index = index > 0 and index or nil
        rows = WC.RenderHistory(list, index, time(), WC.view.confirming)
        WC.UpdateHistoryUI(f, list[index])
    else
        if WC.SectionShown("ask") then
            for _, r in ipairs(WC.RenderAsks(items, note, time(), collapsed)) do rows[#rows + 1] = r end
        end
        WC.UpdateHistoryUI(f, nil)
    end

    local compact = WC.db.settings.compact
    if compact and not WC.view.history then rows = WC.CompactRows(rows, WC.view.expanded) end
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
    f:SetSize(340, compact and math.max(COMPACT_MIN, math.min(FULL_HEIGHT, f.scrollTop + f.scrollBottom + y)) or FULL_HEIGHT)
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
