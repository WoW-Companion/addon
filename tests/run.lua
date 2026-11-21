-- Tiny test runner: loads the TOC's Lua files in order against the stub.
local root = (arg and arg[1]) or "WoWCompanion"
local report = print
local Stub = dofile("tests/wow_stub.lua")

local frames = {}

local function fresh_client(savedvars)
    for k in pairs(WoWCompanion or {}) do WoWCompanion[k] = nil end
    WoWCompanion, WoWCompanionDB, SLASH_WOWC1, WoWCompanionAnswers = nil, savedvars, nil, nil
    Stub.install(_G)
    frames = {}
    local create = CreateFrame
    CreateFrame = function(...)
        local f = create(...)
        frames[#frames + 1] = f
        return f
    end
    local toc = assert(io.open(root .. "/WoWCompanion.toc"))
    for line in toc:lines() do
        local file = line:match("^([%w_]+%.lua)%s*$")
        if file then assert(loadfile(root .. "/" .. file))() end
    end
    toc:close()
    Stub.fire(frames, "ADDON_LOADED", "WoWCompanion")
end

-- Loads the slot file the way the game does: after WoWCompanion, then redraws.
local function load_digest(file)
    WoWCompanionDigest = nil
    assert(loadfile(file))()
    Stub.fire(frames, "PLAYER_LOGIN")
end

local function digest_client(name)
    fresh_client(nil)
    load_digest("tests/fixtures/digest_" .. name .. ".lua")
    return WoWCompanion.panel
end

local function slash() SlashCmdList.WOWC("") end

-- A client whose queue holds one question (id 1799999000-1); answers come from a fixture or none.
local function ask_client(answers_fixture)
    fresh_client({ asks = { { id = "1799999000-1", asked_at = 1799999000, character = "Thrall", text = "What next?" } } })
    if answers_fixture then LOD_FILES.WoWCompanion_Answers = "tests/fixtures/answers_" .. answers_fixture .. ".lua" end
    WoWCompanionPanel:Hide()
    WoWCompanionPanel:Show()
    return WoWCompanion.panel
end

local cases = {
    { "slash command is /wowc", function()
        fresh_client(nil)
        assert(SLASH_WOWC1 == "/wowc")
    end },
    { "panel is hidden after load", function()
        fresh_client(nil)
        assert(WoWCompanionPanel:IsShown() == false)
    end },
    { "slash toggles visibility", function()
        fresh_client(nil)
        local seen = {}
        for i = 1, 3 do slash(); seen[i] = WoWCompanionPanel:IsShown() end
        assert(seen[1] == true and seen[2] == false and seen[3] == true)
    end },
    { "panel shows the no-advice text", function()
        fresh_client(nil)
        assert(WoWCompanion.panel.plain:find("No advice yet", 1, true))
        assert(WoWCompanion.panel.title:GetText() == "WoW Companion")
    end },
    { "position round-trips through WoWCompanionDB", function()
        fresh_client(nil)
        local p = WoWCompanionPanel
        p:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -75)
        p.scripts.OnDragStop(p)
        local saved = WoWCompanionDB
        fresh_client(saved)
        local point, _, relPoint, x, y = WoWCompanionPanel:GetPoint()
        assert(point == "TOPLEFT" and relPoint == "TOPLEFT" and x == 40 and y == -75)
    end },
    { "default position is centred", function()
        fresh_client(nil)
        assert(WoWCompanionPanel:GetPoint() == "CENTER")
    end },
    { "empty digest shows no-advice text", function()
        local p = digest_client("empty")
        assert(p.plain:find("No advice yet", 1, true))
        assert(p.header:GetText() == "")
    end },
    { "full digest shows header and every section", function()
        local p = digest_client("full")
        local h, t = p.header:GetText(), p.plain
        assert(h:find("Thrall", 1, true) and h:find("1 h ago", 1, true))
        local last = 0
        for _, want in ipairs({ "Next quests", "[quest 1234]", "Upgrades", "[item 5678]", "Keep materials", "Notes" }) do
            local at = t:find(want, last + 1, true)
            assert(at, "missing " .. want)
            last = at
        end
    end },
    { "digest over 12 hours old shows its age and the refresh note", function()
        local p = digest_client("stale")
        assert(p.header:GetText():find("updated 1 d ago", 1, true))
        assert(p.plain:find("Ask your AI client to refresh your digest, then /reload.", 1, true))
        local fresh = digest_client("full")
        assert(fresh.header:GetText():find("updated 1 h ago", 1, true) and not fresh.plain:find("refresh your digest", 1, true))
    end },
    { "digest for another character is refused", function()
        local p = digest_client("wrongchar")
        assert(p.plain:find("written for Jaina, not Thrall", 1, true))
        assert(not p.plain:find("Next quests", 1, true))
    end },
    { "unknown schema version is refused", function()
        local p = digest_client("badschema")
        assert(p.plain:find("unknown format (schema 99)", 1, true))
        assert(not p.plain:find("Next quests", 1, true))
    end },
    { "long digest scrolls", function()
        local p = digest_client("long")
        assert(p.plain:find("Quest line number 60", 1, true))
        assert(p.content:GetHeight() > p.scroll:GetHeight())
        assert(p.scrollRange > 0)
        local short = digest_client("full")
        assert(short.scrollRange == 0)
    end },
    { "digest text cannot inject color codes", function()
        local _, rows = WoWCompanion.RenderDigest(
            { schema = 1, character = "Thrall", generated = NOW,
              sections = { { id = "notes", lines = { { text = "|cffff0000red" } } } } }, NOW, "Thrall")
        local t = WoWCompanion.RowsText(rows)
        assert(t:find("||cffff0000red", 1, true))
    end },
}

local function row_with(p, text)
    for _, r in ipairs(p.rows) do
        if r:IsShown() and r.label:GetText():find(text, 1, true) then return r end
    end
    error("no row " .. text)
end

local polish_cases = {
    { "hovering an item line shows its tooltip; leaving hides it", function()
        local p = digest_client("full")
        local row = row_with(p, "[item 5678]")
        row.scripts.OnEnter(row)
        local c = GameTooltip.calls
        assert(c[1][1] == "SetOwner" and c[1][2] == row and c[2][1] == "SetHyperlink" and c[2][2] == "item:5678" and c[3][1] == "Show")
        row.scripts.OnLeave(row)
        assert(c[4][1] == "Hide")
        assert(row_with(p, "Pick up the next").scripts.OnEnter == nil)
    end },
    { "bad item ids get no tooltip", function()
        local _, rows = WoWCompanion.RenderDigest(
            { schema = 1, character = "Thrall", generated = NOW, sections = { { id = "notes", lines = {
                { text = "a", item = "x|r" }, { text = "b", item = -3 }, { text = "c", item = 1.5 } } } } }, NOW, "Thrall")
        for i = 2, 4 do assert(rows[i].item == nil, i) end
    end },
    { "collapse state persists in WoWCompanionDB and survives a reload", function()
        local p = digest_client("full")
        local h = row_with(p, "Upgrades")
        assert(h.label:GetText():find("[-]", 1, true) and p.plain:find("Hammer of Fate", 1, true))
        h.scripts.OnClick(h)
        assert(WoWCompanionDB.collapsed.upgrades == true)
        assert(not p.plain:find("Hammer of Fate", 1, true) and p.plain:find("Linen Cloth", 1, true))
        assert(row_with(p, "Upgrades").label:GetText():find("[+]", 1, true))
        local saved = WoWCompanionDB
        fresh_client(saved)
        load_digest("tests/fixtures/digest_full.lua")
        assert(not WoWCompanion.panel.plain:find("Hammer of Fate", 1, true))
        local again = row_with(WoWCompanion.panel, "Upgrades")
        again.scripts.OnClick(again)
        assert(WoWCompanionDB.collapsed.upgrades == nil and WoWCompanion.panel.plain:find("Hammer of Fate", 1, true))
    end },
    { "the questions section collapses too", function()
        local p = ask_client(nil)
        local h = row_with(p, "Questions")
        h.scripts.OnClick(h)
        assert(WoWCompanionDB.collapsed.ask and not p.plain:find("What next?", 1, true))
    end },
    { "/wowc help lists the commands", function()
        fresh_client(nil)
        SlashCmdList.WOWC("help")
        local all = table.concat(PRINTED, "\n")
        for _, want in ipairs({ "/wowc ask", "/wowc reset", "/wowc help", "/ask" }) do assert(all:find(want, 1, true), want) end
        assert(not WoWCompanionPanel:IsShown())
    end },
    { "/wowc reset restores position and collapse state", function()
        local p = digest_client("full")
        p:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -75)
        p.scripts.OnDragStop(p)
        local h = row_with(p, "Notes")
        h.scripts.OnClick(h)
        SlashCmdList.WOWC("reset")
        assert(WoWCompanionDB.position == nil and WoWCompanionDB.collapsed == nil)
        assert(p:GetPoint() == "CENTER" and p.plain:find("Bank has 3", 1, true))
    end },
}
for _, c in ipairs(polish_cases) do cases[#cases + 1] = c end

local ask_cases = {
    { "/ask queues a question and shows it as queued", function()
        fresh_client(nil)
        NOW = 1800000100
        SlashCmdList.WOWCASK("  What should I do next?  ")
        local a = WoWCompanionDB.asks[1]
        assert(a.text == "What should I do next?" and a.character == "Thrall" and a.asked_at == NOW and a.id)
        assert(SLASH_WOWCASK1 == "/ask" and WoWCompanionPanel:IsShown())
        assert(WoWCompanionPanel.plain:find("queued; /reload to send", 1, true))
    end },
    { "/wowc ask queues; bare /wowc ask and empty /ask do not", function()
        fresh_client(nil)
        SlashCmdList.WOWC("ask hello there")
        SlashCmdList.WOWC("ask")
        SlashCmdList.WOWCASK("   ")
        assert(#WoWCompanionDB.asks == 1 and WoWCompanionDB.asks[1].text == "hello there")
    end },
    { "queue is capped at 10 (oldest dropped) and text at 500", function()
        fresh_client(nil)
        for i = 1, 12 do SlashCmdList.WOWCASK("q" .. i) end
        assert(#WoWCompanionDB.asks == 10)
        assert(WoWCompanionDB.asks[1].text == "q3" and WoWCompanionDB.asks[10].text == "q12")
        SlashCmdList.WOWCASK(string.rep("x", 800))
        assert(#WoWCompanionDB.asks[10].text == 500)
        local ids = {}
        for _, a in ipairs(WoWCompanionDB.asks) do assert(not ids[a.id]); ids[a.id] = true end
    end },
    { "question text is shown as data, color codes escaped", function()
        fresh_client(nil)
        SlashCmdList.WOWCASK("|cffff0000red")
        assert(WoWCompanionPanel.plain:find("||cffff0000red", 1, true))
    end },
    { "opening the panel loads the answers addon", function()
        local p = ask_client("full")
        assert(LOADED_ADDONS[#LOADED_ADDONS] == "WoWCompanion_Answers")
        assert(p.plain:find("A: Do the Hungry Ettin", 1, true))
    end },
    { "answer shows under its question with time and sources; ask marked answered", function()
        local p = ask_client("full")
        local t = p.plain
        local q, a, s = t:find("Q: What next?", 1, true), t:find("A: Do the", 1, true), t:find("sources: Quest 1234, Item 5678", 1, true)
        assert(q and a and s and q < a and a < s)
        assert(t:find("(1 min ago)", 1, true) and not t:find("queued;", 1, true))
        local ask = WoWCompanionDB.asks[1]
        assert(ask.answered == true and ask.answered_at == 1799999900)
    end },
    { "unanswered question stays queued when answers are absent", function()
        local p = ask_client(nil)
        assert(p.plain:find("queued; /reload to send", 1, true))
        assert(not WoWCompanionDB.asks[1].answered)
    end },
    { "malformed answer files are ignored with a panel note", function()
        for _, name in ipairs({ "badschema", "malformed" }) do
            local p = ask_client(name)
            local t = p.plain
            assert(t:find("queued; /reload to send", 1, true), name)
            assert(t:find("ignored", 1, true), name)
            assert(not WoWCompanionDB.asks[1].answered, name)
        end
    end },
}
local box_cases = {
    { "box: Enter queues like /ask, clears, shows queued; hint is shown", function()
        fresh_client(nil)
        local p = WoWCompanion.panel
        assert(p.askHint.text:find("/reload again to see the answer", 1, true) and p.askBox.maxLetters == 500)
        NOW = 1800000200
        p.askBox:SetText("  Best gear?  ")
        p.askBox.scripts.OnEnterPressed(p.askBox)
        local a = WoWCompanionDB.asks[1]
        assert(a.text == "Best gear?" and a.character == "Thrall" and a.asked_at == NOW and a.id)
        assert(p.askBox:GetText() == "" and p.plain:find("queued; /reload to send", 1, true))
    end },
    { "box: button queues; empty input ignored and kept; shares the queue with /ask", function()
        fresh_client(nil)
        local p = WoWCompanion.panel
        p.askBox:SetText("   ")
        p.askButton.scripts.OnClick(p.askButton)
        assert(WoWCompanionDB.asks == nil)
        SlashCmdList.WOWCASK("from slash")
        p.askBox:SetText("from box")
        p.askButton.scripts.OnClick(p.askButton)
        assert(#WoWCompanionDB.asks == 2 and WoWCompanionDB.asks[1].text == "from slash" and WoWCompanionDB.asks[2].text == "from box")
        assert(WoWCompanionDB.asks[1].id ~= WoWCompanionDB.asks[2].id)
    end },
    { "box: text capped at 500 like /ask; Escape clears focus and keeps text", function()
        fresh_client(nil)
        local p = WoWCompanion.panel
        p.askBox:SetText(string.rep("x", 800))
        p.askBox.scripts.OnEnterPressed(p.askBox)
        assert(#WoWCompanionDB.asks[1].text == 500)
        p.askBox.focused = true
        p.askBox:SetText("keep")
        p.askBox.scripts.OnEscapePressed(p.askBox)
        assert(p.askBox.focused == false and p.askBox:GetText() == "keep" and #WoWCompanionDB.asks == 1)
    end },
}
for _, c in ipairs(box_cases) do cases[#cases + 1] = c end
for _, c in ipairs(ask_cases) do cases[#cases + 1] = c end

-- Slot file safety: small table of sources through the static checker.
local Slot = dofile("tests/slotcheck.lua")
local slot_rows = {
    { true,  'WoWCompanionDigest = {}' },
    { true,  '-- c\nWoWCompanionDigest = { a = 1, b = { "x", true, { c = "y(" } } }' },
    { false, 'WoWCompanionDigest = {}\nprint("x")' },
    { false, 'WoWCompanionDigest = { f = function() end }' },
    { false, 'WoWCompanionDigest = { a = os.time() }' },
    { false, 'WoWCompanionDigest = { a = x }' },
    { false, 'WoWCompanionDigest = {}\nWoWCompanionDigest2 = {}' },
    { false, 'WoWCompanionDigest = { a = f"x" }' },
    { false, 'WoWCompanionDigest = { a = f{} }' },
    { false, 'x = 1\nWoWCompanionDigest = {}' },
    { false, 'WoWCompanionAnswers = {}' },
}
cases[#cases + 1] = { "slot checker accepts data and rejects code", function()
    for i, row in ipairs(slot_rows) do
        assert(Slot.check(row[2]) == row[1], "row " .. i)
    end
    assert(Slot.check('WoWCompanionAnswers = { answers = { ["a-1"] = { text = "x" } } }', "WoWCompanionAnswers"))
    assert(not Slot.check('WoWCompanionAnswers = { a = os.time() }', "WoWCompanionAnswers"))
end }

local failed = 0
for _, c in ipairs(cases) do
    local ok, err = pcall(c[2])
    report((ok and "ok   " or "FAIL ") .. c[1] .. (ok and "" or (": " .. tostring(err))))
    if not ok then failed = failed + 1 end
end
report(string.format("%d/%d passed", #cases - failed, #cases))
os.exit(failed == 0 and 0 or 1)
