-- WoW Companion: shared namespace, saved variables and the /wowc command.
-- Read-only: this addon only displays data and never sends anything.

WoWCompanion = WoWCompanion or {}
local WC = WoWCompanion

WC.NO_ADVICE = "No advice yet \226\128\148 the companion hasn't written a digest."

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(_, _, name)
    if name ~= "WoWCompanion" then return end
    WoWCompanionDB = WoWCompanionDB or {}
    WC.db = WoWCompanionDB
    WC.CreatePanel()
end)

SLASH_WOWC1 = "/wowc"
SlashCmdList["WOWC"] = function()
    WC.TogglePanel()
end
