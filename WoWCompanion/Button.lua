-- WoW Companion: a button that toggles the panel. Uses the addon compartment when the client
-- has one, otherwise a plain-frame minimap button that can be dragged around the minimap edge.

local WC = WoWCompanion

WC.ICON = "Interface\\Icons\\INV_Misc_Book_09"
WC.MINIMAP_RADIUS = 80

-- Angle in degrees from the minimap centre (mx, my) to the cursor (cx, cy), given the minimap's scale.
function WC.MinimapAngle(cx, cy, mx, my, scale)
    local atan2 = math.atan2 or math.atan
    return math.deg(atan2(cy / scale - my, cx / scale - mx))
end

function WC.PlaceMinimapButton()
    local b = WC.minimapButton
    if not b then return end
    local a = math.rad(WC.db.settings.minimap.angle)
    b:ClearAllPoints()
    b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * WC.MINIMAP_RADIUS, math.sin(a) * WC.MINIMAP_RADIUS)
end

local function create_minimap_button()
    local b = CreateFrame("Button", "WoWCompanionMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp")
    b:RegisterForDrag("LeftButton")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(20, 20)
    b.icon:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.icon:SetTexture(WC.ICON)
    b:SetScript("OnClick", function() WC.TogglePanel() end)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            WC.db.settings.minimap.angle = WC.MinimapAngle(cx, cy, mx, my, Minimap:GetEffectiveScale())
            WC.PlaceMinimapButton()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    WC.minimapButton = b
    WC.PlaceMinimapButton()
end

function WC.CreateButton()
    if AddonCompartmentFrame and AddonCompartmentFrame.RegisterAddon then
        AddonCompartmentFrame:RegisterAddon({
            text = WC.L.ADDON_NAME,
            icon = WC.ICON,
            notCheckable = true,
            func = function() WC.TogglePanel() end,
        })
        WC.buttonMode = "compartment"
    else
        create_minimap_button()
        WC.buttonMode = "minimap"
    end
end
