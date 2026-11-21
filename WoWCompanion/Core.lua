-- WoW Companion: shared namespace, saved variables and the /wowc command.
-- Read-only: this addon only displays data and never sends anything.

WoWCompanion = WoWCompanion or {}
local WC = WoWCompanion
local L = WC.L

WC.NO_ADVICE = L.NO_ADVICE

-- The release zip leaves out the two data files so an update never overwrites a player's data;
-- until the companion writes them the globals are empty tables. The slot addons load after this
-- file, so a real data file replaces these.
WoWCompanionDigest = WoWCompanionDigest or {}
WoWCompanionAnswers = WoWCompanionAnswers or {}

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(_, _, name)
    if name ~= "WoWCompanion" then return end
    local fresh = WoWCompanionDB == nil or next(WoWCompanionDB) == nil
    WoWCompanionDB = WoWCompanionDB or {}
    WC.db = WoWCompanionDB
    WC.InitSettings(WC.db)
    WC.CreatePanel()
    WC.CreateTracker()
    WC.InitWhatsNew(WC.db, fresh)
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
    L.HELP_TITLE, L.HELP_PANEL, L.HELP_ASK, L.HELP_HISTORY, L.HELP_SETTINGS, L.HELP_RESET, L.HELP_STATUS, L.HELP_HELP,
}

SlashCmdList["WOWC"] = function(msg)
    msg = msg or ""
    local question = msg:match("^%s*ask%s+(.*)$")
    local cmd = (msg:match("^%s*(%S+)") or ""):lower()
    if question then
        ask(question)
    elseif cmd == "" or cmd == "ask" then
        WC.TogglePanel()
    elseif cmd == "history" then
        local sub = (msg:match("^%s*%S+%s+(%S+)") or ""):lower()
        if sub == "clear" then WC.RequestClearHistory() else WC.ShowHistory(true, false) end
    elseif cmd == "settings" or cmd == "options" then
        WC.OpenSettings()
    elseif cmd == "status" then
        WC.PrintStatus()
    elseif cmd == "reset" then
        WC.ResetPanel()
    else
        for _, line in ipairs(WC.HELP) do print(line) end
    end
end

SlashCmdList["WOWCASK"] = ask
