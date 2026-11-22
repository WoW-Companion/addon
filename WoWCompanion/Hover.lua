-- WoW Companion: mouse-over highlights for the panel, linked to the world map and minimap badges.
-- Hovering an entry brightens it and pulses its badges on the maps; hovering a badge on the world map
-- highlights its entry and scrolls it into view. Display only: it recolours our own frames.

local WC = WoWCompanion

-- The hover state: the highlighted entry groups (group key -> true), the quest ids they cover (id -> true)
-- and where the hover came from: "panel", "map" (a world map badge) or "card" (Show on map).
WC.hover = { groups = {}, quests = {}, source = nil }

local HL_ALPHA, DIM_ALPHA, LIFT = 0.14, 0.45, 0.45

-- A colour moved toward white, so the hovered title and objectives read brighter in their own hue.
function WC.Brighten(c)
    return { math.min(1, c[1] + (1 - c[1]) * LIFT), math.min(1, c[2] + (1 - c[2]) * LIFT), math.min(1, c[3] + (1 - c[3]) * LIFT) }
end

local function panel_rows()
    return WC.panel and WC.panel.rows or {}
end

-- Sets the row's look from the hover state: highlight bar, brighter text, dimmed when it is not the hovered one.
function WC.ApplyRowHover(row)
    local h = WC.hover
    local on = WC.Setting("hoverHighlight")
    local any = on and next(h.groups) ~= nil
    local lit = any and row.group ~= nil and h.groups[row.group] == true
    if row.hl then
        if lit then
            local c = WC.Setting("headerColor")
            row.hl:SetColorTexture(c[1], c[2], c[3], HL_ALPHA)
        end
        row.hl:SetShown(lit)
    end
    if row.baseColor then
        local c = lit and WC.Brighten(row.baseColor) or row.baseColor
        row.label:SetTextColor(c[1], c[2], c[3])
    end
    if row.SetAlpha then row:SetAlpha((any and not lit and WC.Setting("hoverDim")) and DIM_ALPHA or 1) end
end

-- Redraws the highlight on every panel row and the pulse on the maps.
function WC.ApplyHover()
    for _, row in ipairs(panel_rows()) do
        if row:IsShown() then WC.ApplyRowHover(row) end
    end
    if WC.ApplyMapHover then WC.ApplyMapHover() end
end

-- Scrolls the panel so the row is in view (only when it is not already).
local function scroll_into_view(row)
    local f = WC.panel
    local sf = f and f.scroll
    if not (sf and sf.SetVerticalScroll and sf.GetVerticalScroll and row.top) then return end
    local view, cur = sf:GetHeight() or 0, sf:GetVerticalScroll() or 0
    if row.top < cur or row.top + (row.hh or 0) > cur + view then
        sf:SetVerticalScroll(math.max(0, math.min(f.scrollRange or 0, row.top - 4)))
    end
end

local function set_state(groups, quests, source)
    WC.hover = { groups = groups, quests = quests, source = source }
    WC.ApplyHover()
end

-- The mouse entered a panel row of an entry: highlight the entry and pulse its badges.
function WC.HoverEnterRow(row)
    if not row.group then return end
    local quests = {}
    for _, r in ipairs(panel_rows()) do
        if r:IsShown() and r.group == row.group and r.quest then quests[r.quest] = true end
    end
    set_state({ [row.group] = true }, quests, "panel")
end

-- The mouse left a panel row (only clears what the panel set).
function WC.HoverLeaveRow()
    if WC.hover.source == "panel" then set_state({}, {}, nil) end
end

-- The mouse entered a world map badge (a group of plan steps): highlight its entries and scroll to the first.
function WC.HoverEnterBadge(group)
    if not WC.Setting("hoverMapLink") or not group then return end
    local quests = {}
    for _, s in ipairs(group.steps or {}) do
        if (s.questID or 0) > 0 then quests[s.questID] = true end
    end
    if next(quests) == nil then return end
    local groups, first = {}, nil
    for _, r in ipairs(panel_rows()) do
        if r:IsShown() and r.group and r.quest and quests[r.quest] then
            groups[r.group] = true
            first = first or r
        end
    end
    set_state(groups, quests, "map")
    if first and WC.Setting("hoverHighlight") then scroll_into_view(first) end
end

function WC.HoverLeaveBadge()
    if WC.hover.source == "map" then set_state({}, {}, nil) end
end

-- Pulses the badges of these quest ids on the maps for a moment (the card's Show on map).
function WC.PulseQuests(quests, seconds)
    local mine = { groups = {}, quests = quests, source = "card" }
    WC.hover = mine
    WC.ApplyHover()
    if C_Timer and C_Timer.After then
        C_Timer.After(seconds or 4, function()
            if WC.hover == mine then set_state({}, {}, nil) end
        end)
    end
end

-- True when a plan step's badge should pulse for the current hover (an entry of its quest is hovered).
function WC.StepHot(step)
    local h = WC.hover
    return h.source ~= nil and h.source ~= "map" and WC.Setting("hoverMapLink") and step ~= nil
        and (step.questID or 0) > 0 and h.quests[step.questID] == true
end

-- True when any step of a badge group is hot.
function WC.GroupHot(group)
    for _, s in ipairs(group and group.steps or {}) do
        if WC.StepHot(s) then return true end
    end
    return false
end

-- Drops the hover when its rows are gone (a redraw removed them while the mouse was over them).
function WC.HoverCheck()
    local h = WC.hover
    if h.source == nil or h.source == "card" then return end
    for _, r in ipairs(panel_rows()) do
        if r:IsShown() and r.group and h.groups[r.group] then return end
    end
    WC.hover = { groups = {}, quests = {}, source = nil }
    if WC.ApplyMapHover then WC.ApplyMapHover() end
end
