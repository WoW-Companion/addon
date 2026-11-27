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
WC.PAGES = { "panel", "plan", "map", "badges", "tracker", "minimap", "tooltips" }
local GOLD_LINE = { 1, 0.82, 0 }
local D = {
    -- Panel
    { key = "locked", type = "bool", default = false, page = "panel", box = "window", label = "LOCK_PANEL", name = "Lock" },
    { key = "openOnLogin", type = "bool", default = false, page = "panel", box = "window", label = "OPEN_ON_LOGIN", name = "Login" },
    { key = "startCollapsed", type = "bool", default = false, page = "panel", box = "window", label = "START_COLLAPSED", name = "StartCollapsed" },
    { key = "view", type = "choice", default = "full", choices = { "full", "compact", "next" }, page = "panel", box = "window", label = "VIEW_LABEL", name = "View", choiceKey = "VIEW_", widget = "dropdown", apply = "compact" },
    { key = "hideInCombat.panel", type = "bool", default = false, page = "panel", box = "window", label = "HIDE_PANEL_COMBAT", name = "HidePanel" },
    { key = "showWhatsNew", type = "bool", default = true, page = "panel", box = "window", label = "SHOW_WHATS_NEW", name = "WhatsNew" },
    { key = "scale", visual = true, type = "range", default = 1, min = 0.7, max = 1.3, step = 0.05, page = "panel", box = "window", label = "SCALE_LABEL", name = "Scale", show = "num2" },
    { key = "fontSize", visual = true, type = "choice", default = "normal", choices = { "small", "normal", "large" }, page = "panel", box = "window", label = "FONT_LABEL", name = "Font", choiceKey = "FONT_" },
    { key = "bgOpacity", visual = true, type = "range", default = 0.45, min = 0, max = 1, step = 0.05, page = "panel", box = "window", label = "BG_OPACITY_LABEL", name = "BgOpacity", show = "pct" },
    { key = "panelWidth", visual = true, type = "range", default = 340, min = 280, max = 520, step = 10, page = "panel", box = "window", label = "PANEL_WIDTH_LABEL", name = "Width", show = "int" },
    { key = "panelSizeMode", visual = true, type = "choice", default = "auto", choices = { "auto", "manual" }, page = "panel", box = "window", label = "SIZE_MODE_LABEL", name = "SizeMode", choiceKey = "SIZE_MODE_", widget = "dropdown" },
    { key = "panelHeight", visual = true, hidden = true, type = "range", default = 320, min = 100, max = 4000, step = 1, page = "panel", box = "window", label = "PANEL_HEIGHT_LABEL", name = "Height", show = "int" },
    { key = "showLevels", type = "bool", default = true, page = "panel", box = "content", label = "SHOW_LEVELS", name = "Levels" },
    { key = "colorByDifficulty", type = "bool", default = true, page = "panel", box = "content", label = "COLOR_DIFFICULTY", name = "Difficulty" },
    { key = "showOptional", type = "bool", default = true, page = "panel", box = "content", label = "SHOW_OPTIONAL", name = "Optional" },
    { key = "showWhy", type = "bool", default = true, page = "panel", box = "content", label = "SHOW_WHY", name = "Why" },
    { key = "showNpcLines", type = "bool", default = true, page = "panel", box = "content", label = "SHOW_NPC_LINES", name = "Npc" },
    { key = "timeFormat", type = "choice", default = "client", choices = { "client", "12", "24" }, page = "panel", box = "content", label = "TIME_FORMAT_LABEL", name = "TimeFormat", choiceKey = "TIME_", widget = "dropdown" },
    { key = "showThen", type = "bool", default = true, page = "panel", box = "content", label = "SHOW_THEN", name = "ShowThen" },
    { key = "showNew", type = "bool", default = true, page = "panel", box = "content", label = "SHOW_NEW", name = "ShowNew" },
    { key = "keepObserved", type = "bool", default = true, page = "panel", box = "content", label = "KEEP_OBSERVED", name = "KeepObserved" },
    { key = "recordCharacter", type = "bool", default = true, page = "panel", box = "content", label = "RECORD_CHARACTER", name = "RecordCharacter" },
    { key = "hoverHighlight", type = "bool", default = true, page = "panel", box = "interact", label = "HOVER_HIGHLIGHT", name = "HoverHighlight" },
    { key = "hoverDim", type = "bool", default = false, page = "panel", box = "interact", label = "HOVER_DIM", name = "HoverDim" },
    { key = "clickAction", type = "choice", default = "questlog", choices = { "questlog", "card" }, page = "panel", box = "interact", label = "CLICK_ACTION_LABEL", name = "ClickAction", choiceKey = "CLICK_", widget = "dropdown" },
    { key = "cardSide", type = "choice", default = "right", choices = { "right", "left" }, page = "panel", box = "interact", label = "CARD_SIDE_LABEL", name = "CardSide", choiceKey = "SIDE_", widget = "dropdown" },
    -- Plan: what the plan holds for you (the app reads these from planPrefs on its next save)
    { key = "planReach", type = "limit", default = 3, min = 0, max = 11, page = "plan", box = "reach", label = "PLAN_REACH_LABEL", labelAll = "PLAN_REACH_ANY", name = "PlanReach", show = "limit" },
    { key = "planElite", type = "bool", default = false, page = "plan", box = "reach", label = "PLAN_ELITE", name = "PlanElite" },
    -- Map & route
    { key = "planMap", type = "bool", default = true, page = "map", box = "map", label = "SHOW_PLAN_MAP", name = "PlanMap" },
    { key = "alsoDoingMax", type = "range", default = 3, min = 0, max = 10, step = 1, page = "map", box = "map", label = "ALSO_DOING_MAX_LABEL", name = "AlsoDoingMax", show = "int" },
    { key = "planShow", type = "limit", default = "all", min = 1, max = 25, page = "map", box = "map", label = "PLAN_SHOW_LABEL", name = "PlanShow", show = "limit" },
    { key = "mergeDistance", type = "range", default = 1.2, min = 0, max = 5, step = 0.1, page = "map", box = "map", label = "MERGE_LABEL", name = "Merge", show = "num1" },
    { key = "hoverMapLink", type = "bool", default = true, page = "map", box = "map", label = "HOVER_MAP_LINK", name = "HoverMapLink" },
    { key = "planLines", type = "bool", default = true, page = "map", box = "route", label = "SHOW_PLAN_LINES", name = "PlanLines" },
    { key = "mapButton", type = "bool", default = true, page = "map", box = "map", label = "SHOW_MAP_BUTTON", name = "MapButton" },
    { key = "panelOpenOnTab", type = "bool", default = false, page = "map", box = "map", label = "PANEL_OPEN_ON_TAB", name = "PanelOpenOnTab" },
    { key = "mapRoundY", position = true, type = "number", default = 0, page = "map", box = "map", hidden = true }, -- the round map button's offset from its slot; 0 = the slot
    { key = "panelZone", type = "choice", default = "shown", choices = { "shown", "all" }, page = "map", box = "map", label = "PANEL_ZONE_LABEL", name = "PanelZone", choiceKey = "PANEL_ZONE_", widget = "dropdown" },
    { key = "panelShowDone", type = "bool", default = true, page = "map", box = "map", label = "PANEL_SHOW_DONE", name = "PanelShowDone" },
    { key = "showUpcoming", type = "bool", default = true, page = "map", box = "route", label = "SHOW_UPCOMING", name = "ShowUpcoming" },
    { key = "ghostsPerChain", type = "range", default = 1, min = 1, max = 3, step = 1, page = "map", box = "route", label = "GHOSTS_PER_CHAIN", name = "GhostsPerChain", show = "num0" },
    { key = "planArrows", type = "bool", default = true, page = "map", box = "route", label = "SHOW_PLAN_ARROWS", name = "PlanArrows" },
    { key = "planChevrons", type = "bool", default = true, page = "map", box = "route", label = "SHOW_CHEVRONS", name = "Chevrons" },
    { key = "lineColor", visual = true, type = "color", default = GOLD_LINE, page = "map", box = "route", label = "LINE_COLOR", name = "LineColor" },
    { key = "lineWidth", visual = true, type = "range", default = 2.5, min = 1, max = 6, step = 0.5, page = "map", box = "route", label = "LINE_WIDTH_LABEL", name = "LineWidth", show = "num1" },
    { key = "lineOpacity", visual = true, type = "range", default = 0.7, min = 0.1, max = 1, step = 0.05, page = "map", box = "opacity", label = "LINE_OPACITY_LABEL", name = "LineOpacity", show = "pct" },
    { key = "arrowSize", visual = true, type = "range", default = 8, min = 2, max = 24, step = 1, page = "map", box = "route", label = "ARROW_SIZE_LABEL", name = "ArrowSize", show = "int" },
    { key = "opacBadge", visual = true, type = "range", default = 0.9, min = 0.1, max = 1, step = 0.1, page = "map", box = "opacity", label = "OPAC_BADGE_LABEL", name = "OpacBadge", show = "pct" },
    { key = "opacLabel", visual = true, type = "range", default = 0.8, min = 0.1, max = 1, step = 0.1, page = "map", box = "opacity", label = "OPAC_LABEL_LABEL", name = "OpacLabel", show = "pct" },
    { key = "opacNext", visual = true, type = "range", default = 0.9, min = 0.1, max = 1, step = 0.1, page = "map", box = "opacity", label = "OPAC_NEXT_LABEL", name = "OpacNext", show = "pct" },
    { key = "opacRing", visual = true, type = "range", default = 0.5, min = 0.1, max = 1, step = 0.1, page = "map", box = "opacity", label = "OPAC_RING_LABEL", name = "OpacRing", show = "pct" },
    { key = "opacMinimap", visual = true, type = "range", default = 0.9, min = 0.1, max = 1, step = 0.1, page = "map", box = "opacity", label = "OPAC_MINIMAP_LABEL", name = "OpacMinimap", show = "pct" },
    { key = "hoverFull", visual = true, type = "bool", default = true, page = "map", box = "opacity", label = "OPAC_HOVER_FULL", name = "OpacHoverFull" },
    -- Badges
    { key = "planSize", visual = true, type = "choice", default = "normal", choices = { "small", "normal", "large" }, page = "badges", box = "size", label = "PLAN_SIZE_LABEL", name = "PlanSize", choiceKey = "PLAN_SIZE_" },
    { key = "badgeScale", visual = true, type = "range", default = 1, min = 0.7, max = 1.5, step = 0.05, page = "badges", box = "size", label = "BADGE_SCALE_LABEL", name = "BadgeScale", show = "num2" },
    { key = "nextGrow", visual = true, type = "range", default = 1.3, min = 1, max = 2, step = 0.05, page = "badges", box = "size", label = "NEXT_GROW_LABEL", name = "NextGrow", show = "num2" },
    { key = "tagScale", visual = true, type = "range", default = 0.75, min = 0.4, max = 1, step = 0.05, page = "badges", box = "size", label = "TAG_SCALE_LABEL", name = "TagScale", show = "num2" },
    { key = "badgeFill", visual = true, type = "color", default = { 0.05, 0.22, 0.13 }, page = "badges", box = "look", label = "BADGE_FILL", name = "BadgeFill" },
    { key = "badgeOpacity", visual = true, type = "range", default = 0.80, min = 0.2, max = 1, step = 0.05, page = "badges", box = "look", label = "BADGE_OPACITY_LABEL", name = "BadgeOpacity", show = "pct" },
    { key = "nextPulse", type = "bool", default = true, page = "badges", box = "look", label = "NEXT_PULSE", name = "NextPulse" },
    -- Tracker
    { key = "planTracker", type = "bool", default = false, page = "tracker", box = "tracker", label = "SHOW_PLAN_TRACKER", name = "PlanTracker" },
    { key = "tracker", type = "bool", default = false, page = "tracker", box = "tracker", label = "SHOW_TRACKER", name = "Tracker" },
    { key = "hideInCombat.tracker", type = "bool", default = true, page = "tracker", box = "tracker", label = "HIDE_TRACKER_COMBAT", name = "HideTracker" },
    -- Minimap
    { key = "minimap.show", type = "bool", default = true, page = "minimap", box = "button", label = "SHOW_MINIMAP_BUTTON", name = "MinimapShow" },
    { key = "minimap.compartment", type = "bool", default = true, page = "minimap", box = "button", label = "SHOW_COMPARTMENT", name = "MinimapCompartment" },
    { key = "minimap.locked", type = "bool", default = false, page = "minimap", box = "button", label = "LOCK_MINIMAP_BUTTON", name = "MinimapLocked" },
    { key = "minimapPin", type = "bool", default = true, page = "minimap", box = "minimap", label = "SHOW_MINIMAP_PIN", name = "MinimapPin" },
    { key = "arrivalPulse", type = "bool", default = true, page = "minimap", box = "minimap", label = "ARRIVAL_PULSE", name = "Arrival" },
    { key = "minimap.angle", position = true, type = "number", default = 180, page = "minimap", box = "minimap", hidden = true },
    -- Visual customization (every row below is also restored by /wowc reset visuals)
    { key = "bgColor", visual = true, type = "color", default = { 0, 0, 0 }, page = "panel", box = "colors", label = "BG_COLOR", name = "BgColor" },
    { key = "borderShow", visual = true, type = "bool", default = true, page = "panel", box = "colors", label = "BORDER_SHOW", name = "BorderShow" },
    { key = "borderColor", visual = true, type = "color", default = { 0.4, 0.4, 0.4 }, page = "panel", box = "colors", label = "BORDER_COLOR", name = "BorderColor" },
    { key = "borderOpacity", visual = true, type = "range", default = 0.5, min = 0, max = 1, step = 0.05, page = "panel", box = "colors", label = "BORDER_OPACITY_LABEL", name = "BorderOpacity", show = "pct" },
    { key = "headerColor", visual = true, type = "color", default = GOLD_LINE, page = "panel", box = "colors", label = "HEADER_COLOR", name = "HeaderColor" },
    { key = "sectionColor", visual = true, type = "color", default = { 0.72, 0.72, 0.72 }, page = "panel", box = "colors", label = "SECTION_COLOR", name = "SectionColor" },
    { key = "objectiveColor", visual = true, type = "color", default = { 1, 1, 1 }, page = "panel", box = "colors", label = "OBJECTIVE_COLOR", name = "ObjectiveColor" },
    { key = "doneColor", visual = true, type = "color", default = { 0.55, 0.55, 0.55 }, page = "panel", box = "colors", label = "DONE_COLOR", name = "DoneColor" },
    { key = "readyColor", visual = true, type = "color", default = { 0.25, 0.9, 0.25 }, page = "panel", box = "colors", label = "READY_COLOR", name = "ReadyColor" },
    { key = "lineSpacing", visual = true, type = "range", default = 1, min = 0, max = 8, step = 1, page = "panel", box = "colors", label = "LINE_SPACING_LABEL", name = "LineSpacing", show = "int" },
    { key = "padding", visual = true, type = "range", default = 10, min = 4, max = 24, step = 1, page = "panel", box = "colors", label = "PADDING_LABEL", name = "Padding", show = "int" },
    { key = "nextLineColor", visual = true, type = "color", default = "auto", page = "map", box = "route", label = "NEXT_LINE_COLOR", name = "NextLineColor" },
    { key = "outlineColor", visual = true, type = "color", default = { 0, 0, 0 }, page = "map", box = "route", label = "OUTLINE_COLOR", name = "OutlineColor" },
    { key = "outlineOpacity", visual = true, type = "range", default = 0.6, min = 0, max = 1, step = 0.05, page = "map", box = "route", label = "OUTLINE_OPACITY_LABEL", name = "OutlineOpacity", show = "pct" },
    { key = "chevronSize", visual = true, type = "range", default = 9, min = 4, max = 20, step = 1, page = "map", box = "route", label = "CHEVRON_SIZE_LABEL", name = "ChevronSize", show = "int" },
    { key = "ringColor", visual = true, type = "color", default = GOLD_LINE, page = "badges", box = "rings", label = "RING_COLOR", name = "RingColor" },
    { key = "nextRingColor", visual = true, type = "color", default = { 1, 0.95, 0.6 }, page = "badges", box = "rings", label = "NEXT_RING_COLOR", name = "NextRingColor" },
    { key = "numberColor", visual = true, type = "color", default = GOLD_LINE, page = "badges", box = "rings", label = "NUMBER_COLOR", name = "NumberColor" },
    { key = "glowColor", visual = true, type = "color", default = GOLD_LINE, page = "badges", box = "rings", label = "GLOW_COLOR", name = "GlowColor" },
    { key = "glowOpacity", visual = true, type = "range", default = 0.5, min = 0, max = 1, step = 0.05, page = "badges", box = "rings", label = "GLOW_OPACITY_LABEL", name = "GlowOpacity", show = "pct" },
    { key = "pulseSpeed", visual = true, type = "range", default = 1, min = 0.5, max = 3, step = 0.1, page = "badges", box = "rings", label = "PULSE_SPEED_LABEL", name = "PulseSpeed", show = "num1" },
    { key = "tagFillOpacity", visual = true, type = "range", default = 0.8, min = 0, max = 1, step = 0.05, page = "badges", box = "tags", label = "TAG_FILL_OPACITY_LABEL", name = "TagFillOpacity", show = "pct" },
    { key = "tagRingOpacity", visual = true, type = "range", default = 1, min = 0, max = 1, step = 0.05, page = "badges", box = "tags", label = "TAG_RING_OPACITY_LABEL", name = "TagRingOpacity", show = "pct" },
    { key = "planBgColor", visual = true, type = "color", default = { 0, 0, 0 }, page = "tracker", box = "plan", label = "PLAN_BG_COLOR", name = "PlanBgColor" },
    { key = "planBgOpacity", visual = true, type = "range", default = 0.5, min = 0, max = 1, step = 0.05, page = "tracker", box = "plan", label = "PLAN_BG_OPACITY_LABEL", name = "PlanBgOpacity", show = "pct" },
    { key = "planTextSize", visual = true, type = "range", default = 12, min = 8, max = 20, step = 1, page = "tracker", box = "plan", label = "PLAN_TEXT_SIZE_LABEL", name = "PlanTextSize", show = "int" },
    { key = "minimapBadgeSize", visual = true, type = "range", default = 17, min = 10, max = 30, step = 1, page = "minimap", box = "minimap", label = "MM_BADGE_SIZE_LABEL", name = "MinimapBadgeSize", show = "int" },
    { key = "minimapFill", visual = true, type = "color", default = { 0.05, 0.22, 0.13 }, page = "minimap", box = "minimap", label = "MM_FILL_COLOR", name = "MinimapFill" },
    { key = "minimapFillOpacity", visual = true, type = "range", default = 0.8, min = 0, max = 1, step = 0.05, page = "minimap", box = "minimap", label = "MM_FILL_OPACITY_LABEL", name = "MinimapFillOpacity", show = "pct" },
    { key = "minimapArrow", visual = true, type = "bool", default = true, page = "minimap", box = "minimap", label = "MM_ARROW", name = "MinimapArrow" },
    -- Tooltips
    { key = "tooltips", type = "bool", default = true, page = "tooltips", box = "tooltips", label = "SHOW_TOOLTIPS", name = "Tooltips" },
    { key = "badgeTips", type = "bool", default = true, page = "tooltips", box = "tooltips", label = "SHOW_BADGE_TIPS", name = "BadgeTips" },
    { key = "badgeTipsXP", type = "bool", default = true, page = "tooltips", box = "tooltips", label = "SHOW_BADGE_TIP_XP", name = "BadgeTipsXP" },
    { key = "badgeTipsHideCombat", type = "bool", default = false, page = "tooltips", box = "tooltips", label = "HIDE_BADGE_TIPS_COMBAT", name = "BadgeTipsHideCombat" },
}
D[#D + 1] = { key = "showChips", type = "bool", default = true, page = "panel", box = "chips", label = "SHOW_CHIPS", name = "ShowChips" }
for _, id in ipairs(WC.CHIP_ORDER) do
    D[#D + 1] = { key = "chips." .. id, type = "bool", default = true, page = "panel", box = "chips", label = "SHOW_CHIP", labelArg = L["CHIP_" .. id], name = "Chip" .. id }
end
D[#D + 1] = { key = "chipPulse", type = "bool", default = true, page = "panel", box = "chips", label = "CHIP_PULSE", name = "ChipPulse" }
D[#D + 1] = { key = "upgradesSection", type = "bool", default = false, page = "panel", box = "chips", label = "UPGRADES_SECTION", name = "UpgradesSection" }
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
        if def.default == "auto" and v == "auto" then return "auto" end
        if type(v) ~= "table" then return copy(def.default) end
        local out = {}
        for i = 1, 3 do
            local n = tonumber(v[i])
            out[i] = n and math.max(0, math.min(1, n)) or (type(def.default) == "table" and def.default[i] or 1)
        end
        return out
    elseif t == "limit" then
        if v == "all" then return "all" end
        local n = tonumber(v)
        return (n and n >= (def.min or 1) and n == n and n < 1e6) and math.floor(n) or def.default
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

-- A brighter, lighter shade of a route colour: each channel moves part of the way to white.
function WC.LighterShade(c)
    local t = 0.45
    return { c[1] + (1 - c[1]) * t, c[2] + (1 - c[2]) * t, c[3] + (1 - c[3]) * t }
end

-- The colour of the line to the next stop: the player's own pick, or "auto", a lighter shade of lineColor.
function WC.NextLineColor()
    local v = WC.Setting("nextLineColor")
    if type(v) == "table" then return v end
    return WC.LighterShade(WC.Setting("lineColor"))
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
    s.chips = type(s.chips) == "table" and s.chips or {}
    s.minimap = type(s.minimap) == "table" and s.minimap or {}
    -- 0.4.3: the old compact checkbox became the View setting.
    if s.view == nil and s.compact == true then s.view = "compact" end
    s.compact = nil
    -- 0.4.3: the separate plan tracker is off once for existing saves; a later choice to turn it on sticks.
    db.migrated = type(db.migrated) == "table" and db.migrated or {}
    if not db.migrated.planTrackerOff then
        s.planTracker = false
        db.migrated.planTrackerOff = true
    end
    -- 0.4.6: arrowheads got smaller; a save still on the old default of 14 moves to 8 once, a chosen value stays.
    if not db.migrated.arrowSize8 then
        if s.arrowSize == nil or s.arrowSize == 14 then s.arrowSize = 8 end
        db.migrated.arrowSize8 = true
    end
    -- 0.6.45: the next-stop line follows lineColor by default; a save still on the old default yellow moves to "auto".
    if not db.migrated.nextLineAuto then
        local c = s.nextLineColor
        local old = type(c) == "table" and math.abs((tonumber(c[1]) or 0) - 1) < 1e-6 and math.abs((tonumber(c[2]) or 0) - 0.95) < 1e-6
            and math.abs((tonumber(c[3]) or 0) - 0.6) < 1e-6
        if c == nil or old then s.nextLineColor = "auto" end
        db.migrated.nextLineAuto = true
    end
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

-- Puts every row the test accepts back to its default; no other row is touched.
local function reset_where(accept)
    for _, def in ipairs(D) do
        if accept(def) then set_at(WC.db.settings, def.key, copy(def.default)) end
    end
    WC.view.expanded = {}
    WC.ApplySettings()
    if WC.SyncOptions then WC.SyncOptions() end
end

-- Puts the rows of one page (or all, page nil) back to their defaults; no other row is touched.
function WC.ResetPage(page)
    reset_where(function(def) return not page or def.page == page end)
end

-- Puts one setting back to its default and applies it; no other key is touched.
function WC.ResetSetting(key)
    local def = WC.DEF_OF[key]
    if not def or not WC.db then return end
    set_at(WC.db.settings, key, copy(def.default))
    WC.ApplyDef(def)
end

-- Every visual row (colours, opacity, sizes, spacing) back to its default; behaviour settings stay.
function WC.ResetVisuals()
    reset_where(function(def) return def.visual end)
end

-- Every setting back to its default except saved positions (the minimap button's angle).
function WC.ResetEverything()
    reset_where(function(def) return not def.position end)
end

-- True when a row holds its shipped value.
function WC.IsDefault(key)
    local def = WC.DEF_OF[key]
    if not def then return true end
    local v, d = WC.Setting(key), def.default
    if type(d) == "table" then
        return type(v) == "table" and v[1] == d[1] and v[2] == d[2] and v[3] == d[3]
    end
    return v == d
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
    if WC.SyncPlanPrefs then WC.SyncPlanPrefs() end
    if WC.panel then WC.panel:SetScale(WC.db.settings.scale) end
    if WC.ApplyButtons then WC.ApplyButtons() end
    WC.Refresh()
    if WC.RefreshPlan then WC.RefreshPlan() end
    if WC.RefreshMapPanel then WC.RefreshMapPanel() end
end

-- The panel's view: "full", "compact" or "next" (the next step only).
function WC.ViewMode()
    return WC.Setting("view")
end

-- The header button: compact on, or back to full (also leaves the next-step-only view).
function WC.SetCompact(v)
    WC.SetSetting("view", v and "compact" or "full")
end

WC.VIEW_ORDER = { "full", "compact", "next" }

-- The view after mode in the header button's cycle: Full, Compact, Next step only, Full.
function WC.NextView(mode)
    for i, v in ipairs(WC.VIEW_ORDER) do
        if v == mode then return WC.VIEW_ORDER[i % #WC.VIEW_ORDER + 1] end
    end
    return "full"
end

-- The button's label names the view you are in now.
function WC.ViewButtonLabel(mode)
    for _, v in ipairs(WC.VIEW_ORDER) do
        if v == mode then return L["VIEW_BUTTON_" .. v] end
    end
    return L.VIEW_BUTTON_full
end

-- The button's tooltip lines: the three views with the current one marked, then "Click for <next view>".
function WC.ViewTipLines(mode)
    local cur = WC.ViewButtonLabel(mode)
    local out = { { string.format(L.VIEW_TIP_TITLE, cur), true } }
    for _, v in ipairs(WC.VIEW_ORDER) do
        out[#out + 1] = { (v == mode and "> " or "   ") .. L["VIEW_" .. v], v == mode }
    end
    out[#out + 1] = { string.format(L.VIEW_CLICK, L["VIEW_BUTTON_" .. WC.NextView(mode)]), false }
    return out
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
