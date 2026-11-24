-- WoW Companion: hides the panel and the Next up line during combat and brings them back after.
-- Display only. Every frame we create is a plain Frame/Button/EditBox/Slider with no secure or
-- protected template, so Show and Hide are allowed in combat and nothing here touches a protected action.

local WC = WoWCompanion

-- The frames this can hide: the setting key and the frame's getter.
local TARGETS = {
    { "tracker", function() return WC.tracker end },
    { "panel", function() return WC.panel end },
}

WC.inCombat = false
WC.combatShown = {} -- keys of the frames that were visible when combat began

-- True while combat is holding this frame ("tracker" or "panel") hidden by the setting.
function WC.CombatHides(key)
    return WC.inCombat and WC.db ~= nil and WC.db.settings.hideInCombat[key] == true
end

function WC.EnterCombat()
    if WC.inCombat or not WC.db then return end
    WC.inCombat = true
    for _, t in ipairs(TARGETS) do
        local f = t[2]()
        if f and WC.db.settings.hideInCombat[t[1]] and f:IsShown() then
            WC.combatShown[t[1]] = true
            f:Hide()
        end
    end
end

function WC.LeaveCombat()
    if not WC.inCombat then return end
    WC.inCombat = false
    for _, t in ipairs(TARGETS) do
        local f = t[2]()
        if f and WC.combatShown[t[1]] then f:Show() end
    end
    WC.combatShown = {}
    WC.RefreshTracker()
    if WC.SidePanelCombatEnded then WC.SidePanelCombatEnded() end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        WC.EnterCombat()
    elseif event == "PLAYER_REGEN_ENABLED" then
        WC.LeaveCombat()
    elseif InCombatLockdown and InCombatLockdown() then
        -- A /reload in combat fires no PLAYER_REGEN_DISABLED, so start from the login itself.
        WC.EnterCombat()
    end
end)
