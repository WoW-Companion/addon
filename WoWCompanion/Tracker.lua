-- WoW Companion: an optional one-line "Next up" tracker showing the digest's first next step.
-- Display only: it reads the digest table as data and a click only opens the panel.

local WC = WoWCompanion
local L = WC.L

local function plain(s)
    return (tostring(s):gsub("|", "||"))
end

-- The tracker's text for a digest: its first next_quests line and how many steps follow it.
function WC.TrackerText(d, player)
    if type(d) ~= "table" or d.schema ~= WC.SCHEMA or d.character ~= player or type(d.sections) ~= "table" then
        return L.TRACKER_EMPTY
    end
    for _, section in ipairs(d.sections) do
        local lines = section.id == "next_quests" and section.lines
        if type(lines) == "table" and type(lines[1]) == "table" and lines[1].text then
            local text = string.format(L.TRACKER_NEXT, plain(lines[1].text))
            if #lines > 1 then text = text .. string.format(L.TRACKER_MORE, #lines - 1) end
            return text
        end
    end
    return L.TRACKER_EMPTY
end

function WC.CreateTracker()
    local f = CreateFrame("Button", "WoWCompanionTracker", UIParent)
    f:SetSize(280, 22)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForClicks("LeftButtonUp")
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if not WC.db.settings.locked then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        WC.db.trackerPosition = { point = point, relPoint = relPoint, x = x, y = y }
    end)
    f:SetScript("OnClick", function() WC.ShowPanel() end)

    local pos = WC.db.trackerPosition
    if type(pos) == "table" and pos.point then
        f:SetPoint(pos.point, UIParent, pos.relPoint, tonumber(pos.x) or 0, tonumber(pos.y) or 0)
    else
        f:SetPoint("TOP", UIParent, "TOP", 0, -120)
    end
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints(f)
    f.bg:SetColorTexture(0, 0, 0, 0.5)
    f.label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.label:SetPoint("LEFT", f, "LEFT", 6, 0)
    f.label:SetWidth(268)
    f.label:SetJustifyH("LEFT")
    WC.tracker = f
    WC.RefreshTracker()
end

-- Shows or hides the line per the setting and redraws it from the current digest.
function WC.RefreshTracker()
    local f = WC.tracker
    if not f then return end
    if not WC.db.settings.tracker then
        f:Hide()
        return
    end
    WC.StyleText(f.label)
    local who = UnitName("player")
    f.label:SetText(WC.TrackerText(WoWCompanionDigest, who))
    f:Show()
end
