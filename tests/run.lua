-- Tiny test runner: loads the TOC's Lua files in order against the stub.
local root = (arg and arg[1]) or "WoWCompanion"
local report = print
local Stub = dofile("tests/wow_stub.lua")

local frames = {}

local function fresh_client(savedvars)
    for k in pairs(WoWCompanion or {}) do WoWCompanion[k] = nil end
    WoWCompanion, WoWCompanionDB, SLASH_WOWC1 = nil, savedvars, nil
    WoWCompanionMinimapButton, ForeverScribeDB = nil, nil
    Stub.install(_G)
    frames = {}
    local create = CreateFrame
    CreateFrame = function(...)
        local f = create(...)
        frames[#frames + 1] = f
        return f
    end
    TOC_VERSION = nil
    local toc = assert(io.open(root .. "/WoWCompanion.toc"))
    for line in toc:lines() do
        local file = line:match("^([%w_\\]+%.lua)%s*$")
        if file then assert(loadfile(root .. "/" .. file:gsub("\\", "/")))() end
        TOC_VERSION = TOC_VERSION or line:match("^## Version:%s*(%S+)")
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
        for _, want in ipairs({ "Next quests", "Turn in The Hungry Ettin", "Upgrades", "Equip Hammer of Fate", "Keep materials", "Notes" }) do
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
        assert(p.plain:find("No advice for Thrall yet.", 1, true) and p.plain:find("3. Type /reload again.", 1, true))
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
        local row = row_with(p, "Hammer of Fate")
        row.scripts.OnEnter(row)
        local c = GameTooltip.calls
        assert(c[1][1] == "SetOwner" and c[1][2] == row and c[2][1] == "SetHyperlink" and c[2][2] == "item:5678" and c[3][1] == "Show")
        row.scripts.OnLeave(row)
        assert(c[4][1] == "Hide")
        assert(row_with(p, "Pick up the next").scripts.OnEnter == nil)
    end },
    { "schema 1.2 renders dungeons and talents with tooltip ids", function()
        local p = digest_client("v12")
        assert(p.plain:find("[-] Dungeons", 1, true) and p.plain:find("[-] Talents", 1, true))
        assert(p.plain:find("Deadmines: Level fit 15-20", 1, true) and p.plain:find("Next point: Mortal Strike", 1, true))
        local d, t, w = row_with(p, "Deadmines"), row_with(p, "Mortal Strike"), row_with(p, "Wailing Caverns")
        d.scripts.OnEnter(d)
        t.scripts.OnEnter(t)
        local c = GameTooltip.calls
        assert(c[2][1] == "SetHyperlink" and c[2][2] == "item:5198", "item tooltip")
        assert(c[5][1] == "SetHyperlink" and c[5][2] == "spell:12294", "spell tooltip")
        assert(w.scripts.OnEnter == nil)
    end },
    { "absent dungeon and talent sections stay hidden; a 1.1 digest renders", function()
        local p = digest_client("v11")
        assert(p.plain:find("Bank has 3", 1, true))
        assert(not p.plain:find("Dungeons", 1, true) and not p.plain:find("Talents", 1, true))
        p = digest_client("full")
        assert(not p.plain:find("Dungeons", 1, true))
        assert(WoWCompanion.SchemaOK("1.0") and WoWCompanion.SchemaOK(1) and not WoWCompanion.SchemaOK("2.0") and not WoWCompanion.SchemaOK("1."))
    end },
    { "dungeons and talents collapse and the settings toggles hide them", function()
        local p = digest_client("v12")
        local h = row_with(p, "Dungeons")
        h.scripts.OnClick(h)
        assert(WoWCompanionDB.collapsed.dungeons and not p.plain:find("Deadmines", 1, true) and p.plain:find("Mortal Strike", 1, true))
        h.scripts.OnClick(h)
        WoWCompanionOptionShowdungeons.checked = false
        WoWCompanionOptionShowdungeons.scripts.OnClick(WoWCompanionOptionShowdungeons)
        assert(not p.plain:find("Deadmines", 1, true) and p.plain:find("Mortal Strike", 1, true))
        WoWCompanionOptionShowtalents.checked = false
        WoWCompanionOptionShowtalents.scripts.OnClick(WoWCompanionOptionShowtalents)
        assert(not p.plain:find("Talents", 1, true))
    end },
    { "dungeon and talent lists are capped and sanitised", function()
        local list = {}
        for i = 1, 5 do list[i] = { line = "t" .. i, spell_id = "x|r" } end
        local _, rows = WoWCompanion.RenderDigest({ schema = "1.2", character = "Thrall", generated = NOW, talents = list,
            dungeons = { { name = "A|r", line = "b" }, "junk" } }, NOW, "Thrall")
        local t = WoWCompanion.RowsText(rows)
        assert(t:find("t3", 1, true) and not t:find("t4", 1, true) and t:find("A||r: b", 1, true))
        for _, r in ipairs(rows) do assert(r.spell == nil and r.item == nil) end
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
    { "/ask queues a question and prints the queued line", function()
        fresh_client(nil)
        NOW = 1800000100
        SlashCmdList.WOWCASK("  What should I do next?  ")
        local a = WoWCompanionDB.asks[1]
        assert(a.text == "What should I do next?" and a.character == "Thrall" and a.asked_at == NOW and a.id)
        assert(SLASH_WOWCASK1 == "/ask")
        assert(PRINTED[#PRINTED] == "Queued for WoW Companion. /reload and the overlay will answer it.")
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
    { "the panel has no Ask box, History or answers, and shows no queued questions", function()
        fresh_client(nil)
        SlashCmdList.WOWCASK("anything")
        local p = WoWCompanion.panel
        assert(not p.askBox and not p.histButton and not p.copyBox and not p.questionBox)
        assert(not WoWCompanion.ShowHistory and not WoWCompanion.LoadAnswers and not WoWCompanion.MatchAnswers)
        assert(not p.plain:find("queued", 1, true) and not p.plain:find("Questions", 1, true))
        for _, sec in ipairs(WoWCompanion.SECTIONS) do assert(sec[1] ~= "ask" and sec[1] ~= "history") end
        PRINTED = {}
        SlashCmdList.WOWC("history")
        assert(PRINTED[1] == "WoW Companion commands:" and not table.concat(PRINTED, "\n"):find("history", 1, true))
    end },
}
for _, c in ipairs(ask_cases) do cases[#cases + 1] = c end

-- Settings and the panel button.
local function scroll_top(p)
    return p.scroll.anchors.TOPLEFT[5]
end
local function settings() return WoWCompanion.db.settings end
-- Clicks like the client does: a check button flips before its handler runs.
local function click(b)
    if b.get then b.checked = not b.checked end
    b.scripts.OnClick(b)
end

local DEFAULT_SHOW = { quests = true, upgrades = true, materials = true, notes = true }
local settings_cases = {
    { "settings take defaults on first run", function()
        fresh_client(nil)
        local s = settings()
        assert(s.scale == 1 and s.locked == false and s.openOnLogin == false and s.minimap.angle == 215)
        for id, v in pairs(DEFAULT_SHOW) do assert(s.show[id] == v, id) end
        assert(WoWCompanionPanel.scale == 1)
    end },
    { "settings repair bad saved values", function()
        local rows = {
            { { scale = 9 }, 1.3 }, { { scale = 0.1 }, 0.7 }, { { scale = "x" }, 1 },
            { { scale = 0.82 }, 0.8 }, { "junk", 1 },
        }
        for i, r in ipairs(rows) do
            fresh_client({ settings = r[1] })
            assert(settings().scale == r[2] and type(settings().show) == "table", "row " .. i)
        end
        fresh_client({ settings = { show = { notes = false, talents = "no" } } })
        assert(settings().show.notes == false and settings().show.talents == true)
    end },
    { "settings persist through WoWCompanionDB", function()
        fresh_client(nil)
        click(WoWCompanionOptionLock)
        click(WoWCompanionOptionLogin)
        click(WoWCompanionOptionShownotes)
        WoWCompanionOptionScale.scripts.OnValueChanged(WoWCompanionOptionScale, 1.2)
        local saved = WoWCompanionDB
        fresh_client(saved)
        local s = settings()
        assert(s.locked and s.openOnLogin and s.show.notes == false and s.scale == 1.2)
        assert(WoWCompanionPanel.scale == 1.2 and WoWCompanionOptionLock.checked == true)
    end },
    { "locked panel does not start moving", function()
        fresh_client(nil)
        local p = WoWCompanionPanel
        p.scripts.OnDragStart(p)
        assert(p.moving == true)
        p.moving = false
        click(WoWCompanionOptionLock)
        p.scripts.OnDragStart(p)
        assert(not p.moving)
    end },
    { "open on login shows the panel", function()
        fresh_client({ settings = { openOnLogin = true } })
        load_digest("tests/fixtures/digest_full.lua")
        assert(WoWCompanionPanel:IsShown())
        fresh_client(nil)
        load_digest("tests/fixtures/digest_full.lua")
        assert(not WoWCompanionPanel:IsShown())
    end },
    { "section visibility changes the panel layout", function()
        local rows = {
            { "quests", "Next quests" }, { "upgrades", "Upgrades" },
            { "materials", "Keep materials" }, { "notes", "Notes" },
        }
        for _, r in ipairs(rows) do
            local p = digest_client("full")
            assert(p.plain:find(r[2], 1, true), r[2])
            click(_G["WoWCompanionOptionShow" .. r[1]])
            assert(not p.plain:find(r[2], 1, true), "still shows " .. r[2])
            click(_G["WoWCompanionOptionShow" .. r[1]])
            assert(p.plain:find(r[2], 1, true), "not restored " .. r[2])
        end
    end },
    { "compartment button toggles the panel", function()
        WITH_COMPARTMENT = true
        fresh_client(nil)
        WITH_COMPARTMENT = nil
        local reg = AddonCompartmentFrame.registered
        assert(#reg == 1 and reg[1].text == "WoW Companion" and WoWCompanion.buttonMode == "compartment")
        assert(WoWCompanionMinimapButton == nil)
        reg[1].func()
        assert(WoWCompanionPanel:IsShown())
        reg[1].func()
        assert(not WoWCompanionPanel:IsShown())
    end },
    { "minimap button is the fallback and toggles the panel", function()
        fresh_client(nil)
        local b = WoWCompanionMinimapButton
        assert(AddonCompartmentFrame == nil and WoWCompanion.buttonMode == "minimap" and b)
        click(b)
        assert(WoWCompanionPanel:IsShown())
        click(b)
        assert(not WoWCompanionPanel:IsShown())
    end },
    { "minimap button drags around the edge and saves its angle", function()
        fresh_client(nil)
        local b = WoWCompanionMinimapButton
        local _, _, _, x, y = b:GetPoint()
        assert(math.abs(x - math.cos(math.rad(215)) * 80) < 1e-6 and math.abs(y - math.sin(math.rad(215)) * 80) < 1e-6)
        b.scripts.OnDragStart(b)
        CURSOR[1], CURSOR[2] = 0, 300
        b.scripts.OnUpdate(b)
        b.scripts.OnDragStop(b)
        assert(b.scripts.OnUpdate == nil and settings().minimap.angle == 90)
        _, _, _, x, y = b:GetPoint()
        assert(math.abs(x) < 1e-6 and math.abs(y - 80) < 1e-6)
        local saved = WoWCompanionDB
        fresh_client(saved)
        assert(settings().minimap.angle == 90)
    end },
    { "minimap angle from cursor", function()
        local rows = { { 10, 0, 0, 0, 1, 0 }, { 0, 10, 0, 0, 1, 90 }, { -10, 0, 0, 0, 1, 180 },
                       { 0, -10, 0, 0, 1, -90 }, { 20, 20, 10, 10, 1, 45 }, { 20, 20, 5, 5, 2, 45 } }
        for i, r in ipairs(rows) do
            assert(math.abs(WoWCompanion.MinimapAngle(r[1], r[2], r[3], r[4], r[5]) - r[6]) < 1e-6, "row " .. i)
        end
    end },
    { "settings page: plain frame fallback", function()
        fresh_client(nil)
        assert(WoWCompanion.settingsMode == "frame" and not WoWCompanionSettings:IsShown())
        SlashCmdList.WOWC("settings")
        assert(WoWCompanionSettings:IsShown())
        SlashCmdList.WOWC("settings")
        assert(not WoWCompanionSettings:IsShown())
    end },
    { "settings page: client Settings API", function()
        WITH_SETTINGS_API = true
        fresh_client(nil)
        WITH_SETTINGS_API = nil
        assert(WoWCompanion.settingsMode == "settings" and Settings.registered.frame == WoWCompanionSettings)
        SlashCmdList.WOWC("settings")
        assert(Settings.opened[1] == 42)
    end },
}
for _, c in ipairs(settings_cases) do cases[#cases + 1] = c end

-- Locale: fallback to the key, and the lint (small rows plus one scan of the real files).
local Lint = dofile("tests/lint.lua")
local lint_rows = {
    { true,  'f.title:SetText(L.ADDON_NAME)' },
    { true,  'f.box:SetText("")' },
    { true,  'f.text:SetText(string.format(L.SCALE_LABEL, 1.5))' },
    { true,  'f.text:SetText(string.format("%.2f", s))' },
    { true,  'local x = "plain" -- SetText("comment")' },
    { true,  'text = L.NO_ADVICE' },
    { true,  'text = "  - " .. L.X' },
    { false, 'f.title:SetText("Hello")' },
    { false, 'f.text:SetText("Scale: " .. L.X)' },
    { false, 'print("Hello")' },
    { false, 'rows[1] = { kind = "text", text = "Hello" }' },
    { false, 'note = "The notes file"' },
    { false, 'f:SetText(L.X .. " items")' },
}
cases[#cases + 1] = { "lint flags literals that skip L", function()
    for i, row in ipairs(lint_rows) do
        assert(Lint.check(row[2]) == row[1], "row " .. i)
    end
end }
cases[#cases + 1] = { "every addon string goes through L", function()
    local bad = Lint.scan(root)
    assert(#bad == 0, table.concat(bad, "\n"))
end }
cases[#cases + 1] = { "a missing locale key falls back to the key, never nil", function()
    fresh_client(nil)
    local L = WoWCompanion.L
    assert(L.COMPACT == "Compact" and L.NOT_A_REAL_KEY == "NOT_A_REAL_KEY" and rawget(L, "NOT_A_REAL_KEY") == nil)
    L.COMPACT = nil
    assert(L.COMPACT == "COMPACT")
end }

-- What's new: once per version, never on a fresh install, dismissed for good.
local function upgrade_client(seen)
    fresh_client({ lastSeenVersion = seen, position = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 } })
    return WoWCompanion.whatsNew
end
cases[#cases + 1] = { "what's new shows once per version", function()
    local box = upgrade_client("0.0.0")
    assert(box and box.title.text == "What's new in " .. TOC_VERSION and box.body.text:find("overlay answers", 1, true))
    assert(box.body.text:find("\n", 1, true) and not box.body.text:find("WHATS_NEW", 1, true))
    assert(WoWCompanionDB.lastSeenVersion == "0.0.0", "not recorded until dismissed")
    -- Ignored, the note comes back on the next load.
    box = upgrade_client("0.0.0")
    assert(box)
    WoWCompanionWhatsNewButton.scripts.OnClick()
    assert(box:IsShown() == false and WoWCompanionDB.lastSeenVersion == TOC_VERSION)
    local saved = WoWCompanionDB
    fresh_client(saved)
    assert(WoWCompanion.whatsNew == nil, "same version shows nothing")
end }
cases[#cases + 1] = { "what's new is skipped on a fresh install and without a changelog entry", function()
    fresh_client(nil)
    assert(WoWCompanion.whatsNew == nil and WoWCompanionDB.lastSeenVersion == TOC_VERSION)
    local WC = WoWCompanion
    local db = {}
    assert(WC.WhatsNewPending(db, "9.9.9", false) == nil and db.lastSeenVersion == "9.9.9")
    assert(WC.WhatsNewPending({}, nil, false) == nil)
    assert(WC.CHANGELOG[TOC_VERSION] and #WC.CHANGELOG[TOC_VERSION] >= 1, "changelog covers the TOC version")
end }

-- Slot file safety: small table of sources through the static checker.
-- Tracker line and font size.
local tracker_rows = {
    { nil, "Next up: No digest yet" },
    { {}, "Next up: No digest yet" },
    { { schema = 2, character = "Thrall" }, "Next up: No digest yet" },
    { { schema = 1, character = "Jaina", sections = {} }, "No digest for Thrall" },
    { { schema = "2.0", characters = {} }, "No digest for Thrall" },
    { { schema = "2.0", characters = { thrall = { schema = "1.2", sections = { { id = "next_quests", lines = { { text = "Z" } } } } } } }, "Next up: Z" },
    { { schema = 1, character = "Thrall", sections = { { id = "notes", lines = { { text = "n" } } } } }, "Next up: No digest yet" },
    { { schema = 1, character = "Thrall", sections = { { id = "next_quests", lines = { { text = "A|r" } } } } }, "Next up: A||r" },
    { { schema = 1, character = "Thrall", sections = { { id = "next_quests", lines = { { text = "A" }, { text = "B" }, { text = "C" } } } } }, "Next up: A (+2 more)" },
}
local tracker_cases = {
    { "tracker text rows", function()
        fresh_client(nil)
        for i, r in ipairs(tracker_rows) do
            assert(WoWCompanion.TrackerText(r[1], "Thrall") == r[2], "row " .. i)
        end
    end },
    { "tracker is hidden by default", function()
        digest_client("full")
        assert(settings().tracker == false and WoWCompanionTracker:IsShown() == false)
    end },
    { "enabling the tracker shows the first step", function()
        digest_client("full")
        click(WoWCompanionSettings.checks[3])
        assert(settings().tracker == true and WoWCompanionTracker:IsShown())
        assert(WoWCompanionTracker.label:GetText() == "Next up: Turn in The Hungry Ettin (+1 more)")
    end },
    { "clicking the tracker opens the panel", function()
        digest_client("full")
        settings().tracker = true
        WoWCompanion.ApplySettings()
        assert(not WoWCompanionPanel:IsShown())
        WoWCompanionTracker.scripts.OnClick(WoWCompanionTracker)
        assert(WoWCompanionPanel:IsShown())
    end },
    { "tracker without a digest says no digest yet", function()
        fresh_client({ settings = { tracker = true } })
        WoWCompanionDigest = nil
        WoWCompanion.Refresh()
        assert(WoWCompanionTracker:IsShown() and WoWCompanionTracker.label:GetText() == "Next up: No digest yet")
    end },
    { "tracker position is saved and restored", function()
        fresh_client({ settings = { tracker = true } })
        local t = WoWCompanionTracker
        t:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 30, -60)
        t.scripts.OnDragStop(t)
        fresh_client(WoWCompanionDB)
        local point, _, _, x, y = WoWCompanionTracker:GetPoint()
        assert(point == "TOPLEFT" and x == 30 and y == -60)
    end },
    { "font size applies to the panel and the tracker", function()
        digest_client("full")
        settings().tracker = true
        local sizes = {}
        for _, id in ipairs({ "small", "normal", "large" }) do
            settings().fontSize = id
            WoWCompanion.ApplySettings()
            sizes[id] = { WoWCompanionPanel.header.fontSize, WoWCompanionPanel.rows[1].label.fontSize, WoWCompanionTracker.label.fontSize }
        end
        assert(sizes.small[1] == 10 and sizes.small[2] == 10 and sizes.small[3] == 10)
        assert(sizes.normal[1] == 12 and sizes.large[1] == 15 and sizes.large[2] == 15 and sizes.large[3] == 15)
    end },
    { "font size button cycles and bad values repair", function()
        digest_client("full")
        local b = WoWCompanionOptionFont
        local seen = {}
        for i = 1, 3 do b.scripts.OnClick(b); seen[i] = settings().fontSize end
        assert(seen[1] == "large" and seen[2] == "small" and seen[3] == "normal")
        assert(b:GetText() == "Text size: Normal")
        fresh_client({ settings = { fontSize = "huge", tracker = "yes" } })
        assert(settings().fontSize == "normal" and settings().tracker == false)
    end },
}
for _, c in ipairs(tracker_cases) do cases[#cases + 1] = c end

-- Hide in combat: rows are { saved settings, panel shown, tracker shown, panel after, tracker after }.
local function combat_client(hide, panel_on, tracker_on)
    fresh_client({ settings = { tracker = true, hideInCombat = hide } })
    WoWCompanionDigest = nil
    if panel_on then WoWCompanionPanel:Show() else WoWCompanionPanel:Hide() end
    if not tracker_on then WoWCompanionTracker:Hide() end
end
local combat_rows = {
    { nil,                              true,  true,  true,  false }, -- defaults: tracker only
    { { tracker = true, panel = true }, true,  true,  false, false },
    { { tracker = false },              true,  true,  true,  true  }, -- option off: no change
    { { panel = true },                 false, true,  false, false }, -- a hidden panel stays hidden
}
local combat_cases = {
    { "hide in combat hides and restores only what was visible", function()
        for i, r in ipairs(combat_rows) do
            combat_client(r[1], r[2], r[3])
            Stub.fire(frames, "PLAYER_REGEN_DISABLED")
            assert(WoWCompanionPanel:IsShown() == r[4] and WoWCompanionTracker:IsShown() == (r[3] and not (r[1] == nil or r[1].tracker ~= false)), "hide row " .. i)
            Stub.fire(frames, "PLAYER_REGEN_ENABLED")
            assert(WoWCompanionPanel:IsShown() == r[2] and WoWCompanionTracker:IsShown() == r[3], "restore row " .. i)
        end
    end },
    { "hide in combat defaults and repair", function()
        fresh_client(nil)
        assert(settings().hideInCombat.tracker == true and settings().hideInCombat.panel == false)
        fresh_client({ settings = { hideInCombat = "x" } })
        assert(settings().hideInCombat.tracker == true and settings().hideInCombat.panel == false)
    end },
    { "a refresh in combat keeps the tracker hidden until combat ends", function()
        combat_client(nil, false, true)
        Stub.fire(frames, "PLAYER_REGEN_DISABLED")
        WoWCompanion.Refresh()
        assert(not WoWCompanionTracker:IsShown())
        Stub.fire(frames, "PLAYER_REGEN_ENABLED")
        assert(WoWCompanionTracker:IsShown())
    end },
    { "a reload in combat starts hidden and restores on combat end", function()
        fresh_client({ settings = { tracker = true, hideInCombat = { panel = true }, openOnLogin = true } })
        COMBAT = true
        Stub.fire(frames, "PLAYER_LOGIN")
        assert(not WoWCompanionTracker:IsShown() and not WoWCompanionPanel:IsShown())
        COMBAT = false
        Stub.fire(frames, "PLAYER_REGEN_ENABLED")
        assert(WoWCompanionTracker:IsShown() and WoWCompanionPanel:IsShown())
    end },
    { "hide in combat checkboxes save the setting", function()
        fresh_client(nil)
        local checks = WoWCompanionSettings.checks
        click(checks[#checks - 1]); click(checks[#checks])
        assert(settings().hideInCombat.tracker == false and settings().hideInCombat.panel == true)
    end },
}
for _, c in ipairs(combat_cases) do cases[#cases + 1] = c end

-- /wowc status: rows through WC.StatusLines, plus one wiring case through the slash command.
local function status_text(db, digest, installed_map)
    fresh_client(db)
    WoWCompanionDigest = digest
    for k in pairs(MISSING_ADDONS) do MISSING_ADDONS[k] = nil end
    for k, v in pairs(installed_map or {}) do MISSING_ADDONS[k] = v end
    PRINTED = {}
    SlashCmdList.WOWC("status")
    return table.concat(PRINTED, "\n")
end
local NOW0 = 1800000000
local status_rows = {
    { "no digest, empty queue", {}, nil, {}, { "Digest: none yet", "Questions queued: 0", "WoWCompanion_Digest: installed" } },
    { "digest age and schema", {}, { schema = 1, character = "Thrall", generated = NOW0 - 7200 }, {}, { "Digest: updated 2 h ago, schema 1" } },
    { "digest with unknown schema", {}, { schema = 9, generated = NOW0 }, {}, { "schema 9" } },
    { "queued count", { asks = { { id = "a", text = "q" }, { id = "b", text = "q" } } }, nil, {}, { "Questions queued: 2" } },
    { "missing slot addon", {}, nil, { WoWCompanion_Digest = true }, { "WoWCompanion_Digest: not installed" } },
}
cases[#cases + 1] = { "status lines table", function()
    for i, row in ipairs(status_rows) do
        local text = status_text(row[2], row[3], row[4])
        for _, want in ipairs(row[5]) do assert(text:find(want, 1, true), "row " .. i .. " (" .. row[1] .. "): " .. want .. "\n" .. text) end
    end
end }
cases[#cases + 1] = { "status shows version and build and leaves the panel alone", function()
    local text = status_text({}, nil)
    assert(text:find("Addon " .. TOC_VERSION .. ", client build 1.15.7 (63456)", 1, true), text)
    assert(not WoWCompanionPanel:IsShown())
    fresh_client(nil)
    SlashCmdList.WOWC("help")
    assert(table.concat(PRINTED, "\n"):find("/wowc status", 1, true))
end }

-- Staleness against ForeverScribe's capture time, and the button tooltip.
local GEN = 1799996400 -- digest_full's generated
local function fs_db(captured) return { chars = { ["Testrealm:Thrall"] = { snapshot = { capturedAt = captured } } } } end
local function panel_text(fs)
    fresh_client(nil)
    ForeverScribeDB = fs
    load_digest("tests/fixtures/digest_full.lua")
    return WoWCompanion.panel.plain
end
local HINT = "Advice may be out of date"
local capture_rows = {
    { "capture 20 minutes after digest", fs_db(GEN + 1200), true },
    { "capture just over 15 minutes after", fs_db(GEN + 901), true },
    { "capture a few seconds after (the /reload)", fs_db(GEN + 5), false },
    { "capture at 15 minutes", fs_db(GEN + 900), false },
    { "capture before digest", fs_db(GEN - 50), false },
    { "ForeverScribe absent", nil, false },
    { "no record for this character", { chars = { ["Testrealm:Other"] = { snapshot = { capturedAt = GEN + 9999 } } } }, false },
    { "malformed global", { chars = "x" }, false },
    { "found by identity name", { chars = { ["k"] = { snapshot = { identity = { name = "Thrall" }, capturedAt = GEN + 9999 } } } }, true },
}
cases[#cases + 1] = { "stale vs fresh digest against the capture time", function()
    for i, row in ipairs(capture_rows) do
        assert((panel_text(row[2]):find(HINT, 1, true) ~= nil) == row[3], "row " .. i .. " (" .. row[1] .. ")")
    end
    local before = fs_db(GEN + 1200)
    panel_text(before)
    assert(before.chars["Testrealm:Thrall"].snapshot.capturedAt == GEN + 1200 and next(before) == "chars")
end }
local tip_rows = {
    { "2.0 file without this character", {}, { schema = "2.0", generated = NOW0, characters = {} }, { "Digest: none yet" } },
    { "1.2 file for another character", {}, { schema = "1.2", character = "Jaina", generated = NOW0 }, { "Digest: none yet" } },
    { "no digest, empty queue", {}, nil, { "Digest: none yet", "Questions queued: 0", "Click to open" } },
    { "digest and queue", { asks = { { id = "a", text = "q" }, { id = "b", text = "q" } } },
      { character = "Thrall", generated = NOW0 - 7200 }, { "Digest: updated 2 h ago", "Questions queued: 2", "Click to open" } },
}
local outdated_rows = {
    { "fresh, capture seconds later", { generated = 1000 }, 1100, 1010, false },
    { "capture 20 minutes later", { generated = 1000 }, 1100, 2200, true },
    { "no capture, under the stale age", { generated = 1000 }, 1100, nil, false },
    { "over the stale age", { generated = 1000 }, 1000 + 13 * 3600, nil, true },
    { "over 24 hours", { generated = 1000 }, 1000 + 25 * 3600, nil, true },
}
cases[#cases + 1] = { "out-of-date rule table, tracker, tooltip and status", function()
    fresh_client(nil)
    for i, r in ipairs(outdated_rows) do
        assert(WoWCompanion.DigestOutdated(r[2], r[3], r[4]) == r[5], "row " .. i .. " (" .. r[1] .. ")")
    end
    local d = { schema = "1.2", character = "Thrall", generated = NOW0 - 7200,
        sections = { { id = "next_quests", lines = { { text = "Turn in X" } } } } }
    local function tip(c) return table.concat(WoWCompanion.TooltipLines({ digest = d, db = {}, player = "Thrall", now = NOW0, captured = c }), "\n") end
    local function stat(c) return table.concat(WoWCompanion.StatusLines({ digest = d, db = {}, player = "Thrall", now = NOW0, captured = c, installed = {} }), "\n") end
    assert(not WoWCompanion.TrackerText(d, "Thrall", NOW0, NOW0 - 7190):find("out of date", 1, true))
    assert(WoWCompanion.TrackerText(d, "Thrall", NOW0, NOW0 - 7200 + 1200):find("out of date", 1, true))
    assert(not tip(NOW0 - 7190):find("out of date", 1, true) and tip(NOW0 - 7200 + 1200):find("out of date", 1, true))
    assert(not stat(NOW0 - 7190):find("out of date", 1, true) and stat(NOW0 - 7200 + 1200):find("out of date", 1, true))
end }
cases[#cases + 1] = { "tooltip lines table", function()
    for i, row in ipairs(tip_rows) do
        fresh_client(nil)
        local text = table.concat(WoWCompanion.TooltipLines({ digest = row[3], db = row[2], player = "Thrall", now = NOW0 }), "\n")
        for _, want in ipairs(row[4]) do assert(text:find(want, 1, true), "row " .. i .. ": " .. want .. "\n" .. text) end
    end
end }
cases[#cases + 1] = { "button hover fills and hides the tooltip on both button kinds", function()
    local function hover(enter, leave, owner)
        GameTooltip.calls = {}
        enter(owner)
        local lines = {}
        for _, c in ipairs(GameTooltip.calls) do if c[1] == "AddLine" then lines[#lines + 1] = c[2] end end
        assert(GameTooltip.calls[1][1] == "SetOwner" and GameTooltip.calls[#GameTooltip.calls][1] == "Show")
        assert(lines[#lines] == "Click to open" and lines[2] == "Digest: none yet")
        leave(owner)
        assert(GameTooltip.calls[#GameTooltip.calls][1] == "Hide")
    end
    WoWCompanionDigest = nil
    fresh_client(nil)
    local b = WoWCompanionMinimapButton
    hover(b.scripts.OnEnter, b.scripts.OnLeave, b)
    WITH_COMPARTMENT = true
    fresh_client(nil)
    WITH_COMPARTMENT = nil
    WoWCompanionDigest = nil
    local reg = AddonCompartmentFrame.registered[1]
    hover(reg.funcOnEnter, reg.funcOnLeave, {})
end }

-- Compact mode and keyboard paging.
local function key(p, k) p.scripts.OnKeyDown(p, k); return p.propagate end
local compact_cases = {
    { "compact: first line per section, frame shrinks, header click expands, mode persists", function()
        local p = digest_client("full")
        local full_lines, full_h = select(2, p.plain:gsub("\n", "")), p.h
        click(WoWCompanionCompactButton)
        assert(WoWCompanionDB.settings.compact == true and WoWCompanionCompactButton:GetText() == "Full")
        assert(select(2, p.plain:gsub("\n", "")) < full_lines and p.h < full_h and p.h >= 150)
        assert(p.plain:find("Turn in", 1, true) and not p.plain:find("Pick up the next", 1, true))
        assert(select(2, p.plain:gsub("\n", "")) + 1 == 8 and full_lines + 1 == 9, "4 headers + 1 line each: 8 rows vs 9")
        local rows = WoWCompanion.CompactRows({
            { kind = "header", id = "a", title = "A", text = "[-] A" }, { kind = "line", text = "1" }, { kind = "line", text = "2" },
            { kind = "header", id = "b", title = "B", text = "[-] B" }, { kind = "line", text = "3" },
            { kind = "text", text = "note" },
        }, {})
        assert(#rows == 5 and rows[1].text == "[+] A" and rows[3].text == "[-] B")
        assert(#WoWCompanion.CompactRows({ { kind = "header", id = "a", title = "A", text = "[-] A" },
            { kind = "line" }, { kind = "line" } }, { a = true }) == 3)
        local h = row_with(p, "[+]")
        local before = #p.plain
        h.scripts.OnClick(h)
        assert(#p.plain > before and WoWCompanion.view.expanded[h.sectionId] and not WoWCompanionDB.collapsed)
        local saved = WoWCompanionDB
        fresh_client(saved)
        assert(settings().compact == true and WoWCompanionCompactButton:GetText() == "Full" and WoWCompanionOptionCompact.checked == true)
        click(WoWCompanionOptionCompact)
        assert(settings().compact == false and WoWCompanionPanel.h == 320)
    end },
}
for _, c in ipairs(compact_cases) do cases[#cases + 1] = c end

local Slot = dofile("tests/slotcheck.lua")
local slot_rows = {
    { true,  'WoWCompanionDigest = {}' },
    { true,  '-- c\nWoWCompanionDigest = { a = 1, b = { "x", true, { c = "y(" } } }' },
    { true,  'WoWCompanionDigest = { schema = "2.0", characters = { ["Testchar"] = { schema = "1.2", sections = { { id = "notes" } } } } }' },
    { false, 'WoWCompanionDigest = { characters = { ["Testchar"] = { f = function() end } } }' },
    { false, 'WoWCompanionDigest = { characters = { ["Test" .. "char"] = {} } }' },
    { false, 'WoWCompanionDigest = { characters = { [x] = {} } }' },
    { false, 'WoWCompanionDigest = {}\nprint("x")' },
    { false, 'WoWCompanionDigest = { f = function() end }' },
    { false, 'WoWCompanionDigest = { a = os.time() }' },
    { false, 'WoWCompanionDigest = { a = x }' },
    { false, 'WoWCompanionDigest = {}\nWoWCompanionDigest2 = {}' },
    { false, 'WoWCompanionDigest = { a = f"x" }' },
    { false, 'WoWCompanionDigest = { a = f{} }' },
    { false, 'x = 1\nWoWCompanionDigest = {}' },
}
cases[#cases + 1] = { "slot checker accepts data and rejects code", function()
    for i, row in ipairs(slot_rows) do
        assert(Slot.check(row[2]) == row[1], "row " .. i)
    end
end }

-- Schema 2.0 files: the panel picks characters[UnitName("player")] and says what to do on a miss.
local v2_rows = {
    -- name, player, fixture, must show, must not show
    { "2.0 hit", "Testchar", "v2", { "Next quests", "Turn in The Hungry Ettin" }, { "Other note", "No advice for" } },
    { "case-insensitive hit", "TESTCHAR", "v2", { "Next quests", "Turn in The Hungry Ettin" }, { "No advice for" } },
    { "2.0 miss lists the others", "Missingchar", "v2", { "No advice for Missingchar yet.", "1. Type /reload so ForeverScribe", "2. Ask your AI", "wowc-advisor digest", "3. Type /reload again.", "Digests here for: Otherchar, Testchar" }, { "Next quests" } },
    { "1.2 file for another character", "Thrall", "wrongchar", { "No advice for Thrall yet.", "1. Type /reload", "3. Type /reload again." }, { "Digests here for", "Next quests" } },
    { "1.2 file for this character", "Thrall", "full", { "Next quests", "Turn in The Hungry Ettin" }, { "No advice for", "1. Type /reload" } },
    { "empty digest keeps the hint", "Thrall", "empty", { "No advice yet", "1. Type /reload", "3. Type /reload again." }, { "Digests here for" } },
    { "unknown schema", "Thrall", "badschema", { "unknown format (schema 99)" }, { "No advice for", "Next quests" } },
}
cases[#cases + 1] = { "schema 2 digest rows through the panel", function()
    for i, row in ipairs(v2_rows) do
        PLAYER_NAME = row[2]
        local ok, err = pcall(function()
            local p = digest_client(row[3])
            for _, want in ipairs(row[4]) do assert(p.plain:find(want, 1, true), "row " .. i .. " (" .. row[1] .. "): " .. want .. "\n" .. p.plain) end
            for _, no in ipairs(row[5]) do assert(not p.plain:find(no, 1, true), "row " .. i .. " (" .. row[1] .. "): unwanted " .. no) end
        end)
        PLAYER_NAME = nil
        assert(ok, err)
    end
end }
cases[#cases + 1] = { "schema 2 digest drives the tracker, status and tooltip", function()
    PLAYER_NAME = "Testchar"
    local ok, err = pcall(function()
        digest_client("v2")
        local d = WoWCompanionDigest
        assert(WoWCompanion.TrackerText(d, "Testchar") == "Next up: Turn in The Hungry Ettin (+1 more)")
        assert(WoWCompanion.TrackerText(d, "Missingchar") == "No digest for Missingchar")
        assert(status_text({}, d):find("Digest: updated", 1, true))
        PLAYER_NAME = "Missingchar"
        assert(status_text({}, d):find("Digest: none yet", 1, true))
    end)
    PLAYER_NAME = nil
    assert(ok, err)
end }

-- "Ask about this": right-click queues the line's templated question, like /ask.
local function dofile_digest(file)
    local keep = WoWCompanionDigest
    WoWCompanionDigest = nil
    assert(loadfile(file))()
    local d = WoWCompanionDigest
    WoWCompanionDigest = keep
    return d
end
local function ask_row_client()
    fresh_client(nil)
    load_digest("tests/fixtures/digest_full.lua")
    local d = WoWCompanionDigest
    local v12 = dofile_digest("tests/fixtures/digest_v12.lua")
    d.dungeons, d.talents = v12.dungeons, v12.talents
    WoWCompanion.Refresh()
    return WoWCompanion.panel
end
local ask_rows = {
    { "Turn in The Hungry Ettin", "Where do I go for   - Turn in The Hungry Ettin, and what's the fastest route?" },
    { "Hammer of Fate", "Where does   - Equip Hammer of Fate (+12 ilvl) (item 5678) drop, and is it worth farming?" },
    { "Linen Cloth", "What should I make with   - Keep Linen Cloth for tailoring (item 2589)?" },
    { "Deadmines", "Should I run Deadmines now, and what should I bring?" },
    { "Mortal Strike", "Why   - Next point: Mortal Strike next for my spec?" },
}
cases[#cases + 1] = { "ask about this: right-click queues each line type's template and prints one line", function()
    local p = ask_row_client()
    for i, c in ipairs(ask_rows) do
        PRINTED = {}
        local row = row_with(p, c[1])
        row.scripts.OnClick(row, "RightButton")
        local a = WoWCompanionDB.asks[i]
        assert(a and a.text:find(c[1], 1, true), c[1])
        assert(a.text:find("^%u") and a.character == "Thrall" and a.asked_at == NOW and a.id, c[1])
        assert(#PRINTED == 1 and PRINTED[1] == "Queued for WoW Companion. /reload and the overlay will answer it.", c[1])
    end
    assert(#WoWCompanionDB.asks == #ask_rows)
    local before = #WoWCompanionDB.asks
    local notes = row_with(p, "Bank has")
    notes.scripts.OnClick(notes, "RightButton")
    local h = row_with(p, "Upgrades")
    h.scripts.OnClick(h, "RightButton")
    assert(not WoWCompanionDB.collapsed and #WoWCompanionDB.asks == before)
end }
cases[#cases + 1] = { "ask about this: AskTemplate by line type", function()
    local T = WoWCompanion.AskTemplate
    assert(T({ ask = { kind = "quest", subject = "Q" } }) == "Where do I go for Q, and what's the fastest route?")
    assert(T({ ask = { kind = "upgrade", subject = "I" } }) == "Where does I drop, and is it worth farming?")
    assert(T({ ask = { kind = "material", subject = "M" } }) == "What should I make with M?")
    assert(T({ ask = { kind = "dungeon", subject = "D" } }) == "Should I run D now, and what should I bring?")
    assert(T({ ask = { kind = "talent", subject = "T" } }) == "Why T next for my spec?")
    assert(T({}) == nil and T(nil) == nil and T({ ask = { kind = "bogus", subject = "x" } }) == nil)
end }
cases[#cases + 1] = { "panel content and rows follow the panel's visibility, and carry no id tags", function()
    local p = digest_client("full")
    assert(#p.rows > 0 and not p:IsVisible())
    local function any_visible()
        if p.content:IsVisible() then return true end
        for _, r in ipairs(p.rows) do if r:IsVisible() then return true end end
        return false
    end
    assert(not any_visible(), "nothing visible while the panel is closed")
    WoWCompanion.ShowPanel()
    assert(p.content:IsVisible() and row_with(p, "Hammer of Fate"):IsVisible())
    WoWCompanion.TogglePanel()
    assert(not any_visible(), "hidden again after closing")
    assert(not p.plain:find("[item ", 1, true) and not p.plain:find("[quest ", 1, true))
end }

-- Game tooltips: gold lines for a digest upgrade item and a next-step quest, none when switched off.
local function tooltip_client(setup)
    fresh_client(nil)
    load_digest("tests/fixtures/digest_full.lua")
    return WoWCompanion
end
local function tooltip_lines()
    local out = {}
    for _, c in ipairs(GameTooltip.calls) do if c[1] == "AddLine" then out[#out + 1] = c end end
    return out
end
cases[#cases + 1] = { "tooltips: upgrade item and next-step quest get a gold line; others and the off setting get none", function()
    local WC = tooltip_client()
    INVTYPE_WEAPON = "One-Hand"
    GetItemInfoInstant = function() return 5678, "Weapon", "Hammer", "INVTYPE_WEAPON" end
    assert(WC.TooltipLine("item", 5678) == "WoW Companion: upgrade for One-Hand")
    assert(WC.TooltipLine("quest", 1234) == "WoW Companion: next step #1")
    assert(WC.TooltipLine("item", 2589) == nil and WC.TooltipLine("quest", 99) == nil and WC.TooltipLine("item", nil) == nil)
    assert(WC.TooltipLine("item", 1234) == nil and WC.TooltipLine("quest", 5678) == nil)
    GetItemInfoInstant = nil
    assert(WC.TooltipLine("item", 5678) == "WoW Companion: upgrade for your gear")
    WoWCompanionDB.settings.tooltips = false
    assert(WC.TooltipLine("item", 5678) == nil and WC.TooltipLine("quest", 1234) == nil)
    WoWCompanionDB.settings.tooltips = true
    PLAYER_NAME = "Jaina"
    assert(WC.TooltipLine("item", 5678) == nil)
    PLAYER_NAME = nil
end }
cases[#cases + 1] = { "tooltips: the TooltipDataProcessor hook adds the gold line to the game tooltip", function()
    local posts = {}
    Enum = { TooltipDataType = { Item = 1, Quest = 2 } }
    TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) posts[kind] = fn end }
    local ok, err = pcall(function()
        tooltip_client()
        assert(WoWCompanion.tooltipMode == "processor" and posts[1] and posts[2])
        GameTooltip.calls = {}
        posts[1](GameTooltip, { id = 5678 })
        posts[2](GameTooltip, { id = 1234 })
        posts[1](GameTooltip, { id = 2589 })
        posts[1]({}, { id = 5678 })
        local lines = tooltip_lines()
        assert(#lines == 2 and lines[1][2]:find("upgrade for", 1, true) and lines[2][2] == "WoW Companion: next step #1")
        assert(lines[1][3] == 1 and lines[1][4] == 0.82 and lines[1][5] == 0)
        WoWCompanionDB.settings.tooltips = false
        GameTooltip.calls = {}
        posts[1](GameTooltip, { id = 5678 })
        assert(#tooltip_lines() == 0)
    end)
    Enum, TooltipDataProcessor = nil, nil
    assert(ok, err)
end }
cases[#cases + 1] = { "tooltips: older clients hook the tooltip instead; the setting defaults on and has a checkbox", function()
    WITH_TOOLTIP_HOOKS = true
    local ok, err = pcall(function()
        tooltip_client()
        local hooks = HOOKS
        assert(WoWCompanion.tooltipMode == "hook" and WoWCompanionDB.settings.tooltips == true)
        GameTooltip.calls = {}
        hooks.OnTooltipSetItem(GameTooltip)
        hooks.SetHyperlink(GameTooltip, "quest:1234")
        local lines = tooltip_lines()
        assert(#lines == 2 and lines[2][2] == "WoW Companion: next step #1")
        click(WoWCompanionOptionTooltips)
        assert(WoWCompanionDB.settings.tooltips == false)
    end)
    WITH_TOOLTIP_HOOKS = nil
    assert(ok, err)
end }

-- Locale strings are plain text: no markdown backticks (the game would print them literally).
cases[#cases + 1] = { "no locale string contains a backtick; the stale hint reads plainly", function()
    fresh_client(nil)
    local n = 0
    for k, v in pairs(WoWCompanion.L) do
        n = n + 1
        assert(not tostring(v):find("`", 1, true), "backtick in " .. k)
    end
    assert(n > 50)
    assert(WoWCompanion.L.OLDER_THAN_CAPTURE == "Advice may be out of date: /reload (the overlay refreshes it) or run wowc-advisor digest.")
end }

local failed = 0
for _, c in ipairs(cases) do
    local ok, err = pcall(c[2])
    report((ok and "ok   " or "FAIL ") .. c[1] .. (ok and "" or (": " .. tostring(err))))
    if not ok then failed = failed + 1 end
end
report(string.format("%d/%d passed", #cases - failed, #cases))
os.exit(failed == 0 and 0 or 1)
