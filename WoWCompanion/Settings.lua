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

-- The settings table: one row per saved value. Every row says where it lives (key, a dotted path into
-- WC.db.settings), what it is (bool, range, choice, color, limit or number), its default (today's shipped
-- look), and which options page and box show it. The options window is built from these rows, and
-- InitSettings, Setting and the Defaults buttons all read the same ones.
-- page ids, in display order:
WC.PAGES = { "panel", "map", "badges", "tracker", "minimap", "tooltips" }
local GOLD_LINE = { 1, 0.82, 0 }
local D = {
    -- Panel
    { key = "locked", type = "bool", default = false, page = "panel", box = "window", label = "LOCK_PANEL", name = "Lock" },
    { key = "openOnLogin", type = "bool", default = false, page = "panel", box = "window", label = "OPEN_ON_LOGIN", name = "Login" },
    { key = "compact", type = "bool", default = false, page = "panel", box = "window", label = "COMPACT_PANEL", name = "Compact", apply = "compact" },
    { key = "hideInCombat.panel", type = "bool", default = false, page = "panel", box = "window", label = "HIDE_PANEL_COMBAT", name = "HidePanel" },
    { key = "showWhatsNew", type = "bool", default = true, page = "panel", box = "window", label = "SHOW_WHATS_NEW", name = "WhatsNew" },
    { key = "scale", type = "range", default = 1, min = 0.7, max = 1.3, step = 0.05, page = "panel", box = "window", label = "SCALE_LABEL", name = "Scale", show = "num2" },
    { key = "fontSize", type = "choice", default = "normal", choices = { "small", "normal", "large" }, page = "panel", box = "window", label = "FONT_LABEL", name = "Font", choiceKey = "FONT_" },
    { key = "bgOpacity", type = "range", default = 0.45, min = 0, max = 1, step = 0.05, page = "panel", box = "window", label = "BG_OPACITY_LABEL", name = "BgOpacity", show = "pct" },
    { key = "panelWidth", type = "range", default = 340, min = 280, max = 520, step = 10, page = "panel", box = "window", label = "PANEL_WIDTH_LABEL", name = "Width", show = "int" },
    { key = "showLevels", type = "bool", default = true, page = "panel", box = "content", label = "SHOW_LEVELS", name = "Levels" },
    { key = "colorByDifficulty", type = "bool", default = true, page = "panel", box = "content", label = "COLOR_DIFFICULTY", name = "Difficulty" },
    { key = "showOptional", type = "bool", default = true, page = "panel", box = "content", label = "SHOW_OPTIONAL", name = "Optional" },
    { key = "showNpcLines", type = "bool", default = true, page = "panel", box = "content", label = "SHOW_NPC_LINES", name = "Npc" },
    { key = "timeFormat", type = "choice", default = "client", choices = { "client", "12", "24" }, page = "panel", box = "content", label = "TIME_FORMAT_LABEL", name = "TimeFormat", choiceKey = "TIME_", widget = "dropdown" },
    -- Map & route
    { key = "planMap", type = "bool", default = true, page = "map", box = "map", label = "SHOW_PLAN_MAP", name = "PlanMap" },
    { key = "planShow", type = "limit", default = "all", min = 1, max = 25, page = "map", box = "map", label = "PLAN_SHOW_LABEL", name = "PlanShow", show = "limit" },
    { key = "mergeDistance", type = "range", default = 1.2, min = 0, max = 5, step = 0.1, page = "map", box = "map", label = "MERGE_LABEL", name = "Merge", show = "num1" },
    { key = "planLines", type = "bool", default = true, page = "map", box = "route", label = "SHOW_PLAN_LINES", name = "PlanLines" },
    { key = "planArrows", type = "bool", default = true, page = "map", box = "route", label = "SHOW_PLAN_ARROWS", name = "PlanArrows" },
    { key = "planChevrons", type = "bool", default = true, page = "map", box = "route", label = "SHOW_CHEVRONS", name = "Chevrons" },
    { key = "lineColor", type = "color", default = GOLD_LINE, page = "map", box = "route", label = "LINE_COLOR", name = "LineColor" },
    { key = "lineWidth", type = "range", default = 2.5, min = 1, max = 6, step = 0.5, page = "map", box = "route", label = "LINE_WIDTH_LABEL", name = "LineWidth", show = "num1" },
    { key = "lineOpacity", type = "range", default = 0.7, min = 0.1, max = 1, step = 0.05, page = "map", box = "route", label = "LINE_OPACITY_LABEL", name = "LineOpacity", show = "pct" },
    { key = "arrowSize", type = "range", default = 14, min = 8, max = 24, step = 1, page = "map", box = "route", label = "ARROW_SIZE_LABEL", name = "ArrowSize", show = "int" },
    -- Badges
    { key = "planSize", type = "choice", default = "normal", choices = { "small", "normal", "large" }, page = "badges", box = "size", label = "PLAN_SIZE_LABEL", name = "PlanSize", choiceKey = "PLAN_SIZE_" },
    { key = "badgeScale", type = "range", default = 1, min = 0.7, max = 1.5, step = 0.05, page = "badges", box = "size", label = "BADGE_SCALE_LABEL", name = "BadgeScale", show = "num2" },
    { key = "nextGrow", type = "range", default = 1.3, min = 1, max = 2, step = 0.05, page = "badges", box = "size", label = "NEXT_GROW_LABEL", name = "NextGrow", show = "num2" },
    { key = "tagScale", type = "range", default = 0.75, min = 0.4, max = 1, step = 0.05, page = "badges", box = "size", label = "TAG_SCALE_LABEL", name = "TagScale", show = "num2" },
    { key = "badgeFill", type = "color", default = { 0.05, 0.22, 0.13 }, page = "badges", box = "look", label = "BADGE_FILL", name = "BadgeFill" },
    { key = "badgeOpacity", type = "range", default = 0.80, min = 0.2, max = 1, step = 0.05, page = "badges", box = "look", label = "BADGE_OPACITY_LABEL", name = "BadgeOpacity", show = "pct" },
    { key = "nextPulse", type = "bool", default = true, page = "badges", box = "look", label = "NEXT_PULSE", name = "NextPulse" },
    -- Tracker
    { key = "planTracker", type = "bool", default = true, page = "tracker", box = "tracker", label = "SHOW_PLAN_TRACKER", name = "PlanTracker" },
    { key = "tracker", type = "bool", default = false, page = "tracker", box = "tracker", label = "SHOW_TRACKER", name = "Tracker" },
    { key = "hideInCombat.tracker", type = "bool", default = true, page = "tracker", box = "tracker", label = "HIDE_TRACKER_COMBAT", name = "HideTracker" },
    -- Minimap
    { key = "minimapPin", type = "bool", default = true, page = "minimap", box = "minimap", label = "SHOW_MINIMAP_PIN", name = "MinimapPin" },
    { key = "arrivalPulse", type = "bool", default = true, page = "minimap", box = "minimap", label = "ARRIVAL_PULSE", name = "Arrival" },
    { key = "minimap.angle", type = "number", default = 215, page = "minimap", box = "minimap", hidden = true },
    -- Tooltips
    { key = "tooltips", type = "bool", default = true, page = "tooltips", box = "tooltips", label = "SHOW_TOOLTIPS", name = "Tooltips" },
}
for _, sec in ipairs(WC.SECTIONS) do
    D[#D + 1] = { key = "show." .. sec[1], type = "bool", default = true, page = "panel", box = "sections", label = "SHOW_SECTION", labelArg = sec[2], name = "Show" .. sec[1] }
end
WC.DEFS = D
WC.DEF_OF = {}
for _, d in ipairs(D) do WC.DEF_OF[d.key] = d end

-- Reads and writes a dotted key ("hideInCombat.panel") in a settings table.
local function get_at(s, key)
    local dot = key:find(".", 1, true)
    if not dot then return s[key] end
    local sub = type(s[key:sub(1, dot - 1)]) == "table" and s[key:sub(1, dot - 1)] or {}
    return sub[key:sub(dot + 1)]
end
local function set_at(s, key, v)
    local dot = key:find(".", 1, true)
    if not dot then s[key] = v return end
    local head = key:sub(1, dot - 1)
    s[head] = type(s[head]) == "table" and s[head] or {}
    s[head][key:sub(dot + 1)] = v
end

local function copy(v)
    if type(v) ~= "table" then return v end
    return { v[1], v[2], v[3] }
end

-- A value repaired to what the row allows: a wrong type or an out-of-range number falls back or clamps.
function WC.Repair(def, v)
    local t = def.type
    if t == "bool" then
        if def.default then return v ~= false end
        return v == true
    elseif t == "range" then
        v = tonumber(v)
        if not v or v ~= v then return def.default end
        if def.step >= 1 then
            v = math.floor(v / def.step + 0.5) * def.step
        else
            local inv = math.floor(1 / def.step + 0.5)
            v = math.floor(v * inv + 0.5) / inv
        end
        return math.max(def.min, math.min(def.max, v))
    elseif t == "choice" then
        for _, c in ipairs(def.choices) do
            if c == v then return v end
        end
        return def.default
    elseif t == "color" then
        if type(v) ~= "table" then return copy(def.default) end
        local out = {}
        for i = 1, 3 do
            local n = tonumber(v[i])
            out[i] = n and math.max(0, math.min(1, n)) or def.default[i]
        end
        return out
    elseif t == "limit" then
        local n = tonumber(v)
        return (n and n >= 1 and n == n and n < 1e6) and math.floor(n) or "all"
    end
    local n = tonumber(v)
    return n and n == n and n or def.default
end

-- The saved value of a key, or its default when there is no saved table yet (pure code paths and tests).
function WC.Setting(key)
    local def = WC.DEF_OF[key]
    local s = WC.db and WC.db.settings
    local v = s and get_at(s, key)
    if v == nil then return def and copy(def.default) end
    return v
end

function WC.ClampScale(v)
    return WC.Repair(WC.DEF_OF.scale, v)
end

-- Fills in defaults and repairs anything a hand-edited saved file got wrong.
function WC.InitSettings(db)
    local s = type(db.settings) == "table" and db.settings or {}
    db.settings = s
    local h = type(s.hideInCombat) == "table" and s.hideInCombat or {}
    s.hideInCombat = h
    s.show = type(s.show) == "table" and s.show or {}
    s.minimap = type(s.minimap) == "table" and s.minimap or {}
    for _, def in ipairs(D) do set_at(s, def.key, WC.Repair(def, get_at(s, def.key))) end
end

-- Saves one value (repaired first) and applies it live. Returns the stored value.
function WC.SetSetting(key, v)
    local def = WC.DEF_OF[key]
    if not def or not WC.db then return nil end
    v = WC.Repair(def, v)
    set_at(WC.db.settings, key, v)
    WC.ApplyDef(def)
    return v
end

-- What a row's change touches: compact also drops the temporary expansions; everything else redraws.
function WC.ApplyDef(def)
    if def.apply == "compact" then WC.view.expanded = {} end
    WC.ApplySettings()
    if WC.SyncOptions then WC.SyncOptions() end
end

-- Puts the rows of one page (or all, page nil) back to their defaults; no other row is touched.
function WC.ResetPage(page)
    for _, def in ipairs(D) do
        if not page or def.page == page then set_at(WC.db.settings, def.key, copy(def.default)) end
    end
    WC.view.expanded = {}
    WC.ApplySettings()
    if WC.SyncOptions then WC.SyncOptions() end
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
    WC.SetSetting("compact", v)
end

-- The page registered in the client's AddOns settings: a short note and a button that opens the options window.
function WC.CreateSettings()
    local mode = (Settings and Settings.RegisterCanvasLayoutCategory and "settings")
        or (InterfaceOptions_AddCategory and "interface") or "frame"
    local f = CreateFrame("Frame", "WoWCompanionSettings", UIParent)
    f:SetSize(320, 120)
    f.name = L.ADDON_NAME
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -16)
    f.title:SetText(L.ADDON_NAME)
    f.blurb = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.blurb:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -44)
    f.blurb:SetText(L.OPTIONS_NOTE)
    f.open = CreateFrame("Button", "WoWCompanionOpenOptions", f, "UIPanelButtonTemplate")
    f.open:SetSize(200, 24)
    f.open:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -70)
    f.open:SetText(L.OPEN_OPTIONS)
    f.open:SetScript("OnClick", function() WC.OpenOptions(true) end)
    WC.settingsFrame, WC.settingsMode = f, mode

    if mode == "settings" then
        local category = Settings.RegisterCanvasLayoutCategory(f, f.name)
        Settings.RegisterAddOnCategory(category)
        WC.settingsCategory = category
    elseif mode == "interface" then
        InterfaceOptions_AddCategory(f)
    else
        f:Hide()
    end
end

-- Opens the client's AddOns settings entry for this addon (which holds the button to the options window).
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
    else
        WC.OpenOptions()
    end
end
