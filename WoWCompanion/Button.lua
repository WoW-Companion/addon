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

-- The tooltip's lines from plain values: info = { digest, db, player, now }.
function WC.TooltipLines(info)
    local L = WC.L
    local out = { L.ADDON_NAME }
    local d = WC.EntryFor(info.digest, info.player)
    local gen = type(d) == "table" and tonumber(d.generated)
    out[#out + 1] = gen and string.format(L.TIP_DIGEST, WC.FormatClock(gen), WC.FormatAge(math.max(0, info.now - gen))) or L.TIP_DIGEST_NONE
    if type(d) == "table" and gen and WC.DigestOutdated(d, info.now, info.captured) then out[#out + 1] = L.TIP_OUT_OF_DATE end
    out[#out + 1] = string.format(L.TIP_QUEUED, WC.Unanswered(info.db))
    out[#out + 1] = L.TIP_CLICK
    return out
end

-- Display only: fills the game tooltip next to the button.
local function show_tooltip(owner)
    local lines = WC.TooltipLines({ digest = WoWCompanionDigest, db = WC.db or {}, player = UnitName("player"), now = time(),
        captured = WC.OwnCapturedAt(UnitName("player")) })
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    for _, line in ipairs(lines) do GameTooltip:AddLine(line) end
    GameTooltip:Show()
end

local function hide_tooltip() GameTooltip:Hide() end

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
    b:SetScript("OnEnter", show_tooltip)
    b:SetScript("OnLeave", hide_tooltip)
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
            funcOnEnter = show_tooltip,
            funcOnLeave = hide_tooltip,
        })
        WC.buttonMode = "compartment"
    else
        create_minimap_button()
        WC.buttonMode = "minimap"
    end
end
