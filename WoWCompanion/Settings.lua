-- WoW Companion: settings (scale, lock, section visibility, open on login) and their page.
-- Everything here is saved in WoWCompanionDB.settings and only changes how the panel looks.

local WC = WoWCompanion
local L = WC.L

WC.SCALE_MIN, WC.SCALE_MAX, WC.SCALE_STEP = 0.7, 1.3, 0.05
-- Text sizes in points: the setting's id, and what each id means for body text.
WC.FONT_SIZES = { small = 10, normal = 12, large = 15 }
WC.FONT_ORDER = { "small", "normal", "large" }
local STEPS_PER_UNIT = 20 -- 1 / SCALE_STEP, kept whole so the rounded value is exact

-- Settings section ids, in display order, and the digest section ids they control.
WC.SECTIONS = {
    { "quests", L.SECTION_quests }, { "upgrades", L.SECTION_upgrades }, { "materials", L.SECTION_materials },
    { "notes", L.SECTION_notes }, { "dungeons", L.SECTION_dungeons },
    { "talents", L.SECTION_talents },
}
WC.SECTION_OF = { next_quests = "quests", upgrades = "upgrades", keep_materials = "materials", notes = "notes", dungeons = "dungeons", talents = "talents" }

function WC.ClampScale(v)
    v = tonumber(v) or 1
    v = math.floor(v * STEPS_PER_UNIT + 0.5) / STEPS_PER_UNIT
    return math.max(WC.SCALE_MIN, math.min(WC.SCALE_MAX, v))
end

-- Fills in defaults and repairs anything a hand-edited saved file got wrong.
function WC.InitSettings(db)
    local s = type(db.settings) == "table" and db.settings or {}
    db.settings = s
    s.scale = WC.ClampScale(s.scale)
    s.locked = s.locked == true
    s.openOnLogin = s.openOnLogin == true
    s.fontSize = WC.FONT_SIZES[s.fontSize] and s.fontSize or "normal"
    s.tracker = s.tracker == true
    s.compact = s.compact == true
    s.planTracker = s.planTracker ~= false
    s.planMap = s.planMap ~= false
    s.planLines = s.planLines ~= false
    s.planArrows = s.planArrows ~= false
    s.planShow = (tonumber(s.planShow) and tonumber(s.planShow) >= 1) and math.floor(tonumber(s.planShow)) or "all"
    s.planSize = WC.PIN_SIZES and WC.PIN_SIZES[s.planSize] and s.planSize or "normal"
    s.tooltips = s.tooltips ~= false
    local h = type(s.hideInCombat) == "table" and s.hideInCombat or {}
    s.hideInCombat = { tracker = h.tracker ~= false, panel = h.panel == true }
    s.show = type(s.show) == "table" and s.show or {}
    for _, sec in ipairs(WC.SECTIONS) do s.show[sec[1]] = s.show[sec[1]] ~= false end
    s.minimap = type(s.minimap) == "table" and s.minimap or {}
    s.minimap.angle = tonumber(s.minimap.angle) or 215
end

function WC.SectionShown(id)
    return WC.db.settings.show[id] ~= false
end

-- Sets a font string to the chosen text size; delta shifts it (the hint line is a little smaller).
function WC.StyleText(fs, delta)
    if fs.SetFont then fs:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", WC.FONT_SIZES[WC.db.settings.fontSize] + (delta or 0)) end
end

-- Applies the saved settings to the panel and redraws it.
function WC.ApplySettings()
    if WC.panel then WC.panel:SetScale(WC.db.settings.scale) end
    WC.Refresh()
    if WC.RefreshPlan then WC.RefreshPlan() end
end

-- Turns compact mode on or off (saved in the settings); temporary expansions are dropped.
function WC.SetCompact(v)
    WC.db.settings.compact = v and true or false
    WC.view.expanded = {}
    if WC.settingsFrame then WC.settingsFrame.sync() end
    WC.Refresh()
end

local function sync(f)
    local s = WC.db.settings
    f.scale:SetValue(s.scale)
    f.scaleText:SetText(string.format(L.SCALE_LABEL, s.scale))
    local size = L["FONT_" .. s.fontSize]
    f.fontButton:SetText(string.format(L.FONT_LABEL, size))
    if f.planShow then
        f.planShow:SetText(string.format(L.PLAN_SHOW_LABEL, tostring(s.planShow)))
    end
    if f.planSize then
        local name = L["PLAN_SIZE_" .. s.planSize]
        f.planSize:SetText(string.format(L.PLAN_SIZE_LABEL, name))
    end
    for _, c in ipairs(f.checks) do c:SetChecked(c.get()) end
end

function WC.CreateSettings()
    local mode = (Settings and Settings.RegisterCanvasLayoutCategory and "settings")
        or (InterfaceOptions_AddCategory and "interface") or "frame"
    local f = CreateFrame("Frame", "WoWCompanionSettings", UIParent, mode == "frame" and "BasicFrameTemplateWithInset" or nil)
    f:SetSize(320, 656)
    f.name = L.ADDON_NAME
    f.checks = {}

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 16, mode == "frame" and -6 or -16)
    f.title:SetText(L.ADDON_NAME)

    f.scaleText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.scaleText:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -40)
    f.scale = CreateFrame("Slider", "WoWCompanionOptionScale", f, "OptionsSliderTemplate")
    f.scale:SetSize(180, 16)
    f.scale:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -62)
    f.scale:SetMinMaxValues(WC.SCALE_MIN, WC.SCALE_MAX)
    f.scale:SetValueStep(WC.SCALE_STEP)
    f.scale:SetScript("OnValueChanged", function(_, v)
        local scale = WC.ClampScale(v)
        if scale == WC.db.settings.scale then return end
        WC.db.settings.scale = scale
        f.scaleText:SetText(string.format(L.SCALE_LABEL, scale))
        WC.ApplySettings()
    end)

    f.fontButton = CreateFrame("Button", "WoWCompanionOptionFont", f, "UIPanelButtonTemplate")
    f.fontButton:SetSize(180, 22)
    f.fontButton:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -88)
    f.fontButton:SetScript("OnClick", function()
        local cur = WC.db.settings.fontSize
        for i, id in ipairs(WC.FONT_ORDER) do
            if id == cur then WC.db.settings.fontSize = WC.FONT_ORDER[i % #WC.FONT_ORDER + 1]; break end
        end
        sync(f)
        WC.ApplySettings()
    end)

    f.planSize = CreateFrame("Button", "WoWCompanionOptionPlanSize", f, "UIPanelButtonTemplate")
    f.planSize:SetSize(180, 22)
    f.planSize:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -114)
    f.planSize:SetScript("OnClick", function() WC.CyclePlanSize() end)

    f.planShow = CreateFrame("Button", "WoWCompanionOptionPlanShow", f, "UIPanelButtonTemplate")
    f.planShow:SetSize(180, 22)
    f.planShow:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -140)
    f.planShow:SetScript("OnClick", function()
        local cur = WC.db.settings.planShow
        WC.SetPlanShow(cur == "all" and 5 or (cur == 5 and 10 or "all"))
    end)

    local y = -170
    local function check(name, label, get, set)
        local c = CreateFrame("CheckButton", "WoWCompanionOption" .. name, f, "UICheckButtonTemplate")
        c:SetPoint("TOPLEFT", f, "TOPLEFT", 14, y)
        y = y - 26
        c.label = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        c.label:SetPoint("LEFT", c, "RIGHT", 4, 0)
        c.label:SetText(label)
        c.get = get
        c:SetScript("OnClick", function(self)
            set(self:GetChecked() and true or false)
            WC.ApplySettings()
        end)
        f.checks[#f.checks + 1] = c
    end
    local s = WC.db.settings
    check("Lock", L.LOCK_PANEL, function() return s.locked end, function(v) s.locked = v end)
    check("Login", L.OPEN_ON_LOGIN, function() return s.openOnLogin end, function(v) s.openOnLogin = v end)
    check("Tracker", L.SHOW_TRACKER, function() return s.tracker end, function(v) s.tracker = v end)
    check("PlanTracker", L.SHOW_PLAN_TRACKER, function() return s.planTracker end, function(v) s.planTracker = v end)
    check("PlanMap", L.SHOW_PLAN_MAP, function() return s.planMap end, function(v) s.planMap = v end)
    check("PlanLines", L.SHOW_PLAN_LINES, function() return s.planLines end, function(v) s.planLines = v end)
    check("PlanArrows", L.SHOW_PLAN_ARROWS, function() return s.planArrows end, function(v) s.planArrows = v end)
    check("Tooltips", L.SHOW_TOOLTIPS, function() return s.tooltips end, function(v) s.tooltips = v end)
    check("Compact", L.COMPACT_PANEL, function() return s.compact end, function(v) s.compact = v; WC.view.expanded = {} end)
    for _, sec in ipairs(WC.SECTIONS) do
        local id = sec[1]
        check("Show" .. id, string.format(L.SHOW_SECTION, sec[2]), function() return s.show[id] end, function(v) s.show[id] = v end)
    end
    check("HideTracker", L.HIDE_TRACKER_COMBAT, function() return s.hideInCombat.tracker end, function(v) s.hideInCombat.tracker = v end)
    check("HidePanel", L.HIDE_PANEL_COMBAT, function() return s.hideInCombat.panel end, function(v) s.hideInCombat.panel = v end)

    f:SetScript("OnShow", function() sync(f) end)
    sync(f)
    f.sync = function() sync(f) end
    WC.settingsFrame, WC.settingsMode = f, mode

    if mode == "settings" then
        local category = Settings.RegisterCanvasLayoutCategory(f, f.name)
        Settings.RegisterAddOnCategory(category)
        WC.settingsCategory = category
    elseif mode == "interface" then
        InterfaceOptions_AddCategory(f)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        f:Hide()
    end
end

function WC.OpenSettings()
    local f, mode = WC.settingsFrame, WC.settingsMode
    if not f then return end
    if mode == "settings" then
        local c = WC.settingsCategory
        Settings.OpenToCategory(c.GetID and c:GetID() or c.ID)
    elseif mode == "interface" then
        -- Called twice on purpose: the first call can land on the wrong tab in older clients.
        InterfaceOptionsFrame_OpenToCategory(f)
        InterfaceOptionsFrame_OpenToCategory(f)
    elseif f:IsShown() then
        f:Hide()
    else
        f:Show()
    end
end
