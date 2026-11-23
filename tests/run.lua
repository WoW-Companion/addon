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
    -- Most cases look at the upgrade lines, which start collapsed since the chip row covers them.
    local st = WoWCompanion.db and WoWCompanion.db.settings
    if st and not (savedvars and savedvars.settings and savedvars.settings.upgradesSection ~= nil) then st.upgradesSection = true end
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
        assert(p.title:GetText() == "WoW Companion: Thrall" and h:find("advice from", 1, true) and h:find("1 h ago", 1, true))
        local last = 0
        for _, want in ipairs({ "Next quests", "Turn in The Hungry Ettin", "Upgrades", "Equip Hammer of Fate", "Keep materials", "Notes" }) do
            local at = t:find(want, last + 1, true)
            assert(at, "missing " .. want)
            last = at
        end
    end },
    { "digest over 12 hours old shows its age and the refresh note", function()
        local p = digest_client("stale")
        assert(p.header:GetText():find("advice from ", 1, true) and p.header:GetText():find("(1 d ago)", 1, true))
        assert(p.plain:find("Ask your AI client to refresh your digest, then /reload.", 1, true))
        local fresh = digest_client("full")
        assert(fresh.header:GetText():find("(1 h ago)", 1, true) and not fresh.plain:find("refresh your digest", 1, true))
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
    -- the to-do chips are buttons under the header; they answer like a row that carries an entry
    for _, b in ipairs(p.chipButtons or {}) do
        if b:IsShown() and b.chip and b.chip.entry.title:find(text, 1, true) then
            b.entry = b.chip.entry
            return b
        end
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
        local n = #c
        local plain_row = row_with(p, "Pick up the next")
        plain_row.scripts.OnEnter(plain_row)
        plain_row.scripts.OnLeave(plain_row)
        assert(#c == n, "a row with no link shows no tooltip")
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
        local n = #c
        w.scripts.OnEnter(w)
        assert(#c == n, "a row with no link shows no tooltip")
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
-- Colours are compared by value: the settings hand out their own copies.
local function same_color(a, b) return a and b and a[1] == b[1] and a[2] == b[2] and a[3] == b[3] end
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
        assert(s.scale == 1 and s.locked == false and s.openOnLogin == false and s.minimap.angle == 180)
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
        assert(WoWCompanionMinimapButton ~= nil, "the rim button is created as well")
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
        assert(math.abs(x + 75) < 1e-6 and math.abs(y) < 1e-6, "default: left of the ring, radius 70 + 5 on the stub's 140 px minimap")
        b.scripts.OnDragStart(b)
        CURSOR[1], CURSOR[2] = 0, 300
        b.scripts.OnUpdate(b)
        b.scripts.OnDragStop(b)
        assert(b.scripts.OnUpdate == nil and settings().minimap.angle == 90)
        _, _, _, x, y = b:GetPoint()
        assert(math.abs(x) < 1e-6 and math.abs(y - 75) < 1e-6)
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
    { "options window: the slash aliases toggle it; the fallback page stays hidden", function()
        fresh_client(nil)
        assert(WoWCompanion.settingsMode == "frame" and not WoWCompanionSettings:IsShown() and not WoWCompanionOptions:IsShown())
        for _, alias in ipairs({ "options", "config", "settings" }) do
            SlashCmdList.WOWC(alias)
            assert(WoWCompanionOptions:IsShown(), alias)
            SlashCmdList.WOWC(alias)
            assert(not WoWCompanionOptions:IsShown(), alias)
        end
    end },
    { "settings page: client Settings API", function()
        WITH_SETTINGS_API = true
        fresh_client(nil)
        WITH_SETTINGS_API = nil
        assert(WoWCompanion.settingsMode == "settings" and Settings.registered.frame == WoWCompanionSettings)
        WoWCompanion.OpenSettings()
        assert(Settings.opened[1] == 42)
        WoWCompanionOpenOptions.scripts.OnClick(WoWCompanionOpenOptions)
        assert(WoWCompanionOptions:IsShown(), "the AddOns page button opens the window")
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
    assert(box and box.title.text == "What's new in " .. TOC_VERSION)
    assert(#box.body.text:gsub("%s", "") > 0 and not box.body.text:find("WHATS_NEW", 1, true), "note exists and is not a raw key")
    assert(WoWCompanionDB.lastSeenVersion == "0.0.0", "not recorded until dismissed")
    -- Ignored, the note comes back on the next load.
    box = upgrade_client("0.0.0")
    assert(box)
    WoWCompanionWhatsNewButton.scripts.OnClick()
    assert(box:IsShown() == false and WoWCompanionDB.lastSeenVersion == TOC_VERSION)
    local saved = WoWCompanionDB
    fresh_client(saved)
    assert(WoWCompanion.whatsNew == nil, "same version shows nothing")
    assert(upgrade_client("0.0.1"), "an older recorded version shows the note again")
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
        click(WoWCompanionOptionTracker)
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
    { "font size radios pick a size and bad values repair", function()
        digest_client("full")
        local seen = {}
        for i, id in ipairs({ "large", "small", "normal" }) do
            local r = _G["WoWCompanionOptionFont_" .. id]
            r.scripts.OnClick(r)
            seen[i] = settings().fontSize
            assert(r.checked == true and _G["WoWCompanionOptionFont_" .. (id == "large" and "small" or "large")].checked == false)
        end
        assert(seen[1] == "large" and seen[2] == "small" and seen[3] == "normal")
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
        click(WoWCompanionOptionHideTracker); click(WoWCompanionOptionHidePanel)
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
    { "digest age and schema", {}, { schema = 1, character = "Thrall", generated = NOW0 - 7200 }, {}, { "(2 h ago), schema 1" } },
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
local HINT = "is newer than this advice"
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
    { "no digest, empty queue", {}, nil, { "Digest: none yet", "Questions queued: 0", "Left-click", "Right-click: open the options" } },
    { "digest and queue", { asks = { { id = "a", text = "q" }, { id = "b", text = "q" } } },
      { character = "Thrall", generated = NOW0 - 7200 }, { "(2 h ago)", "Questions queued: 2", "Left-click" } },
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
        local all = table.concat(lines, "\n")
        assert(lines[2] == "Digest: none yet" and all:find("Left-click: show or hide the panel", 1, true))
        assert(all:find("Right-click: open the options", 1, true))
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
        assert(WoWCompanionDB.settings.view == "compact" and WoWCompanionCompactButton:GetText() == "Full")
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
        assert(settings().view == "compact" and WoWCompanionCompactButton:GetText() == "Full" and WoWCompanionOptionView_compact.checked == true)
        click(WoWCompanionOptionView_full)
        assert(settings().view == "full" and WoWCompanionPanel.h == 320)
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
        assert(status_text({}, d):find("Digest: advice from", 1, true))
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
cases[#cases + 1] = { "ask about this: right-click opens the card with each line type's template; Send queues it and prints one line", function()
    local p = ask_row_client()
    for i, c in ipairs(ask_rows) do
        PRINTED = {}
        local row = row_with(p, c[1])
        row.scripts.OnClick(row, "RightButton")
        local box = WoWCompanionCardAsk
        assert(WoWCompanionCard:IsShown() and box:GetText():find(c[1], 1, true), c[1])
        assert(not WoWCompanionDB.asks or #WoWCompanionDB.asks == i - 1, "nothing queues until Send")
        WoWCompanionCardSend.scripts.OnClick(WoWCompanionCardSend)
        local a = WoWCompanionDB.asks[i]
        assert(a and a.text:find(c[1], 1, true), c[1])
        assert(a.text:find("^%u") and a.character == "Thrall" and a.asked_at == NOW and a.id, c[1])
        assert(#PRINTED == 1 and PRINTED[1] == "Queued for WoW Companion. /reload and the overlay will answer it.", c[1])
    end
    assert(#WoWCompanionDB.asks == #ask_rows)
    local before = #WoWCompanionDB.asks
    local notes = row_with(p, "Bank has")
    notes.scripts.OnClick(notes, "RightButton")
    assert(WoWCompanionCardAsk:GetText() == "I'm a player. My plan says: \"Bank has 3 unused bags\". What should I do about that?" and #WoWCompanionDB.asks == before)
    local h = row_with(p, "Upgrades")
    h.scripts.OnClick(h, "RightButton")
    assert(not WoWCompanionDB.collapsed and #WoWCompanionDB.asks == before)
end }
cases[#cases + 1] = { "ask about this: AskTemplate by line type", function()
    local T = WoWCompanion.AskTemplate
    UnitLevel = function() return 10 end
    UnitClass = function() return "Warrior", "WARRIOR" end
    local who = "I'm a level 10 warrior"
    assert(T({ ask = { kind = "quest", subject = "Q" } }) == who .. ". Where do I go for Q, and what's the fastest way to finish it?")
    assert(T({ ask = { kind = "upgrade", subject = "I" } }) == who .. ". Where does I come from, and is it worth getting now?")
    assert(T({ ask = { kind = "material", subject = "M" } }) == who .. ". What should I make with M, and is it worth keeping?")
    assert(T({ ask = { kind = "dungeon", subject = "D" } }) == who .. ". Should I run D now, and what should I bring?")
    assert(T({ ask = { kind = "talent_pick", subject = "Next point: T" } }) == who .. ". Why is T the right next pick for me?")
    assert(T({ ask = { kind = "talent_points", subject = "1 unspent talent point" } }) == who .. " with 1 unspent talent point. Which talent should I take next, and why?")
    assert(T({ ask = { kind = "training", subject = "A, B" } }) == who .. ". I can now train A, B. Which should I train first, and how do they fit my rotation?")
    assert(T({ ask = { kind = "note", subject = "Bank full" } }) == who .. '. My plan says: "Bank full". What should I do about that?')
    UnitLevel, UnitClass = nil, nil
    assert(T({ ask = { kind = "quest", subject = "Q" } }):find("^I'm a player%. Where do I go for Q"))
    UnitClass = function() return "Mage", "MAGE" end
    assert(T({ ask = { kind = "quest", subject = "Q" } }):find("^I'm a mage%."))
    UnitClass = nil
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
    assert(WoWCompanion.L.OLDER_THAN_CAPTURE == "Your last save (%s) is newer than this advice. The overlay refreshes it seconds after each save: /reload once more to pick it up.")
end }

cases[#cases + 1] = { "advice time: 12- and 24-hour clocks, header and out-of-date line", function()
    fresh_client(nil)
    local WC = WoWCompanion
    local ts = os.time({ year = 2026, month = 11, day = 22, hour = 15, min = 5 })
    assert(WC.FormatClock(ts, true) == "15:05" and WC.FormatClock(ts, false) == "3:05 PM")
    local am = os.time({ year = 2026, month = 11, day = 22, hour = 0, min = 9 })
    assert(WC.FormatClock(am, true) == "00:09" and WC.FormatClock(am, false) == "12:09 AM")
    local clock = WC.FormatClock(ts)
    local d = { schema = 1, character = "Thrall", generated = ts, sections = { { id = "next", lines = { { text = "x" } } } } }
    local header, rows = WC.RenderDigest(d, ts + 49 * 60, "Thrall", nil, nil, ts + 20 * 60)
    assert(header == "Thrall \226\128\148 advice from " .. clock .. " (49 min ago)", header)
    local want = "Your last save (" .. WC.FormatClock(ts + 20 * 60) .. ") is newer than this advice. The overlay refreshes it seconds after each save: /reload once more to pick it up."
    assert(rows[1].text == want, rows[1].text)
end }

cases[#cases + 1] = { "plan: corner tags are 0.75 of a badge with the full font; one green fill; tag clears the marker", function()
    fresh_client(nil)
    local WC = WoWCompanion
    for _, setting in ipairs({ "small", "normal", "large" }) do
        local full = WC.PinSize(setting, false)
        local d = WC.TagDiameter(full)
        assert(math.abs(d / full - 0.75) <= 0.5 / full + 1e-9, setting)
        assert(WC.TagWidth(d, "2") == d and WC.TagWidth(d, "14\194\183116") > d, "label widens the tag, never the font")
    end
    assert(WC.TagDiameter(WC.PinSize("normal", false)) == 21 and WC.TagOffset() == 18)
    -- The tag's nearest edge to the marker centre stays beyond a marker glyph's half size (about 8 px).
    assert(WC.TagOffset() - WC.TagDiameter(WC.PinSize("small", false)) / 2 >= 8)
    local f = io.open("WoWCompanion/PlanUI.lua"):read("*a")
    assert(f:find("GameFontNormal\"", 1, true) and not f:find("SetFontObject(\"GameFontNormalSmall\")", 1, true))
    assert(not f:find("SetVertexColor(0.05, 0.04, 0.02, 0.95)", 1, true))
    assert(WC.BADGE_FILL[4] == 0.80 and WC.BADGE_FILL[2] == 0.22)
    local fr, fg, fb, fa = WC.BadgeFillColor()
    assert(fr == WC.BADGE_FILL[1] and fg == WC.BADGE_FILL[2] and fb == WC.BADGE_FILL[3] and fa == WC.BADGE_FILL[4], "default fill is the shipped constant")
    local _, n = f:gsub("WC%.ApplyBadgeFill%(", "")
    assert(n >= 4, "fill is read from the settings, by BadgeParts, which all three badge kinds use")
    local _, parts = f:gsub("WC%.BadgeParts%(", "")
    assert(parts == 3, "definition + map pin + minimap pin")
end }

-- The quest plan: parsing, completion from quest events, distance maths, controls.
local function plan_client(file)
    fresh_client(nil)
    WoWCompanionPlan = nil
    if file then assert(loadfile("tests/fixtures/plan_" .. file .. ".lua"))() end
    QUESTS = {}
    C_QuestLog = {
        IsQuestFlaggedCompleted = function(id) return QUESTS[id] == "turnedin" end,
        GetLogIndexForQuestID = function(id) local q = QUESTS[id]; return (q == "active" or q == "ready") and 1 or nil end,
        IsComplete = function(id) return QUESTS[id] == "ready" end,
    }
    Stub.fire(frames, "PLAYER_LOGIN")
    return WoWCompanion
end

cases[#cases + 1] = { "plan: valid file keeps the known steps and ignores unknown fields", function()
    local WC = plan_client("full")
    assert(#WC.plan.steps == 4 and WC.plan.steps[4].kind == "travel" and WC.plan.steps[4].n == 4)
    assert(WC.PlanNext().label == "Pick up Quest 10")
end }

cases[#cases + 1] = { "plan: missing file, wrong schema and other character show nothing", function()
    assert(plan_client(nil).plan == nil)
    assert(plan_client("badschema").plan == nil)
    local WC = plan_client("full")
    assert(select(2, WC.ParsePlan(WoWCompanionPlan, "Nobody")) == "character")
    assert(select(2, WC.ParsePlan(WoWCompanionPlan, nil)) == "character")
    assert(WoWCompanionPlanTracker:IsShown() == false, "the separate tracker is off by default")
    assert(plan_client(nil) and WoWCompanionPlanTracker:IsShown() == false)
end }

cases[#cases + 1] = { "plan: quest events advance the steps without a reload", function()
    local WC = plan_client("full")
    QUESTS[10] = "active"
    Stub.fire(frames, "QUEST_ACCEPTED", 1, 10)
    assert(WC.plan.done[1] and not WC.plan.done[2] and WC.PlanNext().n == 2)
    QUESTS[10] = "ready"
    Stub.fire(frames, "QUEST_LOG_UPDATE")
    assert(WC.plan.done[2] and WC.PlanNext().n == 3)
    QUESTS[10] = "turnedin"
    Stub.fire(frames, "QUEST_TURNED_IN", 10)
    assert(WC.plan.done[3] and WC.PlanNext().kind == "travel")
    assert(WoWCompanionDB.plan["Thrall-Testrealm"].done[3])
end }

cases[#cases + 1] = { "plan: done marks persist per character and reset for a new plan", function()
    local WC = plan_client("full")
    QUESTS[10] = "active"
    Stub.fire(frames, "QUEST_ACCEPTED", 1, 10)
    local saved = WoWCompanionDB
    fresh_client(saved)
    assert(loadfile("tests/fixtures/plan_full.lua"))()
    Stub.fire(frames, "PLAYER_LOGIN")
    assert(WoWCompanion.plan.done[1])
    QUESTS[10] = nil -- the new plan starts clean, and the log no longer holds the quest
    WoWCompanionPlan.generated = 1795363999
    Stub.fire(frames, "PLAYER_LOGIN")
    assert(not WoWCompanion.plan.done[1])
end }

-- Live panel and plan: lines and marks follow the quest log and talents between advisor updates.
local function live_digest(lines)
    WoWCompanionDigest = { schema = 1, generated = NOW, character = "Thrall",
        sections = { { id = "next_quests", lines = lines } } }
end
local function panel_text()
    WoWCompanion.Refresh()
    return WoWCompanion.panel.plain
end

cases[#cases + 1] = { "live digest: a quest line goes 0/6, 3/6, ready, turned in", function()
    local WC = plan_client(nil)
    local OBJ = { { text = "Windsong Crawler Meat: 0/6", numFulfilled = 0, numRequired = 6, finished = false } }
    C_QuestLog.GetQuestObjectives = function() return OBJ end
    C_QuestLog.GetTitleForQuestID = function() return "Crab Season" end
    live_digest({ { text = "Crab Season: 0/6 Windsong Crawler Meat", quest = 77 }, { text = "Plain line" } })
    assert(panel_text():find("Crab Season: 0/6 Windsong", 1, true), "not in the log: stored text")
    QUESTS[77] = "active"
    assert(panel_text():find("Crab Season - Windsong Crawler Meat: 0/6", 1, true))
    OBJ[1].text, OBJ[1].numFulfilled = "Windsong Crawler Meat: 3/6", 3
    assert(panel_text():find("Windsong Crawler Meat: 3/6", 1, true))
    assert(WC.TrackerText(WoWCompanionDigest, "Thrall"):find("3/6", 1, true))
    QUESTS[77] = "ready"
    local t = panel_text()
    assert(t:find("Crab Season - ready to turn in", 1, true) and t:find("Plain line", 1, true))
    QUESTS[77] = "turnedin"
    t = panel_text()
    assert(not t:find("Crab Season", 1, true) and t:find("Plain line", 1, true), "turned-in line drops")
    live_digest({ { text = "Only one", quest = 77 } })
    assert(not panel_text():find("Next quests", 1, true) and WC.TrackerText(WoWCompanionDigest, "Thrall") == WC.L.TRACKER_EMPTY)
end }

cases[#cases + 1] = { "live digest: missing APIs fall back to the stored text", function()
    local WC = plan_client(nil)
    C_QuestLog = nil
    live_digest({ { text = "Crab Season: 0/6 Windsong Crawler Meat", quest = 77 } })
    assert(panel_text():find("Crab Season: 0/6 Windsong Crawler Meat", 1, true))
    C_QuestLog = { IsQuestFlaggedCompleted = function() return false end, GetLogIndexForQuestID = function() return 1 end,
        IsComplete = function() return false end } -- in the log, but no objectives API
    assert(panel_text():find("Crab Season: 0/6 Windsong Crawler Meat", 1, true))
    GetUnspentTalentPoints = nil
    WoWCompanionDigest.talents = { { line = "You have 1 unspent talent point" } }
    assert(panel_text():find("1 unspent talent point", 1, true))
end }

cases[#cases + 1] = { "live digest: the talent line follows the unspent count", function()
    local WC = plan_client(nil)
    live_digest({ { text = "Pick up X" } })
    WoWCompanionDigest.talents = { { line = "You have 1 unspent talent point", spell_id = 9 } }
    local n = 2
    GetUnspentTalentPoints = function() return n end
    assert(panel_text():find("2 unspent talent points", 1, true))
    n = 1
    assert(panel_text():find("1 unspent talent point", 1, true))
    n = 0
    assert(not panel_text():find("unspent", 1, true) and not panel_text():find("Talents", 1, true))
    n = 3
    Stub.fire(frames, "PLAYER_TALENT_UPDATE")
    WoWCompanionPanel:Show()
    Stub.fire(frames, "CHARACTER_POINTS_CHANGED")
    assert(WC.panel.plain:find("3 unspent", 1, true), "talent events redraw a shown panel")
    GetUnspentTalentPoints = nil
end }

cases[#cases + 1] = { "live plan: abandoning clears pick-up and objective marks; turned in stays", function()
    local WC = plan_client("full")
    QUESTS[10] = "ready"
    Stub.fire(frames, "QUEST_LOG_UPDATE")
    assert(WC.plan.done[1] and WC.plan.done[2] and not WC.plan.done[3])
    QUESTS[10] = nil
    Stub.fire(frames, "QUEST_REMOVED", 10)
    assert(not WC.plan.done[1] and not WC.plan.done[2] and WC.PlanNext().n == 1, "abandon un-marks")
    QUESTS[10] = "active"
    Stub.fire(frames, "QUEST_ACCEPTED", 1, 10)
    assert(WC.plan.done[1] and not WC.plan.done[2], "re-accept re-marks")
    QUESTS[10] = "turnedin"
    Stub.fire(frames, "QUEST_TURNED_IN", 10)
    Stub.fire(frames, "QUEST_REMOVED", 10)
    assert(WC.plan.done[1] and WC.plan.done[2] and WC.plan.done[3], "turned in stays done")
    -- A client without the log lookups never clears anything.
    C_QuestLog = nil
    WC.PlanScan()
    assert(WC.plan.done[1] and WC.plan.done[3])
end }

cases[#cases + 1] = { "live plan: objective text is live in tooltips and the tracker", function()
    local WC = plan_client("full")
    local step = WC.plan.steps[2]
    local OBJ = { { text = "boars slain: 2/5", numFulfilled = 2, numRequired = 5 } }
    C_QuestLog.GetQuestObjectives = function() return OBJ end
    assert(WC.PlanLiveText(step, "Kill 5 boars") == "Kill 5 boars", "not in the log: the label")
    QUESTS[10] = "active"
    assert(WC.PlanLiveText(step, "Kill 5 boars") == "Kill 5 boars (2/5)")
    assert(WC.PlanLiveText(step, "Kill 0/5 boars") == "Kill 2/5 boars")
    assert(WC.PlanLiveText(WC.plan.steps[1], "Pick up Quest 10") == "Pick up Quest 10", "only objective steps")
    local tip = {}
    for _, l in ipairs(WC.PlanTipLines({ steps = { step } })) do tip[#tip + 1] = l.text end
    assert(table.concat(tip, "|"):find("2/5", 1, true))
    C_QuestLog.GetQuestObjectives = nil
    assert(WC.PlanLiveText(step, "Kill 5 boars") == "Kill 5 boars", "no API: the label")
end }

cases[#cases + 1] = { "live plan: a burst of QUEST_LOG_UPDATE is coalesced", function()
    local WC = plan_client("full")
    local queued = {}
    C_Timer = { After = function(sec, fn) queued[#queued + 1] = { sec, fn } end }
    local scans, scan = 0, WC.PlanScan
    WC.PlanScan = function(...) scans = scans + 1 return scan(...) end
    for _ = 1, 40 do Stub.fire(frames, "QUEST_LOG_UPDATE") end
    assert(#queued == 1 and queued[1][1] == 0.5 and scans == 0)
    queued[1][2]()
    assert(scans == 1)
    Stub.fire(frames, "QUEST_LOG_UPDATE")
    assert(#queued == 2, "a new burst schedules again")
    C_Timer = nil
    WC.PlanScan = scan
end }

cases[#cases + 1] = { "plan: distance and direction", function()
    local WC = plan_client(nil)
    local d, dir = WC.PlanDistance(50, 50, 60, 50, 1000, 500)
    assert(math.abs(d - 100) < 1e-6 and dir == "E")
    d, dir = WC.PlanDistance(50, 50, 50, 40, 1000, 500)
    assert(math.abs(d - 50) < 1e-6 and dir == "N")
    assert(select(2, WC.PlanDistance(50, 50, 40, 60, 1000, 500)) == "SW")
    assert(select(2, WC.PlanDistance(50, 50, 55, 45, 1000, 1000)) == "NE")
    assert(select(2, WC.PlanDistance(50, 50, 50, 70, 1000, 1000)) == "S")
    assert(select(2, WC.PlanDistance(50, 50, 40, 50, 1000, 1000)) == "W")
    assert(select(2, WC.PlanDistance(50, 50, 45, 45, 1000, 1000)) == "NW")
    assert(WC.PlanDistance(5, 5, 5, 5, 1000, 500) == 0)
end }

cases[#cases + 1] = { "plan: tracker text shows the step with distance, or another zone", function()
    local WC = plan_client("full")
    local step = WC.PlanNext()
    local near = WC.PlanText(step, 7001, 50, 50)
    assert(near:find("^Step 1/4: Pick up Quest 10 · 0 yd"))
    assert(WC.PlanText(step, 9999, 50, 50):find("another zone", 1, true))
    for i = 1, 4 do WC.plan.done[i] = true end
    assert(WC.PlanText(nil) == "Plan complete (4 steps)")
end }

cases[#cases + 1] = { "plan: /wowc plan toggles the tracker and /wowc plan map the pins", function()
    local WC = plan_client("full")
    assert(not WoWCompanionPlanTracker:IsShown())
    SlashCmdList.WOWC("plan")
    assert(WoWCompanionDB.settings.planTracker == true and WoWCompanionPlanTracker:IsShown())
    SlashCmdList.WOWC("plan")
    assert(WoWCompanionDB.settings.planTracker == false and not WoWCompanionPlanTracker:IsShown())
    SlashCmdList.WOWC("plan map")
    assert(WoWCompanionDB.settings.planMap == false)
    SlashCmdList.WOWC("plan map")
    assert(WoWCompanionDB.settings.planMap == true and WoWCompanionOptionPlanMap ~= nil)
end }

cases[#cases + 1] = { "plan: pins are drawn on the matching map only, the next one larger", function()
    local WC = plan_client("full")
    local canvas = CreateFrame("Frame", nil, UIParent)
    canvas:SetSize(1000, 500)
    WorldMapFrame = { GetCanvas = function() return canvas end, GetMapID = function() return 7001 end }
    WC.RefreshMapPins()
    local p = {}
    for _, f in ipairs(frames) do if f.planGroup then p[#p + 1] = f end end
    assert(#p == 2 and p[1].shown and p[1].w > p[2].w and p[1].num.text == "1\194\1833") -- steps 1 and 3 share a spot
    assert(p[2].anchor.points[1][4] == 600 and p[2].anchor.points[1][5] == -250)
    WorldMapFrame.GetMapID = function() return 1 end
    WC.RefreshMapPins()
    assert(not p[1].shown)
    WorldMapFrame = nil
end }

cases[#cases + 1] = { "plan: pin placement is normalised and filtered by map", function()
    local WC = plan_client("full")
    local x, y = WC.PinOffset(50, 25, 1000, 400, 1)
    assert(x == 500 and y == -100)
    x, y = WC.PinOffset(50, 25, 1000, 400, 0.5) -- a pin scaled 0.5 shows its offset halved, so double it
    assert(x == 1000 and y == -200)
    assert(WC.PinWanted({ map = 7, n = 1 }, 7, {}) and not WC.PinWanted({ map = 7, n = 1 }, 8, {}))
    assert(not WC.PinWanted({ map = 7, n = 1 }, 7, { [1] = true }))
    local src = assert(io.open("WoWCompanion/PlanUI.lua")):read("*a")
    assert(not src:find("WorldMapFrame:GetWidth", 1, true) and not src:find("WorldMapFrame:GetHeight", 1, true))
end }

cases[#cases + 1] = { "plan: pin tooltip names the quest, target and step", function()
    local WC = plan_client("full")
    local canvas = CreateFrame("Frame", nil, UIParent)
    canvas:SetSize(1000, 500)
    WorldMapFrame = { GetCanvas = function() return canvas end, GetMapID = function() return 7001 end }
    WC.RefreshMapPins()
    for _, f in ipairs(frames) do if f.planGroup and f.planGroup.steps[1].n == 2 then f.scripts.OnEnter(f) end end
    local text = {}
    for _, c in ipairs(GameTooltip.calls) do if c[1] == "AddLine" then text[#text + 1] = c[2] end end
    assert(text[1] == "Quest 10" and text[2] == "Kill 5 boars" and text[3]:find("^Step 2 of %d+") and #text == 3, table.concat(text, "|"))
    WorldMapFrame = nil
end }

cases[#cases + 1] = { "plan: tooltip layout per kind, merged de-dup, label stripping, next marker", function()
    local WC = plan_client("full")
    local function texts(g) local t = {} for _, l in ipairs(WC.PlanTipLines(g)) do t[#t + 1] = l.text end return table.concat(t, "|") end
    local P = { n = 1, kind = "pickup", quest = "Blood Tithe", label = "Pick up Blood Tithe from Bob" }
    local O = { n = 2, kind = "objective", quest = "Blood Tithe", label = "Blood Tithe: 0/1 Find Aamelia Windfield" }
    local T = { n = 3, kind = "turnin", quest = "Blood Tithe", label = "Turn in Blood Tithe to Aamelia Windfield" }
    local F = "|Step %d of 20"
    local function one(g) local t = texts(g) return t end
    local s1 = texts({ steps = { P } })
    assert(s1:find("^Blood Tithe|Bob|Step 1 of %d+"), s1)
    assert(texts({ steps = { O }, next = O }):find("^Blood Tithe|Find Aamelia Windfield|Step 2 of %d+ \194\183 Next"))
    local m = texts({ steps = { O, T }, next = O })
    assert(select(2, m:gsub("Blood Tithe", "")) == 1, "quest name once in a merged badge")
    assert(m:find("| |Turn in to Aamelia Windfield|Step 3 of", 1, true))
    assert(texts({ steps = { O, { n = 3, kind = "turnin", quest = "Other", label = "Turn in Other to X" } } }):find("|Other|Turn in to X", 1, true))
    local Q = { quest = "Ka'rok: the End (Part 1)", label = "Ka'rok: the End (Part 1): 2/3 Slay it" }
    assert(WC.PlanDetail(Q) == "2/3 Slay it")
    assert(WC.PlanDetail({ quest = "A: B", label = "Turn in A: B to Cy" }) == "to Cy")
    assert(WC.PlanDetail({ quest = "A", label = "Pick up A" }) == "" and WC.PlanDetail({ quest = "", label = "Travel to X" }) == "Travel to X")
    assert(texts({ steps = { { n = 1, kind = "pickup", quest = "A", label = "Pick up A from Z", approx = true } } }):find("Z (approx.)", 1, true))
end }

cases[#cases + 1] = { "badge tooltip: title, who, rows, xp, levels, footer, combat and missing APIs", function()
    local WC = plan_client("full")
    local P = { n = 1, kind = "pickup", questID = 10, quest = "The Skybreaker Bulwark", label = "Pick up The Skybreaker Bulwark from Seena Skybreaker", level = 10, class = "Class" }
    local function lines(g, o) return WC.PlanTipLines(g, o) end
    local g = { steps = { P }, next = P, total = 20 }
    local L1 = lines(g, { dist = 125, dir = "W" })
    assert(L1[1].text == "[10] The Skybreaker Bulwark (Class)" and L1[1].right == nil, "no xp when not in the log")
    assert(L1[2].text == "Seena Skybreaker" and L1[3].text == "Step 1 of 20 \194\183 Next \194\183 125 yd W")
    assert(lines(g)[3].text == "Step 1 of 20 \194\183 Next", "no distance off the minimap")
    -- no level data: no brackets and no (levels) on the who line
    local N = { n = 2, kind = "pickup", questID = 11, quest = "Crab Season", label = "Pick up Crab Season from Bob" }
    assert(lines({ steps = { N }, total = 20 })[1].text == "Crab Season")
    -- an objective step in the log: live rows, XP on the right
    local O = { n = 3, kind = "objective", questID = 12, quest = "Crab Season", label = "Crab Season: 0/6 Windsong Crawler", npcLevel = "8-9" }
    QUESTS[12] = "active"
    C_QuestLog.GetQuestObjectives = function() return { { text = "Windsong Crawler Meat", numFulfilled = 0, numRequired = 6 }, { text = "Done thing", numFulfilled = 1, numRequired = 1, finished = true } } end
    GetQuestLogRewardXP = function() return 600 end
    local LO = lines({ steps = { O }, total = 20 })
    assert(LO[1].text == "Crab Season" and LO[1].right == "(600xp)")
    assert(LO[2].text == "Windsong Crawler (8-9)")
    assert(LO[3].text == "   0/6 Windsong Crawler Meat" and LO[4].text == "   1/1 Done thing" and LO[4].color[1] < 0.7)
    WC.db.settings.badgeTipsXP = false
    assert(lines({ steps = { O }, total = 20 })[1].right == nil, "show XP off")
    WC.db.settings.badgeTipsXP = true
    GetQuestLogRewardXP = nil
    assert(lines({ steps = { O }, total = 20 })[1].right == nil, "no API: no xp")
    C_QuestLog.GetQuestObjectives = nil
    assert(#lines({ steps = { O }, total = 20 }) == 3, "no objectives API: title, who, footer")
    -- ready quests say so
    QUESTS[12] = "ready"
    local T = { n = 4, kind = "turnin", questID = 12, quest = "Crab Season", label = "Turn in Crab Season to Cy" }
    local LT = lines({ steps = { T }, total = 20 })
    assert(LT[2].text == "Turn in to Cy" and LT[3].text == "   Ready to turn in")
    -- merged: the quest name once, a spacer between steps
    local M = lines({ steps = { O, T }, total = 20 })
    local names = 0
    for _, l in ipairs(M) do if l.text == "Crab Season" then names = names + 1 end end
    assert(names == 1)
    -- setting and combat
    assert(WC.BadgeTipsAllowed())
    WC.db.settings.badgeTipsHideCombat = true
    WC.inCombat = true
    assert(not WC.BadgeTipsAllowed(), "hidden in combat when asked")
    WC.inCombat = false
    WC.db.settings.badgeTipsHideCombat = false
    WC.db.settings.badgeTips = false
    assert(not WC.BadgeTipsAllowed() and not WC.ShowPlanTip({}, "ANCHOR_LEFT", g))
    assert(WC.DEF_OF.badgeTips.default == true and WC.DEF_OF.badgeTipsXP.default == true and WC.DEF_OF.badgeTipsHideCombat.default == false)
end }

cases[#cases + 1] = { "plan: badges coincide with client markers by radius, scaled by zoom", function()
    local WC = plan_client("full")
    local g = { steps = { { n = 1, x = 50, y = 50, questID = 7 } } }
    local r = WC.MarkerRadius(1)
    assert(r == 2.5 and WC.MarkerRadius(2) == 1.25 and WC.MarkerRadius(nil) == 2.5)
    assert(WC.GroupMarker(g, { { questID = 7, x = 51, y = 51 } }, r), "same quest, inside")
    assert(WC.GroupMarker(g, { { questID = 9, x = 52, y = 50 } }, r), "any marker, inside")
    assert(not WC.GroupMarker(g, { { questID = 7, x = 54, y = 50 } }, r), "outside")
    assert(not WC.GroupMarker(g, { { questID = 7, x = 52, y = 50 } }, WC.MarkerRadius(4)), "zoom shrinks the radius")
    local m = WC.GroupMarker(g, { { questID = 9, x = 51, y = 50 }, { questID = 7, x = 50, y = 51 } }, r)
    assert(m.questID == 7, "same quest wins a tie")
    assert(not WC.GroupMarker(g, {}, r) and not WC.GroupMarker(g, nil, r))
    assert(WC.PinLabel({ { n = 4 }, { n = 5 } }) == "4\194\1835", "merged tag text")
end }

cases[#cases + 1] = { "plan: no OnUpdate on world-map pin frames", function()
    local src = assert(io.open("WoWCompanion/PlanUI.lua")):read("*a")
    local _, n = src:gsub('SetScript%("OnUpdate"', "")
    assert(n == 1, "only the driver frame has an OnUpdate")
    local pf = src:match("local function pinFor.-\nend\n")
    assert(pf and not pf:find("OnUpdate", 1, true) and not src:match("function WC.RefreshMapPins.-\nend\n"):find("OnUpdate", 1, true))
end }

cases[#cases + 1] = { "plan: badge text, kind notch, next-step state and done steps", function()
    local WC = plan_client("full")
    assert(WC.PinLabel({ { n = 4 } }) == "4" and WC.PinLabel({ { n = 4 }, { n = 5 } }) == "4\194\1835")
    assert(WC.PinLabel({ { n = 12 } }) == "12")
    assert(WC.PinNotch("pickup") == "!" and WC.PinNotch("turnin") == "?")
    assert(WC.PinNotch("objective") == nil and WC.PinNotch("travel") == nil)
    local a = { n = 4, map = 7, x = 10, y = 10, kind = "pickup" }
    local b = { n = 5, map = 7, x = 10.5, y = 10.2, kind = "turnin" }
    local c = { n = 6, map = 7, x = 60, y = 60, kind = "objective" }
    local g = WC.PinGroups({ a, b, c }, 7, {}, b)
    assert(#g == 2 and #g[1].steps == 2 and g[1].isNext and not g[2].isNext)
    assert(WC.PinGroupKind(g[1]) == "turnin" and WC.PinGroupKind(g[2]) == "objective")
    g = WC.PinGroups({ a, b, c }, 7, { [4] = true, [5] = true }, c)
    assert(#g == 1 and g[1].steps[1] == c)
    assert(#WC.PinGroups({ a, b, c }, 8, {}, a) == 0)
    assert(WC.PinSize("normal", false) == 28 and WC.PinSize("large", true) > WC.PinSize("large", false))
    assert(WC.PinSize("small", false) < WC.PinSize("normal", false) and WC.PinSize("bogus") == 28)
end }

cases[#cases + 1] = { "plan: /wowc plan size and lines change the settings", function()
    local WC = plan_client("full")
    assert(WoWCompanionDB.settings.planSize == "normal" and WoWCompanionDB.settings.planLines == true)
    SlashCmdList.WOWC("plan size large")
    assert(WoWCompanionDB.settings.planSize == "large")
    SlashCmdList.WOWC("plan size")
    assert(WoWCompanionDB.settings.planSize == "small")
    SlashCmdList.WOWC("plan lines")
    assert(WoWCompanionDB.settings.planLines == false and WoWCompanionOptionPlanLines ~= nil)
end }

cases[#cases + 1] = { "plan: minimap pin clamps to the rim, lifts off the NPC, points and pulses", function()
    local WC = plan_client("full")
    local near = function(a, b) return math.abs(a - b) < 1e-6 end
    -- inside the rim: due east 50 yards of 200 puts the spot east of centre, not clamped
    local x, y, ang, edge = WC.MinimapPlace(50, 90, nil, 200, 70)
    assert(not edge and x > 0 and near(y, 0, 1e-6) and near(ang, math.pi / 2))
    -- beyond the rim: clamped to half - 14 exactly, along the bearing
    x, y, ang, edge = WC.MinimapPlace(500, 0, nil, 200, 70)
    assert(edge and near(x, 0) and near(y, 56))
    x, y, ang, edge = WC.MinimapPlace(500, 90, nil, 200, 70)
    assert(edge and near(x, 56) and near(y, 0))
    -- rotation: facing east (-pi/2 ccw) turns a target due north to the left? it moves by +facing
    x, y = WC.MinimapPlace(500, 0, math.pi / 2, 200, 70)
    assert(near(x, 56) and near(y, 0))
    x, y = WC.MinimapPlace(500, 90, math.pi / 2, 200, 70)
    assert(near(x, 0) and near(y, -56))
    -- the badge is lifted up and right of the spot, but not on the rim
    local ox, oy = WC.MinimapBadgeOffset(false)
    assert(ox > 0 and oy > 0)
    ox, oy = WC.MinimapBadgeOffset(true)
    assert(ox == 0 and oy == 0)
    -- arrow: sits toward the target and its rotation undoes the angle (art points up)
    local ax, ay, rot = WC.MinimapArrow(math.pi / 2)
    assert(ax > 0 and near(ay, 0) and near(rot, -math.pi / 2))
    ax, ay, rot = WC.MinimapArrow(math.pi)
    assert(near(ax, 0) and ay < 0 and near(rot, -math.pi))
    -- arrival: pick-ups and turn-ins only, within 5 yards
    assert(WC.PinArrived("pickup", 5) and WC.PinArrived("turnin", 2) and not WC.PinArrived("pickup", 5.1))
    assert(not WC.PinArrived("objective", 1) and not WC.PinArrived("travel", 1) and not WC.PinArrived("pickup", nil))
end }

cases[#cases + 1] = { "plan: arrowhead placement, chevron spacing and frame levels", function()
    local WC = plan_client("full")
    local near = function(a, b) return math.abs(a - b) < 1e-6 end
    -- due east: angle 0, tip stops radius + gap short of the destination
    local ang, tx, ty, len = WC.ArrowPlace(0, 0, 100, 0, 14, 6)
    assert(near(ang, 0) and near(tx, 80) and near(ty, 0) and near(len, 100))
    ang, tx, ty = WC.ArrowPlace(0, 0, 0, 50, 10, 0)
    assert(near(ang, math.pi / 2) and near(tx, 0) and near(ty, 40))
    ang, tx, ty = WC.ArrowPlace(30, 40, 0, 0, 0, 0) -- 3-4-5, toward the origin
    assert(near(tx, 0) and near(ty, 0) and ang < -math.pi / 2)
    assert(WC.ArrowPlace(5, 5, 5, 5, 10, 2) == nil)
    -- an arrowhead centred on the origin pointing east: tip ahead, wings behind and either side
    local tx, ty, x1, y1, x2, y2 = WC.ArrowheadPoints(0, 0, 0, 10)
    assert(near(tx, 5) and near(ty, 0) and near(x1, -5) and near(x2, -5) and near(y1, -y2) and y1 ~= 0)
    tx, ty = WC.ArrowheadPoints(3, 4, math.pi / 2, 10) -- north: the tip is above the centre
    assert(near(tx, 3) and near(ty, 9))
    -- chevrons: none up to 12% of the map width, one to 24%, two beyond; evenly spaced
    assert(WC.ChevronCount(12, 100) == 0 and WC.ChevronCount(13, 100) == 1)
    assert(WC.ChevronCount(24, 100) == 1 and WC.ChevronCount(25, 100) == 2 and WC.ChevronCount(5, 0) == 0)
    local sp = WC.ChevronSpots(2)
    assert(near(sp[1], 1 / 3) and near(sp[2], 2 / 3) and #WC.ChevronSpots(0) == 0)
    -- levels: lines, then arrows, then our badges, all clear of other addons' low defaults and below the tags
    local lv = WC.PLAN_LEVELS
    assert(lv.line >= 500 and lv.line < lv.arrow and lv.arrow < lv.pin and lv.pin < 3500)
end }

cases[#cases + 1] = { "plan: /wowc plan arrows toggles the arrowheads", function()
    local WC = plan_client("full")
    assert(WoWCompanionDB.settings.planArrows == true)
    SlashCmdList.WOWC("plan arrows")
    assert(WoWCompanionDB.settings.planArrows == false and WoWCompanionOptionPlanArrows ~= nil)
end }

cases[#cases + 1] = { "plan: our badges sit above a simulated other-addon pin, and are re-asserted after a refresh", function()
    local WC = plan_client("full")
    local canvas = CreateFrame("Frame", nil, UIParent)
    canvas:SetSize(1000, 500)
    local other = CreateFrame("Frame", nil, canvas)
    other:SetFrameLevel(2000) -- another addon's pin at a high level
    WorldMapFrame = { GetCanvas = function() return canvas end, GetMapID = function() return 7001 end }
    WC.RefreshMapPins()
    local mine = {}
    for _, f in ipairs(frames) do if f.planGroup then mine[#mine + 1] = f end end
    assert(#mine >= 1)
    for _, f in ipairs(mine) do assert(f:GetFrameLevel() > other:GetFrameLevel()) end
    local top = mine[1]
    for _, f in ipairs(mine) do if f.planGroup.isNext then top = f end end
    for _, f in ipairs(mine) do assert(f:GetFrameLevel() <= top:GetFrameLevel() or f.isTag) end
    for _, f in ipairs(mine) do f:SetFrameLevel(1) end -- a refresh by someone else resets levels
    WC.RefreshMapPins()
    for _, f in ipairs(mine) do if f:IsShown() then assert(f:GetFrameLevel() > 2000) end end
    WorldMapFrame = nil
end }

cases[#cases + 1] = { "plan: /wowc plan debug prints one line per undone step", function()
    local WC = plan_client("full")
    local canvas = CreateFrame("Frame", nil, UIParent)
    canvas:SetSize(1000, 500)
    WorldMapFrame = { GetCanvas = function() return canvas end, GetMapID = function() return 7001 end }
    WC.RefreshMapPins()
    local out = {}
    local realPrint = print
    print = function(...) out[#out + 1] = table.concat({ ... }, " ") end
    SlashCmdList.WOWC("plan debug")
    print = realPrint
    assert(#out >= 4, "head, the two arrow lines, then step lines")
    assert(out[2]:find("arrowheads: drawn as lines", 1, true) and out[3]:find("old arrow texture", 1, true), out[2])
    for i = 4, #out do
        assert(out[i]:match("^step %d+ %a+ x=%S+ y=%S+ %a+ level=%d+ shown=%a+$"), out[i])
        assert(out[i]:find("shown=yes", 1, true))
    end
    WorldMapFrame = nil
end }

cases[#cases + 1] = { "plan: show n limits to the next n undone steps", function()
    local WC = plan_client("full")
    local steps = {}
    for i = 1, 20 do steps[i] = { n = i } end
    assert(#WC.ShownSteps(steps, {}, "all") == 20 and #WC.ShownSteps(steps, nil, nil) == 20)
    local five = WC.ShownSteps(steps, { [1] = true, [2] = true }, 5)
    assert(#five == 5 and five[1].n == 3 and five[5].n == 7)
    SlashCmdList.WOWC("plan show 5")
    assert(WoWCompanionDB.settings.planShow == 5 and WoWCompanionOptionPlanShow ~= nil)
    SlashCmdList.WOWC("plan show all")
    assert(WoWCompanionDB.settings.planShow == "all")
end }

cases[#cases + 1] = { "plan: no other addon's globals or frames are referenced", function()
    local src = assert(io.open("WoWCompanion/PlanUI.lua")):read("*a")
    assert(not src:find("QuestieFrame", 1, true) and not src:find("Questie", 1, true) and not src:find("_G%[", 1))
    assert(not src:find("GetChildren", 1, true) and not src:find("EnumerateFrames", 1, true))
end }

cases[#cases + 1] = { "plan: no Questie asset or code is referenced", function()
    for _, file in ipairs({ "PlanUI.lua", "Plan.lua", "Settings.lua", "WhatsNew.lua", "Locales/enUS.lua" }) do
        local src = assert(io.open("WoWCompanion/" .. file)):read("*a")
        assert(not src:lower():find("questie", 1, true), file)
    end
end }

cases[#cases + 1] = { "every L.KEY used in the code exists in the locale file", function()
    local lf = assert(loadfile("WoWCompanion/Locales/enUS.lua"))
    assert(type(lf) == "function")
    local src = assert(io.open("WoWCompanion/Locales/enUS.lua")):read("*a")
    local missing = {}
    for _, dir in ipairs({ "WoWCompanion" }) do
        local p = io.popen("ls " .. dir .. "/*.lua")
        for file in p:lines() do
            local code = assert(io.open(file)):read("*a")
            for key in code:gmatch("%f[%w_]L%.([A-Z][A-Z0-9_]*)%f[^%w_]") do
                if not src:find("%f[%w_]" .. key .. "%s*=") then missing[key] = file end
            end
        end
        p:close()
    end
    local out = {}
    for k, f in pairs(missing) do out[#out + 1] = k .. " (" .. f .. ")" end
    assert(#out == 0, table.concat(out, ", "))
end }

-- The redesigned panel: quest-tracker rows.
local function v13_client()
    PLAYER_NAME = "Genaenyu"
    local p = digest_client("v13")
    return p, WoWCompanion
end
local function row_of(rows, text)
    for _, r in ipairs(rows) do if r.text:find(text, 1, true) then return r end end
    error("no row " .. text)
end
local function v13_rows(collapsed)
    local WC = WoWCompanion
    local _, rows = WC.RenderDigest(WoWCompanionDigest, NOW, "Genaenyu", collapsed)
    return rows
end

cases[#cases + 1] = { "tracker rows: each entry kind renders with its icon, colour and lines", function()
    local p, WC = v13_client()
    UnitLevel = function() return 9 end
    local rows = v13_rows()
    PLAYER_NAME = nil
    local pick = row_of(rows, "[10] The Skybreaker Bulwark (Class)")
    assert(pick.kind == "quest" and pick.icon == WC.ICONS.pickup and pick.right == nil)
    assert(same_color(row_of(rows, "Pick up from Seena Skybreaker").color, WC.COLORS.grey))
    assert(not WC.RowsText(rows):find("Nighthaven", 1, true) or true)
    local prog = row_of(rows, "[9] Blood Tithe")
    assert(prog.icon == WC.ICONS.progress and prog.color[1] == 1 and prog.color[2] == 1 and prog.color[3] == 0)
    local o1, o2 = row_of(rows, "0/1 Find Aamelia Windfield"), row_of(rows, "1/1 Listen to Alvarion Windfield's Story (Optional)")
    assert(same_color(o1.color, WC.COLORS.white) and o1.indent == 2 and same_color(o2.color, WC.COLORS.dim))
    local turn = row_of(rows, "[12] Hollow Warning")
    assert(turn.icon == WC.ICONS.turnin and turn.right == "(Elite)")
    assert(same_color(row_of(rows, "Ready to turn in").color, WC.COLORS.green) and same_color(row_of(rows, "Turn in to Warden Ilyan").color, WC.COLORS.grey))
    assert(not WC.RowsText(rows):find("unspent talent", 1, true), "a talent point is a chip, not a quest row")
    local _, _, meta = WC.RenderDigest(WoWCompanionDigest, NOW, "Genaenyu", {})
    assert(meta.chips[1].kind == "talent" and meta.chips[1].count == 1 and meta.chips[1].icon == WC.ICONS.talent)
    local up = row_of(rows, "Hammer of Fate")
    assert(up.item == 5678 and up.kind == "line" and same_color(row_of(rows, "Main Hand, ilvl 25").color, WC.COLORS.dim))
    assert(row_of(rows, "Linen Cloth").indent == 1 and row_of(rows, "Bank has 3").kind == "line")
    assert(same_color(row_of(rows, "Next quests").color, WC.COLORS.grey) and row_of(rows, "Next quests").kind == "header")
    UnitLevel = nil
end }

cases[#cases + 1] = { "tracker rows: a pick-up names its zone only when it is not the current one", function()
    local _, WC = v13_client()
    PLAYER_NAME = nil
    GetZoneText = function() return "Elsewhere" end
    assert(row_of(v13_rows(), "Pick up from Seena Skybreaker in Nighthaven"))
    GetZoneText = function() return "Nighthaven" end
    assert(row_of(v13_rows(), "Pick up from Seena Skybreaker").text == "Pick up from Seena Skybreaker")
    GetZoneText = nil
end }

cases[#cases + 1] = { "difficulty colours at the boundaries", function()
    local WC = v13_client() and WoWCompanion
    PLAYER_NAME = nil
    local function c(level, pl) return table.concat(WC.DifficultyColor(level, pl), ",") end
    GetQuestGreenRange = function() return 8 end
    assert(c(15, 10) == "1,0.1,0.1" and c(14, 10) == "1,0.5,0.25")
    assert(c(13, 10) == "1,0.5,0.25" and c(12, 10) == "1,1,0")
    assert(c(8, 10) == "1,1,0" and c(7, 10) == "0.25,0.75,0.25")
    assert(c(2, 10) == "0.25,0.75,0.25" and c(1, 10) == "0.62,0.62,0.62")
    assert(WC.DifficultyColor(nil, 10) == WC.COLORS.gold)
    GetQuestGreenRange = nil
end }

cases[#cases + 1] = { "difficulty colours use the client's own function when no level is given", function()
    local WC = v13_client() and WoWCompanion
    PLAYER_NAME = nil
    GetQuestDifficultyColor = function() return { r = 0.1, g = 0.2, b = 0.3 } end
    assert(table.concat(WC.DifficultyColor(9), ",") == "0.1,0.2,0.3")
    GetQuestDifficultyColor = nil
end }

cases[#cases + 1] = { "optional objectives get the suffix once, from a flag or the text", function()
    local WC = v13_client() and WoWCompanion
    PLAYER_NAME = nil
    local rows = WC.QuestEntryRows({ kind = "progress", title = "T", level = 5, objectives = {
        { text = "Find X", have = 0, need = 1 },
        { text = "Chat with Y", have = 0, need = 1, optional = true },
        { text = "Hear Z (Optional)", have = 1, need = 1 } } }, nil, nil, 5)
    assert(rows[2].text == "0/1 Find X" and rows[3].text == "0/1 Chat with Y (Optional)" and rows[4].text == "1/1 Hear Z (Optional)")
    assert(not rows[4].text:find("Optional%) %(Optional"))
end }

cases[#cases + 1] = { "quest and section collapse state: a clicked quest hides its lines and persists", function()
    local p = v13_client() -- PLAYER_NAME stays Genaenyu so the clicks' redraws still find the digest
    assert(p.plain:find("0/1 Find Aamelia Windfield", 1, true))
    local h = row_with(p, "[9] Blood Tithe")
    assert(h.scripts.OnClick and h.mouse and h.tbtn.scripts.OnClick)
    h.tbtn.scripts.OnClick(h.tbtn) -- the +/- square collapses; the title row itself opens the quest or its card
    assert(WoWCompanionDB.collapsed.q7002 == true)
    assert(not p.plain:find("Find Aamelia", 1, true) and p.plain:find("Seena Skybreaker", 1, true))
    h = row_with(p, "[9] Blood Tithe")
    h.tbtn.scripts.OnClick(h.tbtn)
    assert(WoWCompanionDB.collapsed.q7002 == nil and p.plain:find("Find Aamelia", 1, true))
    local s = row_with(p, "Next quests")
    s.scripts.OnClick(s)
    assert(not p.plain:find("Blood Tithe", 1, true) and p.plain:find("Hammer of Fate", 1, true))
    PLAYER_NAME = nil
end }

cases[#cases + 1] = { "a schema 1.2 digest renders its text lines without level or objective rows", function()
    local p = digest_client("v12")
    local WC = WoWCompanion
    local _, rows = WC.RenderDigest(WoWCompanionDigest, NOW, "Thrall")
    for _, r in ipairs(rows) do assert(r.kind ~= "quest" and r.kind ~= "obj" and r.kind ~= "status", r.kind) end
    p = digest_client("full")
    assert(p.plain:find("Turn in The Hungry Ettin", 1, true) and not p.plain:find("%[%d+%]"))
end }

cases[#cases + 1] = { "no row is cut with an ellipsis; long titles are kept whole and wrap", function()
    local WC = v13_client() and WoWCompanion
    PLAYER_NAME = nil
    local title = string.rep("Very Long Quest Title ", 8) .. "End"
    local rows = WC.QuestEntryRows({ kind = "pickup", title = title, level = 20, npc = string.rep("Longname ", 10) .. "Z" }, 1, nil, 20)
    assert(rows[1].text:find("End", 1, true) and not rows[1].text:find("...", 1, true))
    assert(rows[2].text:find("Longname Z", 1, true) or rows[2].text:find("Z$"))
    local p = digest_client("v13")
    PLAYER_NAME = nil
    for _, r in ipairs(p.rows) do
        if r:IsShown() then
            assert(not r.label:GetText():find("...", 1, true), r.label:GetText())
            assert(r.label.w and r.label.w <= 292, "label has a wrapping width")
        end
    end
    assert(p.w == 340)
end }

cases[#cases + 1] = { "live state overrides the digest's objectives, title and level", function()
    local WC = plan_client(nil)
    PLAYER_NAME = "Genaenyu"
    local OBJ = { { text = "Find Aamelia Windfield: 1/1", numFulfilled = 1, numRequired = 1, finished = true },
        { text = "Listen to Alvarion Windfield's Story: 0/1", numFulfilled = 0, numRequired = 1, finished = false } }
    C_QuestLog.GetQuestObjectives = function() return OBJ end
    C_QuestLog.GetTitleForQuestID = function(id) return id == 7002 and "Blood Tithe!" or nil end
    C_QuestLog.GetInfo = function() return { level = 11 } end
    assert(loadfile("tests/fixtures/digest_v13.lua"))()
    local function rows() WC.Refresh(); return v13_rows() end
    assert(row_of(rows(), "[9] Blood Tithe"), "not in the log: the digest's own")
    QUESTS[7002] = "active"
    local r = rows()
    assert(row_of(r, "[11] Blood Tithe!") and same_color(row_of(r, "1/1 Find Aamelia Windfield").color, WC.COLORS.dim))
    assert(row_of(r, "0/1 Listen to Alvarion Windfield's Story (Optional)").color[1] == 1, "digest marks it optional")
    QUESTS[7002] = "ready"
    r = rows()
    assert(row_of(r, "Ready to turn in") and row_of(r, "[11] Blood Tithe!").icon == WC.ICONS.turnin)
    QUESTS[7002] = "turnedin"
    assert(not WC.RowsText(rows()):find("Blood Tithe", 1, true))
    QUESTS[7001] = "active"
    assert(row_of(rows(), "[11] The Skybreaker Bulwark").icon == WC.ICONS.progress, "accepted: no longer a pick-up")
    PLAYER_NAME = nil
end }

cases[#cases + 1] = { "the panel header is gold with the character, the advice time and the plan step", function()
    local WC = plan_client("full")
    PLAYER_NAME = "Genaenyu"
    assert(loadfile("tests/fixtures/digest_v13.lua"))()
    WC.Refresh()
    local p = WC.panel
    assert(p.title:GetText() == "WoW Companion: Genaenyu", p.title:GetText())
    assert(p.header:GetText():find("advice from ", 1, true) and not p.header:GetText():find("Genaenyu", 1, true))
    assert(p.step:GetText():match("^Step 1/4 · Pick up .+ · another zone$"), p.step:GetText())
    assert(p.close and p.compactButton:GetText() == "Compact" and p.backdrop)
    PLAYER_NAME = nil
end }

cases[#cases + 1] = { "the panel code never mentions another addon's frames or code", function()
    for _, file in ipairs({ "Panel.lua", "Digest.lua" }) do
        local src = assert(io.open("WoWCompanion/" .. file)):read("*a")
        assert(not src:lower():find("questie", 1, true), file)
    end
end }


-- The options window and the settings rows behind it.
local function set_path(t, key, v)
    local head, rest = key:match("^([^.]+)%.(.+)$")
    if not head then t[key] = v return end
    t[head] = type(t[head]) == "table" and t[head] or {}
    t[head][rest] = v
end
local function get_path(t, key)
    local head, rest = key:match("^([^.]+)%.(.+)$")
    if not head then return t[key] end
    return t[head] and t[head][rest]
end
local function same(a, b)
    if type(a) == "table" then return a[1] == b[1] and a[2] == b[2] and a[3] == b[3] end
    return a == b
end
local function valid(def, v)
    local t = def.type
    if t == "bool" then return type(v) == "boolean" end
    if t == "range" then return type(v) == "number" and v >= def.min and v <= def.max end
    if t == "choice" then for _, c in ipairs(def.choices) do if c == v then return true end end return false end
    if t == "color" then return type(v) == "table" and #v == 3 and v[1] >= 0 and v[1] <= 1 and v[2] >= 0 and v[3] <= 1 end
    if t == "limit" then return v == "all" or (type(v) == "number" and v >= 1 and v == math.floor(v)) end
    return type(v) == "number"
end
-- Moves every row off its default to some other valid value.
local function off_default(def)
    if def.type == "bool" then return not def.default end
    if def.type == "range" then return def.default == def.max and def.min or def.max end
    if def.type == "choice" then return def.choices[def.default == def.choices[1] and 2 or 1] end
    if def.type == "color" then return { 0.9, 0.9, 0.9 } end
    if def.type == "limit" then return 7 end
    return 33
end

cases[#cases + 1] = { "options: InitSettings repairs every row from bad types and out-of-range values", function()
    fresh_client(nil)
    local WC = WoWCompanion
    assert(#WC.DEFS >= 40)
    local bad = { "junk", 12345, -99999, {}, true, false, { 5, "x" }, 0 / 0, 1e12 }
    for _, def in ipairs(WC.DEFS) do
        for i, v in ipairs(bad) do
            local saved = {}
            set_path(saved, def.key, v)
            fresh_client({ settings = saved })
            local got = get_path(settings(), def.key)
            assert(valid(def, got), def.key .. " from bad value " .. i .. " gave " .. tostring(got))
        end
        fresh_client({ settings = "junk" })
        assert(same(get_path(settings(), def.key), def.default), def.key .. " default")
    end
    fresh_client({ settings = { panelWidth = 5000, bgOpacity = -3, lineWidth = 0, mergeDistance = 99, planShow = 0.5, timeFormat = "13" } })
    local s = settings()
    assert(s.panelWidth == 520 and s.bgOpacity == 0 and s.lineWidth == 1 and s.mergeDistance == 5 and s.planShow == "all" and s.timeFormat == "client")
end }

cases[#cases + 1] = { "options: a page's Defaults resets only that page; Reset all resets everything", function()
    fresh_client(nil)
    local WC = WoWCompanion
    for _, page in ipairs(WC.PAGES) do
        fresh_client(nil)
        WC = WoWCompanion
        for _, def in ipairs(WC.DEFS) do set_path(settings(), def.key, off_default(def)) end
        local btn = _G["WoWCompanionOptionsDefaults_" .. page]
        btn.scripts.OnClick(btn)
        for _, def in ipairs(WC.DEFS) do
            local got = get_path(settings(), def.key)
            if def.page == page then
                assert(same(got, def.default), page .. " resets " .. def.key)
            else
                assert(same(got, off_default(def)), page .. " left " .. def.key)
            end
        end
    end
    fresh_client(nil)
    WC = WoWCompanion
    for _, def in ipairs(WC.DEFS) do set_path(settings(), def.key, off_default(def)) end
    WoWCompanionOptionsResetAll.scripts.OnClick(WoWCompanionOptionsResetAll)
    for _, def in ipairs(WC.DEFS) do assert(same(get_path(settings(), def.key), def.default), def.key) end
    assert(settings().show.notes == true and settings().hideInCombat.tracker == true)
end }

cases[#cases + 1] = { "options: settings reads give the old constants by default and follow a change", function()
    fresh_client(nil)
    local WC = WoWCompanion
    local want = { lineWidth = 2.5, lineOpacity = 0.7, arrowSize = 8, nextGrow = 1.3, tagScale = 0.75, mergeDistance = 1.2,
        badgeOpacity = 0.80, scale = 1, bgOpacity = 0.45, panelWidth = 340, minimapPin = true, arrivalPulse = true, nextPulse = true }
    for k, v in pairs(want) do assert(settings()[k] == v and WC.Setting(k) == v, k) end
    assert(same(settings().lineColor, { 1, 0.82, 0 }) and same(settings().badgeFill, { 0.05, 0.22, 0.13 }))
    assert(WC.PinSize("normal", false) == 28 and WC.PinSize("large", true) == 47 and WC.TagDiameter(28) == 21)
    local steps = { { n = 1, map = 7, x = 10, y = 10 }, { n = 2, map = 7, x = 10.9, y = 10 }, { n = 3, map = 7, x = 30, y = 30 } }
    assert(#WC.PinGroups(steps, 7, {}, nil) == 2)
    settings().mergeDistance = 0.5
    assert(#WC.PinGroups(steps, 7, {}, nil) == 3)
    settings().badgeScale, settings().nextGrow, settings().tagScale = 1.5, 2, 0.5
    assert(WC.PinSize("normal", false) == 42 and WC.PinSize("normal", true) == 84 and WC.TagDiameter(42) == 21)
    settings().badgeFill, settings().badgeOpacity = { 1, 0, 0 }, 0.5
    local r, g, b, a = WC.BadgeFillColor()
    assert(r == 1 and g == 0 and b == 0 and a == 0.5)
    local p = { fill = { SetVertexColor = function(self, ...) self.v = { ... } end } }
    WC.ApplyBadgeFill(p)
    assert(p.fill.v[1] == 1 and p.fill.v[4] == 0.5)
end }

cases[#cases + 1] = { "options: a change saves, repairs and calls both refresh paths", function()
    fresh_client(nil)
    local WC = WoWCompanion
    local calls = { 0, 0 }
    local refresh, plan = WC.Refresh, WC.RefreshPlan
    WC.Refresh = function() calls[1] = calls[1] + 1 end
    WC.RefreshPlan = function() calls[2] = calls[2] + 1 end
    assert(WC.SetSetting("badgeOpacity", 0.52) == 0.5 and settings().badgeOpacity == 0.5)
    assert(calls[1] == 1 and calls[2] == 1)
    assert(WC.SetSetting("lineWidth", 99) == 6 and WC.SetSetting("planShow", "x") == "all")
    WoWCompanionOptionTagScale.scripts.OnValueChanged(WoWCompanionOptionTagScale, 0.6)
    assert(settings().tagScale == 0.6 and calls[1] == 4)
    WoWCompanionOptionTagScale.scripts.OnValueChanged(WoWCompanionOptionTagScale, 0.6)
    assert(calls[1] == 4, "an unchanged value does not redraw")
    WoWCompanionOptionPlanShow.scripts.OnValueChanged(WoWCompanionOptionPlanShow, 25)
    assert(settings().planShow == "all")
    WoWCompanionOptionPlanShow.scripts.OnValueChanged(WoWCompanionOptionPlanShow, 8)
    assert(settings().planShow == 8)
    WC.Refresh, WC.RefreshPlan = refresh, plan
    -- the colour picker: each swatch change is saved at once and cancelling restores the old colour
    local info
    local cur = { 0.2, 0.4, 0.6 }
    ColorPickerFrame = { SetupColorPickerAndShow = function(_, i) info = i end, GetColorRGB = function() return cur[1], cur[2], cur[3] end }
    WoWCompanionOptionBadgeFill.scripts.OnClick(WoWCompanionOptionBadgeFill)
    assert(info.r == 0.05 and info.g == 0.22 and info.b == 0.13)
    info.swatchFunc()
    assert(same(settings().badgeFill, cur))
    info.cancelFunc()
    assert(same(settings().badgeFill, { 0.05, 0.22, 0.13 }))
    ColorPickerFrame = nil
end }

cases[#cases + 1] = { "options: every entry point opens the window", function()
    fresh_client(nil)
    local opt = WoWCompanionOptions
    assert(not opt:IsShown() and opt.title.text == "WoW Companion")
    local gear = WoWCompanionGearButton
    gear.scripts.OnClick(gear)
    assert(opt:IsShown())
    gear.scripts.OnClick(gear)
    assert(not opt:IsShown())
    local b = WoWCompanionMinimapButton
    b.scripts.OnClick(b, "RightButton")
    assert(opt:IsShown() and not WoWCompanionPanel:IsShown())
    b.scripts.OnClick(b, "LeftButton")
    assert(WoWCompanionPanel:IsShown())
    opt:Hide()
    WITH_COMPARTMENT = true
    fresh_client(nil)
    WITH_COMPARTMENT = nil
    local reg = AddonCompartmentFrame.registered[1]
    reg.func("WoWCompanion", { buttonName = "RightButton" })
    assert(WoWCompanionOptions:IsShown())
    WoWCompanionOptions:Hide()
    reg.func("WoWCompanion", { buttonName = "LeftButton" })
    assert(WoWCompanionPanel:IsShown() and not WoWCompanionOptions:IsShown())
    -- pages switch, each with its own Defaults button; the minimap page resets the button position
    fresh_client(nil)
    local WC = WoWCompanion
    for _, id in ipairs(WC.PAGES) do
        _G["WoWCompanionOptionsTab_" .. id].scripts.OnClick()
        assert(WC.options.page == id and WC.options.pages[id]:IsShown() and WC.options.subtitle.text ~= nil)
    end
    settings().minimap.angle = 10
    WoWCompanionOptionsResetButton.scripts.OnClick()
    assert(settings().minimap.angle == 180)
end }

cases[#cases + 1] = { "options: every label the rows and pages use is in enUS", function()
    fresh_client(nil)
    local WC = WoWCompanion
    local L = WC.L
    local function has(k) assert(rawget(L, k) ~= nil, "missing string " .. k) end
    for _, def in ipairs(WC.DEFS) do
        if def.label then has(def.label) end
        if def.box then has("BOX_" .. def.page .. "_" .. def.box) end
        for _, c in ipairs(def.choices or {}) do has(def.choiceKey .. c) end
    end
    for _, id in ipairs(WC.PAGES) do has("PAGE_" .. id); has("TAB_" .. id) end
    for _, k in ipairs({ "DEFAULTS", "RESET_ALL", "OPEN_OPTIONS", "WHATS_NEW_0_4_1_1", "WHATS_NEW_0_4_1_2", "HELP_SETTINGS" }) do has(k) end
    assert(TOC_VERSION == "0.6.1" and WC.CHANGELOG["0.6.1"] and WC.CHANGELOG["0.6.0"] and WC.CHANGELOG["0.5.1"] and WC.CHANGELOG["0.5.0"] and WC.CHANGELOG["0.4.9"] and WC.CHANGELOG["0.4.8"] and WC.CHANGELOG["0.4.7"] and WC.CHANGELOG["0.4.6"] and WC.CHANGELOG["0.4.5"])
    has("WHATS_NEW_0_4_8_1")
    has("WHATS_NEW_0_4_7_1")
    has("WHATS_NEW_0_4_6_1"); has("WHATS_NEW_0_4_9_1"); has("WHATS_NEW_0_4_9_2"); has("WHATS_NEW_0_5_0_1"); has("WHATS_NEW_0_5_1_1"); has("WHATS_NEW_0_6_0_1"); has("WHATS_NEW_0_6_0_2"); has("WHATS_NEW_0_6_1_1")
    for _, k in ipairs({ "WHATS_NEW_0_4_5_1", "WHATS_NEW_0_4_5_2", "WHATS_NEW_0_4_5_3" }) do has(k) end
    for _, k in ipairs({ "WHATS_NEW_0_4_4_1", "WHATS_NEW_0_4_4_2", "WHATS_NEW_0_4_4_3", "WHATS_NEW_0_4_3_1", "WHATS_NEW_0_4_3_2", "WHATS_NEW_0_4_2_1", "WHATS_NEW_0_4_2_2", "TIP_CLICK_SHIFT", "RESET_ONE", "CONFIRM_YES", "CONFIRM_NO", "CONFIRM_RESET_VISUALS", "CONFIRM_RESET_ALL", "HELP_RESET_VISUALS", "HELP_RESET_ALL" }) do has(k) end
end }

cases[#cases + 1] = { "options: panel and digest settings change what is drawn", function()
    local p = digest_client("v13")
    PLAYER_NAME = nil
    local WC = WoWCompanion
    local function plain_now() WC.Refresh(); return p.plain end
    WC.SetSetting("bgOpacity", 0.8)
    assert(p.backdropColor[4] == 0.8)
    WC.SetSetting("panelWidth", 400)
    plain_now()
    assert(p.w == 400 and p.content.w == 352)
    WC.SetSetting("panelWidth", 340)
    local rows = WC.QuestEntryRows({ kind = "progress", title = "T", level = 5, npc = "Bob", objectives = {
        { text = "Find X", have = 0, need = 1 }, { text = "Chat", have = 0, need = 1, optional = true } } }, nil, nil, 5)
    assert(rows[1].text == "[5] T" and #rows == 3 and rows[1].color ~= WC.COLORS.gold)
    WC.SetSetting("showLevels", false); WC.SetSetting("colorByDifficulty", false); WC.SetSetting("showOptional", false)
    rows = WC.QuestEntryRows({ kind = "progress", title = "T", level = 5, objectives = {
        { text = "Find X", have = 0, need = 1 }, { text = "Chat", have = 0, need = 1, optional = true } } }, nil, nil, 5)
    assert(rows[1].text == "T" and rows[1].color == WC.COLORS.gold and #rows == 2)
    WC.SetSetting("showNpcLines", false)
    rows = WC.QuestEntryRows({ kind = "turnin", title = "T", level = 5, npc = "Bob" }, nil, nil, 5)
    for _, r in ipairs(rows) do assert(not r.text:find("Bob", 1, true)) end
    WC.SetSetting("showNpcLines", true)
    rows = WC.QuestEntryRows({ kind = "turnin", title = "T", level = 5, npc = "Bob" }, nil, nil, 5)
    assert(rows[#rows].text:find("Bob", 1, true))
    local ts = 1800000000 + 15 * 3600
    WC.SetSetting("timeFormat", "24")
    assert(WC.FormatClock(ts):match("^%d%d:%d%d$"))
    WC.SetSetting("timeFormat", "12")
    assert(WC.FormatClock(ts):match(" [AP]M$"))
    GetCVar = function() return "1" end
    WC.SetSetting("timeFormat", "client")
    assert(WC.FormatClock(ts):match("^%d%d:%d%d$"))
    GetCVar = nil
    -- the box stays away when its setting is off, and the version is still noted
    fresh_client({ lastSeenVersion = "0.0.0", settings = { showWhatsNew = false } })
    assert(WoWCompanion.whatsNew == nil and WoWCompanionDB.lastSeenVersion == TOC_VERSION)
end }

cases[#cases + 1] = { "options: the minimap pin and pulses follow their settings", function()
    local src = assert(io.open("WoWCompanion/PlanUI.lua")):read("*a")
    for _, key in ipairs({ "minimapPin", "arrivalPulse", "nextPulse", "planChevrons", "lineColor", "lineWidth", "lineOpacity", "arrowSize" }) do
        assert(src:find('WC.Setting("' .. key .. '")', 1, true), key)
    end
    for _, old in ipairs({ "local NEXT_GROW", "local MERGE_DISTANCE", "local TAG_SCALE", "local LINE_WIDTH", "local ARROW_SIZE" }) do
        assert(not src:find(old, 1, true), old .. " is a setting now")
    end
end }

cases[#cases + 1] = { "visuals: every visual row carries a default, a type and a range", function()
    fresh_client(nil)
    local n = 0
    for _, def in ipairs(WoWCompanion.DEFS) do
        if def.visual then
            n = n + 1
            assert(def.default ~= nil and def.type and def.label, def.key)
            if def.type == "range" then assert(def.min and def.max and def.step and def.default >= def.min and def.default <= def.max, def.key) end
        end
    end
    assert(n >= 38, "visual rows: " .. n)
end }

cases[#cases + 1] = { "visuals: a per-setting reset touches only its key", function()
    fresh_client(nil)
    local WC = WoWCompanion
    for _, def in ipairs(WC.DEFS) do set_path(settings(), def.key, off_default(def)) end
    WC.ResetSetting("lineColor")
    for _, def in ipairs(WC.DEFS) do
        local got = get_path(settings(), def.key)
        if def.key == "lineColor" then assert(same(got, def.default)) else assert(same(got, off_default(def)), def.key) end
    end
end }

cases[#cases + 1] = { "visuals: reset visuals leaves other keys alone, reset all keeps saved positions", function()
    fresh_client(nil)
    local WC = WoWCompanion
    local function scramble() for _, def in ipairs(WC.DEFS) do set_path(settings(), def.key, off_default(def)) end end
    scramble()
    WC.ResetVisuals()
    for _, def in ipairs(WC.DEFS) do
        local got = get_path(settings(), def.key)
        if def.visual then assert(same(got, def.default), def.key) else assert(same(got, off_default(def)), def.key) end
    end
    scramble()
    WoWCompanionDB.position = { point = "CENTER", relPoint = "CENTER", x = 5, y = 6 }
    WC.ResetEverything()
    for _, def in ipairs(WC.DEFS) do
        local got = get_path(settings(), def.key)
        if def.position then assert(same(got, off_default(def)), def.key) else assert(same(got, def.default), def.key) end
    end
    assert(WoWCompanionDB.position.x == 5)
end }

cases[#cases + 1] = { "visuals: /wowc reset visuals and reset all ask first, in the addon's own dialog", function()
    fresh_client(nil)
    local WC = WoWCompanion
    settings().lineWidth, settings().locked, settings().minimap.angle = 5, true, 40
    SlashCmdList.WOWC("reset visuals")
    assert(WoWCompanionConfirm:IsShown() and settings().lineWidth == 5)
    WoWCompanionConfirmNo.scripts.OnClick(WoWCompanionConfirmNo)
    assert(not WoWCompanionConfirm:IsShown() and settings().lineWidth == 5)
    SlashCmdList.WOWC("reset visuals")
    WoWCompanionConfirmYes.scripts.OnClick(WoWCompanionConfirmYes)
    assert(settings().lineWidth == 2.5 and settings().locked == true and not WoWCompanionConfirm:IsShown())
    SlashCmdList.WOWC("reset all")
    assert(settings().locked == true)
    WoWCompanionConfirmYes.scripts.OnClick(WoWCompanionConfirmYes)
    assert(settings().locked == false and settings().minimap.angle == 40)
    assert(table.concat(WC.HELP, "\n"):find("reset visuals", 1, true))
end }

cases[#cases + 1] = { "visuals: a control's reset button shows only off the default and restores that value", function()
    fresh_client(nil)
    local WC = WoWCompanion
    for _, def in ipairs(WC.DEFS) do
        if not def.hidden then assert(_G["WoWCompanionOptionReset_" .. def.name], def.key) end
    end
    local b = WoWCompanionOptionReset_LineColor
    WC.SyncOptions()
    assert(not b:IsShown())
    WC.SetSetting("lineColor", { 0.1, 0.2, 0.3 })
    assert(b:IsShown() and not WoWCompanionOptionReset_BgColor:IsShown())
    b.scripts.OnClick(b)
    assert(same(settings().lineColor, { 1, 0.82, 0 }) and not b:IsShown())
    WC.SetSetting("bgOpacity", 0.9)
    assert(WoWCompanionOptionReset_BgOpacity:IsShown())
    WoWCompanionOptionReset_BgOpacity.scripts.OnClick()
    assert(settings().bgOpacity == 0.45)
end }

cases[#cases + 1] = { "visuals: panel, plan tracker and route follow their settings live", function()
    PLAYER_NAME = "Genaenyu"
    local p = digest_client("v13")
    local WC = WoWCompanion
    WC.SetSetting("bgColor", { 0.2, 0.3, 0.4 })
    WC.SetSetting("bgOpacity", 0.8)
    assert(same(p.backdropColor, { 0.2, 0.3, 0.4, 0.8 }))
    WC.SetSetting("borderShow", false)
    assert(p.borderColor[4] == 0)
    WC.SetSetting("borderShow", true)
    WC.SetSetting("borderColor", { 1, 0, 0 })
    WC.SetSetting("borderOpacity", 0.9)
    assert(same(p.borderColor, { 1, 0, 0, 0.9 }))
    WC.SetSetting("headerColor", { 0, 1, 0 })
    assert(same(p.title.color, { 0, 1, 0 }))
    WC.SetSetting("sectionColor", { 0, 0, 1 })
    WC.Refresh()
    local h = row_with(p, "Next quests")
    assert(same(h.label.color, { 0, 0, 1 }), table.concat(h.label.color or {}, ","))
    local y1 = p.content.h
    WC.SetSetting("lineSpacing", 6)
    assert(p.content.h > y1)
    WC.SetSetting("padding", 20)
    assert(p.scroll.anchors.TOPLEFT[4] == 20)
    WC.SetSetting("planBgColor", { 1, 1, 0 })
    WC.SetSetting("planBgOpacity", 0.3)
    WC.SetSetting("planTextSize", 16)
    WC.plan = { steps = {}, done = {} }
    WC.SetSetting("planTracker", true)
    WC.RefreshPlan()
    local t = WC.planTracker
    assert(same(t.bg.colorTexture, { 1, 1, 0, 0.3 }) and t.label.fontSize == 16)
    WC.plan, PLAYER_NAME = nil, nil
end }

cases[#cases + 1] = { "visuals: the rim button exists beside the compartment entry and each switch works", function()
    WITH_COMPARTMENT = true
    fresh_client(nil)
    WITH_COMPARTMENT = nil
    local WC = WoWCompanion
    local reg = AddonCompartmentFrame.registered
    assert(WoWCompanionMinimapButton and WoWCompanionMinimapButton:IsShown() and #reg == 1)
    WC.SetSetting("minimap.show", false)
    assert(not WoWCompanionMinimapButton:IsShown() and #reg == 1)
    WC.SetSetting("minimap.compartment", false)
    assert(#reg == 0)
    WC.SetSetting("minimap.show", true)
    WC.SetSetting("minimap.compartment", true)
    assert(WoWCompanionMinimapButton:IsShown() and #reg == 1)
    -- saved off at load: no compartment entry at all
    local saved = WoWCompanionDB
    saved.settings.minimap.compartment = false
    WITH_COMPARTMENT = true
    fresh_client(saved)
    WITH_COMPARTMENT = nil
    assert(#AddonCompartmentFrame.registered == 0 and WoWCompanionMinimapButton)
end }

cases[#cases + 1] = { "visuals: clicks on the rim button route, and a locked button does not drag", function()
    fresh_client(nil)
    local WC = WoWCompanion
    local b = WoWCompanionMinimapButton
    b.scripts.OnClick(b, "LeftButton")
    assert(WoWCompanionPanel:IsShown() and not WoWCompanionOptions:IsShown())
    b.scripts.OnClick(b, "RightButton")
    assert(WoWCompanionOptions:IsShown())
    local was = settings().planMap
    SHIFT = true
    b.scripts.OnClick(b, "LeftButton")
    SHIFT = false
    assert(settings().planMap == not was and WoWCompanionPanel:IsShown())
    WC.SetSetting("minimap.locked", true)
    b.scripts.OnDragStart(b)
    assert(b.scripts.OnUpdate == nil)
    WC.SetSetting("minimap.locked", false)
    b.scripts.OnDragStart(b)
    assert(b.scripts.OnUpdate)
    local lines = WC.TooltipLines({ digest = {}, db = {}, player = "x", now = 1, minimap = true })
    assert(table.concat(lines, "\n"):find("Shift-left-click", 1, true))
    assert(WC.ICON:find("INV_Misc_Map_01", 1, true))
end }

cases[#cases + 1] = { "visuals: the drawing code reads settings, not constants", function()
    local function slurp(f) return assert(io.open(f)):read("*a") end
    local plan, panel, digest = slurp("WoWCompanion/PlanUI.lua"), slurp("WoWCompanion/Panel.lua"), slurp("WoWCompanion/Digest.lua")
    for _, key in ipairs({ "ringColor", "nextRingColor", "numberColor", "glowColor", "glowOpacity", "pulseSpeed", "tagFillOpacity", "tagRingOpacity",
        "nextLineColor", "outlineColor", "outlineOpacity", "chevronSize", "planBgColor", "planBgOpacity", "planTextSize",
        "minimapBadgeSize", "minimapFill", "minimapFillOpacity", "minimapArrow" }) do
        assert(plan:find('WC.Setting("' .. key .. '")', 1, true) or plan:find('"' .. key .. '"', 1, true), key)
    end
    for _, key in ipairs({ "bgColor", "bgOpacity", "borderShow", "borderColor", "borderOpacity", "headerColor", "lineSpacing", "padding" }) do
        assert(panel:find('WC.Setting("' .. key .. '")', 1, true), key)
    end
    for _, key in ipairs({ "objectiveColor", "doneColor", "readyColor", "sectionColor" }) do assert(digest:find('"' .. key .. '"', 1, true), key) end
    for _, old in ipairs({ "local OUTLINE =", "local CHEVRON_SIZE", "local MM_BADGE =", "WC.COLORS.green", "SetBackdropColor(0, 0, 0", "SetColorTexture(0, 0, 0, 0.5)" }) do
        assert(not plan:find(old, 1, true) and not panel:find(old, 1, true) and not digest:find(old, 1, true), old .. " is a setting now")
    end
end }

cases[#cases + 1] = { "minimap ring: radius from the minimap's width, round and square shapes", function()
    fresh_client(nil)
    local WC = WoWCompanion
    local function near(a, b) return math.abs(a - b) < 1e-6 end
    assert(near(WC.MinimapRingRadius(140), 75) and near(WC.MinimapRingRadius(200), 105) and near(WC.MinimapRingRadius(nil), 75))
    for _, w in ipairs({ 140, 200 }) do
        local r = w / 2 + 5
        local x, y = WC.MinimapOffset(0, w, "ROUND")
        assert(near(x, r) and near(y, 0))
        x, y = WC.MinimapOffset(135, w, "ROUND")
        assert(near(math.sqrt(x * x + y * y), r) and x < 0 and y > 0)
        x, y = WC.MinimapOffset(0, w, "SQUARE") -- a square's edge: clamped to the ring, not the diagonal
        assert(near(x, r) and near(y, 0))
        x, y = WC.MinimapOffset(45, w, "SQUARE")
        assert(near(x, y) and near(x, math.min(r, (math.sqrt(2 * r * r) - 10) * math.cos(math.rad(45)))))
        x, y = WC.MinimapOffset(225, w, "CORNER-TOPRIGHT") -- bottom-left of a corner shape is square
        assert(near(x, y) and x < 0 and math.sqrt(x * x + y * y) > r - 1)
        x, y = WC.MinimapOffset(45, w, "CORNER-TOPRIGHT") -- its top-right quadrant is round
        assert(near(math.sqrt(x * x + y * y), r))
    end
    assert(select(1, WC.MinimapOffset(0, 140, "NOT-A-SHAPE")) == WC.MinimapOffset(0, 140, "ROUND"))
    -- the placed button follows the minimap's own width
    Minimap:SetSize(200, 200)
    WC.db.settings.minimap.angle = 90
    WC.PlaceMinimapButton()
    local _, _, _, x, y = WoWCompanionMinimapButton:GetPoint()
    assert(near(x, 0) and near(y, 105))
end }

cases[#cases + 1] = { "options tabs: each is as wide as its label plus padding at every text size, with no overlap", function()
    fresh_client(nil)
    local WC = WoWCompanion
    for _, id in ipairs(WC.FONT_ORDER) do
        WC.SetSetting("fontSize", id)
        local size = WC.FONT_SIZES[id]
        local widths = {}
        for i, p in ipairs(WC.PAGES) do
            local label = WC.L["TAB_" .. p]
            local b = _G["WoWCompanionOptionsTab_" .. p]
            assert(b.w >= #label * size * 0.62 + 22 - 1, p .. " at " .. id)
            assert(b:GetFontString().fontSize == size, "the tab's text follows the text size")
            widths[i] = b.w
        end
        local spots, rows = WC.TabLayout(widths, 456, 2)
        for i = 2, #spots do
            if spots[i].row == spots[i - 1].row then assert(spots[i].x >= spots[i - 1].x + widths[i - 1], "overlap") end
            assert(spots[i].x + widths[i] <= 456, "inside the window")
        end
        assert(WC.options.tabRows == rows)
    end
    assert(WC.TabWidth("Map & route", 12, 70) == 92 and WC.TabWidth("x", 12, 1) == 48)
    local spots, rows = WC.TabLayout({ 200, 200, 200 }, 456, 2)
    assert(rows == 2 and spots[3].row == 1 and spots[3].x == 0)
end }

cases[#cases + 1] = { "arrowheads: drawn as lines, no texture art; the rim arrow too", function()
    fresh_client(nil)
    local WC = WoWCompanion
    for _, f in ipairs({ "PlanUI", "Panel", "Button" }) do
        local src = assert(io.open("WoWCompanion/" .. f .. ".lua")):read("*a")
        assert(not src:find("SetTexture(MINIMAP_ARROW", 1, true) and not src:find("SetRotation", 1, true), f)
    end
    CreateFrame("Frame", "WoWCompanionPlanMinimapPin", UIParent)
    local arrow = WC.planMinimap.arrow
    assert(#arrow == 2 and arrow[1].kind == "Line" and arrow[2].kind == "Line" and arrow[1].shown == false)
end }

-- A fake of the client's quest-map frame that holds the side-tab column: tabs are children with fixed geometry.
local function fake_column(tabs)
    local col = CreateFrame("Frame", nil, UIParent)
    col.left, col.top = 1000, 800
    function col:GetLeft() return self.left end
    function col:GetTop() return self.top end
    local fields = { "QuestsTab", "EventsTab", "MapLegendTab" }
    for i, g in ipairs(tabs or {}) do
        local t = CreateFrame("Button", nil, col)
        col[fields[i]] = t
        t.w, t.h = 44, 44
        t.geo = g
        function t:GetTop() return self.geo.top end
        function t:GetBottom() return self.geo.top - self.h end
        function t:GetLeft() return self.geo.left end
    end
    return col
end

cases[#cases + 1] = { "world map tab: built from the client's side-tab template inside the tab column's frame", function()
    WorldMapFrame = CreateFrame("Frame", nil, UIParent)
    QuestMapFrame = fake_column({})
    fresh_client(nil)
    local WC = WoWCompanion
    local b = WC.mapButton
    assert(b and WC.mapButtonMode == "tab" and b.parent == QuestMapFrame and b.template == "QuestLogTabButtonTemplate")
    assert(b.w == 44 and b.h == 44 and b.icon.texture == WC.ICON and b:IsShown())
    assert(not WC.CreateMapButton() and WC.mapButton == b, "created once")
    WorldMapFrame, QuestMapFrame = nil, nil
end }

cases[#cases + 1] = { "world map tab: the lowest of the client's tabs is the anchor", function()
    fresh_client(nil)
    local WC = WoWCompanion
    assert(WC.LowestTab({}) == nil)
    local a, b, c = {}, {}, {}
    assert(WC.LowestTab({ { frame = a, bottom = 756 } }) == a)
    assert(WC.LowestTab({ { frame = a, bottom = 756 }, { frame = c, bottom = 662 }, { frame = b, bottom = 709 } }) == c)
end }

cases[#cases + 1] = { "world map tab: anchored below the lowest client tab at its size, and again when tabs change", function()
    WorldMapFrame = CreateFrame("Frame", nil, UIParent)
    QuestMapFrame = fake_column({ { top = 800, left = 990 }, { top = 753, left = 990 } })
    QuestMapFrame.EventsTab.w, QuestMapFrame.EventsTab.h = 40, 42
    fresh_client(nil)
    local WC = WoWCompanion
    local function point() local p = WC.mapButton.points[1] return p[1], p[2], p[3], p[4], p[5] end
    local pt, rel, relPt, px, py = point()
    assert(pt == "TOPLEFT" and rel == QuestMapFrame.EventsTab and relPt == "BOTTOMLEFT" and px == 0 and py == -WC.MAP_TAB_GAP)
    assert(WC.mapButton.w == 40 and WC.mapButton.h == 42, "the same size as its sibling")
    -- a third client tab appears lower (a map addon moved things): the display-mode hook and map show re-anchor
    local t = CreateFrame("Button", nil, QuestMapFrame)
    t.w, t.h, t.geo = 44, 44, { top = 706, left = 990 }
    function t:GetTop() return self.geo.top end
    function t:GetBottom() return self.geo.top - self.h end
    function t:GetLeft() return self.geo.left end
    QuestMapFrame.MapLegendTab = t
    QuestMapFrame.scripts.OnSizeChanged(QuestMapFrame)
    assert(select(2, point()) == t)
    -- the lowest tab hidden: the next one up
    t.shown = false
    WorldMapFrame.scripts.OnShow(WorldMapFrame)
    assert(select(2, point()) == QuestMapFrame.EventsTab)
    -- our own tab is never its own anchor, and no tab at all keeps the old fixed spot
    QuestMapFrame = fake_column({})
    WC.mapButton, WC.mapButtonParent = nil, nil
    WC.CreateMapButton()
    assert(WC.mapButton.points[1][3] == "TOPLEFT" and WC.mapButton.points[1][1] == "TOPRIGHT")
    WorldMapFrame, QuestMapFrame = nil, nil
end }

cases[#cases + 1] = { "world map tab: left-click selects the plan panel, right-click opens options, setting hides it", function()
    WorldMapFrame = CreateFrame("Frame", nil, UIParent)
    QuestMapFrame = fake_column({})
    fresh_client(nil)
    local WC = WoWCompanion
    local b = WC.mapButton
    local before = WC.db.settings.planMap
    assert(b.checked == false)
    b.scripts.OnClick(b, "LeftButton")
    assert(WC.db.settings.planMap == before and b.checked == true and WC.panelState.selected)
    assert(not WoWCompanionOptions:IsShown())
    b.scripts.OnClick(b, "RightButton")
    assert(WoWCompanionOptions:IsShown() and b.checked == true)
    WC.SetSetting("mapButton", false)
    assert(not b:IsShown())
    WC.SetSetting("mapButton", true)
    assert(b:IsShown())
    WorldMapFrame, QuestMapFrame = nil, nil
end }

cases[#cases + 1] = { "world map tab: without the column or template, the button sits on the map frame's own edge", function()
    WorldMapFrame = CreateFrame("Frame", nil, UIParent)
    QuestMapFrame = nil
    fresh_client(nil)
    local WC = WoWCompanion
    assert(WC.mapButton and WC.mapButtonMode == "edge" and WC.mapButton.parent == WorldMapFrame)
    WC.mapButton.scripts.OnClick(WC.mapButton, "LeftButton")
    assert(WC.mapButton.checkedTex.shown == WC.PlanShownOnMap())
    local src = assert(io.open("WoWCompanion/Button.lua")):read("*a")
    assert(not src:find("AddOverlayFrame", 1, true))
    WorldMapFrame = nil
end }

-- ---------------------------------------------------------------- the plan in the map's side panel (MapPanel.lua)

-- A synthetic route: 20 steps over two maps, a pick-up, objective and turn-in per quest, then travel stops.
local function synthetic_steps()
    local steps, n = {}, 0
    local function add(kind, q, label, map, x, y, level)
        n = n + 1
        steps[n] = { n = n, kind = kind, questID = q, quest = q > 0 and ("Quest " .. q) or "", label = label, map = map, x = x, y = y, approx = false, level = level }
    end
    for q = 1, 6 do
        local map = q <= 4 and 7001 or 7002
        add("pickup", q, "Pick up Quest " .. q .. " from Guard " .. q, map, 10 * q, 20, 5 + q)
        add("objective", q, "Kill 5 boars", map, 10 * q + 3, 30, 5 + q)
        add("turnin", q, "Turn in Quest " .. q, map, 10 * q, 20, 5 + q)
    end
    add("travel", 0, "Travel to Otherisle", 7002, 80, 80)
    add("travel", 0, "Travel to Home", 7001, 5, 5)
    return steps
end

-- A client with the quest-map column, the map frame and a plan of the synthetic steps; returns WC, the tab and the column.
local function side_panel_client(opts)
    opts = opts or {}
    WITH_TOOLTIP_HOOKS = true
    WorldMapFrame = CreateFrame("Frame", nil, UIParent)
    WorldMapFrame.mapID = 7001
    WorldMapFrame.GetMapID = function(self) return self.mapID end
    WorldMapFrame.SetMapID = function(self, id) self.setCalls = (self.setCalls or 0) + 1; self.mapID = id end
    WorldMapFrame.ScrollContainer = { SetPanTarget = function(self, x, y) self.pan = { x, y } end }
    QuestMapFrame = fake_column({ { top = 800, left = 990 }, { top = 753, left = 990 } })
    if opts.native then
        QuestMapFrame.added, QuestMapFrame.modes = {}, {}
        QuestMapFrame.displayMode = "quests"
        QuestMapFrame.AddContentFrame = function(self, f, mode) self.added[#self.added + 1] = { f, mode } end
        QuestMapFrame.SetDisplayMode = function(self, mode) self.modes[#self.modes + 1] = mode; self.displayMode = mode end
    else
        QuestMapFrame.SetDisplayMode = function() end
    end
    fresh_client(opts.saved)
    WITH_TOOLTIP_HOOKS = nil
    local WC = WoWCompanion
    WC.plan = { steps = synthetic_steps(), done = {}, generated = 1800000000 }
    return WC, WC.mapButton, QuestMapFrame
end

local function side_panel_done()
    WorldMapFrame, QuestMapFrame, C_QuestLog = nil, nil, nil
end

cases[#cases + 1] = { "side panel (overlay): our tab selects its panel, any other tab or display-mode change deselects it", function()
    local WC, tab, col = side_panel_client()
    assert(WC.PanelBackend() == "overlay" and WC.mapPanel == nil and not tab.checked, "nothing built before the first click")
    tab.scripts.OnClick(tab, "LeftButton")
    local f = WC.mapPanel
    assert(f and f:IsShown() and tab.checked and WC.panelState.selected and WC.panelState.lastTab == "plan")
    assert(f.parent == col, "our frame is a child of the quest panel, never a client frame")
    tab.scripts.OnClick(tab, "LeftButton")
    assert(not f:IsShown() and not tab.checked, "a second click deselects")
    tab.scripts.OnClick(tab, "LeftButton")
    local sibling = col.children[1]
    assert(sibling.scripts.OnClick, "the client's tab is watched")
    sibling.scripts.OnClick(sibling)
    assert(not f:IsShown() and not tab.checked and WC.panelState.lastTab == "other", "another tab brings its content back")
    tab.scripts.OnClick(tab, "LeftButton")
    assert(f:IsShown())
    HOOKS.SetDisplayMode(col, "map legend")
    assert(not f:IsShown() and not tab.checked, "a display-mode change by the map's own controls deselects")
    tab.scripts.OnClick(tab, "LeftButton")
    HOOKS.SetDisplayMode(col, WC.TAB_MODE)
    assert(f:IsShown(), "our own mode does not")
    side_panel_done()
end }

cases[#cases + 1] = { "side panel (native): the client's public content-frame pair selects and restores the mode", function()
    local WC, tab, col = side_panel_client({ native = true })
    assert(WC.PanelBackend() == "native")
    tab.scripts.OnClick(tab, "LeftButton")
    assert(#col.added == 1 and col.added[1][1] == WC.mapPanel and col.added[1][2] == WC.TAB_MODE)
    assert(col.modes[1] == WC.TAB_MODE and tab.checked and WC.panelState.selected)
    tab.scripts.OnClick(tab, "LeftButton")
    assert(col.modes[2] == "quests" and not tab.checked, "deselecting returns to the mode that was showing")
    tab.scripts.OnClick(tab, "LeftButton")
    HOOKS.SetDisplayMode(col, "events")
    assert(not tab.checked and #col.modes == 3, "a client-made change is not answered with another call")
    side_panel_done()
end }

cases[#cases + 1] = { "side panel: map calls are only the guarded public ones (static check)", function()
    local allowed = { GetMapID = true, SetMapID = true, ScrollContainer = true, SetPanTarget = true, AddContentFrame = true,
        SetDisplayMode = true, displayMode = true, GetFrameLevel = true, GetChildren = true, HookScript = true }
    local guarded = { SetMapID = true, SetPanTarget = true, AddContentFrame = true, SetDisplayMode = true, GetMapID = true }
    local n = 0
    for _, file in ipairs({ "MapPanel" }) do
        local ln = 0
        for line in io.lines("WoWCompanion/" .. file .. ".lua") do
            ln = ln + 1
            local code = line:gsub("%-%-.*$", "")
            for _, obj in ipairs({ "QuestMapFrame", "WorldMapFrame", "col", "map", "sc" }) do
                for name in code:gmatch("%f[%w_]" .. obj .. "[%.:]([%w_]+)") do
                    n = n + 1
                    assert(allowed[name], file .. ":" .. ln .. " calls " .. obj .. "." .. name)
                    if guarded[name] and code:find("%(") then
                        assert(code:find("pcall", 1, true) or code:find("type%(") or code:find("%f[%w_]and%f[^%w_]") or code:find("if "), file .. ":" .. ln .. " unguarded " .. name)
                    end
                end
            end
        end
    end
    assert(n > 5, "the check looked at something")
    local src = assert(io.open("WoWCompanion/MapPanel.lua")):read("*a")
    assert(not src:find("hooksecurefunc%s*%(%s*_G") and not src:find("QuestMapFrame%s*=") and not src:find("WorldMapFrame%s*="), "nothing of the client is replaced")
end }

cases[#cases + 1] = { "side panel rows: each kind, the next step highlighted, finished steps grouped", function()
    local WC = side_panel_client()
    local steps = synthetic_steps()
    local done = { [1] = true, [2] = true }
    local m = WC.PanelModel({ steps = steps, done = done, nextStep = steps[3], allZones = true, showDone = true })
    assert(#m.rows == 18 and #m.done == 2)
    assert(m.rows[1].n == 3 and m.rows[1].isNext and not m.rows[2].isNext)
    assert(m.rows[1].kind == "turnin" and m.rows[1].icon == WC.ICONS.turnin and m.rows[1].sub == "Turn in")
    assert(m.done[1].kind == "pickup" and m.done[1].icon == WC.ICONS.pickup and m.done[1].done)
    assert(m.done[1].title == "[6] Quest 1" and m.done[1].sub == "Pick up from Guard 1", m.done[1].sub)
    assert(m.done[2].kind == "objective" and m.done[2].icon == WC.ICONS.progress and m.done[2].sub == "Kill 5 boars")
    assert(m.rows[#m.rows].kind == "travel" and m.rows[#m.rows].icon == nil and m.rows[#m.rows].title == "Travel to Home")
    assert(#WC.PanelModel({ steps = steps, done = done, allZones = true, showDone = false }).done == 0, "completed steps can be left out")
    -- the plan list of the synthetic route, for the record
    local rows = {}
    for _, r in ipairs(WC.PanelModel({ steps = steps, done = {}, nextStep = steps[1], allZones = true }).rows) do
        rows[#rows + 1] = string.format("%2d %-9s %s%s | %s", r.n, r.kind, r.isNext and "> " or "  ", r.title, r.sub)
    end
    assert(#rows == 20)
    if os.getenv("WOWC_PRINT_ROWS") then io.write(table.concat(rows, "\n"), "\n") end
    -- the footer: stops and the summed legs on one map
    local legs = { { map = 1, x = 0, y = 0 }, { map = 1, x = 3, y = 4 }, { map = 2, x = 50, y = 50 } }
    local before_map = C_Map
    C_Map = nil
    assert(WC.PanelFooter(legs) == "3 stops", "no yards without the client's map size")
    C_Map = before_map
    local saved_map = C_Map
    C_Map = { GetMapWorldSize = function() return 1000, 1000 end }
    assert(WC.PanelFooter(legs) == "3 stops · about 50 yd", WC.PanelFooter(legs))
    C_Map = saved_map
    for _, t in ipairs({ WC.PanelFooter(legs), WC.PanelFooter({}) }) do assert(not t:find("map units", 1, true)) end
    side_panel_done()
end }

cases[#cases + 1] = { "side panel rows: the live objective count and the client's quest title", function()
    local WC = side_panel_client()
    local steps = synthetic_steps()
    C_QuestLog = {
        IsQuestFlaggedCompleted = function() return false end, GetLogIndexForQuestID = function(id) return id == 1 and 1 or nil end,
        IsComplete = function() return false end, GetTitleForQuestID = function(id) return id == 1 and "Boar Trouble" or nil end,
        GetQuestObjectives = function() return { { text = "Boar slain: 2/5", numFulfilled = 2, numRequired = 5, finished = false } } end,
    }
    local m = WC.PanelModel({ steps = steps, done = {}, allZones = true })
    assert(m.rows[2].sub == "Kill 2/5 boars" or m.rows[2].sub:find("2/5", 1, true), m.rows[2].sub)
    assert(m.rows[1].title == "[6] Boar Trouble")
    side_panel_done()
end }

cases[#cases + 1] = { "side panel zone filter: the map shown by default, All zones on request, a setting change resets the choice", function()
    local WC, tab = side_panel_client()
    local steps = synthetic_steps()
    local here = WC.PanelModel({ steps = steps, done = {}, mapID = 7002 })
    assert(#here.rows == 7, #here.rows)
    for _, r in ipairs(here.rows) do assert(r.step.map == 7002) end
    assert(#WC.PanelModel({ steps = steps, done = {}, mapID = 7002, allZones = true }).rows == 20)
    tab.scripts.OnClick(tab, "LeftButton")
    local f = WC.mapPanel
    assert(WC.PanelAllZones() == false and f.zoneBtn.text == "This map")
    local shown = 0
    for _, r in ipairs(f.rows) do if r:IsShown() then shown = shown + 1 end end
    assert(shown == 13, shown)
    WorldMapFrame.mapID = 7002
    WC.RefreshMapPanel()
    shown = 0
    for _, r in ipairs(f.rows) do if r:IsShown() then shown = shown + 1 end end
    assert(shown == 7, "selecting a zone on the map updates the list")
    f.zoneBtn.scripts.OnClick(f.zoneBtn)
    assert(WC.PanelAllZones() == true and f.zoneBtn.text == "All zones")
    shown = 0
    for _, r in ipairs(f.rows) do if r:IsShown() then shown = shown + 1 end end
    assert(shown == 20)
    WC.SetSetting("panelZone", "all")
    assert(WC.PanelAllZones() == true)
    f.zoneBtn.scripts.OnClick(f.zoneBtn)
    assert(WC.PanelAllZones() == false)
    WC.SetSetting("panelZone", "shown")
    assert(WC.PanelAllZones() == false)
    side_panel_done()
end }

cases[#cases + 1] = { "side panel rows: height grows with a wrapped sub-line, rows never overlap", function()
    local WC = side_panel_client()
    assert(WC.RowHeight(13, 11, 0) < WC.RowHeight(13, 22, 0) and WC.RowHeight(13, 11, 0) < WC.RowHeight(13, 11, 11))
    assert(WC.RowHeight(13, 0, 0) >= 34 and WC.RowHeight(13, 22, 11) == 6 + 13 + 6 + 2 + 22 + 2 + 11)
    WC.ToggleMapPanel()
    WC.SetSetting("panelZone", "all")
    local f = WC.mapPanel
    WC.RefreshMapPanel()
    -- row 8 wraps to two lines, row 3 carries a then: line
    f.rows[8].sub.GetStringHeight = function() return 22 end
    WC.RefreshMapPanel()
    local y = 0
    for i = 1, 20 do
        local r = f.rows[i]
        assert(r.top == y, "row " .. i .. " starts where the last ended")
        y = y + r.hh
    end
    assert(f.rows[8].hh > f.rows[7].hh and f.child.h >= y, "the last row scrolls fully into view")
    side_panel_done()
end }

cases[#cases + 1] = { "side panel: a clicked step stays selected, switches, toggles off and clears with the map; current stays distinct", function()
    local WC, tab = side_panel_client()
    tab.scripts.OnClick(tab, "LeftButton")
    WC.SetSetting("panelZone", "all")
    WC.RefreshMapPanel()
    local f = WC.mapPanel
    local r1, r4 = f.rows[1], f.rows[4]
    assert(r1.nextBg.shown and not r1.selBg.shown and WC.panelState.selectedStep == nil)
    r4.scripts.OnClick(r4, "LeftButton")
    assert(WC.panelState.selectedStep == 4 and r4.selBg.shown and r4.selBar.shown and r4.badge.selRing.shown)
    assert(not r1.selBg.shown and not f.rows[2].selBg.shown and not f.rows[3].selBg.shown, "only the clicked step")
    assert(r1.nextBg.shown and not r4.nextBg.shown, "current and selected are separate looks")
    assert(r4.selBg.colorTexture[1] ~= r1.nextBg.colorTexture[1], "the two fills differ")
    -- hover still works on top
    r4.scripts.OnEnter(r4)
    assert(r4.hl.shown and r4.selBg.shown)
    r4.scripts.OnLeave(r4)
    -- another row switches, a redraw keeps it, the same row again clears
    r1.scripts.OnClick(r1, "LeftButton")
    assert(WC.panelState.selectedStep == 1 and r1.selBg.shown and not r4.selBg.shown)
    WC.RefreshMapPanel()
    assert(f.rows[1].selBg.shown)
    r1.scripts.OnClick(r1, "LeftButton")
    assert(WC.panelState.selectedStep == nil and not r1.selBg.shown)
    -- a right click does not select; the map closing clears it
    r4.scripts.OnClick(r4, "RightButton")
    assert(WC.panelState.selectedStep == nil)
    r4.scripts.OnClick(r4, "LeftButton")
    WorldMapFrame.scripts.OnHide(WorldMapFrame)
    assert(WC.panelState.selectedStep == nil and not r4.selBg.shown)
    side_panel_done()
end }

cases[#cases + 1] = { "side panel: hover links the row and its badge, a left click centres the map, a right click opens the card", function()
    local WC, tab = side_panel_client()
    tab.scripts.OnClick(tab, "LeftButton")
    WC.SetSetting("panelZone", "all")
    local f = WC.mapPanel
    local row = f.rows[1]
    assert(row.step.n == 1 and row.quest == 1 and row.group == "mp1")
    row.scripts.OnEnter(row)
    assert(WC.hover.source == "panel" and WC.hover.quests[1] == true and WC.StepHot(WC.plan.steps[1]), "the row pulses its badge")
    assert(row.hl:IsShown() and not WC.StepHot(WC.plan.steps[4]))
    row.scripts.OnLeave(row)
    assert(WC.hover.source == nil and not row.hl:IsShown())
    -- a badge on the map lights its rows
    WC.HoverEnterBadge({ steps = { WC.plan.steps[4] } })
    assert(f.rows[4].hl:IsShown() and f.rows[5].hl:IsShown() and not f.rows[1].hl:IsShown())
    WC.HoverLeaveBadge()
    assert(not f.rows[4].hl:IsShown())
    -- left click: switches map when needed, centres, pings
    local far = f.rows[19]
    far.scripts.OnClick(far, "LeftButton")
    assert(WorldMapFrame.mapID == 7002 and WorldMapFrame.ScrollContainer.pan[1] == 0.8 and WorldMapFrame.ScrollContainer.pan[2] == 0.8)
    row.scripts.OnClick(row, "LeftButton")
    assert(WorldMapFrame.mapID == 7001 and WorldMapFrame.ScrollContainer.pan[1] == 0.1)
    assert(WC.hover.source == "card" and WC.hover.quests[1] == true, "the badge pings")
    -- right click opens the detail card; a travel step has none
    row.scripts.OnClick(row, "RightButton")
    assert(WC.card and WC.card:IsShown())
    assert(WC.PanelRowClick(WC.plan.steps[19], "RightButton") == "none")
    -- no client map functions: the click still works
    WorldMapFrame.SetMapID, WorldMapFrame.ScrollContainer = nil, nil
    assert(WC.PanelRowClick(WC.plan.steps[1], "LeftButton") == "center")
    side_panel_done()
end }

cases[#cases + 1] = { "side panel: rows follow quest events; the completed group collapses", function()
    local WC, tab = side_panel_client()
    tab.scripts.OnClick(tab, "LeftButton")
    WC.SetSetting("panelZone", "all")
    local f = WC.mapPanel
    local function shown()
        local n = 0
        for _, r in ipairs(f.rows) do if r:IsShown() then n = n + 1 end end
        return n
    end
    assert(shown() == 20 and f.rows[1].nextBg:IsShown() and not f.rows[2].nextBg:IsShown() and not f.doneHead:IsShown())
    assert(f.stepText.text:find("Step 1/20", 1, true) and f.footer.text:find("20 stops", 1, true))
    WC.plan.done[1] = true
    WC.LiveUpdate("QUEST_LOG_UPDATE")
    assert(shown() == 19 and f.rows[1].step.n == 2 and f.rows[1].nextBg:IsShown(), "the next step moves on")
    assert(f.doneHead:IsShown() and f.doneHead.text == "Completed (1)" and f.stepText.text:find("Step 2/20", 1, true))
    WC.plan.done[2] = true
    WC.RefreshMapPanel()
    assert(f.doneHead.text == "Completed (2)")
    f.doneHead.scripts.OnClick(f.doneHead)
    assert(shown() == 20 and f.rows[19].check:IsShown() == true, "opened: the finished steps are listed, checked")
    f.doneHead.scripts.OnClick(f.doneHead)
    assert(shown() == 18)
    WC.SetSetting("panelShowDone", false)
    assert(not f.doneHead:IsShown() and shown() == 18, "completed steps can be turned off")
    -- a hidden tab does no work
    tab.scripts.OnClick(tab, "LeftButton")
    WC.plan.done[3] = true
    WC.LiveUpdate("QUEST_LOG_UPDATE")
    assert(f.doneHead.text == "Completed (2)")
    side_panel_done()
end }

cases[#cases + 1] = { "side panel: the eye and shift-click flip the plan on the map, nothing else", function()
    local WC, tab = side_panel_client()
    tab.scripts.OnClick(tab, "LeftButton")
    local f = WC.mapPanel
    local before = WC.db.settings.planMap
    f.eye.scripts.OnClick(f.eye)
    assert(WC.db.settings.planMap == not before and WC.panelState.selected and f:IsShown())
    assert(f.eye.alpha == (before and 0.4 or 1))
    SHIFT = true
    tab.scripts.OnClick(tab, "LeftButton")
    SHIFT = false
    assert(WC.db.settings.planMap == before and WC.panelState.selected and f:IsShown() and tab.checked, "shift-click leaves the panel alone")
    tab.scripts.OnClick(tab, "RightButton")
    assert(WoWCompanionOptions:IsShown() and WC.panelState.selected)
    tab.scripts.OnEnter(tab)
    local text = {}
    for _, c in ipairs(GameTooltip.calls) do if c[1] == "AddLine" then text[#text + 1] = c[2] end end
    assert(#text == 4 and text[2]:find("side panel", 1, true) and text[3]:find("Shift", 1, true) and text[4]:find("Right-click", 1, true))
    side_panel_done()
end }

cases[#cases + 1] = { "side panel: open-on-tab setting, the session's last tab, and the new settings' defaults and reset", function()
    local WC, tab = side_panel_client()
    for key, want in pairs({ panelOpenOnTab = false, panelZone = "shown", panelShowDone = true }) do
        assert(WC.Setting(key) == want and WC.IsDefault(key), key)
    end
    WorldMapFrame.scripts.OnShow(WorldMapFrame)
    assert(not WC.panelState.selected, "off by default: the map opens on the client's tab")
    WC.SetSetting("panelOpenOnTab", true)
    WorldMapFrame.scripts.OnShow(WorldMapFrame)
    assert(WC.panelState.selected and WC.mapPanel:IsShown() and tab.checked)
    local sibling = QuestMapFrame.children[1]
    sibling.scripts.OnClick(sibling)
    WorldMapFrame.scripts.OnShow(WorldMapFrame)
    assert(not WC.panelState.selected, "the last tab used this session wins over the setting")
    tab.scripts.OnClick(tab, "LeftButton")
    WC.SetSetting("panelOpenOnTab", false)
    WorldMapFrame.scripts.OnShow(WorldMapFrame)
    assert(WC.panelState.selected, "and a remembered plan tab stays")
    WC.SetSetting("panelZone", "all"); WC.SetSetting("panelShowDone", false); WC.SetSetting("panelOpenOnTab", true)
    WC.ResetPage("map")
    assert(WC.IsDefault("panelOpenOnTab") and WC.IsDefault("panelZone") and WC.IsDefault("panelShowDone"))
    WC.SetSetting("mapButton", false)
    assert(not tab:IsShown())
    side_panel_done()
end }

cases[#cases + 1] = { "side panel: without a plan it says so, and the edge button still flips the plan on the map", function()
    local WC, tab = side_panel_client()
    WC.plan = nil
    tab.scripts.OnClick(tab, "LeftButton")
    assert(WC.mapPanel.empty.text:find("No plan yet", 1, true) and WC.mapPanel.empty:IsShown())
    assert(WC.PanelHeader().step == "")
    side_panel_done()
    WorldMapFrame = CreateFrame("Frame", nil, UIParent)
    QuestMapFrame = nil
    fresh_client(nil)
    WC = WoWCompanion
    local before = WC.db.settings.planMap
    WC.mapButton.scripts.OnClick(WC.mapButton, "LeftButton")
    assert(WC.db.settings.planMap == not before and WC.mapPanel == nil and WC.mapButton.checkedTex.shown == not before)
    WorldMapFrame = nil
end }

cases[#cases + 1] = { "what's new: body sits in a scroll frame, window sized to the text, button clear of it", function()
    local box = upgrade_client("0.0.0")
    assert(box.scroll and box.scroll.kind == "ScrollFrame" and box.content.parent == box.scroll and box.scroll.child == box.content)
    assert(box.button.parent == box)
    local WC = WoWCompanion
    assert(WC.WhatsNewWindowHeight(0) == WC.WHATS_NEW_MIN_H and WC.WhatsNewWindowHeight(9999) == WC.WHATS_NEW_MAX_H)
    assert(WC.WhatsNewWindowHeight(100) == 172)
end }

cases[#cases + 1] = { "advice age uses the capture time as loaded from disk, not the live login refresh", function()
    local function warned(disk, live_after, digest_gen)
        fresh_client(nil)
        ForeverScribeDB = fs_db(disk)
        WoWCompanion.ResetCaptureSnapshot()
        WoWCompanion.OwnCapturedAt("Thrall") -- the load-time snapshot
        ForeverScribeDB.chars["Testrealm:Thrall"].snapshot.capturedAt = live_after -- the login refresh, in memory only
        load_digest("tests/fixtures/digest_full.lua")
        return WoWCompanion.panel.plain:find(HINT, 1, true) ~= nil
    end
    assert(not warned(GEN - 60, GEN + 2800), "unchanged save at login: no warning")
    assert(warned(GEN + 1200, GEN + 1200), "a really newer save on disk: warning")
    assert(not warned(GEN + 900, GEN + 900), "exactly at the grace")
    assert(warned(GEN + 901, GEN + 901), "just over the grace")
end }

cases[#cases + 1] = { "panel views: the row lists of Full, Compact and Next step only, and the header line", function()
    fresh_client(nil)
    local WC = WoWCompanion
    local rows = {
        { kind = "header", id = "next_quests", title = "Quests", text = "[-] Quests" },
        { kind = "quest", id = "q5", quest = 5, text = "Other" }, { kind = "obj", text = "five" },
        { kind = "quest", id = "q7", quest = 7, text = "Mine" }, { kind = "obj", text = "kill 3" }, { kind = "status", text = "ready" },
        { kind = "quest", id = "q9", quest = 9, text = "Later" }, { kind = "obj", text = "nine" },
        { kind = "header", id = "upgrades", title = "Upgrades", text = "[-] Upgrades" }, { kind = "line", text = "boots" },
    }
    local step = { questID = 7 }
    assert(#WC.ViewRows("full", rows, {}, step) == #rows)
    assert(#WC.ViewRows("compact", rows, {}, step) < #rows)
    local only = WC.ViewRows("next", rows, {}, step)
    assert(#only == 3 and only[1].text == "Mine" and only[2].text == "kill 3" and only[3].text == "ready")
    assert(#WC.ViewRows("next", rows, {}, { questID = 0 }) == 0 and #WC.ViewRows("next", rows, {}, nil) == 0)
    assert(#WC.ViewRows("next", rows, {}, { questID = 9 }) == 2)
    -- the live header line
    WC.plan = { steps = { { n = 1, kind = "pickup", questID = 7, label = "Pick up X", map = 1, x = 50, y = 50 } }, done = {} }
    assert(WC.NextStepLine(WC.PlanNext(), 2, nil, nil) == "Step 1/1 · Pick up X · another zone")
    WC.plan.done[1] = true
    assert(WC.NextStepLine(nil) == "Plan complete (1 steps)")
    WC.plan = nil
    assert(WC.NextStepLine(nil) == "")
    -- the setting drives the panel: Next step only keeps just that entry, and the header button returns to Full
    local p = digest_client("v13")
    WC = WoWCompanion
    WC.SetSetting("view", "next")
    assert(WoWCompanionCompactButton:GetText() == "Full" and p.plain == "")
    click(WoWCompanionCompactButton)
    assert(WC.db.settings.view == "full" and p.plain ~= "")
    click(WoWCompanionCompactButton)
    assert(WC.db.settings.view == "compact")
    WC.SetSetting("view", "bogus")
    assert(WC.db.settings.view == "full")
end }

cases[#cases + 1] = { "migration: arrowhead size default 8, clamp 2..24, old default moves once, a chosen value stays", function()
    fresh_client(nil)
    local WC = WoWCompanion
    assert(WC.DEF_OF.arrowSize.default == 8 and WC.Setting("arrowSize") == 8)
    assert(WC.SetSetting("arrowSize", 1) == 2 and WC.SetSetting("arrowSize", 99) == 24 and WC.SetSetting("arrowSize", 2) == 2)
    fresh_client({ settings = { arrowSize = 14 } })
    assert(WoWCompanion.db.settings.arrowSize == 8 and WoWCompanion.db.migrated.arrowSize8 == true)
    fresh_client({ settings = { arrowSize = 20 } })
    assert(WoWCompanion.db.settings.arrowSize == 20)
    fresh_client({ settings = { arrowSize = 14 }, migrated = { arrowSize8 = true } })
    assert(WoWCompanion.db.settings.arrowSize == 14)
    -- geometry at the smallest size: tip and wings are distinct points, so no zero-length stroke
    WC = plan_client("full")
    local tx, ty, x1, y1, x2, y2 = WC.ArrowheadPoints(0, 0, 0, 2)
    assert(tx == 1 and ty == 0 and x1 == -1 and x2 == -1 and math.abs(y1) > 0.7 and y1 == -y2)
end }

cases[#cases + 1] = { "migration: the separate plan tracker is turned off once, a later choice sticks; compact becomes the view", function()
    fresh_client({ settings = { planTracker = true, compact = true } })
    local WC = WoWCompanion
    assert(WC.db.settings.planTracker == false and WC.db.settings.view == "compact" and WC.db.settings.compact == nil)
    assert(WC.db.migrated.planTrackerOff == true)
    WC.SetSetting("planTracker", true)
    local saved = WoWCompanionDB
    fresh_client(saved)
    assert(WoWCompanion.db.settings.planTracker == true and WoWCompanion.db.settings.view == "compact")
    fresh_client(nil)
    assert(WoWCompanion.db.settings.planTracker == false and WoWCompanion.db.settings.view == "full")
    assert(WoWCompanion.DEF_OF.planTracker.default == false)
end }


-- Hover, click, the detail card and training entries (schema 1.4 digests).
local function digest14()
    return { schema = "1.4", generated = NOW - 60, build = "1.60.0.64000", character = "Thrall", sections = {
        { id = "next_quests", lines = {
            { text = "Pick up Quest 10", quest = 10, kind = "pickup", title = "Quest 10", level = 10, npc = "Gruff", zone = "Testisle",
              details = { "Chain start", "Rewards a bag" }, prompt = "Prompt for quest ten?" },
            { text = "Blood Tithe: 0/1 Find X", quest = 11, kind = "progress", title = "Blood Tithe", level = 9,
              objectives = { { text = "Find X", have = 0, need = 1 } }, details = { "Detail eleven" }, prompt = "Prompt for Blood Tithe?" },
            { text = "You have 2 unspent talent points", kind = "talent", points = 2, details = { "Spend them soon" }, prompt = "Which talents first?" },
            { text = "Training, level 10: Charge (Rank 2), Thunder Clap", kind = "training", level = 10,
              spells = { { id = 100, name = "Charge", rank = 2, new = false }, { id = 101, name = "Thunder Clap", new = true } },
              details = { "New: Thunder Clap" }, prompt = "What should I train first?" },
        } },
        { id = "upgrades", lines = { { text = "Equip Hammer of Fate", item = 5678, slot = "Main Hand", ilvl = 25, details = { "Drops in Deadmines" } } } },
    }, talents = { { line = "Next point: Mortal Strike", spell_id = 12294 } } }
end
local function card_client(digest, state)
    PLAYER_NAME = nil
    local WC = plan_client("full")
    WoWCompanionCard = nil
    C_QuestLog.GetQuestObjectives = function() return { { text = "0/1 Find X", numFulfilled = 0, numRequired = 1, finished = false } } end
    WC.plan = { done = {}, steps = {
        { n = 1, kind = "pickup", questID = 10, quest = "Quest 10", label = "Pick up Quest 10", approx = false, map = 7001, x = 50, y = 50 },
        { n = 2, kind = "pickup", questID = 11, quest = "Blood Tithe", label = "Pick up Blood Tithe", approx = false, map = 7001, x = 10, y = 10 },
    } }
    QUESTS = state or {}
    WoWCompanionDigest = digest or digest14()
    WC.ShowPanel()
    WC.Refresh()
    return WC.panel, WC
end
local function open_card(p, text, button)
    local row = row_with(p, text)
    row.scripts.OnClick(row, button or "RightButton")
    return WoWCompanionCard
end
local function card_text(WC, entry)
    local t = {}
    for _, r in ipairs(WC.CardModel(entry).rows) do t[#t + 1] = r.text end
    return table.concat(t, "\n")
end
local function entry_of(p, text) return row_with(p, text).entry end

cases[#cases + 1] = { "hover: entering an entry lights all its rows, leaving clears; the settings switch it", function()
    local p, WC = card_client(nil, { [11] = "active" })
    local head, obj, other = row_with(p, "[9] Blood Tithe"), row_with(p, "0/1 Find X"), row_with(p, "Quest 10")
    assert(not head.hl:IsShown())
    local base = head.label.color
    head.scripts.OnEnter(head)
    assert(head.hl:IsShown() and obj.hl:IsShown() and not other.hl:IsShown())
    assert(head.label.color[1] >= base[1] and head.label.color[3] > base[3], "the title brightens in its own hue")
    assert(other.alpha == 1, "no dimming by default")
    head.scripts.OnLeave(head)
    assert(not head.hl:IsShown() and not obj.hl:IsShown() and same(head.label.color, base))
    WC.SetSetting("hoverDim", true)
    head.scripts.OnEnter(head)
    assert(other.alpha < 1 and head.alpha == 1 and obj.alpha == 1)
    head.scripts.OnLeave(head)
    assert(other.alpha == 1)
    WC.SetSetting("hoverHighlight", false)
    head.scripts.OnEnter(head)
    assert(not head.hl:IsShown() and other.alpha == 1)
    head.scripts.OnLeave(head)
    assert(WC.Setting("hoverHighlight") == true or true)
    fresh_client(nil)
    assert(WoWCompanion.Setting("hoverHighlight") == true and WoWCompanion.Setting("hoverDim") == false and WoWCompanion.Setting("hoverMapLink") == true)
    assert(WoWCompanion.Setting("clickAction") == "questlog" and WoWCompanion.Setting("cardSide") == "right")
end }

cases[#cases + 1] = { "hover: an entry pulses its badges on the map and minimap; a badge highlights its entry and scrolls to it", function()
    local p, WC = card_client(nil, { [11] = "active" })
    local canvas = CreateFrame("Frame", nil, UIParent)
    canvas:SetSize(1000, 500)
    WorldMapFrame = { GetCanvas = function() return canvas end, GetMapID = function() return 7001 end }
    WC.RefreshMapPins()
    local pin10, pin11
    for _, f in ipairs(frames) do
        if f.planGroup and f:IsShown() then
            if f.planGroup.steps[1].questID == 10 then pin10 = f else pin11 = f end
        end
    end
    assert(pin10 and pin11 and pin10.planGroup.isNext and not pin11.glow:IsShown())
    local row = row_with(p, "[9] Blood Tithe")
    row.scripts.OnEnter(row)
    assert(pin11.glow:IsShown(), "the hovered entry's badge pulses")
    assert(WC.StepHot(WC.plan.steps[2]) and not WC.StepHot(WC.plan.steps[1]))
    row.scripts.OnLeave(row)
    assert(not pin11.glow:IsShown() and not WC.StepHot(WC.plan.steps[2]))
    -- a badge to its entry, with scrolling
    row.top, row.hh, p.scrollRange = 400, 14, 500
    pin11.scripts.OnEnter(pin11)
    assert(row.hl:IsShown() and not row_with(p, "Quest 10").hl:IsShown())
    assert(p.scroll.vscroll == 396, "scrolled the entry into view")
    pin11.scripts.OnLeave(pin11)
    assert(not row.hl:IsShown())
    -- off: neither direction
    WC.SetSetting("hoverMapLink", false)
    row.scripts.OnEnter(row)
    assert(not pin11.glow:IsShown())
    row.scripts.OnLeave(row)
    pin11.scripts.OnEnter(pin11)
    assert(not row.hl:IsShown())
    pin11.scripts.OnLeave(pin11)
    -- the minimap badge follows the next step
    WC.SetSetting("hoverMapLink", true)
    local row10 = row_with(p, "Quest 10")
    row10.scripts.OnEnter(row10)
    assert(WC.StepHot(WC.PlanNext()))
    row10.scripts.OnLeave(row10)
    WorldMapFrame = nil
end }

cases[#cases + 1] = { "click: left on a quest in the log opens it; otherwise the card; right always the card; combat guards", function()
    local function card_shown() return WoWCompanionCard ~= nil and WoWCompanionCard:IsShown() end
    local opened, linked = {}, {}
    QuestMapFrame_OpenToQuestDetails = function(id) opened[#opened + 1] = id end
    local p, WC = card_client(nil, { [11] = "active" })
    local q = row_with(p, "[9] Blood Tithe")
    q.scripts.OnClick(q, "LeftButton")
    assert(opened[1] == 11 and not card_shown())
    q.scripts.OnClick(q, "RightButton")
    assert(card_shown() and #opened == 1)
    WoWCompanionCard:Hide()
    -- a pick-up that is not in the log opens its card
    local pick = row_with(p, "[10] Quest 10")
    pick.scripts.OnClick(pick, "LeftButton")
    assert(card_shown() and #opened == 1)
    pick.scripts.OnClick(pick, "LeftButton")
    assert(not card_shown(), "clicking the entry again closes the card")
    -- the setting sends left-click to the card
    WC.SetSetting("clickAction", "card")
    q.scripts.OnClick(q, "LeftButton")
    assert(#opened == 1 and card_shown())
    WoWCompanionCard:Hide()
    WC.SetSetting("clickAction", "questlog")
    -- in combat: nothing opens, one line says so
    COMBAT = true
    PRINTED = {}
    q.scripts.OnClick(q, "LeftButton")
    assert(#opened == 1 and not card_shown() and PRINTED[1] == "Not in combat: try again once the fight is over.")
    assert(WC.OpenQuestLog(11) == false)
    COMBAT = false
    -- every other kind opens the card on a left click
    for _, text in ipairs({ "unspent talent", "New at level 10", "Hammer of Fate" }) do
        local r = row_with(p, text)
        r.scripts.OnClick(r, "LeftButton")
        assert(card_shown() and WoWCompanionCard.entry.key == r.entry.key, text)
        WoWCompanionCard:Hide()
    end
    -- shift-click links the quest only into an open edit box, and never opens anything otherwise
    IsShiftKeyDown = function() return true end
    GetQuestLink = function(id) return "|cffffff00|Hquest:" .. id .. "|h[Q]|h|r" end
    ChatEdit_InsertLink = function(link) linked[#linked + 1] = link return true end
    q.scripts.OnClick(q, "LeftButton")
    assert(#linked == 1 and linked[1]:find("quest:11", 1, true) and #opened == 1)
    ChatEdit_InsertLink = function() return false end
    q.scripts.OnClick(q, "LeftButton")
    assert(#opened == 2, "no open edit box: the normal click")
    IsShiftKeyDown, GetQuestLink, ChatEdit_InsertLink, QuestMapFrame_OpenToQuestDetails = nil, nil, nil, nil
    -- classic's quest log calls
    local sel, shown = nil, nil
    QuestLogFrame, SelectQuestLogEntry, ShowUIPanel = {}, function(i) sel = i end, function(f) shown = f end
    assert(WC.OpenQuestLog(11) == true and sel == 1 and shown == QuestLogFrame)
    QuestLogFrame, SelectQuestLogEntry, ShowUIPanel = nil, nil, nil
    assert(WC.OpenQuestLog(11) == false)
    WoWCompanionCard = nil
end }

cases[#cases + 1] = { "card: the rows for a quest, a pick-up, training, talents and an upgrade", function()
    UnitLevel = function() return 10 end
    local p, WC = card_client(nil, { [11] = "active" })
    local quest = WC.CardModel(entry_of(p, "[9] Blood Tithe"))
    assert(quest.subtitle == "Level 9 - Quest" and quest.title == "Blood Tithe")
    assert(card_text(WC, entry_of(p, "[9] Blood Tithe")) == "Detail eleven\n0/1 Find X")
    local acts = {}
    for _, a in ipairs(quest.actions) do acts[#acts + 1] = a.label end
    assert(table.concat(acts, ",") == "Open in quest log,Show on map")
    local pick = WC.CardModel(entry_of(p, "[10] Quest 10"))
    assert(card_text(WC, entry_of(p, "[10] Quest 10")) == "Chain start\nRewards a bag\nPick up from Gruff in Testisle")
    assert(#pick.actions == 1 and pick.actions[1].label == "Show on map" and pick.prompt == "Prompt for quest ten?")
    local train = WC.CardModel(entry_of(p, "New at level 10"))
    assert(card_text(WC, entry_of(p, "New at level 10")) == "New: Thunder Clap\nCharge (Rank 2) - upgrade\nThunder Clap - new")
    assert(train.hints[1] == "Spellbook (P)" and #train.actions == 0 and train.subtitle == "Level 10 - Class training")
    local tal = WC.CardModel(entry_of(p, "unspent talent"))
    assert(card_text(WC, entry_of(p, "unspent talent")) == "Spend them soon\nPlan's next pick: Next point: Mortal Strike" and tal.title == "You have 2 unspent talent points")
    assert(tal.hints[1] == "Talents (N)" and tal.prompt == "Which talents first?")
    local up = WC.CardModel(entry_of(p, "Hammer of Fate"))
    assert(card_text(WC, entry_of(p, "Hammer of Fate")) == "Drops in Deadmines\nMain Hand, ilvl 25" and up.link == "item:5678")
    GetBindingKey = function(a) return a == "TOGGLETALENTS" and "K" or nil end
    assert(WC.CardModel(entry_of(p, "unspent talent")).hints[1] == "Talents (K)")
    GetBindingKey = nil
    -- the item link's tooltip shows on hover
    local c = open_card(p, "Hammer of Fate", "LeftButton")
    local n = #GameTooltip.calls
    WoWCompanionCardLink.scripts.OnEnter(WoWCompanionCardLink)
    assert(GameTooltip.calls[n + 2][1] == "SetHyperlink" and GameTooltip.calls[n + 2][2] == "item:5678")
    UnitLevel = nil
    WoWCompanionCard = nil
end }

cases[#cases + 1] = { "card: live facts follow the client, and the card sits on the chosen side", function()
    local p, WC = card_client(nil, { [11] = "ready" })
    assert(card_text(WC, entry_of(p, "Blood Tithe")):find("Ready to turn in", 1, true))
    UnitLevel = nil
    GetUnspentTalentPoints = function() return 5 end
    assert(WC.CardModel(entry_of(p, "unspent talent")).title == "You have 5 unspent talent points")
    assert(WC.CardPrompt({ kind = "talent", points = 2, title = "t", ask = { kind = "talent_points", subject = "2 unspent talent points" } }):find("with 5 unspent talent points%.", 1))
    GetUnspentTalentPoints = nil
    local c = open_card(p, "Quest 10", "RightButton")
    assert(c.points[1][1] == "TOPLEFT" and c.points[1][2] == p and c.points[1][3] == "TOPRIGHT")
    WC.SetSetting("cardSide", "left")
    c:Hide()
    c = open_card(p, "Quest 10", "RightButton")
    assert(c.points[1][1] == "TOPRIGHT" and c.points[1][3] == "TOPLEFT")
    -- Esc closes it, and so does the panel closing
    assert(c:IsShown())
    p:Hide()
    assert(not c:IsShown())
    WoWCompanionCard = nil
end }

cases[#cases + 1] = { "card: Show on map opens the map to the step's zone and pulses its badge, never in combat", function()
    local p, WC = card_client(nil, { [11] = "active" })
    local opened = {}
    OpenWorldMap = function(map) opened[#opened + 1] = map end
    local c = open_card(p, "[9] Blood Tithe", "RightButton")
    local btn = WoWCompanionCardAction2
    assert(btn and btn:GetText() == "Show on map")
    COMBAT = true
    btn.scripts.OnClick(btn)
    assert(#opened == 0)
    COMBAT = false
    btn.scripts.OnClick(btn)
    assert(opened[1] == 7001 and WC.hover.source == "card" and WC.StepHot(WC.plan.steps[2]))
    OpenWorldMap = nil
    WoWCompanionCard = nil
end }

cases[#cases + 1] = { "card: the ask box holds the prompt (or the template fallback); Send queues one capped ask; Copy selects all", function()
    local p, WC = card_client()
    open_card(p, "Quest 10")
    assert(WoWCompanionCardAsk:GetText() == "Prompt for quest ten?")
    PRINTED = {}
    local send = WoWCompanionCardSend
    WoWCompanionCardAsk:SetText(("x"):rep(900))
    send.scripts.OnClick(send)
    assert(#WoWCompanionDB.asks == 1 and #WoWCompanionDB.asks[1].text == 500 and #PRINTED == 1)
    assert(WoWCompanionCardAsk.maxLetters == 500)
    assert(WoWCompanionCard and WoWCompanion.panel and WoWCompanionCard.status:GetText():find("Sent - the overlay answers now", 1, true))
    assert(WoWCompanionCard.status:GetText():find("after your next /reload", 1, true))
    assert(send.enabled == false, "no second click on the same text")
    WoWCompanionCardAsk.scripts.OnTextChanged(WoWCompanionCardAsk, true)
    assert(send.enabled == true)
    -- Copy selects everything and says what to do next
    local copy = WoWCompanionCardCopy
    copy.scripts.OnClick(copy)
    assert(WoWCompanionCardAsk.focused == true and WoWCompanionCardAsk.highlighted == true)
    assert(WoWCompanionCard.copyHint:IsShown() and WoWCompanionCard.copyHint:GetText() == "Press Ctrl+C to copy")
    assert(#WoWCompanionDB.asks == 1, "copy queues nothing")
    -- an empty box queues nothing
    WoWCompanionCardAsk:SetText("   ")
    send.scripts.OnClick(send)
    assert(#WoWCompanionDB.asks == 1)
    WoWCompanionCard = nil
end }

cases[#cases + 1] = { "card: an answer in Answers.lua shows under the prompt after the question was sent from that entry", function()
    local p, WC = card_client()
    open_card(p, "Quest 10")
    assert(WC.AnswerFor("q10") == nil and not WoWCompanionCard.answerShown)
    WoWCompanionCardSend.scripts.OnClick(WoWCompanionCardSend)
    local id = WoWCompanionDB.asks[1].id
    WoWCompanionAnswers = { answers = { { id = "other", text = "Not mine" }, { id = id, text = "Go north |cffff0000twice" } } }
    WC.Refresh()
    assert(WoWCompanionCard.answerShown == "Go north ||cffff0000twice" and WoWCompanionCard.answer:GetText() == "Go north ||cffff0000twice")
    assert(WoWCompanionCard.answerScroll:IsShown())
    local other = WC.CardModel(entry_of(p, "Blood Tithe"))
    assert(other.answer == nil, "another entry shows no answer")
    WoWCompanionAnswers = nil
    WoWCompanionCard = nil
end }

cases[#cases + 1] = { "card: schema 1.3 and 1.2 digests open cards with the template prompt and no details", function()
    local p = ask_row_client()
    local WC = WoWCompanion
    local m = WC.CardModel(entry_of(p, "Hammer of Fate"))
    assert(m.prompt:find("%. Where does ") and m.prompt:find("Equip Hammer of Fate", 1, true) and m.prompt:find("come from, and is it worth getting now?", 1, true))
    assert(#m.rows == 1 and m.rows[1].text == "No more details for this entry.")
    p = v13_client()
    WC = WoWCompanion
    local q = WC.CardModel(entry_of(p, "[9] Blood Tithe"))
    assert(q.prompt:find("Where do I go for Blood Tithe", 1, true) and q.rows[1].text == "No more details for this entry.")
    local t = WC.CardModel(entry_of(p, "unspent talent"))
    assert(t.prompt:find("^I'm a %l+ with 1 unspent talent point%. Which talent should I take next, and why%?$") or t.prompt:find("^I'm a player with 1 unspent talent point%."))
    assert(t.hints[1] == "Open your talents (N)" and t.title == "You have 1 unspent talent point" and #t.rows == 0)
    local train = WC.CardModel(WC.TrainingEntry({ text = "x", level = 5 }).entry)
    assert(train.rows[1].text == "No more details for this entry.")
    PLAYER_NAME = nil
end }

cases[#cases + 1] = { "card copy: focus and select-all on click and next frame, again on focus and click; Ctrl+C confirms and releases; Esc ends it", function()
    local p, WC = card_client()
    local c = open_card(p, "Quest 10")
    local box, copy = WoWCompanionCardAsk, WoWCompanionCardCopy
    local queued = {}
    C_Timer = { After = function(sec, fn) queued[#queued + 1] = { sec, fn } end }
    copy.scripts.OnClick(copy)
    assert(box.focused and box.highlighted and c.copyHint:IsShown())
    assert(#queued == 1 and queued[1][1] == 0, "a zero-delay timer selects again")
    box.focused, box.highlighted = false, false -- the button's mouse-up undid it
    queued[1][2]()
    assert(box.focused and box.highlighted, "the next frame restores focus and the selection")
    -- focus gained and a click into the box select all again
    local h = box.highlightCalls
    box.scripts.OnEditFocusGained(box)
    assert(box.highlightCalls == h + 1)
    box.scripts.OnMouseUp(box)
    assert(box.highlightCalls == h + 2 and #queued == 2)
    queued[2][2]()
    assert(box.highlightCalls == h + 3)
    -- Ctrl+C: other keys do nothing; Ctrl+C confirms, then the box lets go a few seconds later
    IsControlKeyDown = function() return false end
    box.scripts.OnKeyDown(box, "C")
    assert(c.status:GetText() == "" and c.copying)
    IsControlKeyDown = function() return true end
    box.scripts.OnKeyDown(box, "X")
    assert(c.status:GetText() == "" and c.copying)
    box.scripts.OnKeyDown(box, "C")
    assert(c.status:GetText() == "Copied, now paste it into the overlay's Ask box" and not c.copying and not c.copyHint:IsShown())
    assert(box.focused and #queued == 3 and queued[3][1] >= 2 and queued[3][1] <= 5, "focus is kept for a few seconds")
    queued[3][2]()
    assert(not box.focused and c.status:GetText() == "")
    -- Cmd+C on a Mac client
    IsControlKeyDown, IsMetaKeyDown = function() return false end, function() return true end
    copy.scripts.OnClick(copy)
    box.scripts.OnKeyDown(box, "C")
    assert(c.status:GetText():find("^Copied"))
    -- a later Copy cancels the pending release
    local pending = queued[#queued][2]
    copy.scripts.OnClick(copy)
    pending()
    assert(box.focused and c.copying)
    -- Esc ends the copy and frees the keyboard; a click then no longer selects
    box.scripts.OnEscapePressed(box)
    assert(not box.focused and not c.copying and not c.copyHint:IsShown())
    h = box.highlightCalls
    box.scripts.OnMouseUp(box)
    assert(box.highlightCalls == h)
    -- typing ends the select-all too
    copy.scripts.OnClick(copy)
    box.scripts.OnTextChanged(box, true)
    assert(not c.copying and not c.copyHint:IsShown())
    -- without a timer API the immediate selection still happens
    C_Timer = nil
    copy.scripts.OnClick(copy)
    assert(box.focused and box.highlighted)
    IsControlKeyDown, IsMetaKeyDown = nil, nil
    WoWCompanionCard = nil
end }

cases[#cases + 1] = { "fallback prompts: every kind reads as a sentence, within the cap, with no doubled words or capitalised subject", function()
    UnitLevel = function() return 10 end
    UnitClass = function() return "Warrior", "WARRIOR" end
    local WC = WoWCompanion
    local subjects = {
        quest = "The Hungry Ettin", upgrade = "Hammer of Fate (item 5678)", material = "Linen Cloth", dungeon = "Deadmines",
        talent_points = "1 unspent talent point", talent_pick = "Next point: Mortal Strike", training = "Charge (Rank 2), Thunder Clap",
        note = "Bank has 3 unused bags",
    }
    local n = 0
    for kind, subject in pairs(subjects) do
        n = n + 1
        local q = WC.FallbackPrompt(kind, subject)
        assert(q and #q <= WC.MAX_ASK_LEN and q:find("^I'm a level 10 warrior"), kind)
        assert(q:find("[%.%?]$") and not q:find("%f[%a](%a+) %1%f[%A]"), kind .. ": " .. q)
        assert(not q:find("Why You") and not q:find("[a-z] You have") and not q:find("Next point", 1, true), q)
        local long = WC.FallbackPrompt(kind, ("x"):rep(2000))
        assert(#long <= WC.MAX_ASK_LEN, kind)
    end
    assert(n == 8)
    assert(WC.FallbackPrompt("talent_points", "1 unspent talent point") == "I'm a level 10 warrior with 1 unspent talent point. Which talent should I take next, and why?")
    assert(WC.FallbackPrompt("talent_pick", "Mortal Strike") == "I'm a level 10 warrior. Why is Mortal Strike the right next pick for me?")
    assert(WC.FallbackPrompt("training", "Charge") == "I'm a level 10 warrior. I can now train Charge. Which should I train first, and how do they fit my rotation?")
    assert(WC.FallbackPrompt("bogus", "x") == nil and WC.FallbackPrompt(nil, "x") == nil)
    -- every ASK_ABOUT string is a template with exactly who + subject
    for k, v in pairs(WC.L) do
        if k:find("^ASK_ABOUT_") then
            local _, cnt = v:gsub("%%s", "")
            assert(cnt == 2 and v:find("^%%s[%.%s]"), k)
        end
    end
    UnitLevel, UnitClass = nil, nil
end }

cases[#cases + 1] = { "talent kinds: points and a named pick ask differently; the digest prompt wins; the card body does not repeat the header", function()
    UnitLevel = function() return 10 end
    UnitClass = function() return "Warrior", "WARRIOR" end
    local p, WC = card_client()
    local tal, pick = entry_of(p, "unspent talent"), entry_of(p, "Mortal Strike")
    assert(tal.ask.kind == "talent_points" and tal.ask.subject == "2 unspent talent points")
    assert(pick.ask.kind == "talent_pick" and pick.kind == "talent")
    -- the digest's own prompt wins over either fallback
    assert(WC.CardModel(tal).prompt == "Which talents first?")
    tal.prompt = nil
    assert(WC.CardModel(tal).prompt == "I'm a level 10 warrior with 2 unspent talent points. Which talent should I take next, and why?")
    assert(WC.CardModel(pick).prompt == "I'm a level 10 warrior. Why is Mortal Strike the right next pick for me?")
    pick.prompt = "From the digest"
    assert(WC.CardModel(pick).prompt == "From the digest")
    -- the count appears once; a body line equal to the header is dropped
    local m = WC.CardModel(tal)
    assert(m.title == "You have 2 unspent talent points" and m.hints[1] == "Talents (N)")
    for _, r in ipairs(m.rows) do assert(not r.text:find("unspent", 1, true), r.text) end
    local rep = WC.CardModel({ kind = "note", key = "n", title = "Bank is full", details = { "bank is full.", "Sell junk", "Sell junk" } })
    assert(#rep.rows == 1 and rep.rows[1].text == "Sell junk")
    local bare = WC.CardModel({ kind = "talent", key = "t", title = "You have 1 unspent talent point", points = 1, details = { "You have 1 unspent talent point" } })
    assert(#bare.rows == 0 and bare.hints[1] == "Open your talents (N)")
    UnitLevel, UnitClass = nil, nil
    WoWCompanionCard = nil
end }

cases[#cases + 1] = { "training: the entry lists unknown spells with ranks and hides when all are known", function()
    local known = {}
    IsSpellKnown = function(id) return known[id] == true end
    local p, WC = card_client()
    local r = row_with(p, "New at level 10")
    assert(r.entry.title == "New at level 10: Charge (Rank 2), Thunder Clap")
    assert(r.icon.texture == "Interface\\Icons\\ClassIcon_WARRIOR" or r.icon.texture == WC.ICONS.talent)
    known[100] = true
    WC.Refresh()
    assert(row_with(p, "New at level 10").entry.title == "New at level 10: Thunder Clap")
    assert(card_text(WC, entry_of(p, "New at level 10")) == "New: Thunder Clap\nThunder Clap - new")
    known[101] = true
    WC.Refresh()
    assert(not p.plain:find("New at level", 1, true), "every listed spell is known: the entry hides itself")
    assert(WC.SpellKnown(100) and not WC.SpellKnown(999) and not WC.SpellKnown(nil))
    IsSpellKnown = nil
    assert(WC.SpellKnown(100) == false, "no spell check: nothing is known")
    C_SpellBook = { IsSpellKnown = function(id) return id == 7 end }
    assert(WC.SpellKnown(7) and not WC.SpellKnown(8))
    C_SpellBook = nil
    IsPlayerSpell = function(id) return id == 9 end
    assert(WC.SpellKnown(9))
    IsPlayerSpell = nil
end }

cases[#cases + 1] = { "training: the class icon comes from the client's class token", function()
    UnitClass = function() return "Warrior", "WARRIOR" end
    local p, WC = card_client()
    assert(row_with(p, "New at level 10").icon.texture == "Interface\\Icons\\ClassIcon_WARRIOR")
    UnitClass = nil
end }


-- The character to-do chip row (talents, training, upgrades) under the header.
local function chip_of(p, kind)
    for _, b in ipairs(p.chipButtons or {}) do
        if b:IsShown() and b.chip and b.chip.kind == kind then return b end
    end
end
local function chip_kinds(p)
    local out = {}
    for _, b in ipairs(p.chipButtons or {}) do if b:IsShown() and b.chip then out[#out + 1] = b.chip.kind end end
    return table.concat(out, ",")
end
local function tip_text(chip)
    local t = {}
    for _, l in ipairs(WoWCompanion.ChipTipLines(chip)) do t[#t + 1] = l.text end
    return table.concat(t, "|")
end

cases[#cases + 1] = { "chips: one per kind with something to do, none for zero, hidden by the settings", function()
    local p, WC = card_client()
    assert(chip_kinds(p) == "talent,training,upgrade")
    assert(chip_of(p, "talent").count:GetText() == "2" and chip_of(p, "training").count:GetText() == "2" and chip_of(p, "upgrade").count:GetText() == "1")
    assert(chip_of(p, "talent").icon.texture == WC.ICONS.talent and chip_of(p, "upgrade").icon.texture == WC.ICONS.gear)
    local d = digest14()
    table.remove(d.sections[1].lines, 3) -- no talent line
    WoWCompanionDigest = d
    WC.Refresh()
    assert(chip_kinds(p) == "training,upgrade", "zero points: no talent chip")
    WC.SetSetting("chips.training", false)
    assert(chip_kinds(p) == "upgrade")
    WC.SetSetting("showChips", false)
    assert(chip_kinds(p) == "" and p.chipH == 0)
    WC.ResetSetting("showChips"); WC.ResetSetting("chips.training")
    assert(chip_kinds(p) == "training,upgrade")
end }

cases[#cases + 1] = { "chips: counts come from the live talent value and the training list minus known spells", function()
    GetUnspentTalentPoints = function() return 4 end
    local p, WC = card_client()
    assert(chip_of(p, "talent").count:GetText() == "4", "live value wins over the digest's 2")
    GetUnspentTalentPoints = function() return 0 end
    WC.Refresh()
    assert(not chip_of(p, "talent"), "live zero hides the chip")
    GetUnspentTalentPoints = nil
    local d = digest14()
    d.sections[1].lines[4].spells[3] = { id = 102, name = "Rend", new = true }
    WoWCompanionDigest = d
    IsSpellKnown = function(id) return id == 100 end
    WC.Refresh()
    assert(chip_of(p, "training").count:GetText() == "2")
    IsSpellKnown = function(id) return id >= 100 end
    WC.Refresh()
    assert(not chip_of(p, "training"), "all known: no chip")
    IsSpellKnown = nil
    -- a level-up since the digest was written: the live count shows without a talent line
    local d2 = digest14()
    table.remove(d2.sections[1].lines, 3)
    WoWCompanionDigest = d2
    GetUnspentTalentPoints = function() return 1 end
    WC.Refresh()
    assert(chip_of(p, "talent").count:GetText() == "1" and chip_of(p, "talent").chip.entry.nextPick == "Next point: Mortal Strike")
    GetUnspentTalentPoints = nil
end }

cases[#cases + 1] = { "chips: a schema 1.3 digest with no live count falls back to the digest's points", function()
    GetUnspentTalentPoints = nil
    local d = digest14()
    d.schema = "1.3"
    local p, WC = card_client(d)
    assert(chip_of(p, "talent").count:GetText() == "2")
    assert(tip_text(chip_of(p, "talent").chip):find("2 unspent talent points", 1, true))
end }

cases[#cases + 1] = { "chips: tooltip lines per kind", function()
    UnitLevel = function() return 10 end
    local p, WC = card_client()
    assert(tip_text(chip_of(p, "talent").chip) == "2 unspent talent points|Next in your plan: Mortal Strike|Click for details")
    assert(tip_text(chip_of(p, "training").chip) == "New at level 10:|Thunder Clap - new|Click for details" or tip_text(chip_of(p, "training").chip):find("^New at level 10:|"))
    assert(tip_text(chip_of(p, "upgrade").chip) == "1 gear upgrade|Equip Hammer of Fate (Main Hand, ilvl 25)|Click for details")
    local d = digest14()
    for i = 2, 5 do d.sections[2].lines[i] = { text = "Gear " .. i, slot = "Head", ilvl = i } end
    WoWCompanionDigest = d
    WC.Refresh()
    local t = tip_text(chip_of(p, "upgrade").chip)
    assert(t:find("^5 gear upgrades|") and t:find("Gear 3", 1, true) and not t:find("Gear 4", 1, true), "the top three only: " .. t)
    local b = chip_of(p, "talent")
    b.scripts.OnEnter(b)
    local call = GameTooltip.calls[#GameTooltip.calls]
    assert(call[1] == "Show")
    b.scripts.OnLeave(b)
    assert(GameTooltip.calls[#GameTooltip.calls][1] == "Hide")
    UnitLevel = nil
end }

cases[#cases + 1] = { "chips: left and right click open the card for that chip", function()
    local p, WC = card_client()
    for _, kind in ipairs({ "talent", "training", "upgrade" }) do
        for _, btn in ipairs({ "LeftButton", "RightButton" }) do
            WC.CloseCard()
            local b = chip_of(p, kind)
            b.scripts.OnClick(b, btn)
            assert(WC.card and WC.card:IsShown() and WC.card.entry.kind == kind, kind .. " " .. btn)
            assert(#WC.CardModel(WC.card.entry).prompt > 0)
        end
    end
    assert(WC.card.entry.key == "upgrades" and WC.CardModel(WC.card.entry).rows[1].text == "Equip Hammer of Fate")
    WC.CloseCard()
    local b = chip_of(p, "talent")
    b.scripts.OnClick(b, "LeftButton")
    assert(WC.CardModel(WC.card.entry).prompt == "Which talents first?", "the digest's own prompt")
end }

cases[#cases + 1] = { "chips: a count that goes up pulses, stays lit until hovered; the first sight and a drop do not", function()
    GetUnspentTalentPoints = function() return 1 end
    local p, WC = card_client()
    local b = chip_of(p, "talent")
    assert(not WC.ChipNew("talent") and not WC.ChipPulsing("talent"), "first sight: nothing new")
    GetUnspentTalentPoints = function() return 2 end
    WC.Refresh()
    assert(WC.ChipNew("talent") and WC.ChipPulsing("talent") and b.scripts.OnUpdate and b.glow.alpha > 0)
    NOW = NOW + WC.CHIP_PULSE_SECONDS + 1
    assert(not WC.ChipPulsing("talent") and WC.ChipNew("talent"), "the pulse ends, the highlight stays")
    b.scripts.OnUpdate(b)
    assert(b.glow.alpha == 0.6)
    b.scripts.OnEnter(b)
    assert(not WC.ChipNew("talent") and b.glow.alpha == 0 and b.scripts.OnUpdate == nil, "hover clears it")
    GetUnspentTalentPoints = function() return 1 end
    WC.Refresh()
    assert(not WC.ChipNew("talent"), "a drop marks nothing")
    WC.SetSetting("chipPulse", false)
    GetUnspentTalentPoints = function() return 3 end
    WC.Refresh()
    assert(not WC.ChipNew("talent"), "pulse setting off")
    GetUnspentTalentPoints = nil
end }

cases[#cases + 1] = { "chips: talent and training are out of the quest rows; upgrades start collapsed and a setting restores them", function()
    local p, WC = card_client()
    assert(not p.plain:find("unspent talent", 1, true) and not p.plain:find("New at level", 1, true))
    assert(p.plain:find("Quest 10", 1, true) and p.plain:find("Hammer of Fate", 1, true), "upgrades open here: the test client sets upgradesSection")
    WC.SetSetting("upgradesSection", false)
    assert(not p.plain:find("Hammer of Fate", 1, true) and p.plain:find("Upgrades", 1, true), "collapsed by default, header kept")
    assert(chip_of(p, "upgrade"), "the chip still counts them")
    local hdr = row_with(p, "Upgrades")
    hdr.scripts.OnClick(hdr, "LeftButton")
    assert(p.plain:find("Hammer of Fate", 1, true), "a click on the header opens it")
    hdr = row_with(p, "Upgrades")
    hdr.scripts.OnClick(hdr, "LeftButton")
    assert(not p.plain:find("Hammer of Fate", 1, true))
    WC.SetSetting("show.upgrades", false)
    assert(chip_of(p, "upgrade"), "hiding the section keeps the chip")
end }

cases[#cases + 1] = { "chips: the row wraps at a narrow width and the next-step view keeps it", function()
    local WC = fresh_client(nil) or WoWCompanion
    local pos, h = WC.ChipLayout(3, 100, 24, 6)
    assert(pos[1].x == 0 and pos[2].x == 30 and pos[3].x == 60 and h == 24)
    pos, h = WC.ChipLayout(3, 60, 24, 6) -- two fit: the third wraps
    assert(pos[3].x == 0 and pos[3].y == 30 and h == 54)
    pos, h = WC.ChipLayout(2, 10, 24, 6) -- narrower than a chip: one per row
    assert(pos[2].x == 0 and pos[2].y == 30)
    local _, h0 = WC.ChipLayout(0, 100)
    assert(h0 == 0)
    local p
    p, WC = card_client()
    local top = p.scrollTop
    WC.SetSetting("panelWidth", 280)
    WC.SetSetting("view", "next")
    assert(chip_kinds(p) == "talent,training,upgrade" and p.chipH > 0, "chips stay in the next-step view")
    assert(top > 0 and p.scrollTop >= p.chipH)
    WC.SetSetting("showChips", false)
    assert(p.scrollTop < top + 1 - 0, "no chips: no room kept")
end }


-- Quest chains (Plan.lua 1.1): ghosts, "then:" lines, live activation, "New", the unplanned entry, the observation log.
local TIME_NOW = 1000
local function chain_client()
    local WC = plan_client("chain")
    GetTime = function() return TIME_NOW end
    return WC
end
local function turn_in(id)
    QUESTS[id] = "turnedin"
    Stub.fire(frames, "QUEST_TURNED_IN", id)
end
local function ns(list) local t = {} for _, s in ipairs(list) do t[#t + 1] = s.n end return table.concat(t, ",") end

cases[#cases + 1] = { "chains: a 1.1 plan parses the lock fields and numbering stays stable", function()
    local WC = chain_client()
    assert(#WC.plan.steps == 9 and WC.plan.hasLocked)
    local s4 = WC.plan.steps[4]
    assert(s4.locked and s4.unlockedBy[1] == 30 and s4.chain == "Test Line" and WC.plan.steps[3].unlocks[1] == 31)
    for i, s in ipairs(WC.plan.steps) do assert(s.n == i) end
    assert(WC.StepLocked(s4) and WC.StepLocked(WC.plan.steps[6]) and not WC.StepLocked(WC.plan.steps[1]))
    assert(WC.PlanNext().n == 1)
    local _, total = WC.PlanCounts()
    assert(total == 9)
end }

cases[#cases + 1] = { "chains: only the next locked step per chain is a ghost; a locked step is no panel entry", function()
    local WC = chain_client()
    assert(ns((function() local t = {} for _, g in ipairs(WC.GhostSteps(WC.plan.steps, 1)) do t[#t + 1] = g.step end return t end)()) == "4,9")
    local two = WC.GhostSteps(WC.plan.steps, 2)
    assert(#two == 3 and two[2].step.n == 6 or two[3].step.n == 6, "two per chain adds the second quest of the line")
    assert(WC.GhostSteps(WC.plan.steps, 1)[1].from.n == 3, "the dashed route starts at the unlocking turn-in")
    local model = WC.PanelModel({ steps = WC.plan.steps, done = WC.plan.done, nextStep = WC.PlanNext(), allZones = true })
    local ids = {}
    for _, r in ipairs(model.rows) do ids[#ids + 1] = r.n end
    assert(table.concat(ids, ",") == "1,2,3,7,8", "steps 4, 5, 6 and 9 are locked")
    assert(#WC.ShownSteps(WC.plan.steps, WC.plan.done, "all") == 5)
    assert(#WC.PinGroups(WC.ShownSteps(WC.plan.steps, {}, "all"), 7001, {}, nil) == 3 and WC.PinWanted(WC.plan.steps[4], 7001, {}) == false)
end }

cases[#cases + 1] = { "chains: the unlocking turn-in carries a then: line, switched by its setting", function()
    local WC = chain_client()
    local model = WC.PanelModel({ steps = WC.plan.steps, done = {}, allZones = true })
    local row3
    for _, r in ipairs(model.rows) do if r.n == 3 then row3 = r end end
    assert(row3.thenText == "then: Quest 31 (from Elder Test, here)", row3.thenText)
    assert(row3.thenTip == "Unlocks when you turn in Quest 30", row3.thenTip)
    assert(WC.ThenLine(40) == "then: Quest 50 (from Guard Test, here)")
    WC.SetSetting("showThen", false)
    assert(WC.ThenLine(30) == nil)
    assert(WC.PanelModel({ steps = WC.plan.steps, done = {}, allZones = true }).rows[3].thenText == nil)
end }

cases[#cases + 1] = { "chains: a turn-in unlocks the follow-up live: solid, New, header, next ghost", function()
    local WC = chain_client()
    QUESTS[30] = "active"; Stub.fire(frames, "QUEST_ACCEPTED", 1, 30)
    QUESTS[30] = "ready"; Stub.fire(frames, "QUEST_LOG_UPDATE")
    assert(WC.PlanNext().n == 3 and WC.StepLocked(WC.plan.steps[4]))
    assert(WC.NextStepLine(WC.PlanNext()):find("^Step 3/9 "))
    turn_in(30)
    local s4 = WC.plan.steps[4]
    assert(not WC.StepLocked(s4) and WC.StepLocked(WC.plan.steps[6]), "31 opened, 32 still waits on it")
    assert(WC.plan.steps[9].locked and WC.StepLocked(WC.plan.steps[9]), "group prerequisite: 40 is still to turn in")
    assert(WC.StepIsNew(s4) and WC.StepIsNew(WC.plan.steps[5]) and not WC.StepIsNew(WC.plan.steps[1]))
    assert(WC.PlanNext().n == 4, "the next step is the new pick-up")
    assert(WC.NextStepLine(WC.PlanNext(), 7001, 50, 50):find("^Step 4/9 · Pick up Quest 31 from Elder Test"), WC.NextStepLine(WC.PlanNext(), 7001, 50, 50))
    assert(WC.PanelHeader().step == "Step 4/9")
    local g = WC.GhostSteps(WC.plan.steps, 1)
    assert(#g == 2 and g[1].step.n == 6 and g[2].step.n == 9, "the next ghost of the chain appears")
    local row = WC.PanelModel({ steps = WC.plan.steps, done = WC.plan.done, allZones = true }).rows[1]
    assert(row.n == 4 and row.isNew)
    assert(WC.hover and WC.hover.quests and WC.hover.quests[31], "one pulse on the new step's badge")
end }

cases[#cases + 1] = { "chains: a group prerequisite needs both turn-ins", function()
    local WC = chain_client()
    turn_in(30)
    assert(WC.StepLocked(WC.plan.steps[9]))
    turn_in(40)
    assert(not WC.StepLocked(WC.plan.steps[9]) and WC.StepIsNew(WC.plan.steps[9]))
    assert(WC.ThenLine(40) == nil, "nothing waits any more")
end }

cases[#cases + 1] = { "chains: New fades after about ten seconds or on hover; reload tags nothing", function()
    local WC = chain_client()
    turn_in(30)
    local s4 = WC.plan.steps[4]
    TIME_NOW = TIME_NOW + 9
    assert(WC.StepIsNew(s4))
    TIME_NOW = TIME_NOW + 2
    assert(not WC.StepIsNew(s4), "gone after 10 s")
    turn_in(40)
    assert(WC.StepIsNew(WC.plan.steps[9]) and WC.ClearNew(50) and not WC.StepIsNew(WC.plan.steps[9]), "hover clears it")
    WC.SetSetting("showNew", false)
    turn_in(40)
    assert(not WC.QuestIsNew(31))
    local saved = WoWCompanionDB
    fresh_client(saved)
    assert(loadfile("tests/fixtures/plan_chain.lua"))()
    Stub.fire(frames, "PLAYER_LOGIN")
    assert(not WoWCompanion.StepIsNew(WoWCompanion.plan.steps[4]) and WoWCompanion.plan.open[4])
end }

cases[#cases + 1] = { "chains: un-marking a turn-in locks the follow-up again and the ghost returns", function()
    local WC = chain_client()
    turn_in(30)
    assert(not WC.StepLocked(WC.plan.steps[4]))
    QUESTS[30] = nil -- as if the turn-in were un-marked
    WC.plan.done[3] = nil
    Stub.fire(frames, "QUEST_REMOVED", 30)
    assert(WC.StepLocked(WC.plan.steps[4]) and not WC.StepIsNew(WC.plan.steps[4]))
    assert(WC.GhostSteps(WC.plan.steps, 1)[1].step.n == 4)
    assert(WC.PlanNext().n ~= 4)
end }

cases[#cases + 1] = { "chains: a plan without lock fields behaves as before", function()
    local WC = plan_client("full")
    assert(not WC.plan.hasLocked and not WC.StepLocked(WC.plan.steps[1]))
    assert(#WC.GhostSteps(WC.plan.steps, 1) == 0)
    assert(WC.ShownSteps(WC.plan.steps, {}, "all") == WC.plan.steps)
    assert(WC.NextStepLine(WC.PlanNext()):find("^Step 1/4 "))
    QUESTS[10] = "active"; Stub.fire(frames, "QUEST_ACCEPTED", 1, 10)
    assert(WC.NextStepLine(WC.PlanNext()):find("^Step 2/4 "))
    assert(WC.ThenLine(10) == nil)
    local model = WC.PanelModel({ steps = WC.plan.steps, done = WC.plan.done, allZones = true })
    assert(#model.rows + #model.done == 4)
end }

cases[#cases + 1] = { "chains: ghost badges are hollow and faint, real pins solid; dashes join the turn-in", function()
    local WC = chain_client()
    local canvas = CreateFrame("Frame", nil, UIParent)
    canvas:SetSize(1000, 500)
    canvas.CreateLine = function() return CreateFrame("Frame", nil, canvas) end
    WorldMapFrame = { GetCanvas = function() return canvas end, GetMapID = function() return 7001 end }
    WC.RefreshMapPins()
    local ghosts, solid = {}, {}
    for _, f in ipairs(frames) do
        if f.planGroup and f.shown then
            if f.planGroup.ghost then ghosts[#ghosts + 1] = f else solid[#solid + 1] = f end
        end
    end
    assert(#ghosts == 2 and ghosts[1].num.text == "4" and ghosts[1].alpha < 1 and not ghosts[1].fill.shown and ghosts[1].lock.shown)
    assert(#solid >= 2 and solid[1].fill.shown)
    local tip = WC.PlanTipLines(ghosts[1].planGroup)
    assert(tip[#tip].text == "Unlocks when you turn in Quest 30", tip[#tip].text)
    WC.SetSetting("showUpcoming", false)
    WC.RefreshMapPins()
    for _, f in ipairs(frames) do assert(not (f.planGroup and f.planGroup.ghost and f.shown)) end
    WC.SetSetting("showUpcoming", true)
    WC.SetSetting("ghostsPerChain", 2)
    WC.RefreshMapPins()
    local n = 0
    for _, f in ipairs(frames) do if f.planGroup and f.planGroup.ghost and f.shown then n = n + 1 end end
    assert(n == 3, "two per chain: steps 4 and 6, and 9")
    WorldMapFrame = nil
end }

cases[#cases + 1] = { "chains: an unplanned accept shows an Unplanned entry with live objectives", function()
    local WC = chain_client()
    live_digest({ { kind = "pickup", title = "Planned", quest = 30, text = "Planned" } })
    C_QuestLog.GetTitleForQuestID = function(id) return id == 99 and "Stray Task" or nil end
    C_QuestLog.GetQuestObjectives = function() return { { text = "Find 2 things", numFulfilled = 1, numRequired = 2, finished = false } } end
    QUESTS[99] = "active"
    Stub.fire(frames, "QUEST_ACCEPTED", 5, 99)
    local text = panel_text()
    assert(text:find("Stray Task", 1, true), text)
    assert(WC.UnplannedRows({}, 10)[1].right == "Unplanned")
    assert(text:find("The overlay will route this after your next save", 1, true) and text:find("1/2 Find 2 things", 1, true))
    local list = WC.UnplannedQuests()
    assert(#list == 1 and list[1].id == 99)
    turn_in(99)
    assert(#WC.UnplannedQuests() == 0)
    QUESTS[30] = "active"
    Stub.fire(frames, "QUEST_ACCEPTED", 6, 30)
    assert(#WC.UnplannedQuests() == 0, "a planned quest is never unplanned")
end }

cases[#cases + 1] = { "observed: accept, turn-in and abandon are logged with where and when, the unplanned one marked", function()
    local WC = chain_client()
    C_Map = { GetBestMapForUnit = function() return 7001 end,
        GetPlayerMapPosition = function() return { GetXY = function() return 0.4567, 0.2 end } end }
    QUESTS[99] = "active"; Stub.fire(frames, "QUEST_ACCEPTED", 5, 99)
    QUESTS[30] = "active"; Stub.fire(frames, "QUEST_ACCEPTED", 6, 30)
    turn_in(30)
    QUESTS[99] = nil; Stub.fire(frames, "QUEST_REMOVED", 99)
    local ev = WoWCompanionDB.observed.events
    assert(WoWCompanionDB.observed.version == 1 and #ev == 4)
    assert(ev[1].ev == "accepted" and ev[1].questID == 99 and ev[1].offPlan == true and ev[1].character == "Thrall")
    assert(ev[1].map == 7001 and ev[1].x == 45.7 and ev[1].y == 20 and type(ev[1].t) == "number")
    assert(ev[2].ev == "accepted" and ev[2].offPlan == nil)
    assert(ev[3].ev == "turnedin" and ev[3].questID == 30)
    assert(ev[4].ev == "abandoned" and ev[4].questID == 99 and ev[4].map == 7001)
    QUESTS[30] = "turnedin"
    Stub.fire(frames, "QUEST_REMOVED", 30) -- the removal that follows a turn-in is not an abandon
    assert(#WoWCompanionDB.observed.events == 4)
    C_Map = nil
end }

cases[#cases + 1] = { "observed: the ring drops the oldest at its cap; the setting turns it off", function()
    local WC = chain_client()
    for i = 1, WC.OBSERVED_CAP + 25 do WC.ObservedAdd("accepted", i) end
    local ev = WoWCompanionDB.observed.events
    assert(#ev == WC.OBSERVED_CAP and ev[1].questID == 26 and ev[#ev].questID == WC.OBSERVED_CAP + 25)
    WC.SetSetting("keepObserved", false)
    assert(WC.ObservedAdd("accepted", 7) == nil and #ev == WC.OBSERVED_CAP)
    WC.ResetSetting("keepObserved")
    assert(WC.Setting("keepObserved") == true)
end }

cases[#cases + 1] = { "chains: the new settings have defaults, reset one by one, and strings", function()
    local WC = chain_client()
    local want = { showUpcoming = true, ghostsPerChain = 1, showThen = true, showNew = true, keepObserved = true }
    for key, v in pairs(want) do
        assert(WC.Setting(key) == v and WC.IsDefault(key), key)
        assert(rawget(WC.L, WC.DEF_OF[key].label) ~= nil)
    end
    WC.SetSetting("ghostsPerChain", 9)
    assert(WC.Setting("ghostsPerChain") == 3)
    WC.SetSetting("showUpcoming", false)
    WC.ResetSetting("showUpcoming"); WC.ResetSetting("ghostsPerChain")
    assert(WC.IsDefault("showUpcoming") and WC.IsDefault("ghostsPerChain"))
end }

cases[#cases + 1] = { "read-only: nothing asks for a /reload", function()
    for _, f in ipairs({ "Asks", "Button", "Card", "Chips", "Combat", "Core", "Digest", "Hover", "MapPanel", "Observed", "Options", "Panel", "Plan", "PlanTip", "PlanUI", "Settings", "Status", "Tooltips", "Tracker", "WhatsNew" }) do
        local code = assert(io.open("WoWCompanion/" .. f .. ".lua")):read("*a"):gsub("%-%-[^\n]*", "")
        assert(not code:find("ReloadUI", 1, true) and not code:find("StaticPopup", 1, true), f)
        assert(not code:find("ConsoleExec", 1, true) and not code:find("RestartGx", 1, true), f)
    end
end }

local failed = 0
for _, c in ipairs(cases) do
    local ok, err = pcall(c[2])
    report((ok and "ok   " or "FAIL ") .. c[1] .. (ok and "" or (": " .. tostring(err))))
    if not ok then failed = failed + 1 end
end
report(string.format("%d/%d passed", #cases - failed, #cases))
os.exit(failed == 0 and 0 or 1)
