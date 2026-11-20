-- WoW Companion: the movable advice panel.

local WC = WoWCompanion

function WC.CreatePanel()
    local f = CreateFrame("Frame", "WoWCompanionPanel", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(320, 120)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
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
    f.title:SetText("WoW Companion")

    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.text:SetPoint("CENTER", f, "CENTER", 0, -10)
    f.text:SetWidth(280)
    f.text:SetText(WC.NO_ADVICE)

    f:Hide()
    WC.panel = f
end

function WC.TogglePanel()
    local f = WC.panel
    if not f then return end
    if f:IsShown() then f:Hide() else f:Show() end
end
