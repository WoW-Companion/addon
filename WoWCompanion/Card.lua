-- WoW Companion: clicking panel entries, and the detail card.
-- A left-click on a quest in the log opens it in the client's own quest log (out of combat); a click on
-- anything else, or a right-click on anything, opens a card beside the panel with the entry's details, live
-- facts and the entry's natural questions as one-click chips. Read-only: nothing leaves the game. A question chip
-- opens a selected edit box under it that the player copies with Ctrl+C and pastes into the overlay.

local WC = WoWCompanion
local L = WC.L

local CARD_W, PAD, SCROLL_W, MARGIN = 320, 10, 18, 24
local MAX_ASK_LEN = 500
local GREY, GOLD, GREEN = { 0.72, 0.72, 0.72 }, { 1, 0.82, 0 }, { 0.25, 0.9, 0.25 }
local ART = "Interface\\Icons\\"
local KIND_ICON = {
    ["note"] = ART .. "INV_Misc_Note_01", ["giver"] = "Interface\\GossipFrame\\AvailableQuestIcon", ["material"] = ART .. "INV_Misc_Bag_08",
    ["dungeon"] = ART .. "INV_Misc_Map_01", ["upgrade"] = ART .. "INV_Misc_QuestionMark",
    ["stats"] = WC.ICONS.stats,
}

-- ---------------------------------------------------------------- client calls (each guarded; none protected)

-- The key bound to a binding action, or the default shown when none is bound or the client cannot say.
function WC.BindingKey(action, default)
    local ok, key = pcall(function() return GetBindingKey and GetBindingKey(action) end)
    return (ok and type(key) == "string" and key ~= "") and key or default
end

local function quest_log_hint()
    return string.format(L.CARD_QUESTLOG_HINT, WC.BindingKey("TOGGLEQUESTLOG", "L"))
end

-- Opens the quest in the client's own quest log, out of combat only. Returns true when a client call was made.
-- Calls: QuestMapFrame_OpenToQuestDetails (retail's map quest log), else QuestLog_OpenToQuest or
-- SelectQuestLogEntry with ShowUIPanel(QuestLogFrame) (classic). None is a protected function; each runs in pcall.
function WC.OpenQuestLog(questID)
    if not questID or (InCombatLockdown and InCombatLockdown()) then return false end
    if type(QuestMapFrame_OpenToQuestDetails) == "function" then
        return (pcall(QuestMapFrame_OpenToQuestDetails, questID))
    end
    local q = C_QuestLog
    local idx = q and type(q.GetLogIndexForQuestID) == "function" and q.GetLogIndexForQuestID(questID) or nil
    if not idx then return false end
    if type(QuestLog_OpenToQuest) == "function" then return (pcall(QuestLog_OpenToQuest, idx)) end
    if type(SelectQuestLogEntry) == "function" and QuestLogFrame and type(ShowUIPanel) == "function" then
        pcall(SelectQuestLogEntry, idx)
        return (pcall(ShowUIPanel, QuestLogFrame))
    end
    return false
end

-- Puts the quest's link in the chat edit box the player already has open: ChatEdit_InsertLink only inserts
-- text into an open box and sends nothing. Returns true when the link went in.
function WC.LinkQuest(questID)
    if not questID or type(ChatEdit_InsertLink) ~= "function" then return false end
    local q = C_QuestLog
    local get = (q and q.GetQuestLink) or GetQuestLink
    if type(get) ~= "function" then return false end
    local ok, link = pcall(get, questID)
    if not ok or type(link) ~= "string" or link == "" then return false end
    local ok2, inserted = pcall(ChatEdit_InsertLink, link)
    return ok2 and inserted == true
end

-- The plan's steps for a quest id, in plan order.
function WC.QuestSteps(questID)
    local out = {}
    for _, s in ipairs(WC.plan and WC.plan.steps or {}) do
        if questID and s.questID == questID then out[#out + 1] = s end
    end
    return out
end

-- Opens the world map on the zone of the quest's next plan step and pulses its badges, out of combat only.
-- Calls: OpenWorldMap(mapID) when the client has it, else WorldMapFrame:SetMapID and ShowUIPanel(WorldMapFrame).
function WC.ShowOnMap(entry)
    local steps = WC.QuestSteps(entry.quest)
    if #steps == 0 then return false end
    if InCombatLockdown and InCombatLockdown() then return false end
    local step = steps[1]
    for _, s in ipairs(steps) do
        if not (WC.plan.done and WC.plan.done[s.n]) then step = s break end
    end
    if type(OpenWorldMap) == "function" then
        pcall(OpenWorldMap, step.map)
    elseif WorldMapFrame then
        if WorldMapFrame.SetMapID then pcall(WorldMapFrame.SetMapID, WorldMapFrame, step.map) end
        if type(ShowUIPanel) == "function" then pcall(ShowUIPanel, WorldMapFrame) elseif WorldMapFrame.Show then WorldMapFrame:Show() end
    end
    WC.PulseQuests({ [entry.quest] = true }, 5)
    return true
end

-- ---------------------------------------------------------------- click routing

-- What a click on an entry does: "card", "quest" (open it in the client's quest log), "link" (shift-click)
-- or "combat" (a quest click while in combat, which does nothing but say so).
function WC.ClickAction(entry, button, shift, combat)
    if button == "RightButton" or entry.kind ~= "quest" then return "card" end
    if shift and entry.quest and type(ChatEdit_InsertLink) == "function" then return "link" end
    if WC.Setting("clickAction") == "card" then return "card" end
    local st = entry.quest and WC.PlanQuestState(entry.quest)
    if st ~= "active" and st ~= "ready" then return "card" end
    if combat then return "combat" end
    return "quest"
end

function WC.EntryClick(entry, button)
    if entry.kind == "upgrade" and not entry.upgrades and WC.OpenUpgradeRow(entry) then return end
    local act = WC.ClickAction(entry, button, IsShiftKeyDown and IsShiftKeyDown(), InCombatLockdown and InCombatLockdown())
    if act == "link" then
        if WC.LinkQuest(entry.quest) then return end
        act = WC.ClickAction(entry, button, false, InCombatLockdown and InCombatLockdown())
    end
    if act == "card" then
        WC.OpenCard(entry)
    elseif act == "combat" then
        print(L.CARD_COMBAT)
    elseif act == "quest" and not WC.OpenQuestLog(entry.quest) then
        print(quest_log_hint())
    end
end

-- ---------------------------------------------------------------- card contents (pure data)

local function row(text, color) return { text = text, color = color or GREY } end

-- The facts a quest card shows live: its state and objectives with counts, or where to pick it up.
local function quest_rows(entry, rows)
    local st = entry.quest and WC.PlanQuestState(entry.quest) or "none"
    if st == "ready" then rows[#rows + 1] = row(L.READY_LINE, WC.Setting("readyColor")) end
    if st == "active" or st == "ready" then
        for _, o in ipairs(WC.QuestObjectives(entry.quest) or {}) do
            rows[#rows + 1] = row(o.text, WC.Setting(o.finished and "doneColor" or "objectiveColor"))
        end
    elseif entry.npc then
        local t = entry.zone and string.format(L.PICK_UP_FROM_IN, entry.npc, entry.zone) or string.format(L.PICK_UP_FROM, entry.npc)
        rows[#rows + 1] = row(t)
    end
    return st
end

-- Removes body rows that say what the header already says, or what an earlier row said.
local function same_words(a)
    return (tostring(a):lower():gsub("^you have ", ""):gsub("[%s%p]+", " "):gsub("^ ", ""):gsub(" $", ""))
end
local function drop_repeats(rows, ...)
    local seen = {}
    for i = 1, select("#", ...) do
        local t = select(i, ...)
        if t then seen[same_words(t)] = true end
    end
    local out = {}
    for _, r in ipairs(rows) do
        local k = same_words(r.text)
        if not seen[k] then
            seen[k] = true
            out[#out + 1] = r
        end
    end
    for i = 1, math.max(#rows, #out) do rows[i] = out[i] end
end

-- One upgrade as a list row: line 1 is the slot and the gain, line 2 what to look for; the detail rows and the
-- question chips show only when the row is expanded. Each fact is said once.
local GAIN_COLOR = { big = { 0.25, 0.9, 0.25 }, solid = { 0.6, 0.9, 0.45 }, small = GREY }
function WC.UpgradeListRow(u)
    local p = WC.UpgradeParts(u)
    local look = string.format(L.CARD_LOOK_FOR, p.look)
    if p.wear then look = p.wear .. " \194\183 " .. look end
    local gain_key = p.gain and p.gain:lower():match("^(%a+)")
    local r = {
        slot = p.slot or L.CARD_KIND_upgrade, gain = p.gain, gainColor = GAIN_COLOR[gain_key] or GREY, look = look,
        icon = WC.PATH_ICONS[u.pathKind], asks = u.asks or {}, entry = u, detail = {},
    }
    r.detail[1] = row(string.format(L.CARD_YOU_WEAR, p.worn), WC.COLORS.white)
    if WC.HasUpgradePath(u) then r.detail[2] = row(u.how, GREY) end
    for _, mat in ipairs(u.materials or {}) do r.detail[#r.detail + 1] = row(string.format(L.CARD_MATERIAL_HAVE, mat.name, mat.have, mat.need)) end
    return r
end

-- The card for an entry as data: { title, icon, subtitle, rows = { {text, color} }, link, actions, hints, asks, ref, answer }.
--  quest/pickup: details, live state and objectives; Open in quest log (in the log), Show on map (a plan step).
--  training: each spell not yet known with its rank and "new"/"upgrade"; a Spellbook key hint.
--  talent: unspent points and the plan's next pick; a Talents key hint.
--  upgrade: slot and item level, and the item link (tooltip on hover). dungeon, material, note: details.
function WC.CardModel(entry)
    local m = { rows = {}, actions = {}, hints = {}, entry = entry }
    local rows, kind = m.rows, entry.kind
    m.title = entry.title or ""
    m.icon = KIND_ICON[kind]
    local level = tonumber(entry.level)
    if kind == "quest" then
        m.title = (entry.quest and WC.QuestTitle(entry.quest)) or m.title
        level = (entry.quest and WC.QuestLevel and WC.QuestLevel(entry.quest)) or level
    end
    local label = L["CARD_KIND_" .. kind] or L.CARD_KIND_note
    m.subtitle = level and string.format(L.CARD_LEVEL_KIND, math.floor(level), label) or label
    if entry.why then rows[#rows + 1] = row(entry.why, WC.COLORS.white) end
    for _, d in ipairs(entry.details or {}) do rows[#rows + 1] = row(d, WC.COLORS.white) end
    if kind == "quest" then
        local st = quest_rows(entry, rows)
        m.icon = WC.ICONS[st == "ready" and "turnin" or (st == "active" and "progress" or "pickup")]
        if st == "active" or st == "ready" then m.actions[#m.actions + 1] = { id = "quest", label = L.CARD_OPEN_QUEST } end
        if #WC.QuestSteps(entry.quest) > 0 then m.actions[#m.actions + 1] = { id = "map", label = L.CARD_SHOW_MAP } end
    elseif kind == "training" then
        m.icon = WC.ICONS.talent
        local left = {}
        for _, sp in ipairs(entry.spells or {}) do
            if not WC.SpellKnown(sp.id) then
                left[#left + 1] = sp
                rows[#rows + 1] = row(string.format(sp.new and L.SPELL_NEW or L.SPELL_UPGRADE, WC.SpellLabel(sp)), WC.COLORS.white)
            end
        end
        if #entry.spells > 0 and #left == 0 then rows[#rows + 1] = row(L.CARD_ALL_KNOWN, GREEN) end
        m.hints[#m.hints + 1] = string.format(L.CARD_SPELLBOOK_KEY, WC.BindingKey("TOGGLESPELLBOOK", "P"))
    elseif kind == "talent" then
        m.icon = WC.ICONS.talent
        local n = WC.UnspentTalentPoints() or tonumber(entry.points)
        -- the count is shown once, in the title; the body gives the plan's next pick or points at the talents
        if n and n > 0 then m.title = string.format(n == 1 and L.CARD_UNSPENT_TITLE_ONE or L.CARD_UNSPENT_TITLE_MANY, math.floor(n)) end
        local key = WC.BindingKey("TOGGLETALENTS", "N")
        if entry.nextPick and entry.nextPick ~= m.title and entry.nextPick ~= entry.title then
            rows[#rows + 1] = row(string.format(L.CARD_NEXT_PICK, entry.nextPick), WC.COLORS.white)
            m.hints[#m.hints + 1] = string.format(L.CARD_TALENTS_KEY, key)
        else
            m.hints[#m.hints + 1] = string.format(L.CARD_OPEN_TALENTS_KEY, key)
        end
    elseif kind == "upgrade" then
        -- one upgrade as two lines that compare it with what you wear, then how to get it with its path icon
        local function upgrade_rows(u)
            local parts = WC.UpgradeParts(u)
            rows[#rows + 1] = row(string.format(L.CARD_YOU_WEAR, parts.worn), WC.COLORS.white)
            local look = parts.look
            if parts.gain then look = look .. " \226\128\148 " .. parts.gain end
            rows[#rows + 1] = row(string.format(L.CARD_LOOK_FOR, look), WC.COLORS.white)
            local how = WC.UpgradeSub(u, true)
            if how then rows[#rows + 1] = row(how) end
            for _, mat in ipairs(u.materials or {}) do rows[#rows + 1] = row(string.format(L.CARD_MATERIAL_HAVE, mat.name, mat.have, mat.need)) end
        end
        if entry.upgrades then -- the chip's card: every upgrade
            local planned = false
            for _, u in ipairs(entry.upgrades) do if WC.HasUpgradePath(u) then planned = true end end
            if planned then -- an older digest keeps the plain item names
                for i = #rows, 1, -1 do rows[i] = nil end
                m.title = string.format(#entry.upgrades == 1 and L.CHIP_UPGRADES_GET_ONE or L.CHIP_UPGRADES_GET, #entry.upgrades)
                m.list = {} -- one compact row per slot; a click expands it (see fill_card)
                for i, u in ipairs(entry.upgrades) do m.list[i] = WC.UpgradeListRow(u) end
                if entry.quest then m.actions[#m.actions + 1] = { id = "map", label = L.CARD_SHOW_MAP } end
            end
        elseif WC.HasUpgradePath(entry) then
            upgrade_rows(entry)
            if entry.pathKind == "quest" and entry.quest and #WC.QuestSteps(entry.quest) > 0 then
                m.actions[#m.actions + 1] = { id = "map", label = L.CARD_SHOW_MAP }
            end
        else
            if entry.slot then rows[#rows + 1] = row(entry.slot) end
            if entry.atLevel then rows[#rows + 1] = row(string.format(L.AT_LEVEL, entry.atLevel)) end
        end
        if entry.item then
            m.link = "item:" .. entry.item
            local icon = GetItemIcon and GetItemIcon(entry.item)
            if icon then m.icon = icon end
        end
    elseif kind == "giver" then
        m.icon = WC.ICONS.pickup
        if entry.npc then
            rows[#rows + 1] = row(entry.zone and string.format(L.PICK_UP_FROM_IN, entry.npc, entry.zone) or string.format(L.PICK_UP_FROM, entry.npc))
        end
        if entry.x and entry.y then rows[#rows + 1] = row(string.format(L.CARD_GIVER_AT, entry.x, entry.y)) end
        if entry.quest and #WC.QuestSteps(entry.quest) > 0 then m.actions[#m.actions + 1] = { id = "map", label = L.CARD_SHOW_MAP } end
    elseif kind == "dungeon" and entry.line then
        if #rows == 0 then rows[#rows + 1] = row(entry.line, WC.COLORS.white) end
    end
    drop_repeats(rows, m.title, entry.title)
    -- a card with nothing more shows the entry's own text (its reason came in above); a note's text is its title
    if #rows == 0 and not m.list and kind ~= "note" and (kind ~= "talent" or #m.hints == 0) and m.title ~= "" then rows[#rows + 1] = row(m.title, WC.COLORS.white) end
    m.icon = m.icon or KIND_ICON.note
    -- an upgrade set and the stats card ask only what the digest gave: never a question built from a summary
    m.asks = (m.list and {}) or entry.asks or ((entry.upgrades or kind == "stats") and {} or WC.FallbackAsks(entry, m.title))
    m.ref = entry.ref
    return m
end

-- ---------------------------------------------------------------- the card frame

local card

local function style_button(b, text, w)
    b:SetSize(w, 22)
    b:SetText(text)
end

local function make_button(name, parent, text, w)
    local b = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
    style_button(b, text, w)
    return b
end

local fill_card -- defined below; a question click redraws the card

-- Copy. Addons cannot write the clipboard, so a click on a question chip leaves the question selected and
-- focused in an edit box under that chip, and the player's own Ctrl+C does the copy. The key handler changes
-- nothing: not the box's text, selection or focus, since the client copies after the handler returns. The
-- confirmation shows on a following frame, the text stays, and the focus is let go a moment later so the
-- movement keys return to the game.
local COPIED_SECONDS = 1.5

local function copy_select(c)
    c.box:SetFocus()
    c.box:HighlightText()
end

local function copy_begin(c)
    c.copying = true
    c.copyToken = (c.copyToken or 0) + 1
    copy_select(c)
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function() -- the button's mouse-up can undo a single SetFocus/HighlightText
            if c.copying then copy_select(c) end
        end)
    end
end

-- A click on the i-th question chip: the question opens, selected, in the box under that chip.
function WC.CardAsk(i)
    local c = card
    local q = c and c.asksShown and c.asksShown[i]
    if not q then return nil end
    c.selected, c.selectedIndex = q, i
    c.status:SetText("")
    fill_card(c.entry, true)
    copy_begin(c)
    return q
end

-- Called on a key press in the box (Ctrl+C, or Cmd+C on a Mac client). Changes nothing itself.
function WC.CardKeyDown(key)
    local c = card
    if not (c and c.copying and type(key) == "string" and key:upper() == "C") then return false end
    if not ((IsControlKeyDown and IsControlKeyDown()) or (IsMetaKeyDown and IsMetaKeyDown())) then return false end
    local token = c.copyToken
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if c.copyToken ~= token or not c.copying then return end
            c.status:SetText(L.CARD_COPIED)
            c.copying = nil
            C_Timer.After(COPIED_SECONDS, function()
                if c.copyToken == token and not c.copying then c.box:ClearFocus() end
            end)
        end)
    end
    return true
end

-- Esc in the box: let go of the keyboard and stop re-selecting.
function WC.CardEscape()
    local c = card
    if not c then return end
    c.copying = nil
    c.box:ClearFocus()
end

local function bordered(box)
    if box.SetBackdrop then
        box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        box:SetBackdropColor(0, 0, 0, 0.5)
        box:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
    end
end

local function create_card()
    local c = CreateFrame("Frame", "WoWCompanionCard", UIParent, "BackdropTemplate")
    c:SetSize(CARD_W, 200)
    if c.SetBackdrop then
        c:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    end
    if c.SetFrameStrata then c:SetFrameStrata("DIALOG") end
    c:EnableMouse(true)
    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetSize(32, 32)
    c.icon:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, -PAD)
    c.title = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    c.title:SetPoint("TOPLEFT", c, "TOPLEFT", PAD + 40, -PAD)
    c.title:SetWidth(CARD_W - PAD * 2 - 64)
    c.title:SetJustifyH("LEFT")
    c.subtitle = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    c.subtitle:SetJustifyH("LEFT")
    c.close = CreateFrame("Button", "WoWCompanionCardClose", c, "UIPanelCloseButton")
    c.close:SetSize(20, 20)
    c.close:SetPoint("TOPRIGHT", c, "TOPRIGHT", 0, 0)
    c.close:SetScript("OnClick", function() c:Hide() end)
    c.lines, c.hints, c.actions, c.chips, c.rowBtns, c.detail = {}, {}, {}, {}, {}, {}
    -- everything under the header lives in a scroll frame, so a long card scrolls instead of running off the screen
    c.scroll = CreateFrame("ScrollFrame", "WoWCompanionCardScroll", c, "UIPanelScrollFrameTemplate")
    c.content = CreateFrame("Frame", nil, c.scroll)
    c.content:SetSize(CARD_W - PAD * 2 - SCROLL_W, 1)
    c.scroll:SetScrollChild(c.content)
    c.scroll:EnableMouseWheel(true)
    c.scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = c.scrollRange or 0
        self:SetVerticalScroll(math.max(0, math.min(range, (self:GetVerticalScroll() or 0) - delta * 36)))
    end)
    c.link = CreateFrame("Button", "WoWCompanionCardLink", c.content)
    c.link.label = c.link:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    c.link.label:SetPoint("TOPLEFT", c.link, "TOPLEFT", 0, 0)
    c.link:SetScript("OnEnter", function(self)
        if not self.itemLink then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(self.itemLink)
        GameTooltip:Show()
    end)
    c.link:SetScript("OnLeave", function() GameTooltip:Hide() end)
    c.askLabel = c.content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    c.askLabel:SetText(L.CARD_ASK)
    c.askLabel:SetTextColor(GREY[1], GREY[2], GREY[3])
    c.askLabel:SetJustifyH("LEFT")
    c.ownLine = c.content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    c.ownLine:SetText(L.CARD_OWN_DIM)
    c.ownLine:SetJustifyH("LEFT")
    -- the clicked question, selected for Ctrl+C
    c.box = CreateFrame("EditBox", "WoWCompanionCardAsk", c.content, "BackdropTemplate")
    c.box:SetAutoFocus(false)
    c.box:SetMaxLetters(MAX_ASK_LEN)
    c.box:SetSize(CARD_W - PAD * 2 - SCROLL_W, 22)
    if c.box.SetFontObject then c.box:SetFontObject("GameFontHighlightSmall") end
    if c.box.SetTextInsets then c.box:SetTextInsets(4, 4, 2, 2) end
    bordered(c.box)
    c.box:SetScript("OnEscapePressed", function() WC.CardEscape() end)
    c.box:SetScript("OnKeyDown", function(_, key) WC.CardKeyDown(key) end)
    c.box:SetScript("OnEditFocusGained", function() if c.copying then c.box:HighlightText() end end)
    c.box:SetScript("OnMouseUp", function()
        if not c.copying then return end
        c.box:HighlightText()
        if C_Timer and C_Timer.After then C_Timer.After(0, function() if c.copying then c.box:HighlightText() end end) end
    end)
    c.box:SetScript("OnTextChanged", function(_, user)
        if not user then return end
        c.copying = nil -- the player is editing the question: stop selecting it all
    end)
    c.box:Hide()
    c.copyHint = c.content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    c.copyHint:SetText(L.CARD_COPY_HINT)
    c.copyHint:SetJustifyH("LEFT")
    c.copyHint:Hide()
    c.status = c.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    c.status:SetJustifyH("LEFT")
    c.status:SetTextColor(GREEN[1], GREEN[2], GREEN[3])
    c:SetScript("OnHide", function() c.entry = nil c.expanded = nil c.copying = nil c.selected, c.selectedIndex = nil, nil end)
    c:Hide()
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "WoWCompanionCard") end -- Esc closes it
    return c
end

local function text_height(fs, fallback)
    local h = fs.GetStringHeight and fs:GetStringHeight()
    return (h and h > 0) and h or fallback
end

local function pooled_text(list, i, parent)
    local fs = list[i]
    if not fs then
        fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetJustifyH("LEFT")
        list[i] = fs
    end
    return fs
end

-- Anchors the card beside the panel on the side the setting picks.
function WC.PlaceCard()
    local c, p = card, WC.panel
    if not (c and p) then return end
    c:ClearAllPoints()
    if WC.Setting("cardSide") == "left" then
        c:SetPoint("TOPRIGHT", p, "TOPLEFT", -6, 0)
    else
        c:SetPoint("TOPLEFT", p, "TOPRIGHT", 6, 0)
    end
    c:SetScale(p.scale or WC.db.settings.scale or 1)
    local bg, bc = WC.Setting("bgColor"), WC.Setting("borderColor")
    if c.SetBackdropColor then
        c:SetBackdropColor(bg[1], bg[2], bg[3], math.max(0.85, WC.Setting("bgOpacity")))
        c:SetBackdropBorderColor(bc[1], bc[2], bc[3], WC.Setting("borderShow") and WC.Setting("borderOpacity") or 0)
    end
end

-- The pooled question chip at index i: a button holding a wrapping label.
local function get_chip(c, i)
    local b = c.chips[i]
    if b then return b end
    b = CreateFrame("Button", "WoWCompanionCardChip" .. i, c.content)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(0.12, 0.14, 0.2, 0.9)
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.label:SetJustifyH("LEFT")
    b.label:SetPoint("TOPLEFT", b, "TOPLEFT", 5, -4)
    b:SetScript("OnClick", function(self) WC.CardAsk(self.index) end)
    b:SetScript("OnEnter", function(self) self.bg:SetColorTexture(0.2, 0.24, 0.36, 0.95) end)
    b:SetScript("OnLeave", function(self) self.bg:SetColorTexture(0.12, 0.14, 0.2, 0.9) end)
    c.chips[i] = b
    return b
end

-- The most height the card may have: from its top edge down to the bottom of the screen, less a margin.
function WC.CardMaxHeight(c)
    local top = c.GetTop and c:GetTop()
    if not top then
        local h = UIParent and UIParent.GetHeight and UIParent:GetHeight() or 0
        top = (h > 0 and h or 768) / ((c.GetScale and c:GetScale()) or 1)
    end
    return math.max(160, top - MARGIN)
end

-- The pooled list row at index i: a button with the path icon, the slot, the gain and the look-for line.
local function get_row(c, i)
    local b = c.rowBtns[i]
    if b then return b end
    b = CreateFrame("Button", "WoWCompanionCardRow" .. i, c.content)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(14, 14)
    b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", 3, -3)
    b.slot = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.slot:SetJustifyH("LEFT")
    b.gain = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.gain:SetJustifyH("RIGHT")
    b.look = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    b.look:SetJustifyH("LEFT")
    b:SetScript("OnClick", function(self) WC.CardToggleRow(self.index) end)
    b:SetScript("OnEnter", function(self) self.hot = true self.bg:SetColorTexture(0.2, 0.24, 0.36, 0.95) end)
    b:SetScript("OnLeave", function(self) self.hot = nil self.bg:SetColorTexture(unpack(self.open and { 0.16, 0.19, 0.3, 0.95 } or { 0.12, 0.14, 0.2, 0.9 })) end)
    c.rowBtns[i] = b
    return b
end

local GAIN_W = 96

-- Draws the card for entry. keepText is a live redraw: the question being copied and the status line stay.
function fill_card(entry, keepText)
    local c = card
    local m = WC.CardModel(entry)
    c.entry = entry
    c.icon:SetTexture(m.icon)
    c.title:SetText(m.title)
    WC.StyleText(c.title)
    c.subtitle:SetText(m.subtitle)
    local ty = text_height(c.title, WC.LINE_HEIGHT)
    c.subtitle:ClearAllPoints()
    c.subtitle:SetPoint("TOPLEFT", c, "TOPLEFT", PAD + 40, -(PAD + ty + 2))
    local top = math.max(PAD + 36, PAD + ty + 2 + WC.LINE_HEIGHT) + 8
    local body = c.content
    local width = CARD_W - PAD * 2 - SCROLL_W
    local y = 0
    if not keepText then
        c.copying, c.selected, c.selectedIndex = nil, nil, nil
        c.status:SetText("")
        c.box:SetText("")
    end
    for i, r in ipairs(m.rows) do
        local fs = pooled_text(c.lines, i, body)
        WC.StyleText(fs)
        fs:SetText(r.text)
        fs:SetTextColor(r.color[1], r.color[2], r.color[3])
        fs:SetWidth(width)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -y)
        fs:Show()
        y = y + text_height(fs, WC.LINE_HEIGHT) + 2
    end
    for i = #m.rows + 1, #c.lines do c.lines[i]:Hide() end
    c.shownRows = m.rows

    -- the question chips for a list of asks, from y; the copy box sits directly under the chip that was clicked
    local asksDone = false
    local function asks_block(asks)
        asksDone = true
        if #asks > 0 then
            c.askLabel:ClearAllPoints()
            c.askLabel:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -y)
            c.askLabel:Show()
            y = y + WC.LINE_HEIGHT + 2
        else
            c.askLabel:Hide()
        end
        c.asksShown = asks
        if c.selected and c.selected ~= asks[c.selectedIndex] then c.selected, c.selectedIndex = nil, nil end
        local boxShown = false
        for i, q in ipairs(asks) do
            local b = get_chip(c, i)
            b.index = i
            b.label:SetWidth(width - 10)
            b.label:SetText(q)
            WC.StyleText(b.label)
            local h = text_height(b.label, WC.LINE_HEIGHT) + 8
            b:SetSize(width, h)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -y)
            b:Show()
            y = y + h + 3
            if c.selected and c.selectedIndex == i then
                if c.box:GetText() ~= c.selected then c.box:SetText(c.selected) end -- never reset a box being copied from
                c.box:ClearAllPoints()
                c.box:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -y)
                c.box:Show()
                y = y + 25
                c.copyHint:ClearAllPoints()
                c.copyHint:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -y)
                c.copyHint:Show()
                y = y + WC.LINE_HEIGHT + 2
                c.status:SetWidth(width)
                c.status:ClearAllPoints()
                c.status:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -y)
                WC.StyleText(c.status)
                c.status:Show()
                y = y + WC.LINE_HEIGHT * 2 + 4 -- room for the confirmation, which appears a frame after the key
                boxShown = true
            end
        end
        for i = #asks + 1, #c.chips do c.chips[i]:Hide() end
        if not boxShown then
            c.box:Hide()
            c.copyHint:Hide()
            c.status:Hide()
        end
    end

    -- the upgrade list: one compact row per slot; the open one shows what you wear, how to get it and its questions
    local list = m.list or {}
    local nDetail = 0
    for i, r in ipairs(list) do
        local b = get_row(c, i)
        b.index = i
        local open = c.expanded == i
        b.open = open
        b.bg:SetColorTexture(unpack(open and { 0.16, 0.19, 0.3, 0.95 } or { 0.12, 0.14, 0.2, 0.9 }))
        if r.icon then b.icon:SetTexture(r.icon) b.icon:Show() else b.icon:Hide() end
        b.slot:SetWidth(width - 24 - GAIN_W)
        b.slot:SetText(r.slot)
        b.gain:SetWidth(GAIN_W)
        b.gain:SetText(r.gain or "")
        b.gain:SetTextColor(r.gainColor[1], r.gainColor[2], r.gainColor[3])
        b.look:SetWidth(width - 24)
        b.look:SetText(r.look)
        WC.StyleText(b.slot) WC.StyleText(b.gain) WC.StyleText(b.look)
        b.slot:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
        b.slot:ClearAllPoints() b.slot:SetPoint("TOPLEFT", b, "TOPLEFT", 22, -3)
        b.gain:ClearAllPoints() b.gain:SetPoint("TOPRIGHT", b, "TOPRIGHT", -4, -3)
        local head = WC.LINE_HEIGHT
        b.look:ClearAllPoints() b.look:SetPoint("TOPLEFT", b, "TOPLEFT", 22, -(3 + head + 1))
        local h = 3 + head + 1 + text_height(b.look, WC.LINE_HEIGHT) + 4
        b:SetSize(width, h)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -y)
        b:Show()
        b.top = y
        y = y + h + 3
        if open then
            for _, d in ipairs(r.detail) do
                nDetail = nDetail + 1
                local fs = pooled_text(c.detail, nDetail, body)
                WC.StyleText(fs)
                fs:SetText(d.text)
                fs:SetTextColor(d.color[1], d.color[2], d.color[3])
                fs:SetWidth(width - 12)
                fs:ClearAllPoints()
                fs:SetPoint("TOPLEFT", body, "TOPLEFT", 12, -y)
                fs:Show()
                y = y + text_height(fs, WC.LINE_HEIGHT) + 2
            end
            y = y + 2
            asks_block(r.asks)
            y = y + 4
        end
    end
    for i = #list + 1, #c.rowBtns do c.rowBtns[i]:Hide() end
    for i = nDetail + 1, #c.detail do c.detail[i]:Hide() end
    c.listShown = list

    if m.link then
        local name = GetItemInfo and select(2, GetItemInfo(m.link)) -- the client's own colored link, when it knows the item
        c.link.itemLink = m.link
        local shown = type(name) == "string" and name or entry.title
        c.link.label:SetText(shown)
        c.link:SetSize(width, WC.LINE_HEIGHT)
        c.link:ClearAllPoints()
        c.link:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -y)
        c.link:Show()
        y = y + WC.LINE_HEIGHT + 4
    else
        c.link.itemLink = nil
        c.link:Hide()
    end
    for i, h in ipairs(m.hints) do
        local fs = pooled_text(c.hints, i, body)
        WC.StyleText(fs)
        fs:SetText(h)
        fs:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
        fs:SetWidth(width)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -y)
        fs:Show()
        y = y + WC.LINE_HEIGHT + 2
    end
    for i = #m.hints + 1, #c.hints do c.hints[i]:Hide() end
    y = y + 4
    for i, a in ipairs(m.actions) do
        local b = c.actions[i]
        if not b then
            b = make_button("WoWCompanionCardAction" .. i, body, a.label, 140)
            c.actions[i] = b
        end
        b:SetText(a.label)
        b.action = a.id
        b:SetScript("OnClick", function(self)
            if self.action == "quest" then
                if not WC.OpenQuestLog(entry.quest) then
                    print((InCombatLockdown and InCombatLockdown()) and L.CARD_COMBAT or quest_log_hint())
                end
            elseif self.action == "map" then
                if not WC.ShowOnMap(entry) then print(L.CARD_COMBAT) end
            end
        end)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", body, "TOPLEFT", ((i - 1) % 2) * 146, -(y + math.floor((i - 1) / 2) * 26))
        b:Show()
    end
    for i = #m.actions + 1, #c.actions do c.actions[i]:Hide() end
    if #m.actions > 0 then y = y + math.ceil(#m.actions / 2) * 26 + 4 end
    if not asksDone then asks_block(m.asks) end
    c.ownLine:SetWidth(width)
    c.ownLine:ClearAllPoints()
    c.ownLine:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -(y + 2))
    WC.StyleText(c.ownLine)
    y = y + WC.LINE_HEIGHT + 6

    -- the card is as tall as its content, up to the bottom of the screen; past that the content scrolls
    local total = top + y + PAD
    local h = math.min(total, WC.CardMaxHeight(c))
    c:SetHeight(h)
    c.scroll:ClearAllPoints()
    c.scroll:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, -top)
    c.scroll:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -(PAD + SCROLL_W), PAD)
    body:SetSize(width, y)
    c.contentHeight, c.viewHeight = y, h - top - PAD
    c.scrollRange = math.max(0, y - c.viewHeight)
    c.scroll:UpdateScrollChildRect()
    if (c.scroll:GetVerticalScroll() or 0) > c.scrollRange then c.scroll:SetVerticalScroll(c.scrollRange) end
    local bar = c.scroll.ScrollBar or (_G and _G.WoWCompanionCardScrollScrollBar)
    if bar then bar:SetShown(c.scrollRange > 0) end -- the slim bar shows only when there is more to see
end

-- A click on the i-th list row: it opens in place and any open one closes; a second click closes it.
function WC.CardToggleRow(i)
    local c = card
    if not (c and c.entry and c.listShown and c.listShown[i]) then return end
    c.expanded = (c.expanded ~= i) and i or nil
    fill_card(c.entry, false)
end

-- Opens the card for an entry; clicking the same entry again closes it.
function WC.OpenCard(entry)
    card = card or create_card()
    WC.card = card
    if card:IsShown() and card.entry and card.entry.key == entry.key then
        card:Hide()
        return
    end
    WC.PlaceCard()
    card.expanded = nil
    fill_card(entry, false)
    if card.scroll.SetVerticalScroll then card.scroll:SetVerticalScroll(0) end
    card:Show()
end

-- A click on an upgrade row of the panel: the upgrades card opens on that row, expanded and scrolled into view.
-- False when the card has no such row (an older digest, or the Upgrades chip is switched off).
function WC.OpenUpgradeRow(entry)
    local chip = WC.panel and WC.panel.chipEntries and WC.panel.chipEntries.upgrades
    if not (chip and chip.upgrades and WC.HasUpgradePath(entry)) then return false end
    local idx
    for i, u in ipairs(chip.upgrades) do if u.key == entry.key then idx = i break end end
    if not idx then return false end
    card = card or create_card()
    WC.card = card
    if card:IsShown() and card.entry and card.entry.key == chip.key and card.expanded == idx then
        card:Hide()
        return true
    end
    WC.PlaceCard()
    card.expanded = idx
    fill_card(chip, false)
    local b = card.rowBtns and card.rowBtns[idx]
    if card.scroll.SetVerticalScroll then card.scroll:SetVerticalScroll(math.min(card.scrollRange or 0, b and b.top or 0)) end
    card:Show()
    return true
end

function WC.CloseCard()
    if card and card:IsShown() then card:Hide() end
end

-- Redraws an open card from the live panel (counts, answers), keeping what the player typed.
function WC.RefreshCard()
    if not (card and card:IsShown() and card.entry) then return end
    local key, fresh = card.entry.key, card.entry
    fresh = WC.panel and WC.panel.chipEntries and WC.panel.chipEntries[key] or fresh
    for _, r in ipairs(WC.panel and WC.panel.rows or {}) do
        if r:IsShown() and r.entry and r.entry.key == key then fresh = r.entry break end
    end
    WC.PlaceCard()
    fill_card(fresh, true)
end
