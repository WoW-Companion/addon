-- WoW Companion: clicking panel entries, and the detail card.
-- A left-click on a quest in the log opens it in the client's own quest log (out of combat); a click on
-- anything else, or a right-click on anything, opens a card beside the panel with the entry's details, live
-- facts and a ready question to send or copy. Read-only: the only thing that leaves the game is a queued
-- question (see docs/ask-format.md), and "copy" is a selected edit box the player copies with Ctrl+C.

local WC = WoWCompanion
local L = WC.L

local CARD_W, PAD, BOX_H, ANSWER_H = 300, 10, 72, 84
local GREY, GOLD, GREEN = { 0.72, 0.72, 0.72 }, { 1, 0.82, 0 }, { 0.25, 0.9, 0.25 }
local ART = "Interface\\Icons\\"
local KIND_ICON = {
    ["note"] = ART .. "INV_Misc_Note_01", ["material"] = ART .. "INV_Misc_Bag_08",
    ["dungeon"] = ART .. "INV_Misc_Map_01", ["upgrade"] = ART .. "INV_Misc_QuestionMark",
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

-- The ask the card pre-fills: the entry's own prompt, else the ASK_ABOUT template for its kind, else its title.
function WC.CardPrompt(entry)
    if entry.prompt then return entry.prompt:sub(1, WC.MAX_ASK_LEN) end
    local ask = entry.ask or { kind = entry.kind, subject = tostring(entry.title or ""):gsub("|", "") }
    local q = WC.AskTemplate({ ask = ask })
    return (q or tostring(entry.title or "")):sub(1, WC.MAX_ASK_LEN)
end

-- The answer the companion wrote for a question asked from this entry, or nil. Answers are plain data in
-- the global WoWCompanionAnswers = { answers = { { id = "<ask id>", question = "<text>", text = "<answer>" }, ... } },
-- written by the companion into WoWCompanion_Answers/Answers.lua; the card matches by the ask id it remembered
-- when it sent the question, or by the question text.
function WC.AnswerFor(key)
    local data = WoWCompanionAnswers
    local list = type(data) == "table" and type(data.answers) == "table" and data.answers or nil
    local sent = WC.db and type(WC.db.cardAsks) == "table" and WC.db.cardAsks[key]
    if not list or type(sent) ~= "table" then return nil end
    local best
    for _, a in ipairs(list) do
        if type(a) == "table" and type(a.text) == "string" and a.text ~= "" and (a.id == sent.id or (a.question ~= nil and a.question == sent.text)) then
            best = a
        end
    end
    return best and (best.text:gsub("|", "||")) or nil
end

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

-- The card for an entry as data: { title, icon, subtitle, rows = { {text, color} }, link, actions, hints, prompt, answer }.
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
    local label = L["CARD_KIND_" .. kind]
    m.subtitle = level and string.format(L.CARD_LEVEL_KIND, math.floor(level), label) or label
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
        if n and n > 0 then rows[#rows + 1] = row(string.format(n == 1 and L.UNSPENT_ONE or L.UNSPENT_MANY, math.floor(n)), GOLD) end
        if entry.nextPick then rows[#rows + 1] = row(string.format(L.CARD_NEXT_PICK, entry.nextPick), WC.COLORS.white) end
        m.hints[#m.hints + 1] = string.format(L.CARD_TALENTS_KEY, WC.BindingKey("TOGGLETALENTS", "N"))
    elseif kind == "upgrade" then
        local meta = {}
        if entry.slot then meta[#meta + 1] = entry.slot end
        if entry.ilvl then meta[#meta + 1] = string.format(L.ILVL, entry.ilvl) end
        if entry.atLevel then meta[#meta + 1] = string.format(L.AT_LEVEL, entry.atLevel) end
        if #meta > 0 then rows[#rows + 1] = row(table.concat(meta, ", ")) end
        if entry.item then
            m.link = "item:" .. entry.item
            local icon = GetItemIcon and GetItemIcon(entry.item)
            if icon then m.icon = icon end
        end
    elseif kind == "dungeon" and entry.line then
        if #rows == 0 then rows[#rows + 1] = row(entry.line, WC.COLORS.white) end
    end
    if #rows == 0 then rows[#rows + 1] = row(L.CARD_NO_DETAILS) end
    m.icon = m.icon or KIND_ICON.note
    m.prompt = WC.CardPrompt(entry)
    m.answer = WC.AnswerFor(entry.key)
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

-- Sends what is in the box through the ask queue: exactly one question, at most MAX_ASK_LEN characters.
function WC.CardSend()
    local c = card
    if not c or not c.entry then return nil end
    local sent = WC.SubmitAsk((c.box:GetText() or ""):sub(1, WC.MAX_ASK_LEN))
    if not sent then return nil end
    print(L.ASK_QUEUED)
    WC.db.cardAsks = type(WC.db.cardAsks) == "table" and WC.db.cardAsks or {}
    WC.db.cardAsks[c.entry.key] = { id = sent.id, text = sent.text }
    local n = 0
    for _ in pairs(WC.db.cardAsks) do n = n + 1 end
    if n > 30 then -- keep the remembered asks bounded: drop any other entry's
        for k in pairs(WC.db.cardAsks) do
            if k ~= c.entry.key then WC.db.cardAsks[k] = nil break end
        end
    end
    c.status:SetText(L.CARD_SENT)
    c.send:SetEnabled(false)
    return sent
end

-- Selects all the text and focuses the box so the player can press Ctrl+C. Addons cannot write the clipboard.
function WC.CardCopy()
    local c = card
    if not c then return end
    c.box:SetFocus()
    c.box:HighlightText()
    c.status:SetText(L.CARD_COPY_HINT)
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
    c.lines, c.hints, c.actions = {}, {}, {}
    c.link = CreateFrame("Button", "WoWCompanionCardLink", c)
    c.link.label = c.link:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    c.link.label:SetPoint("TOPLEFT", c.link, "TOPLEFT", 0, 0)
    c.link:SetScript("OnEnter", function(self)
        if not self.itemLink then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(self.itemLink)
        GameTooltip:Show()
    end)
    c.link:SetScript("OnLeave", function() GameTooltip:Hide() end)
    c.askLabel = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    c.askLabel:SetText(L.CARD_ASK)
    c.askLabel:SetJustifyH("LEFT")
    c.box = CreateFrame("EditBox", "WoWCompanionCardAsk", c, "BackdropTemplate")
    c.box:SetMultiLine(true)
    c.box:SetAutoFocus(false)
    c.box:SetMaxLetters(WC.MAX_ASK_LEN)
    c.box:SetSize(CARD_W - PAD * 2, BOX_H)
    if c.box.SetFontObject then c.box:SetFontObject("GameFontHighlightSmall") end
    if c.box.SetTextInsets then c.box:SetTextInsets(4, 4, 4, 4) end
    if c.box.SetBackdrop then
        c.box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        c.box:SetBackdropColor(0, 0, 0, 0.5)
        c.box:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
    end
    c.box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    c.box:SetScript("OnTextChanged", function(_, user) if user and c.send then c.send:SetEnabled(true) end end)
    c.send = make_button("WoWCompanionCardSend", c, L.CARD_SEND, 80)
    c.send:SetScript("OnClick", function() WC.CardSend() end)
    c.copy = make_button("WoWCompanionCardCopy", c, L.CARD_COPY, 80)
    c.copy:SetScript("OnClick", function() WC.CardCopy() end)
    c.status = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    c.status:SetJustifyH("LEFT")
    c.status:SetTextColor(GREEN[1], GREEN[2], GREEN[3])
    c.answerLabel = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    c.answerLabel:SetText(L.CARD_ANSWER)
    c.answerScroll = CreateFrame("ScrollFrame", "WoWCompanionCardAnswerScroll", c, "UIPanelScrollFrameTemplate")
    c.answerBody = CreateFrame("Frame", nil, c.answerScroll)
    c.answerBody:SetSize(CARD_W - PAD * 2 - 24, 1)
    c.answerScroll:SetScrollChild(c.answerBody)
    c.answer = c.answerBody:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    c.answer:SetPoint("TOPLEFT", c.answerBody, "TOPLEFT", 0, 0)
    c.answer:SetWidth(CARD_W - PAD * 2 - 24)
    c.answer:SetJustifyH("LEFT")
    c:SetScript("OnHide", function() c.entry = nil end)
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

-- Draws the card for entry. keepText leaves the player's edits in the ask box (a live redraw).
local function fill_card(entry, keepText)
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
    local y = math.max(PAD + 36, PAD + ty + 2 + WC.LINE_HEIGHT) + 8
    local width = CARD_W - PAD * 2
    for i, r in ipairs(m.rows) do
        local fs = pooled_text(c.lines, i, c)
        WC.StyleText(fs)
        fs:SetText(r.text)
        fs:SetTextColor(r.color[1], r.color[2], r.color[3])
        fs:SetWidth(width)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, -y)
        fs:Show()
        y = y + text_height(fs, WC.LINE_HEIGHT) + 2
    end
    for i = #m.rows + 1, #c.lines do c.lines[i]:Hide() end
    c.shownRows = m.rows
    if m.link then
        local name = GetItemInfo and select(2, GetItemInfo(m.link)) -- the client's own colored link, when it knows the item
        c.link.itemLink = m.link
        local shown = type(name) == "string" and name or entry.title
        c.link.label:SetText(shown)
        c.link:SetSize(width, WC.LINE_HEIGHT)
        c.link:ClearAllPoints()
        c.link:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, -y)
        c.link:Show()
        y = y + WC.LINE_HEIGHT + 4
    else
        c.link.itemLink = nil
        c.link:Hide()
    end
    for i, h in ipairs(m.hints) do
        local fs = pooled_text(c.hints, i, c)
        WC.StyleText(fs)
        fs:SetText(h)
        fs:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
        fs:SetWidth(width)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, -y)
        fs:Show()
        y = y + WC.LINE_HEIGHT + 2
    end
    for i = #m.hints + 1, #c.hints do c.hints[i]:Hide() end
    y = y + 4
    for i, a in ipairs(m.actions) do
        local b = c.actions[i]
        if not b then
            b = make_button("WoWCompanionCardAction" .. i, c, a.label, 140)
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
        b:SetPoint("TOPLEFT", c, "TOPLEFT", PAD + ((i - 1) % 2) * 146, -(y + math.floor((i - 1) / 2) * 26))
        b:Show()
    end
    for i = #m.actions + 1, #c.actions do c.actions[i]:Hide() end
    if #m.actions > 0 then y = y + math.ceil(#m.actions / 2) * 26 + 4 end
    c.askLabel:ClearAllPoints()
    c.askLabel:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, -y)
    y = y + WC.LINE_HEIGHT + 2
    c.box:ClearAllPoints()
    c.box:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, -y)
    if not keepText then
        c.box:SetText(m.prompt)
        c.status:SetText("")
        c.send:SetEnabled(true)
    end
    y = y + BOX_H + 6
    c.send:ClearAllPoints()
    c.send:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, -y)
    c.copy:ClearAllPoints()
    c.copy:SetPoint("TOPLEFT", c, "TOPLEFT", PAD + 86, -y)
    y = y + 26
    c.status:SetWidth(width)
    c.status:ClearAllPoints()
    c.status:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, -y)
    WC.StyleText(c.status)
    y = y + ((c.status:GetText() or "") ~= "" and (text_height(c.status, WC.LINE_HEIGHT * 2) + 4) or 2)
    c.hasAnswer = m.answer ~= nil
    if m.answer then
        c.answerLabel:ClearAllPoints()
        c.answerLabel:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, -y)
        c.answerLabel:Show()
        y = y + WC.LINE_HEIGHT + 2
        c.answer:SetText(m.answer)
        WC.StyleText(c.answer)
        c.answerBody:SetHeight(text_height(c.answer, ANSWER_H))
        c.answerScroll:ClearAllPoints()
        c.answerScroll:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, -y)
        c.answerScroll:SetSize(width - 22, ANSWER_H)
        c.answerScroll:Show()
        c.answerShown = m.answer
        y = y + ANSWER_H + 6
    else
        c.answerLabel:Hide()
        c.answerScroll:Hide()
        c.answerShown = nil
    end
    c:SetHeight(y + PAD)
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
    fill_card(entry, false)
    card:Show()
end

function WC.CloseCard()
    if card and card:IsShown() then card:Hide() end
end

-- Redraws an open card from the live panel (counts, answers), keeping what the player typed.
function WC.RefreshCard()
    if not (card and card:IsShown() and card.entry) then return end
    local key, fresh = card.entry.key, card.entry
    for _, r in ipairs(WC.panel and WC.panel.rows or {}) do
        if r:IsShown() and r.entry and r.entry.key == key then fresh = r.entry break end
    end
    WC.PlaceCard()
    fill_card(fresh, true)
end
