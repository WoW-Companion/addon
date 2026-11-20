-- WoW Companion: the movable advice panel.

local WC = WoWCompanion

function WC.CreatePanel()
    local f = CreateFrame("Frame", "WoWCompanionPanel", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(340, 260)
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

    f.header = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.header:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -28)
    f.header:SetWidth(300)
    f.header:SetJustifyH("LEFT")

    f.scroll = CreateFrame("ScrollFrame", "WoWCompanionPanelScroll", f, "UIPanelScrollFrameTemplate")
    f.scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -48)
    f.scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -32, 12)
    f.content = CreateFrame("Frame", nil, f.scroll)
    f.content:SetSize(290, 1)
    f.scroll:SetScrollChild(f.content)

    f.text = f.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.text:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, 0)
    f.text:SetWidth(290)
    f.text:SetJustifyH("LEFT")

    f:SetScript("OnShow", WC.Refresh)
    WC.panel = f
    WC.Refresh()
    f:Hide()
end

function WC.TogglePanel()
    local f = WC.panel
    if not f then return end
    if f:IsShown() then f:Hide() else f:Show() end
end

-- Re-reads the global digest table (data only) and redraws the panel.
function WC.Refresh()
    local f = WC.panel
    if not f then return end
    local header, body = WC.RenderDigest(WoWCompanionDigest, time(), UnitName("player"))
    f.header:SetText(header)
    f.text:SetText(body)
    local lines = 1
    for _ in body:gmatch("\n") do lines = lines + 1 end
    local height = lines * WC.LINE_HEIGHT
    f.content:SetHeight(height)
    f.scrollRange = math.max(0, height - f.scroll:GetHeight())
    f.scroll:UpdateScrollChildRect()
end
