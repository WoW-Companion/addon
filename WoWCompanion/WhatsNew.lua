-- WoW Companion: a one-time "What's new" box after the addon version changes.
-- The last version the player dismissed is kept in WoWCompanionDB.lastSeenVersion.

local WC = WoWCompanion
local L = WC.L

-- Per version, the keys (in L) of its main lines.
WC.CHANGELOG = {
    ["0.6.74"] = { "WHATS_NEW_0_6_74_1", "WHATS_NEW_0_6_74_2", "WHATS_NEW_0_6_74_3", "WHATS_NEW_0_6_74_4", "WHATS_NEW_0_6_74_5", "WHATS_NEW_0_6_74_6" },
    ["0.6.73"] = { "WHATS_NEW_0_6_73_1", "WHATS_NEW_0_6_73_2", "WHATS_NEW_0_6_73_3" },
    ["0.6.72"] = { "WHATS_NEW_0_6_72_1", "WHATS_NEW_0_6_72_2", "WHATS_NEW_0_6_72_3", "WHATS_NEW_0_6_72_4", "WHATS_NEW_0_6_72_5", "WHATS_NEW_0_6_72_6", "WHATS_NEW_0_6_72_7", "WHATS_NEW_0_6_72_8", "WHATS_NEW_0_6_72_9", "WHATS_NEW_0_6_72_10" },
    ["0.6.71"] = { "WHATS_NEW_0_6_71_1", "WHATS_NEW_0_6_71_2", "WHATS_NEW_0_6_71_3", "WHATS_NEW_0_6_71_4", "WHATS_NEW_0_6_71_5", "WHATS_NEW_0_6_71_6", "WHATS_NEW_0_6_71_7", "WHATS_NEW_0_6_71_8", "WHATS_NEW_0_6_71_9" },
    ["0.6.70"] = { "WHATS_NEW_0_6_70_1", "WHATS_NEW_0_6_70_2", "WHATS_NEW_0_6_70_3", "WHATS_NEW_0_6_70_4", "WHATS_NEW_0_6_70_5", "WHATS_NEW_0_6_70_6" },
    ["0.6.69"] = { "WHATS_NEW_0_6_69_1" },
    ["0.6.68"] = { "WHATS_NEW_0_6_68_1", "WHATS_NEW_0_6_68_2", "WHATS_NEW_0_6_68_3", "WHATS_NEW_0_6_68_4", "WHATS_NEW_0_6_68_5", "WHATS_NEW_0_6_68_6", "WHATS_NEW_0_6_68_7" },
    ["0.6.67"] = { "WHATS_NEW_0_6_67_1", "WHATS_NEW_0_6_67_2" },
    ["0.6.66"] = { "WHATS_NEW_0_6_66_1" },
    ["0.6.65"] = { "WHATS_NEW_0_6_65_1", "WHATS_NEW_0_6_65_2" },
    ["0.6.64"] = { "WHATS_NEW_0_6_64_1" },
    ["0.6.63"] = { "WHATS_NEW_0_6_63_1" },
    ["0.6.62"] = { "WHATS_NEW_0_6_62_1" },
    ["0.6.61"] = { "WHATS_NEW_0_6_61_1" },
    ["0.6.60"] = { "WHATS_NEW_0_6_60_1" },
    ["0.6.59"] = { "WHATS_NEW_0_6_59_1" },
    ["0.6.58"] = { "WHATS_NEW_0_6_58_1" },
    ["0.6.57"] = { "WHATS_NEW_0_6_57_1" },
    ["0.6.56"] = { "WHATS_NEW_0_6_56_1" },
    ["0.6.55"] = { "WHATS_NEW_0_6_55_1" },
    ["0.6.54"] = { "WHATS_NEW_0_6_54_1" },
    ["0.6.53"] = { "WHATS_NEW_0_6_53_1" },
    ["0.6.52"] = { "WHATS_NEW_0_6_52_1" },
    ["0.6.51"] = { "WHATS_NEW_0_6_51_1" },
    ["0.6.50"] = { "WHATS_NEW_0_6_50_1" },
    ["0.6.49"] = { "WHATS_NEW_0_6_49_1" },
    ["0.6.48"] = { "WHATS_NEW_0_6_48_1" },
    ["0.6.47"] = { "WHATS_NEW_0_6_47_1" },
    ["0.6.46"] = { "WHATS_NEW_0_6_46_1" },
    ["0.6.45"] = { "WHATS_NEW_0_6_45_1" },
    ["0.6.44"] = { "WHATS_NEW_0_6_44_1" },
    ["0.6.43"] = { "WHATS_NEW_0_6_43_1" },
    ["0.6.42"] = { "WHATS_NEW_0_6_42_1" },
    ["0.6.41"] = { "WHATS_NEW_0_6_41_1" },
    ["0.6.40"] = { "WHATS_NEW_0_6_40_1" },
    ["0.6.39"] = { "WHATS_NEW_0_6_39_1" },
    ["0.6.38"] = { "WHATS_NEW_0_6_38_1" },
    ["0.6.37"] = { "WHATS_NEW_0_6_37_1" },
    ["0.6.36"] = { "WHATS_NEW_0_6_36_1" },
    ["0.6.35"] = { "WHATS_NEW_0_6_35_1" },
    ["0.6.34"] = { "WHATS_NEW_0_6_34_1" },
    ["0.6.33"] = { "WHATS_NEW_0_6_33_1" },
    ["0.6.32"] = { "WHATS_NEW_0_6_32_1" },
    ["0.6.31"] = { "WHATS_NEW_0_6_31_1" },
    ["0.6.30"] = { "WHATS_NEW_0_6_30_1" },
    ["0.6.29"] = { "WHATS_NEW_0_6_29_1" },
    ["0.6.28"] = { "WHATS_NEW_0_6_28_1" },
    ["0.6.27"] = { "WHATS_NEW_0_6_27_1" },
    ["0.6.26"] = { "WHATS_NEW_0_6_26_1" },
    ["0.6.25"] = { "WHATS_NEW_0_6_25_1" },
    ["0.6.24"] = { "WHATS_NEW_0_6_24_1" },
    ["0.6.23"] = { "WHATS_NEW_0_6_23_1" },
    ["0.6.22"] = { "WHATS_NEW_0_6_22_1" },
    ["0.6.21"] = { "WHATS_NEW_0_6_21_1" },
    ["0.6.20"] = { "WHATS_NEW_0_6_20_1" },
    ["0.6.19"] = { "WHATS_NEW_0_6_19_1" },
    ["0.6.18"] = { "WHATS_NEW_0_6_18_1" },
    ["0.6.17"] = { "WHATS_NEW_0_6_17_1" },
    ["0.6.16"] = { "WHATS_NEW_0_6_16_1" },
    ["0.6.15"] = { "WHATS_NEW_0_6_15_1" },
    ["0.6.14"] = { "WHATS_NEW_0_6_14_1" },
    ["0.6.13"] = { "WHATS_NEW_0_6_13_1" },
    ["0.6.12"] = { "WHATS_NEW_0_6_12_1" },
    ["0.6.11"] = { "WHATS_NEW_0_6_11_1" },
    ["0.6.10"] = { "WHATS_NEW_0_6_10_1" },
    ["0.6.9"] = { "WHATS_NEW_0_6_9_1", "WHATS_NEW_0_6_8_1" },
    ["0.6.8"] = { "WHATS_NEW_0_6_8_1" },
    ["0.6.7"] = { "WHATS_NEW_0_6_7_1" },
    ["0.6.6"] = { "WHATS_NEW_0_6_6_1" },
    ["0.6.5"] = { "WHATS_NEW_0_6_5_1" },
    ["0.6.4"] = { "WHATS_NEW_0_6_4_1" },
    ["0.6.3"] = { "WHATS_NEW_0_6_3_1" },
    ["0.6.2"] = { "WHATS_NEW_0_6_2_1" },
    ["0.6.1"] = { "WHATS_NEW_0_6_1_1" },
    ["0.6.0"] = { "WHATS_NEW_0_6_0_1", "WHATS_NEW_0_6_0_2" },
    ["0.5.1"] = { "WHATS_NEW_0_5_1_1", "WHATS_NEW_0_5_0_1" }, -- carries 0.5.0's line too: the 0.5.0 zip lacked the map panel
    ["0.5.0"] = { "WHATS_NEW_0_5_0_1" },
    ["0.4.9"] = { "WHATS_NEW_0_4_9_1", "WHATS_NEW_0_4_9_2" },
    ["0.4.8"] = { "WHATS_NEW_0_4_8_1" },
    ["0.4.7"] = { "WHATS_NEW_0_4_7_1" },
    ["0.4.6"] = { "WHATS_NEW_0_4_6_1" },
    ["0.4.5"] = { "WHATS_NEW_0_4_5_1", "WHATS_NEW_0_4_5_2", "WHATS_NEW_0_4_5_3" },
    ["0.4.4"] = { "WHATS_NEW_0_4_4_1", "WHATS_NEW_0_4_4_2", "WHATS_NEW_0_4_4_3" },
    ["0.4.3"] = { "WHATS_NEW_0_4_3_1", "WHATS_NEW_0_4_3_2" },
    ["0.4.2"] = { "WHATS_NEW_0_4_2_1", "WHATS_NEW_0_4_2_2" },
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

WC.WHATS_NEW_TEXT_W = 288
WC.WHATS_NEW_MIN_H, WC.WHATS_NEW_MAX_H = 110, 300

-- The window height for body text of height h: it grows with the text up to a cap, then the text scrolls.
function WC.WhatsNewWindowHeight(h)
    return math.max(WC.WHATS_NEW_MIN_H, math.min(WC.WHATS_NEW_MAX_H, h + 28 + 38 + 6))
end

WC.WHATS_NEW_LONG = 140 -- an entry over this many characters is split into bullets
WC.WHATS_NEW_INDENT, WC.WHATS_NEW_GAP = 10, 4

-- Splits one long legacy entry at sentence ends (". " before a capital) and at "; ". A short entry is returned whole.
function WC.WhatsNewSplit(text)
    if #text <= WC.WHATS_NEW_LONG then return { text } end
    local out, start, i, semi = {}, 1, 1, {}
    while i <= #text do
        local c = text:sub(i, i)
        local cut
        if c == ";" and text:sub(i + 1, i + 1) == " " then cut = i
        elseif c == "." and text:sub(i + 1, i + 1) == " " and text:sub(i + 2, i + 2):match("%u") then cut = i end
        if cut then
            local piece = text:sub(start, c == ";" and cut - 1 or cut)
            if #piece > 0 then out[#out + 1] = piece; semi[#out] = c == ";" end
            start = cut + 2
            i = start
        else
            i = i + 1
        end
    end
    local tail = text:sub(start)
    if #tail > 0 then out[#out + 1] = tail end
    for n, piece in ipairs(out) do
        if semi[n] then out[n] = piece .. "." end -- a "; " cut drops the stop
        if semi[n - 1] then out[n] = out[n]:sub(1, 1):upper() .. out[n]:sub(2) end
    end
    return out
end

-- The bullet texts for a version's keys, long entries split.
function WC.WhatsNewBullets(keys)
    local out = {}
    for _, key in ipairs(keys) do
        for _, piece in ipairs(WC.WhatsNewSplit(L[key])) do out[#out + 1] = piece end
    end
    return out
end

local function create_box(version, keys)
    local f = CreateFrame("Frame", "WoWCompanionWhatsNew", WC.panel, "BasicFrameTemplateWithInset")
    f:SetSize(340, 150) -- resized below to fit the text
    f:SetPoint("TOPLEFT", WC.panel, "BOTTOMLEFT", 0, -4)
    f.version = version
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOP", f, "TOP", 0, -5)
    f.title:SetText(string.format(L.WHATS_NEW_TITLE, version))
    local bullets = WC.WhatsNewBullets(keys)
    -- The text lives in a scroll frame (its bar shows when the text overflows); the Got it button sits below it.
    f.scroll = CreateFrame("ScrollFrame", "WoWCompanionWhatsNewScroll", f, "UIPanelScrollFrameTemplate")
    f.scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -28)
    f.scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -30, 38)
    f.content = CreateFrame("Frame", nil, f.scroll)
    f.content:SetSize(WC.WHATS_NEW_TEXT_W, 1)
    f.scroll:SetScrollChild(f.content)
    -- One row per bullet: a marker, and the text indented past it so wrapped lines line up under the first.
    f.rows, f.marks = {}, {}
    local indent, gap = WC.WHATS_NEW_INDENT, WC.WHATS_NEW_GAP
    local h = 0
    for i, text in ipairs(bullets) do
        local row = f.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        if i == 1 then row:SetPoint("TOPLEFT", f.content, "TOPLEFT", indent, 0)
        else row:SetPoint("TOPLEFT", f.rows[i - 1], "BOTTOMLEFT", 0, -gap) end
        row:SetWidth(WC.WHATS_NEW_TEXT_W - indent)
        row:SetJustifyH("LEFT")
        if WC.StyleText then WC.StyleText(row) end
        row:SetText(WC.SafeText(text))
        local mark = f.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        mark:SetPoint("TOPLEFT", row, "TOPLEFT", -indent, 0)
        mark:SetText("·")
        if WC.StyleText then WC.StyleText(mark) end
        f.rows[i], f.marks[i] = row, mark
        local rh = (row.GetStringHeight and row:GetStringHeight()) or 0
        if rh <= 0 then rh = 14 end
        h = h + rh + (i > 1 and gap or 0)
    end
    f.content:SetHeight(h + 4)
    f.window = WC.WhatsNewWindowHeight(h)
    f:SetSize(340, f.window)
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
