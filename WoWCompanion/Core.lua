-- WoW Companion: shared namespace, saved variables and the /wowc command.
-- Read-only: this addon only displays data and never sends anything.

WoWCompanion = WoWCompanion or {}
local WC = WoWCompanion
local L = WC.L

WC.NO_ADVICE = L.NO_ADVICE

-- The release zip leaves out the data file so an update never overwrites a player's data;
-- until the companion writes it the global is an empty table. The slot addon loads after this
-- file, so a real data file replaces it.
WoWCompanionDigest = WoWCompanionDigest or {}

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(_, _, name)
    if name ~= "WoWCompanion" then return end
    local fresh = WoWCompanionDB == nil or next(WoWCompanionDB) == nil
    WoWCompanionDB = WoWCompanionDB or {}
    WC.db = WoWCompanionDB
    WC.ResetCaptureSnapshot()
    WC.OwnCapturedAt(UnitName("player")) -- snapshot ForeverScribe's on-disk capture time before its login refresh
    WC.InitSettings(WC.db)
    WC.CreatePanel()
    WC.CreateTracker()
    WC.InitWhatsNew(WC.db, fresh)
    WC.CreateOptions()
    WC.CreateSettings()
    WC.CreateButton()
    WC.CreatePlanUI()
    WC.CreateTooltips()
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

-- Queues the text (see docs/ask-format.md) and says so; empty text just toggles the panel.
local function ask(text)
    if WC.SubmitAsk(text) then
        print(L.ASK_QUEUED)
    else
        WC.TogglePanel()
    end
end
WC.Ask = ask

WC.HELP = {
    L.HELP_TITLE, L.HELP_PANEL, L.HELP_ASK, L.HELP_PLAN, L.HELP_SETTINGS, L.HELP_RESET, L.HELP_RESET_VISUALS, L.HELP_RESET_ALL, L.HELP_STATUS, L.HELP_HELP,
}

SlashCmdList["WOWC"] = function(msg)
    msg = msg or ""
    local question = msg:match("^%s*ask%s+(.*)$")
    local cmd = (msg:match("^%s*(%S+)") or ""):lower()
    if question then
        ask(question)
    elseif cmd == "" or cmd == "ask" then
        WC.TogglePanel()
    elseif cmd == "settings" or cmd == "options" or cmd == "config" then
        WC.OpenOptions()
    elseif cmd == "plan" then
        WC.TogglePlan((msg:match("^%s*%S+%s+(%S+)") or ""):lower(), (msg:match("^%s*%S+%s+%S+%s+(%S+)") or ""):lower())
    elseif cmd == "status" then
        WC.PrintStatus()
    elseif cmd == "reset" then
        local what = (msg:match("^%s*%S+%s+(%S+)") or ""):lower()
        if what == "visuals" then
            WC.Confirm(L.CONFIRM_RESET_VISUALS, WC.ResetVisuals)
        elseif what == "all" then
            WC.Confirm(L.CONFIRM_RESET_ALL, WC.ResetEverything)
        else
            WC.ResetPanel()
        end
    else
        for _, line in ipairs(WC.HELP) do print(line) end
    end
end

SlashCmdList["WOWCASK"] = ask
