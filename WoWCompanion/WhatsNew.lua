-- WoW Companion: a one-time "What's new" box after the addon version changes.
-- The last version the player dismissed is kept in WoWCompanionDB.lastSeenVersion.

local WC = WoWCompanion
local L = WC.L

-- Per version, the keys (in L) of its main lines.
WC.CHANGELOG = {
    ["0.4.1"] = { "WHATS_NEW_0_4_1_1", "WHATS_NEW_0_4_1_2" },
    ["0.4.0"] = { "WHATS_NEW_0_4_0_1", "WHATS_NEW_0_4_0_2" },
    ["0.3.9"] = { "WHATS_NEW_0_3_9_1", "WHATS_NEW_0_3_9_2" },
    ["0.3.8"] = { "WHATS_NEW_0_3_8_1", "WHATS_NEW_0_3_8_2" },
    ["0.3.7"] = { "WHATS_NEW_0_3_7_1", "WHATS_NEW_0_3_7_2" },
    ["0.3.6"] = { "WHATS_NEW_0_3_6_1", "WHATS_NEW_0_3_6_2" },
    ["0.3.5"] = { "WHATS_NEW_0_3_5_1", "WHATS_NEW_0_3_5_2" },
    ["0.3.4"] = { "WHATS_NEW_0_3_4_1", "WHATS_NEW_0_3_4_2" },
    ["0.3.3"] = { "WHATS_NEW_0_3_3_1", "WHATS_NEW_0_3_3_2" },
    ["0.3.2"] = { "WHATS_NEW_0_3_2_1", "WHATS_NEW_0_3_2_2" },
    ["0.3.1"] = { "WHATS_NEW_0_3_1_1", "WHATS_NEW_0_3_1_2" },
    ["0.3.0"] = { "WHATS_NEW_0_3_0_1", "WHATS_NEW_0_3_0_2", "WHATS_NEW_0_3_0_3" },
    ["0.2.0"] = { "WHATS_NEW_0_2_0_1", "WHATS_NEW_0_2_0_2", "WHATS_NEW_0_2_0_3", "WHATS_NEW_0_2_0_4" },
    ["0.1.1"] = { "WHATS_NEW_0_1_1_1", "WHATS_NEW_0_1_1_2", "WHATS_NEW_0_1_1_3" },
    ["0.1.0"] = { "WHATS_NEW_0_1_0_1", "WHATS_NEW_0_1_0_2", "WHATS_NEW_0_1_0_3", "WHATS_NEW_0_1_0_4" },
}

-- The installed version, read from the TOC.
function WC.Version()
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    return get and get("WoWCompanion", "Version") or nil
end

-- Decides what to show for version. A fresh install or a version with no changelog entry is
-- recorded as seen at once; otherwise the lines to show are returned until the box is dismissed.
function WC.WhatsNewPending(db, version, fresh)
    if not version or db.lastSeenVersion == version then return nil end
    local keys = WC.CHANGELOG[version]
    if fresh or not keys then
        db.lastSeenVersion = version
        return nil
    end
    return keys
end

function WC.DismissWhatsNew()
    local f = WC.whatsNew
    if not f then return end
    WC.db.lastSeenVersion = f.version
    f:Hide()
end

local function create_box(version, keys)
    local f = CreateFrame("Frame", "WoWCompanionWhatsNew", WC.panel, "BasicFrameTemplateWithInset")
    f:SetSize(340, 150)
    f:SetPoint("TOPLEFT", WC.panel, "BOTTOMLEFT", 0, -4)
    f.version = version
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOP", f, "TOP", 0, -5)
    f.title:SetText(string.format(L.WHATS_NEW_TITLE, version))
    local lines = {}
    for i, key in ipairs(keys) do lines[i] = "- " .. L[key] end
    f.body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.body:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -28)
    f.body:SetWidth(310)
    f.body:SetJustifyH("LEFT")
    f.body:SetText(table.concat(lines, "\n"))
    f.button = CreateFrame("Button", "WoWCompanionWhatsNewButton", f, "UIPanelButtonTemplate")
    f.button:SetSize(80, 22)
    f.button:SetPoint("BOTTOM", f, "BOTTOM", 0, 8)
    f.button:SetText(L.GOT_IT)
    f.button:SetScript("OnClick", function() WC.DismissWhatsNew() end)
    return f
end

-- Called once at load, after the panel exists.
function WC.InitWhatsNew(db, fresh)
    local version = WC.Version()
    if db.settings.showWhatsNew == false and version then
        db.lastSeenVersion = version -- the player turned the box off: note the version, show nothing
        return
    end
    local keys = WC.WhatsNewPending(db, version, fresh)
    if keys then WC.whatsNew = create_box(version, keys) end
end
