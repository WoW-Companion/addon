-- WoW Companion: the plan in the world map's right-hand panel, behind our side tab.
-- Approach: the client has no public way to add a content frame to its quest panel, so by default a child frame of
-- the panel (our own, never a client frame) is shown over the panel's content area while our tab is selected, and
-- hidden the moment another tab or the map's own controls change the view. If a client ever offers
-- QuestMapFrame:AddContentFrame + SetDisplayMode, that public pair is used instead ("native").
-- Display only: nothing here changes a client frame; every client call is guarded and unprotected.

local WC = WoWCompanion
local L = WC.L

local ROW_H, PAD, HEAD_H = 40, 10, 92
local GOLD, DIM = { 1, 0.82, 0 }, { 0.55, 0.55, 0.55 }
WC.TAB_MODE = "WoWCompanionPlan"

-- Session state: whether our tab is selected, the last tab the player used (nil until one is), the zone filter the
-- player flipped (nil = follow the setting) and whether the Completed group is open.
WC.panelState = { selected = false, lastTab = nil, allZones = nil, zoneSeen = nil, doneOpen = false }

-- ---------------------------------------------------------------- pure model

-- The sub-line under a row's title: the pick-up or turn-in giver, or the live objective.
function WC.StepSubLine(step)
    local detail = WC.PlanDetail(step)
    if step.kind == "pickup" or step.kind == "turnin" then
        local who = detail:gsub("^[Ff]rom%s+", ""):gsub("^[Tt]o%s+", "")
        if who == "" then return step.kind == "pickup" and L.PANEL_PICKUP or L.PANEL_TURNIN end
        return string.format(step.kind == "pickup" and L.PANEL_PICKUP_FROM or L.PANEL_TURNIN_TO, who)
    end
    return WC.PlanLiveText(step, detail ~= "" and detail or step.label or "")
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
        if opts.allZones or not opts.mapID or s.map == opts.mapID then
            local isDone = opts.done and opts.done[s.n] == true
            local row = { step = s, n = s.n, kind = s.kind, icon = KIND_ICON[s.kind] and WC.ICONS[KIND_ICON[s.kind]] or nil,
                title = WC.StepTitle(s), sub = WC.StepSubLine(s), isNext = opts.nextStep == s, done = isDone }
            if isDone then
                if opts.showDone ~= false then out.done[#out.done + 1] = row end
            else
                out.rows[#out.rows + 1] = row
            end
        end
    end
    return out
end

-- "20 stops · about 137 map units": the steps and the summed straight legs between consecutive steps on one map.
function WC.PanelFooter(steps)
    local units, prev = 0, nil
    for _, s in ipairs(steps or {}) do
        if prev and prev.map == s.map then units = units + math.sqrt((s.x - prev.x) ^ 2 + (s.y - prev.y) ^ 2) end
        prev = s
    end
    return string.format(L.PANEL_FOOTER, #(steps or {}), math.floor(units + 0.5))
end

-- The header's strings: step counter, distance and direction to the next step, and the advice time.
function WC.PanelHeader()
    local p = WC.plan
    if not p then return { title = L.ADDON_NAME, step = "", dist = "", advice = "" } end
    local done, total = WC.PlanCounts()
    local step = WC.PlanNext()
    local h = { title = L.ADDON_NAME, advice = string.format(L.PANEL_ADVICE_TIME, WC.FormatClock(p.generated or 0)) }
    if not step then h.step, h.dist = string.format(L.PLAN_DONE, total), "" return h end
    h.step = string.format(L.PANEL_STEP, math.min(done + 1, total), total)
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

-- A click on a row: left centres the map on the step, right opens the detail card of its quest.
function WC.PanelRowClick(step, button)
    if button == "RightButton" then
        if (step.questID or 0) <= 0 then return "none" end
        WC.OpenCard(WC.MakeEntry("quest", "mp" .. step.questID, {}, { quest = step.questID, title = step.quest, level = step.level }))
        return "card"
    end
    WC.CenterOnStep(step)
    return "center"
end

-- ---------------------------------------------------------------- frame

local function mp() return WC.mapPanel end

-- One row frame, built once and reused.
local function make_row(f, i)
    local r = CreateFrame("Button", nil, f.child)
    r:SetSize(f.rowWidth, ROW_H)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.hl = r:CreateTexture(nil, "BACKGROUND")
    r.hl:SetAllPoints()
    r.hl:Hide()
    r.nextBg = r:CreateTexture(nil, "BACKGROUND")
    r.nextBg:SetAllPoints()
    r.nextBg:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.12)
    r.badge = CreateFrame("Frame", nil, r)
    r.badge:SetSize(24, 24)
    r.badge:SetPoint("LEFT", r, "LEFT", 2, 0)
    WC.BadgeParts(r.badge, 2, 9, "GameFontNormalSmall", 3)
    r.badge.glow:SetSize(30, 30)
    r.badge.notchBg:Hide()
    r.badge.mark:Hide()
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(14, 14)
    r.icon:SetPoint("LEFT", r.badge, "RIGHT", 4, 0)
    r.label = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.label:SetPoint("TOPLEFT", r, "TOPLEFT", 48, -5)
    r.label:SetWidth(f.rowWidth - 70)
    r.label:SetJustifyH("LEFT")
    r.sub = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.sub:SetPoint("TOPLEFT", r, "TOPLEFT", 48, -21)
    r.sub:SetWidth(f.rowWidth - 70)
    r.sub:SetJustifyH("LEFT")
    r.check = r:CreateTexture(nil, "OVERLAY")
    r.check:SetSize(14, 14)
    r.check:SetPoint("RIGHT", r, "RIGHT", -4, 0)
    r.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    r.owner = f
    r:SetScript("OnEnter", function(self) if self.group then WC.HoverEnterRow(self) end end)
    r:SetScript("OnLeave", function() WC.HoverLeaveRow() end)
    r:SetScript("OnClick", function(self, button) if self.step then WC.PanelRowClick(self.step, button) end end)
    f.rows[i] = r
    return r
end

-- Fills one row frame from a model row and puts it at y.
local function fill_row(f, i, m, y)
    local r = f.rows[i] or make_row(f, i)
    r.step, r.top, r.hh = m.step, y, ROW_H
    r.quest = (m.step.questID or 0) > 0 and m.step.questID or nil
    r.group = r.quest and ("mp" .. r.quest) or nil
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", f.child, "TOPLEFT", 0, -y)
    r.badge.num:SetText(tostring(m.n))
    r.badge.num:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    if m.icon then r.icon:SetTexture(m.icon) r.icon:Show() else r.icon:Hide() end
    r.label:SetText(m.title)
    r.sub:SetText(m.sub)
    r.nextBg:SetShown(m.isNext)
    r.check:SetShown(m.done)
    r.baseColor = m.done and DIM or (m.isNext and { 1, 0.95, 0.6 } or GOLD)
    r.label:SetTextColor(r.baseColor[1], r.baseColor[2], r.baseColor[3])
    r.sub:SetTextColor(m.done and DIM[1] or 0.85, m.done and DIM[2] or 0.85, m.done and DIM[3] or 0.85)
    r:Show()
    WC.ApplyRowHover(r)
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
    local used = 0
    local y = 0
    local function put(m)
        used = used + 1
        fill_row(f, used, m, y)
        y = y + ROW_H
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
    f.child:SetHeight(math.max(y, 1))
    f.scrollRange = math.max(0, y - (f.scroll:GetHeight() or 0))
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

local function create_frame()
    local col = QuestMapFrame
    if WC.mapPanel or not col then return WC.mapPanel end
    local ok, f = pcall(CreateFrame, "Frame", "WoWCompanionMapPanel", col)
    if not ok or type(f) ~= "table" then return end
    f.rowWidth = 270
    f.rows = {}
    f:SetAllPoints(col)
    if f.SetFrameLevel and col.GetFrameLevel then f:SetFrameLevel((col:GetFrameLevel() or 1) + 20) end
    f:EnableMouse(true) -- swallows clicks so they never reach the quest list underneath
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0.06, 0.05, 0.04, 1)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + 4, -14)
    f.stepText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.stepText:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + 4, -36)
    f.advice = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.advice:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + 4, -54)
    f.eye = CreateFrame("Button", "WoWCompanionMapPanelEye", f)
    f.eye:SetSize(22, 22)
    f.eye:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD - 4, -12)
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
    f.zoneBtn:SetSize(130, 20)
    f.zoneBtn:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + 4, -68)
    f.zoneBtn:SetScript("OnClick", function() WC.ToggleMapPanelZones() end)
    f.scroll = CreateFrame("ScrollFrame", "WoWCompanionMapPanelScroll", f, "UIPanelScrollFrameTemplate")
    f.scroll:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -HEAD_H)
    f.scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD - 18, 30)
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
    f.footer:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD + 4, 10)
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

-- Selects or deselects our tab's panel. by == "client" means another tab did it, so nothing is asked of the client.
function WC.SelectMapPanel(on, by)
    local st = WC.panelState
    local f = create_frame()
    if not f then return false end
    on = on and true or false
    if on == st.selected and f:IsShown() == on then return on end
    local native = WC.PanelBackend() == "native"
    if native and not f.registered then
        f.registered = pcall(QuestMapFrame.AddContentFrame, QuestMapFrame, f, WC.TAB_MODE) and true or false
        native = f.registered
    end
    st.selected = on
    st.lastTab = on and "plan" or "other"
    if native and by ~= "client" then
        if on then
            st.prevMode = QuestMapFrame.displayMode
            pcall(QuestMapFrame.SetDisplayMode, QuestMapFrame, WC.TAB_MODE)
        elseif st.prevMode ~= nil then
            pcall(QuestMapFrame.SetDisplayMode, QuestMapFrame, st.prevMode)
        end
    end
    if not native then f:SetShown(on) end
    if on then WC.RefreshMapPanel() end
    WC.RefreshMapTab()
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
