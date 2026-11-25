-- WoW Companion: shared namespace, saved variables and the /wowc command.
-- Read-only: this addon only displays data and never sends anything.

WoWCompanion = WoWCompanion or {}
local WC = WoWCompanion
local L = WC.L

WC.NO_ADVICE = L.NO_ADVICE

-- A value that may be written to SavedVariables: nil for a secret value (the client's issecretvalue, when it
-- exists), otherwise only a string, number or boolean.
function WC.Clean(v)
    if issecretvalue then
        local ok, secret = pcall(issecretvalue, v)
        if not ok or secret then return nil end
    end
    local t = type(v)
    if t == "string" or t == "number" or t == "boolean" then return v end
    return nil
end

-- Removes, in place, every value in a table tree that WC.Clean refuses (secret values, functions, userdata).
function WC.CleanTree(t, depth)
    if type(t) ~= "table" then return t end
    depth = depth or 0
    if depth > 8 then return t end
    for k, v in pairs(t) do
        if type(v) == "table" and not (issecretvalue and select(2, pcall(issecretvalue, v)) ~= false) then
            WC.CleanTree(v, depth + 1)
        elseif type(v) == "table" then t[k] = nil
        elseif WC.Clean(v) == nil then t[k] = nil end
    end
    return t
end

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
    if WC.db then WC.PruneAsks(WC.db, WoWCompanionDigest, time()) end
    WC.Refresh()
    if WC.db and WC.db.settings.openOnLogin then WC.ShowPanel() end
end)

SLASH_WOWC1 = "/wowc"
WC.HELP = {
    L.HELP_TITLE, L.HELP_PANEL, L.HELP_PLAN, L.HELP_SETTINGS, L.HELP_RESET, L.HELP_RESET_VISUALS, L.HELP_RESET_ALL, L.HELP_STATUS, L.HELP_HELP,
}

SlashCmdList["WOWC"] = function(msg)
    msg = msg or ""
    local cmd = (msg:match("^%s*(%S+)") or ""):lower()
    if cmd == "" then
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
    elseif cmd == "copytest" then
        WC.CopyTest()
    else
        for _, line in ipairs(WC.HELP) do print(line) end
        if (msg:match("^%s*%S+%s+(%S+)") or ""):lower() == "debug" then print(L.HELP_COPYTEST) end
    end
end

