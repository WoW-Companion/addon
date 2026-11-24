-- WoW Companion: the plan in the world map's right-hand panel, behind our side tab.
-- Approach: the client has no public way to add a content frame to its quest panel, so by default a child frame of
-- the panel (our own, never a client frame) is shown over the panel's content area while our tab is selected, and
-- hidden the moment another tab or the map's own controls change the view. If a client ever offers
-- QuestMapFrame:AddContentFrame + SetDisplayMode, that public pair is used instead ("native").
-- Display only: nothing here changes a client frame; every client call is guarded and unprotected.

local WC = WoWCompanion
local L = WC.L

local PAD, TOP_INSET, SCROLL_W = 10, 12, 26
local ROW_MIN, ROW_PAD_T, ROW_PAD_B, ROW_GAP = 34, 6, 6, 2
local LINE_TITLE, LINE_SUB = 13, 11 -- a line's height when the client cannot measure the text
local SEL = { 0.45, 0.7, 1 } -- the selected step's accent (the current step stays gold)
local GOLD, DIM = { 1, 0.82, 0 }, { 0.55, 0.55, 0.55 }
WC.TAB_MODE = "WoWCompanionPlan"

-- Session state: whether our tab is selected, the last tab the player used (nil until one is), the zone filter the
-- player flipped (nil = follow the setting) and whether the Completed group is open.
WC.panelState = { selected = false, lastTab = nil, allZones = nil, zoneSeen = nil, doneOpen = false, selectedStep = nil }

-- ---------------------------------------------------------------- pure model

-- The sub-line under a row's title: the pick-up or turn-in giver, or the live objective.
function WC.StepSubLine(step)
    local detail = WC.PlanDetail(step)
    -- a row with no objective progress to show carries its entry's short why instead
    local why = WC.Setting("showWhy") and WC.QuestWhy(step.questID) or nil
    if step.kind == "pickup" or step.kind == "turnin" then
        if why then return why end
        local who = detail:gsub("^[Ff]rom%s+", ""):gsub("^[Tt]o%s+", "")
        if who == "" then return step.kind == "pickup" and L.PANEL_PICKUP or L.PANEL_TURNIN end
        return string.format(step.kind == "pickup" and L.PANEL_PICKUP_FROM or L.PANEL_TURNIN_TO, who)
    end
    local live = WC.PlanLiveText(step, detail ~= "" and detail or step.label or "")
    if why and not live:find("%d+/%d+") then return why end
    return live
end

-- A row's title: "[level] Quest title" (the client's title when it has one, else the plan's).
function WC.StepTitle(step)
    local title = (step.questID or 0) > 0 and WC.QuestTitle(step.questID) or nil
    title = title or (step.quest ~= "" and step.quest) or step.label or ""
    if step.level then return string.format("[%d] %s", math.floor(step.level), title) end
    return title
end

local KIND_ICON = { pickup = "pickup", turnin = "turnin", objective = "progress" }

-- The list the panel shows: { rows = {...}, done = {...} }. A row is { step, n, kind, icon, title, sub, isNext, done }.
-- opts: steps, done (set of step numbers), nextStep, mapID, allZones, showDone.
function WC.PanelModel(opts)
    local out = { rows = {}, done = {} }
    for _, s in ipairs(opts.steps or {}) do
        -- a locked follow-up is not an entry of its own: its unlocking turn-in carries a "then:" line instead
        if not WC.StepLocked(s) and (opts.allZones or not opts.mapID or s.map == opts.mapID) then
            local isDone = opts.done and opts.done[s.n] == true
            local row = { step = s, n = s.n, kind = s.kind, icon = KIND_ICON[s.kind] and WC.ICONS[KIND_ICON[s.kind]] or nil,
                title = WC.StepTitle(s), sub = WC.StepSubLine(s), isNext = opts.nextStep == s, done = isDone }
            if s.kind == "turnin" and not isDone then
                row.thenText = WC.ThenLine(s.questID)
                local info = row.thenText and WC.ThenInfo(s.questID)
                row.thenTip = info and string.format(L.UNLOCKS_TIP, (WC.StepTitle(s):gsub("^%[%d+%] ", ""))) or nil
            end
            row.isNew = not isDone and WC.StepIsNew(s) or false
            if isDone then
                if opts.showDone ~= false then out.done[#out.done + 1] = row end
            else
                out.rows[#out.rows + 1] = row
            end
        end
    end
    return out
end

-- The summed straight legs of the steps in yards, or nil when any leg's map has no real size from the client (the
-- header's "125 yd W" uses the same WC.PlanDistance and WC.MapYards).
function WC.PlanYards(steps)
    local total, prev = 0, nil
    for _, s in ipairs(steps or {}) do
        if prev and prev.map == s.map then
            local w, h
            if C_Map and C_Map.GetMapWorldSize then w, h = C_Map.GetMapWorldSize(s.map) end
            if not (type(w) == "number" and type(h) == "number" and w > 0 and h > 0) then return nil end
            local mw, mh = WC.MapYards(s.map)
            total = total + (WC.PlanDistance(prev.x, prev.y, s.x, s.y, mw, mh))
        end
        prev = s
    end
    return total
end

-- "23 stops", plus " · about 148 yd" only when the distance is known in yards.
function WC.PanelFooter(steps)
    local n = #(steps or {})
    local yd = WC.PlanYards(steps)
    if yd and yd > 0 then return string.format(L.PANEL_FOOTER_YD, n, math.floor(yd + 0.5)) end
    return string.format(L.PANEL_FOOTER, n)
end

-- A row's height from its measured lines (title, sub-line, "then:" line); a 0 line takes no room.
function WC.RowHeight(titleH, subH, thenH)
    local h = ROW_PAD_T + math.max(titleH or 0, 0) + ROW_PAD_B
    if (subH or 0) > 0 then h = h + ROW_GAP + subH end
    if (thenH or 0) > 0 then h = h + ROW_GAP + thenH end
    return math.max(ROW_MIN, h)
end

-- The header's strings: step counter, distance and direction to the next step, and the advice time.
function WC.PanelHeader()
    local p = WC.plan
    if not p then return { title = L.ADDON_NAME, step = "", dist = "", advice = "" } end
    local done, total = WC.PlanCounts()
    local step = WC.PlanNext()
    local h = { title = L.ADDON_NAME, advice = string.format(L.PANEL_ADVICE_TIME, WC.FormatClock(p.generated or 0)) }
    if not step then h.step, h.dist = string.format(L.PLAN_DONE, total), "" return h end
    h.step = string.format(L.PANEL_STEP, WC.StepNumber(step), total)
    local mapID, px, py = WC.PlayerPos()
    if mapID == step.map and px then
        local d, dir = WC.PlanDistance(px, py, step.x, step.y, WC.MapYards(mapID))
        h.dist = string.format(L.PANEL_DISTANCE, math.floor(d + 0.5), dir)
    else
        h.dist = L.PANEL_ELSEWHERE
    end
    return h
end

-- The map the client currently shows, or nil.
local function shown_map()
    if WorldMapFrame and WorldMapFrame.GetMapID then
        local ok, id = pcall(WorldMapFrame.GetMapID, WorldMapFrame)
        if ok and tonumber(id) then return id end
    end
end

-- True when the list covers every zone: the player's choice this session, else the setting.
function WC.PanelAllZones()
    local st = WC.panelState
    local setting = WC.Setting("panelZone")
    if st.zoneSeen ~= setting then st.zoneSeen, st.allZones = setting, nil end
    if st.allZones ~= nil then return st.allZones end
    return setting == "all"
end

-- ---------------------------------------------------------------- row clicks

-- Centres the world map on a step and pings its badge. Only the map's public SetMapID and the scroll container's
-- SetPanTarget are used, each guarded.
function WC.CenterOnStep(step)
    local map = WorldMapFrame
    if map then
        if map.SetMapID and shown_map() ~= step.map then pcall(map.SetMapID, map, step.map) end
        local sc = map.ScrollContainer
        if sc and type(sc.SetPanTarget) == "function" then pcall(sc.SetPanTarget, sc, step.x / 100, step.y / 100) end
    end
    if (step.questID or 0) > 0 then WC.PulseQuests({ [step.questID] = true }, 3) end
end

-- The selected step (its row and map badge stay highlighted until another is clicked, the same one again, or the map
-- closes). Only the one step is selected, never the badge group it shares a spot with.
function WC.SelectStep(step)
    local st = WC.panelState
    local n = step and step.n or nil
    if n == nil or st.selectedStep == n then st.selectedStep = nil else st.selectedStep = n end
    WC.ApplySelection()
    return st.selectedStep
end

function WC.ClearSelectedStep()
    if WC.panelState.selectedStep ~= nil then
        WC.panelState.selectedStep = nil
        WC.ApplySelection()
    end
end

-- Paints the selected look on the panel's rows and map badges, without a redraw.
function WC.ApplySelection()
    local f = WC.mapPanel
    if f then
        for _, r in ipairs(f.rows) do
            if r.selBg then WC.ApplyRowSelection(r) end
        end
    end
    if WC.ApplyMapSelection then WC.ApplyMapSelection() end
end

function WC.ApplyRowSelection(r)
    local on = r.step ~= nil and r:IsShown() and r.step.n == WC.panelState.selectedStep
    r.selBg:SetShown(on)
    r.selBar:SetShown(on)
    r.badge.selRing:SetShown(on)
end

-- A click on a row: left selects the step and centres the map on it, right opens the detail card of its quest.
function WC.PanelRowClick(step, button)
    if button == "RightButton" then
        if (step.questID or 0) <= 0 then return "none" end
        WC.OpenCard(WC.MakeEntry("quest", "mp" .. step.questID, {}, { quest = step.questID, title = step.quest, level = step.level }))
        return "card"
    end
    WC.SelectStep(step)
    WC.CenterOnStep(step)
    return "center"
end

-- ---------------------------------------------------------------- frame

local function mp() return WC.mapPanel end

-- One row frame, built once and reused.
local function make_row(f, i)
    local r = CreateFrame("Button", nil, f.child)
    r:SetSize(f.rowWidth, ROW_MIN)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.hl = r:CreateTexture(nil, "BACKGROUND")
    r.hl:SetAllPoints()
    r.hl:Hide()
    r.nextBg = r:CreateTexture(nil, "BACKGROUND")
    r.nextBg:SetAllPoints()
    r.nextBg:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.12)
    r.selBg = r:CreateTexture(nil, "BACKGROUND")
    r.selBg:SetAllPoints()
    r.selBg:SetColorTexture(SEL[1], SEL[2], SEL[3], 0.2)
    r.selBg:Hide()
    r.selBar = r:CreateTexture(nil, "ARTWORK")
    r.selBar:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
    r.selBar:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
    r.selBar:SetWidth(3)
    r.selBar:SetColorTexture(SEL[1], SEL[2], SEL[3], 1)
    r.selBar:Hide()
    r.badge = CreateFrame("Frame", nil, r)
    r.badge:SetSize(24, 24)
    r.badge:SetPoint("LEFT", r, "LEFT", 2, 0)
    WC.BadgeParts(r.badge, 2, 9, "GameFontNormalSmall", 3)
    r.badge.glow:SetSize(30, 30)
    r.badge.selRing = r.badge:CreateTexture(nil, "BACKGROUND")
    r.badge.selRing:SetTexture(WC.DISC or "Interface\\COMMON\\Indicator-Gray")
    r.badge.selRing:SetPoint("TOPLEFT", r.badge, "TOPLEFT", -3, 3)
    r.badge.selRing:SetPoint("BOTTOMRIGHT", r.badge, "BOTTOMRIGHT", 3, -3)
    r.badge.selRing:SetVertexColor(SEL[1], SEL[2], SEL[3], 1)
    r.badge.selRing:Hide()
    r.badge.notchBg:Hide()
    r.badge.mark:Hide()
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(14, 14)
    r.icon:SetPoint("LEFT", r.badge, "RIGHT", 4, 0)
    r.label = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.label:SetPoint("TOPLEFT", r, "TOPLEFT", 48, -ROW_PAD_T)
    r.label:SetJustifyH("LEFT")
    r.sub = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.sub:SetPoint("TOPLEFT", r.label, "BOTTOMLEFT", 0, -ROW_GAP)
    r.sub:SetJustifyH("LEFT")
    r.thenLine = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.thenLine:SetPoint("TOPLEFT", r.sub, "BOTTOMLEFT", 0, -ROW_GAP)
    r.thenLine:SetJustifyH("LEFT")
    for _, fs in ipairs({ r.label, r.sub, r.thenLine }) do
        if fs.SetWordWrap then fs:SetWordWrap(true) end
    end
    r.newTag = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.newTag:SetPoint("TOPRIGHT", r, "TOPRIGHT", -8, -ROW_PAD_T)
    r.newTag:SetTextColor(0.25, 0.9, 0.25)
    r.newTag:SetText(L.NEW_TAG)
    r.check = r:CreateTexture(nil, "OVERLAY")
    r.check:SetSize(14, 14)
    r.check:SetPoint("RIGHT", r, "RIGHT", -8, 0)
    r.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    r.owner = f
    r:SetScript("OnEnter", function(self)
        if self.group then WC.HoverEnterRow(self) end
        if self.newTag:IsShown() and self.quest and WC.ClearNew(self.quest) then self.newTag:Hide() end -- hovering dismisses "New"
        if self.thenTip and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.thenTip, 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    r:SetScript("OnLeave", function(self)
        WC.HoverLeaveRow()
        if self.thenTip and GameTooltip then GameTooltip:Hide() end
    end)
    r:SetScript("OnClick", function(self, button) if self.step then WC.PanelRowClick(self.step, button) end end)
    f.rows[i] = r
    return r
end

-- Fills one row frame from a model row and puts it at y.
local function fill_row(f, i, m, y)
    local r = f.rows[i] or make_row(f, i)
    r.step, r.top = m.step, y
    r.thenTip = m.thenTip
    r.thenLine:SetText(m.thenText or "")
    r.thenLine:SetShown(m.thenText ~= nil)
    r.newTag:SetShown(m.isNew == true)
    r.quest = (m.step.questID or 0) > 0 and m.step.questID or nil
    r.group = r.quest and ("mp" .. r.quest) or nil
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", f.child, "TOPLEFT", 0, -y)
    r.badge.num:SetText(tostring(m.n))
    r.badge.num:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    if m.icon then r.icon:SetTexture(m.icon) r.icon:Show() else r.icon:Hide() end
    local tw = math.max(60, f.rowWidth - 48 - 26) -- text clears the badge on the left and the check / New tag on the right
    for _, fs in ipairs({ r.label, r.sub, r.thenLine }) do fs:SetWidth(tw) end
    r.label:SetText(m.title)
    r.sub:SetText(m.sub or "")
    local function line_h(fs, shown, fallback)
        if not shown then return 0 end
        local mh = fs.GetStringHeight and fs:GetStringHeight()
        return (type(mh) == "number" and mh > 0) and mh or fallback
    end
    local h = WC.RowHeight(line_h(r.label, true, LINE_TITLE), line_h(r.sub, (m.sub or "") ~= "", LINE_SUB),
        line_h(r.thenLine, m.thenText ~= nil, LINE_SUB))
    r.hh = h
    r:SetSize(f.rowWidth, h)
    r.thenLine:ClearAllPoints()
    r.thenLine:SetPoint("TOPLEFT", (m.sub or "") ~= "" and r.sub or r.label, "BOTTOMLEFT", 0, -ROW_GAP)
    r.nextBg:SetShown(m.isNext)
    r.check:SetShown(m.done)
    r.baseColor = m.done and DIM or (m.isNext and { 1, 0.95, 0.6 } or GOLD)
    r.label:SetTextColor(r.baseColor[1], r.baseColor[2], r.baseColor[3])
    r.sub:SetTextColor(m.done and DIM[1] or 0.85, m.done and DIM[2] or 0.85, m.done and DIM[3] or 0.85)
    r:Show()
    WC.ApplyRowHover(r)
    WC.ApplyRowSelection(r)
    return r
end

-- Redraws the list and header from the live plan. A no-op unless our tab is selected.
function WC.RefreshMapPanel()
    local f, st = mp(), WC.panelState
    if not (f and st.selected and f:IsShown()) then return end
    WC.UpdateMapPanelHeader()
    local p = WC.plan
    local all = WC.PanelAllZones()
    f.zoneBtn:SetText(all and L.PANEL_ALL_ZONES or L.PANEL_THIS_MAP)
    local fs = f.zoneBtn.GetFontString and f.zoneBtn:GetFontString()
    local tw = fs and fs.GetStringWidth and fs:GetStringWidth()
    f.zoneBtn:SetSize((type(tw) == "number" and tw > 0) and (tw + 24) or 90, 22) -- sized to its text, like the client's small buttons
    local sw = f.scroll.GetWidth and f.scroll:GetWidth() or 0
    if sw and sw > 0 then f.rowWidth = math.floor(sw) end
    f.child:SetWidth(f.rowWidth)
    local used = 0
    local y = 0
    local function put(m)
        used = used + 1
        y = y + fill_row(f, used, m, y).hh
    end
    if p then
        local model = WC.PanelModel({ steps = p.steps, done = p.done, nextStep = WC.PlanNext(), mapID = shown_map(),
            allZones = all, showDone = WC.Setting("panelShowDone") })
        for _, m in ipairs(model.rows) do put(m) end
        f.empty:SetShown(#model.rows == 0 and #model.done == 0)
        f.empty:SetText(L.PANEL_EMPTY)
        f.doneHead:SetShown(#model.done > 0)
        if #model.done > 0 then
            f.doneHead:SetText(string.format(L.PANEL_COMPLETED, #model.done))
            f.doneHead:ClearAllPoints()
            f.doneHead:SetPoint("TOPLEFT", f.child, "TOPLEFT", 4, -y - 4)
            y = y + 26
            if st.doneOpen then for _, m in ipairs(model.done) do put(m) end end
        end
        f.footer:SetText(WC.PanelFooter(p.steps))
    else
        f.empty:SetText(L.PANEL_NO_PLAN)
        f.empty:Show()
        f.doneHead:Hide()
        f.footer:SetText("")
    end
    for i = used + 1, #f.rows do f.rows[i]:Hide() end
    f.child:SetHeight(math.max(y + 8, 1))
    f.scrollRange = math.max(0, y + 8 - (f.scroll:GetHeight() or 0))
    if WC.HoverCheck then WC.HoverCheck() end
end

-- The header strings (distance changes as the player walks): called from the plan's tick.
function WC.UpdateMapPanelHeader()
    local f = mp()
    if not (f and WC.panelState.selected) then return end
    local h = WC.PanelHeader()
    f.title:SetText(h.title)
    f.stepText:SetText(h.step .. (h.dist ~= "" and (" · " .. h.dist) or ""))
    f.advice:SetText(h.advice)
    f.eye:SetAlpha(WC.PlanShownOnMap() and 1 or 0.4)
end

-- Coalesces redraws from bursts of map and quest events into one a moment later.
local pending = false
function WC.RefreshMapPanelSoon()
    if not (WC.mapPanel and WC.panelState.selected) then return end
    if not (C_Timer and C_Timer.After) then return WC.RefreshMapPanel() end
    if pending then return end
    pending = true
    C_Timer.After(0.1, function() pending = false; WC.RefreshMapPanel() end)
end

-- The client's content-area inset: the frame the client's own quest list is anchored to, inside the panel's border.
-- QuestMapFrame.ContentsAnchor when the client has it, else whatever the quest list's first anchor points at (when
-- that is not the panel itself), else the panel. Only client frames; nil without a panel.
function WC.MapInset()
    local col = QuestMapFrame
    if not col then return nil end
    local a = col.ContentsAnchor
    if type(a) == "table" and a.GetObjectType then return a end
    local q = QuestScrollFrame
    if type(q) == "table" and q.GetPoint then
        local _, rel = q:GetPoint(1)
        if type(rel) == "table" and rel ~= col and rel ~= q and rel ~= UIParent and rel.GetObjectType then return rel end
    end
    return col
end

-- The client's own quest list frame, whichever of QuestMapFrame.QuestsFrame or its scroll frame exists and is shown.
function WC.QuestListFrame()
    local col = QuestMapFrame
    if type(col) ~= "table" then return nil end
    local q = col.QuestsFrame
    if type(q) ~= "table" then return nil end
    local cands = { q, q.ScrollFrame }
    for _, c in ipairs(cands) do
        if type(c) == "table" and c.IsShown and c:IsShown() and c.GetObjectType then return c end
    end
    return nil
end

WC.PANEL_TOP_FALLBACK = 32 -- pixels below the quest-map frame's top when the client's quest list cannot be found

-- The client's own quest list frame wherever it is (shown or not): its rect is the content area inside the side
-- panel's inset border, and its anchors stay set while another tab is up.
local function quest_list_any()
    local col = QuestMapFrame
    if type(col) ~= "table" then return nil end
    local q = col.QuestsFrame
    for _, c in ipairs({ type(q) == "table" and q or false, type(q) == "table" and q.ScrollFrame or false, type(QuestScrollFrame) == "table" and QuestScrollFrame or false }) do
        if type(c) == "table" and c.GetObjectType and c.GetNumPoints and c:GetNumPoints() > 0 then return c end
    end
    return nil
end

-- Fits the panel exactly over the content area inside the side panel's inset border (the client's content anchor, else
-- the rect of its own quest list), so the border frames our plan the way it frames the quest list and crosses none of
-- our content; the title row is inside that rect. Only anchors of our own frame are set. Without either, a fixed
-- margin inside the quest-map frame.
function WC.PlaceMapPanel()
    local f = WC.mapPanel
    if not f then return end
    local col = QuestMapFrame
    if not col then return end
    local anchor = type(col) == "table" and col.ContentsAnchor
    local rect = (type(anchor) == "table" and anchor.GetObjectType) and anchor or quest_list_any()
    f:ClearAllPoints()
    if rect then
        f:SetPoint("TOPLEFT", rect, "TOPLEFT", 0, 0)
        f:SetPoint("BOTTOMRIGHT", rect, "BOTTOMRIGHT", 0, 0)
        f.top, f.inset = rect, rect
        return
    end
    f:SetPoint("TOPLEFT", col, "TOPLEFT", 9, -WC.PANEL_TOP_FALLBACK)
    f:SetPoint("BOTTOMRIGHT", col, "BOTTOMRIGHT", -9, 9)
    f.top, f.inset = col, WC.MapInset()
end

local function create_frame()
    local col = QuestMapFrame
    if WC.mapPanel or not col then return WC.mapPanel end
    local ok, f = pcall(CreateFrame, "Frame", "WoWCompanionMapPanel", col)
    if not ok or type(f) ~= "table" then return end
    f.rowWidth = 270
    f.rows = {}
    WC.mapPanel = f
    WC.PlaceMapPanel()
    if f.SetFrameLevel and col.GetFrameLevel then f:SetFrameLevel((col:GetFrameLevel() or 1) + 20) end
    f:EnableMouse(true) -- swallows clicks so they never reach the quest list underneath
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0.06, 0.05, 0.04, 1)
    -- a plain header line in the client's header font, as the client shows the zone name; no border or title art of ours
    f.title = f:CreateFontString(nil, "OVERLAY", _G.QuestFont_Huge and "QuestFont_Huge" or "GameFontNormalLarge")
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + 4, -TOP_INSET)
    f.stepText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.stepText:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -5)
    f.advice = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.advice:SetPoint("TOPLEFT", f.stepText, "BOTTOMLEFT", 0, -4)
    f.eye = CreateFrame("Button", "WoWCompanionMapPanelEye", f)
    f.eye:SetSize(22, 22)
    f.eye:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD - SCROLL_W, -TOP_INSET + 2)
    f.eye.tex = f.eye:CreateTexture(nil, "ARTWORK")
    f.eye.tex:SetAllPoints()
    f.eye.tex:SetTexture("Interface\\Icons\\INV_Misc_Eye_01")
    f.eye:SetScript("OnClick", function() WC.TogglePlan("map"); WC.UpdateMapPanelHeader() end)
    f.eye:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(L.TIP_PANEL_EYE)
        GameTooltip:Show()
    end)
    f.eye:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.zoneBtn = CreateFrame("Button", "WoWCompanionMapPanelZone", f, "UIPanelButtonTemplate")
    f.zoneBtn:SetSize(90, 22)
    f.zoneBtn:SetPoint("TOPLEFT", f.advice, "BOTTOMLEFT", 0, -6)
    f.zoneBtn:SetScript("OnClick", function() WC.ToggleMapPanelZones() end)
    f.scroll = CreateFrame("ScrollFrame", "WoWCompanionMapPanelScroll", f, "UIPanelScrollFrameTemplate")
    f.scroll:SetPoint("TOPLEFT", f.zoneBtn, "BOTTOMLEFT", -4, -6)
    f.scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD - SCROLL_W, 40)
    f.child = CreateFrame("Frame", nil, f.scroll)
    f.child:SetSize(f.rowWidth, 1)
    f.scroll:SetScrollChild(f.child)
    f.empty = f.child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.empty:SetPoint("TOPLEFT", f.child, "TOPLEFT", 4, -8)
    f.empty:SetWidth(f.rowWidth - 8)
    f.empty:SetJustifyH("LEFT")
    f.doneHead = CreateFrame("Button", "WoWCompanionMapPanelDone", f.child)
    f.doneHead:SetSize(f.rowWidth - 8, 20)
    f.doneHead:SetNormalFontObject("GameFontNormal")
    f.doneHead:SetScript("OnClick", function() WC.panelState.doneOpen = not WC.panelState.doneOpen; WC.RefreshMapPanel() end)
    f.footer = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.footer:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD + 4, 18)
    f:Hide()
    WC.mapPanel = f
    return f
end

-- Flips the zone filter for the session (the setting itself is the starting point).
function WC.ToggleMapPanelZones()
    local st = WC.panelState
    st.allZones = not WC.PanelAllZones()
    WC.RefreshMapPanel()
end

-- ---------------------------------------------------------------- tab select and deselect

-- "native" when the client offers the public content-frame pair, else "overlay".
function WC.PanelBackend()
    local col = QuestMapFrame
    if col and type(col.AddContentFrame) == "function" and type(col.SetDisplayMode) == "function" then return "native" end
    return "overlay"
end

-- ---------------------------------------------------------------- the side panel (the quest log's own)

local function in_combat()
    return (InCombatLockdown and InCombatLockdown()) or WC.inCombat == true
end

-- "small" or "full": the client's own maximized state of the world map ("full" when it cannot say).
function WC.MapSizeMode()
    local map = WorldMapFrame
    if type(map) ~= "table" then return "full" end
    local v = map.isMaximized
    if type(map.IsMaximized) == "function" then
        local ok, r = pcall(map.IsMaximized, map)
        if ok then v = r end
    end
    if v == false then return "small" end
    return "full"
end

-- True while the quest-log side panel is open.
function WC.SidePanelOpen()
    local col = QuestMapFrame
    return type(col) == "table" and col.IsShown and col:IsShown() and true or false
end

-- Calls the client's own public open or close of the quest log's side panel (the one its quest-log key uses): the
-- map's HandleUserAction method, else the global QuestMapFrame function. Unprotected and guarded; false when this
-- build offers neither.
local SIDE_CALLS = {
    open = { { "method", "HandleUserActionOpenQuestLog" }, { "global", "QuestMapFrame_Open" } },
    close = { { "method", "HandleUserActionCloseQuestLog" }, { "global", "QuestMapFrame_Close" } },
}
local function client_side_call(which)
    for _, c in ipairs(SIDE_CALLS[which]) do
        local fn, self_ = nil, nil
        if c[1] == "method" and type(WorldMapFrame) == "table" and type(WorldMapFrame[c[2]]) == "function" then
            fn, self_ = WorldMapFrame[c[2]], WorldMapFrame
        elseif c[1] == "global" and type(_G[c[2]]) == "function" then
            fn = _G[c[2]]
        end
        if fn then
            if pcall(fn, self_) then return true end
        end
    end
    return false
end

-- Opens the side panel for our plan on the small map; remembers that we did. In combat it waits until combat ends.
function WC.OpenSidePanel()
    local st = WC.panelState
    st.wantClose = nil
    if WC.SidePanelOpen() then return "open" end
    if in_combat() then st.wantOpen = true return "deferred" end
    st.wantOpen = nil
    st.opening = true
    local ok = client_side_call("open")
    if not ok and QuestMapFrame and QuestMapFrame.Show then pcall(QuestMapFrame.Show, QuestMapFrame) end -- a build with no open call
    st.opening = false
    if WC.SidePanelOpen() then st.weOpened = true end
    return "opened"
end

-- Closes the side panel only if we opened it.
function WC.CloseSidePanel()
    local st = WC.panelState
    st.wantOpen = nil
    if not st.weOpened then return "kept" end
    if not WC.SidePanelOpen() then st.weOpened = false return "kept" end
    if in_combat() then st.wantClose = true return "deferred" end
    st.wantClose = nil
    st.opening = true
    local ok = client_side_call("close")
    if not ok and QuestMapFrame and QuestMapFrame.Hide then pcall(QuestMapFrame.Hide, QuestMapFrame) end
    st.opening = false
    st.weOpened = false
    return "closed"
end

-- Combat ended: the open or close that was waiting runs now.
function WC.SidePanelCombatEnded()
    local st = WC.panelState
    if st.wantOpen and st.selected then
        WC.OpenSidePanel()
        if st.selected then WC.SelectMapPanel(true) end
    elseif st.wantClose and not st.selected then
        WC.CloseSidePanel()
    end
    st.wantOpen, st.wantClose = nil, nil
    if WC.PlaceMapTab then WC.PlaceMapTab() end
end

-- Selects or deselects our tab's panel. by == "client" means another tab did it, so nothing is asked of the client.
function WC.SelectMapPanel(on, by)
    local st = WC.panelState
    local f = create_frame()
    if not f then return false end
    on = on and true or false
    if on == st.selected and f:IsShown() == on and not (on and st.wantOpen) then return on end
    local native = WC.PanelBackend() == "native"
    if native and not f.registered then
        f.registered = pcall(QuestMapFrame.AddContentFrame, QuestMapFrame, f, WC.TAB_MODE) and true or false
        native = f.registered
    end
    if on and WC.MapSizeMode() == "small" then
        WC.OpenSidePanel() -- the client's own way, so the map extends to the right as with the quest-log key
    elseif on and QuestMapFrame and QuestMapFrame.IsShown and not QuestMapFrame:IsShown() and QuestMapFrame.Show then
        pcall(QuestMapFrame.Show, QuestMapFrame) -- the full-size map: a collapsed quest log opens first
    end
    st.selected = on
    st.lastTab = on and "plan" or "other"
    if native and by ~= "client" then
        if on then
            st.prevMode = QuestMapFrame.displayMode
            st.opening = true
            pcall(QuestMapFrame.SetDisplayMode, QuestMapFrame, WC.TAB_MODE)
            st.opening = false
        elseif st.prevMode ~= nil then
            pcall(QuestMapFrame.SetDisplayMode, QuestMapFrame, st.prevMode)
        end
    end
    if not native then f:SetShown(on) end
    if on then WC.RefreshMapPanel() end
    if not on then
        if by ~= "client" and WC.MapSizeMode() == "small" then WC.CloseSidePanel() else st.weOpened = false end
    end
    if WC.PlaceMapPanel then WC.PlaceMapPanel() end
    WC.RefreshMapTab()
    if WC.PlaceMapTab then WC.PlaceMapTab() end
    if WC.RecordMapGeometry then WC.RecordMapGeometry() end
    return on
end

function WC.ToggleMapPanel()
    return WC.SelectMapPanel(not WC.panelState.selected)
end

-- On map open: the session's last tab wins; with none yet, the open-on-our-tab setting decides.
function WC.ApplyMapTabState()
    if WC.mapButtonMode ~= "tab" then return end
    local st = WC.panelState
    local want = st.lastTab == "plan" or (st.lastTab == nil and WC.Setting("panelOpenOnTab") == true)
    if want or st.selected then WC.SelectMapPanel(want) end
end

-- Another tab or the map's own controls changed the view: ours deselects.
local function client_changed()
    if WC.panelState.opening then return end -- our own call to the client's open or close
    if WC.panelState.selected then WC.SelectMapPanel(false, "client") end
end

local hooked = {}
-- Hooks the client's display-mode method (after it runs) and each sibling tab's click, once each; every hook only
-- hides our own frame.
function WC.HookClientTabs()
    local col = QuestMapFrame
    if not col then return end
    if not hooked.mode and hooksecurefunc and type(col.SetDisplayMode) == "function" then
        hooked.mode = pcall(hooksecurefunc, col, "SetDisplayMode", function(_, mode)
            WC.PlaceMapTab()
            if mode ~= WC.TAB_MODE then client_changed() end
        end)
    end
    if not col.GetChildren then return end
    for _, c in ipairs({ col:GetChildren() }) do
        if c ~= WC.mapButton and c ~= WC.mapPanel and not hooked[c] and c.HookScript and c.IsShown and c:IsShown()
            and (c:GetWidth() or 0) > 0 and (c:GetWidth() or 0) <= 80 and (c:GetHeight() or 0) <= 80 then
            hooked[c] = pcall(c.HookScript, c, "OnClick", client_changed)
        end
    end
end

-- Sets the tab up once the button exists: hooks, and the map-open behaviour (the map's OnShow hook is in Button.lua).
function WC.InitMapPanel()
    if WC.mapButtonMode ~= "tab" or WC.panelInited then return end
    WC.panelInited = true
    WC.HookClientTabs()
    WC.ApplyMapTabState()
end
