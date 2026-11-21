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

-- The slot addon loads after us, so redraw once everything is in.
local late = CreateFrame("Frame")
late:RegisterEvent("PLAYER_LOGIN")
late:SetScript("OnEvent", function() WC.Refresh() end)

SLASH_WOWC1 = "/wowc"
SLASH_WOWCASK1 = "/ask"

local function ask(text)
    if WC.db and WC.QueueAsk(WC.db, text, UnitName("player"), time()) then
        WC.ShowPanel()
    else
        WC.TogglePanel()
    end
end

SlashCmdList["WOWC"] = function(msg)
    local text = (msg or ""):match("^%s*ask%s+(.*)$")
    if text then ask(text) else WC.TogglePanel() end
end

SlashCmdList["WOWCASK"] = ask
