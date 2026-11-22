-- WoW Companion: an optional one-line "Next up" tracker showing the digest's first next step.
-- Display only: it reads the digest table as data and a click only opens the panel.

local WC = WoWCompanion
local L = WC.L

local function plain(s)
    return (tostring(s):gsub("|", "||"))
end

-- The tracker's text for a digest: its first next_quests line and how many steps follow it.
-- now and captured (optional) add the out-of-date marker, see WC.DigestOutdated.
function WC.TrackerText(d, player, now, captured)
    if type(d) ~= "table" or next(d) == nil then return L.TRACKER_EMPTY end
    local e = WC.EntryFor(d, player)
    if not e then return string.format(L.TRACKER_NONE, plain(player)) end
    d = e
    if not WC.SchemaOK(d.schema) or type(d.sections) ~= "table" then return L.TRACKER_EMPTY end
    for _, section in ipairs(d.sections) do
        local lines = section.id == "next_quests" and section.lines
        if type(lines) == "table" then
            local live = {} -- live text per line; turned-in quests drop out
            for _, line in ipairs(lines) do
                local t = type(line) == "table" and line.text and WC.LiveLineText(line.text, tonumber(line.quest))
                if t then live[#live + 1] = t end
            end
            if live[1] then
                local text = string.format(L.TRACKER_NEXT, plain(live[1]))
                if #live > 1 then text = text .. string.format(L.TRACKER_MORE, #live - 1) end
                if now and WC.DigestOutdated(d, now, captured) then text = text .. " (" .. L.OUT_OF_DATE_SHORT:lower() .. ")" end
                return text
            end
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
    f.label:SetText(WC.TrackerText(WoWCompanionDigest, who, time(), WC.OwnCapturedAt(who)))
    if WC.CombatHides("tracker") then
        -- Held hidden by combat: remember to bring it back when combat ends.
        WC.combatShown.tracker = true
        return
    end
    f:Show()
end
