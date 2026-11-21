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
    WC.InitSettings(WC.db)
    WC.CreatePanel()
    WC.CreateSettings()
    WC.CreateButton()
end)

-- The slot addon loads after us, so redraw once everything is in.
local late = CreateFrame("Frame")
late:RegisterEvent("PLAYER_LOGIN")
late:SetScript("OnEvent", function()
    WC.Refresh()
    if WC.db and WC.db.settings.openOnLogin then WC.ShowPanel() end
end)

SLASH_WOWC1 = "/wowc"
SLASH_WOWCASK1 = "/ask"

local function ask(text)
    if WC.SubmitAsk(text) then
        WC.ShowPanel()
    else
        WC.TogglePanel()
    end
end

WC.HELP = {
    "WoW Companion commands:",
    "  /wowc - show or hide the panel",
    "  /wowc ask <question> (or /ask <question>) - queue a question; it is sent on /reload",
    "  /wowc history - browse past answers; /wowc history clear - clear them (asks first)",
    "  /wowc settings - open the settings page",
    "  /wowc reset - restore the panel position and expand all sections",
    "  /wowc help - show this list",
}

SlashCmdList["WOWC"] = function(msg)
    msg = msg or ""
    local text = msg:match("^%s*ask%s+(.*)$")
    local cmd = (msg:match("^%s*(%S+)") or ""):lower()
    if text then
        ask(text)
    elseif cmd == "" or cmd == "ask" then
        WC.TogglePanel()
    elseif cmd == "history" then
        local sub = (msg:match("^%s*%S+%s+(%S+)") or ""):lower()
        if sub == "clear" then WC.RequestClearHistory() else WC.ShowHistory(true, false) end
    elseif cmd == "settings" or cmd == "options" then
        WC.OpenSettings()
    elseif cmd == "reset" then
        WC.ResetPanel()
    else
        for _, line in ipairs(WC.HELP) do print(line) end
    end
end

SlashCmdList["WOWCASK"] = ask
