-- WoW Companion: adds one gold line to item and quest tooltips that match this character's digest.
-- Read-only: it only appends text to the tooltip the game is already showing, and calls nothing protected.
-- Retail and current Classic clients have TooltipDataProcessor; older ones get hooksecurefunc on the tooltip.

local WC = WoWCompanion
local L = WC.L

local GOLD = { 1, 0.82, 0 }

local function entry()
    local d = WC.EntryFor(WoWCompanionDigest, UnitName("player"))
    return type(d) == "table" and WC.SchemaOK(d.schema) and d or nil
end

local function section_lines(d, id)
    for _, s in ipairs(type(d.sections) == "table" and d.sections or {}) do
        if s.id == id and type(s.lines) == "table" then return s.lines end
    end
    return {}
end

-- The slot name of an item (from the client's own item data), or nil when it is not known yet.
local function slot_of(id)
    local loc = GetItemInfoInstant and select(4, GetItemInfoInstant(id))
    if type(loc) ~= "string" or loc == "" then return nil end
    local name = _G[loc]
    return type(name) == "string" and name or nil
end

-- The line to add for an item id or a quest id, or nil. kind is "item" or "quest".
function WC.TooltipLine(kind, id)
    id = tonumber(id)
    if not id or not WC.db or WC.db.settings.tooltips == false then return nil end
    local d = entry()
    if not d then return nil end
    if kind == "item" then
        for _, line in ipairs(section_lines(d, "upgrades")) do
            if tonumber(line.item) == id then
                local slot = slot_of(id)
                return slot and string.format(L.TOOLTIP_UPGRADE, slot) or L.TOOLTIP_UPGRADE_ANY
            end
        end
    elseif kind == "quest" then
        for n, line in ipairs(section_lines(d, "next_quests")) do
            if tonumber(line.quest) == id then return string.format(L.TOOLTIP_NEXT_STEP, n) end
        end
    end
    return nil
end

local function add(tooltip, kind, id)
    local text = WC.TooltipLine(kind, id)
    if not text then return end
    WC.TipLine(tooltip, text, GOLD)
    if tooltip.Show then tooltip:Show() end -- resizes the tooltip around the new line
end

local function link_id(link, kind)
    return type(link) == "string" and tonumber(link:match(kind .. ":(%d+)")) or nil
end

function WC.CreateTooltips()
    local T = Enum and Enum.TooltipDataType
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and T then
        TooltipDataProcessor.AddTooltipPostCall(T.Item, function(tooltip, data)
            if tooltip == GameTooltip and data then add(tooltip, "item", data.id) end
        end)
        if T.Quest then
            TooltipDataProcessor.AddTooltipPostCall(T.Quest, function(tooltip, data)
                if tooltip == GameTooltip and data then add(tooltip, "quest", data.id) end
            end)
        end
        WC.tooltipMode = "processor"
    elseif hooksecurefunc then
        hooksecurefunc(GameTooltip, "SetHyperlink", function(tooltip, link)
            add(tooltip, "quest", link_id(link, "quest")) -- items arrive through OnTooltipSetItem below
        end)
        if GameTooltip.HookScript then
            GameTooltip:HookScript("OnTooltipSetItem", function(tooltip)
                local _, link = tooltip:GetItem()
                add(tooltip, "item", link_id(link, "item"))
            end)
        end
        WC.tooltipMode = "hook"
    end
end
