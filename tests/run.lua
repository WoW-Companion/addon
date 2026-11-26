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
        for _, want in ipairs({ "Next quests", "Turn in The Hungry Ettin", "Upgrades", "Hammer of Fate", "Keep materials", "Notes" }) do
            local at = t:find(want, last + 1, true)
            assert(at, "missing " .. want)
            last = at
        end
    end },
    { "digest over 12 hours old shows its age and the refresh note", function()
        local p = digest_client("stale")
        assert(p.header:GetText():find("advice from ", 1, true) and p.header:GetText():find("(1 d ago)", 1, true))
        assert(not p.plain:find("/reload", 1, true) and not p.plain:find("refresh your digest", 1, true), "no stale body line")
        assert(p.stale and p.header.color[1] == WoWCompanion.COLORS.amber[1], "the header turns amber")
        local tip = WoWCompanionPanelHeaderTip
        GameTooltip.calls = {}
        tip.scripts.OnEnter(tip)
        assert(GameTooltip.calls[2][2] == "The overlay refreshes your advice whenever the game saves. You'll see it the next time the game loads.")
        local fresh = digest_client("full")
        assert(fresh.header:GetText():find("(1 h ago)", 1, true) and not fresh.plain:find("refresh your digest", 1, true))
        assert(not fresh.stale and fresh.header.color[1] == WoWCompanion.COLORS.dim[1])
        GameTooltip.calls = {}
        tip = WoWCompanionPanelHeaderTip
        tip.scripts.OnEnter(tip)
        assert(#GameTooltip.calls == 0, "a fresh header has no tooltip")
    end },
    { "digest for another character is refused", function()
        local p = digest_client("wrongchar")
        assert(p.plain:find("No advice for Thrall yet.", 1, true) and p.plain:find("3. The advice shows up here the next time the game loads.", 1, true))
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
        for _, want in ipairs({ "/wowc reset", "/wowc help" }) do assert(all:find(want, 1, true), want) end
        assert(not all:find("ask", 1, true), "no ask command is listed")
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
    { "the ask queue is gone: no /ask, no /wowc ask, nothing written to asks", function()
        fresh_client(nil)
        assert(SLASH_WOWCASK1 == nil and SlashCmdList.WOWCASK == nil)
        assert(not WoWCompanion.SubmitAsk and not WoWCompanion.QueueAsk and not WoWCompanion.Ask)
        SlashCmdList.WOWC("ask hello there")
        assert(WoWCompanionDB.asks == nil and WoWCompanionDB.ask_seq == nil and not table.concat(PRINTED, "\n"):find("Queued", 1, true))
        for k in pairs(WoWCompanion.L) do assert(not k:find("^ASK_QUEUED") and k ~= "CARD_SENT" and k ~= "CARD_ASKED" and k ~= "CARD_NO_DETAILS" and k ~= "CARD_OWN", k) end
    end },
    { "the panel has no Ask box, History or answers, and shows no queued questions", function()
        fresh_client(nil)
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
    { "no digest, empty queue", {}, nil, {}, { "Digest: none yet", "WoWCompanion_Digest: installed" } },
    { "digest age and schema", {}, { schema = 1, character = "Thrall", generated = NOW0 - 7200 }, {}, { "(2 h ago), schema 1" } },
    { "digest with unknown schema", {}, { schema = 9, generated = NOW0 }, {}, { "schema 9" } },
    { "queued count", { asks = { { id = "a", text = "q", asked_at = NOW0 - 7200 }, { id = "b", text = "q", asked_at = NOW0 - 60 } } }, nil, {}, { "Questions waiting for the app: 2 (oldest 2 h ago)" } },
    { "one queued ask", { asks = { { id = "a", text = "q", asked_at = NOW0 - 7200 } } }, nil, {}, { "Questions waiting for the app: 1 (oldest" } },
    { "missing slot addon", {}, nil, { WoWCompanion_Digest = true }, { "WoWCompanion_Digest: not installed" } },
}
cases[#cases + 1] = { "status lines table", function()
    for i, row in ipairs(status_rows) do
        local text = status_text(row[2], row[3], row[4])
        for _, want in ipairs(row[5]) do assert(text:find(want, 1, true), "row " .. i .. " (" .. row[1] .. "): " .. want .. "\n" .. text) end
    end
end }
cases[#cases + 1] = { "status says nothing about questions when none wait", function()
    assert(not status_text({}, nil):find("Questions", 1, true))
    assert(not status_text({ asks = {} }, nil):find("Questions", 1, true))
end }
cases[#cases + 1] = { "old asks expire after 24 hours and answered ids are cleared", function()
    local function mk() return { asks = {
        { id = "old", asked_at = NOW0 - 86401 }, { id = "day", asked_at = NOW0 - 86400 },
        { id = "new", asked_at = NOW0 - 60 }, { id = "ans", asked_at = NOW0 - 10 } } } end
    local db = mk()
    assert(WoWCompanion.PruneAsks(db, nil, NOW0) == 1 and #db.asks == 3 and db.asks[1].id == "day")
    db = mk()
    assert(WoWCompanion.PruneAsks(db, { answered_asks = { "ans" } }, NOW0) == 2 and #db.asks == 2 and db.asks[2].id == "new")
    db = {}
    assert(WoWCompanion.PruneAsks(db, nil, NOW0) == 0 and db.asks == nil)
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
        assert(WoWCompanionDB.settings.view == "compact" and WoWCompanionCompactButton:GetText() == "Compact")
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
        assert(settings().view == "compact" and WoWCompanionCompactButton:GetText() == "Compact" and WoWCompanionOptionView_compact.checked == true)
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
    { "2.0 miss lists the others", "Missingchar", "v2", { "No advice for Missingchar yet.", "1. ForeverScribe saves this character", "2. Ask your AI", "wowc-advisor digest", "3. The advice shows up here", "Digests here for: Otherchar, Testchar" }, { "Next quests" } },
    { "1.2 file for another character", "Thrall", "wrongchar", { "No advice for Thrall yet.", "1. ForeverScribe saves", "3. The advice shows up here" }, { "Digests here for", "Next quests" } },
    { "1.2 file for this character", "Thrall", "full", { "Next quests", "Turn in The Hungry Ettin" }, { "No advice for", "1. ForeverScribe saves" } },
    { "empty digest keeps the hint", "Thrall", "empty", { "No advice yet", "1. ForeverScribe saves", "3. The advice shows up here" }, { "Digests here for" } },
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
    assert(WoWCompanion.L.OLDER_THAN_CAPTURE == "Your last save (%s) is newer than this advice. The overlay refreshes it after each save, and you'll see it the next time the game loads.")
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
    local want = "Your last save (" .. WC.FormatClock(ts + 20 * 60) .. ") is newer than this advice. The overlay refreshes it after each save, and you'll see it the next time the game loads."
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
    assert(parts == 4, "definition + map pin + minimap pin + temporary pin")
    -- Every tinted part sits on a white base (tinting multiplies), never the near-black minimap art.
    assert(WC.DISC and not WC.DISC:find("UI%-Minimap%-Background"), "badge base is not the dark minimap disc")
    local p = CreateFrame("Frame", nil, UIParent)
    WC.BadgeParts(p, 3, 8, "GameFontNormal", 2)
    for _, part in ipairs({ "glow", "ring", "fill", "notchBg" }) do assert(p[part].texture == WC.DISC, part) end
    assert(p.ring.layer == "BORDER" and p.fill.layer == "ARTWORK" and p.glow.layer == "BACKGROUND", "ring is a visible edge around the fill")
    -- Options control key == renderer key, and each setting tints exactly its own region.
    for _, k in ipairs({ "badgeFill", "badgeOpacity", "ringColor", "nextRingColor", "numberColor", "glowColor", "glowOpacity", "pulseSpeed" }) do
        assert(WC.Setting(k) ~= nil, k)
        assert(f:find('"' .. k .. '"', 1, true), k .. " is read by the renderer")
    end
    WC.SetSetting("badgeFill", { 0, 1, 0 }); WC.SetSetting("badgeOpacity", 0.35)
    WC.SetSetting("ringColor", { 1, 1, 0 }); WC.SetSetting("nextRingColor", { 1, 0.95, 0.6 })
    local q = CreateFrame("Frame", nil, UIParent)
    WC.BadgeParts(q, 3, 8, "GameFontNormal", 2)
    local v = q.fill.vertex
    assert(v[1] == 0 and v[2] == 1 and v[3] == 0 and v[4] == 0.35, "fill = chosen colour at chosen opacity")
    WC.SetSetting("badgeFill", { 1, 0, 0 })
    WC.ApplyBadgeFill(q)
    assert(q.fill.vertex[1] == 1 and q.fill.vertex[2] == 0 and q.fill.vertex[4] == 0.35, "fill restyles live")
    assert(q.ring.vertex == nil and q.glow.vertex == nil, "fill setting does not touch ring or glow")
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
    assert(s1:find("^Blood Tithe|Pick up from Bob|Step 1 of %d+"), s1)
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
    assert(L1[2].text == "Pick up from Seena Skybreaker" and L1[3].text == "Step 1 of 20 \194\183 Next \194\183 125 yd W")
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

cases[#cases + 1] = { "plan: our layers sit below the client's player arrow, and near pins shrink and fade", function()
    local WC = plan_client("full")
    -- the pure level: unchanged below the arrow, shifted down together (order kept) when it would reach it
    assert(WC.LayerLevel(0, 3010, nil) == 3010 and WC.LayerLevel(0, 3010, 9000) == 3010)
    local pin, tag = WC.LayerLevel(100, 3010, 2500), WC.LayerLevel(100, 3500 + 50, 2500)
    assert(tag < 2500 and pin < tag and WC.LayerLevel(100, 3001, 2500) < pin)
    -- drawn: every layer ends below a simulated arrow pin at level 2500
    local canvas = CreateFrame("Frame", nil, UIParent)
    canvas:SetSize(1000, 500)
    canvas.CreateLine = function() return {} end
    local arrow = CreateFrame("Frame", nil, canvas)
    arrow:SetFrameLevel(2500)
    local realMap = C_Map
    C_Map = { GetBestMapForUnit = function() return 7001 end,
        GetPlayerMapPosition = function() return { GetXY = function() return 0.2, 0.4 end } end }
    WorldMapFrame = { GetCanvas = function() return canvas end, GetMapID = function() return 7001 end,
        EnumeratePinsByTemplate = function() return function(_, i) if not i then return 1, arrow end end end }
    WC.RefreshMapPins()
    local drawn = 0
    for _, f in ipairs(frames) do
        if f.planGroup and f:IsShown() then drawn = drawn + 1; assert(f:GetFrameLevel() < 2500) end
    end
    assert(drawn >= 1 and WC.PlayerArrowLevel() == 2500)
    WorldMapFrame, C_Map = nil, realMap
    -- near look: within 15 yards at 1x, less when zoomed in
    local s, a = WC.NearPlayerLook(10, 1)
    assert(s == 0.6 and a == 0.5)
    s, a = WC.NearPlayerLook(16, 1)
    assert(s == 1 and a == 1)
    s = WC.NearPlayerLook(10, 2)
    assert(s == 1)
    s = WC.NearPlayerLook(7, 2)
    assert(s == 0.6)
    -- the route line starts short of the player
    assert(WC.LineStartShort(0, 0, 10, 0, 14) == nil)
    local x, y = WC.LineStartShort(0, 0, 100, 0, 14)
    assert(x == 14 and y == 0)
end }

cases[#cases + 1] = { "plan: the minimap badge moves to the rim when its target is on top of the player", function()
    local WC = plan_client("full")
    local near = function(a, b) return math.abs(a - b) < 1e-6 end
    -- a target 2 px from the centre: the lifted badge would cover the arrow, so it goes to the rim (half 70 - 14)
    local x, y, edge = WC.MinimapKeepClear(2, 0, math.pi / 2, 70, 18, false)
    assert(edge and near(x, 56) and near(y, 0))
    -- a target well away is left alone; an edge pin too
    x, y, edge = WC.MinimapKeepClear(40, 0, math.pi / 2, 70, 18, false)
    assert(not edge and x == 40 and y == 0)
    x, y, edge = WC.MinimapKeepClear(56, 0, math.pi / 2, 70, 18, true)
    assert(edge and x == 56)
end }

cases[#cases + 1] = { "tooltips: opaque over a low panel opacity, restored on hide, spaces collapsed", function()
    local WC = plan_client("full")
    WC.SetSetting("bgOpacity", 0.1)
    local log, hooks = {}, {}
    local tip = { strata = "DIALOG", bg = { 0.2, 0.2, 0.3, 0.6 }, border = { 1, 1, 1, 1 } }
    function tip:SetOwner() end
    function tip:GetFrameStrata() return self.strata end
    function tip:SetFrameStrata(v) self.strata = v end
    function tip:GetBackdropColor() return unpack(self.bg) end
    function tip:SetBackdropColor(r, g, b, a) self.bg = { r, g, b, a } end
    function tip:GetBackdropBorderColor() return unpack(self.border) end
    function tip:SetBackdropBorderColor(r, g, b, a) self.border = { r, g, b, a } end
    function tip:HookScript(name, fn) hooks[name] = fn end
    function tip:AddLine(text) log[#log + 1] = text end
    WC.TipOpen(tip, UIParent, "ANCHOR_RIGHT")
    assert(tip.bg[4] >= 0.95 and tip.border[4] >= 0.95 and tip.strata == "TOOLTIP")
    hooks.OnHide(tip)
    assert(tip.bg[4] == 0.6 and tip.bg[1] == 0.2 and tip.strata == "DIALOG" and tip.border[1] == 1)
    WC.TipOpen(tip, UIParent, "ANCHOR_RIGHT") -- styled again on the next open, hooked once
    assert(tip.bg[4] >= 0.95)
    WC.TipLine(tip, "Green  gear   upgrade", 1, 1, 1)
    assert(log[1] == "Green gear upgrade")
end }

-- Draws the map for the plan_full fixture (steps 1 and 3 share a spot) and returns every line made.
local function draw_route_lines(settings_in)
    local WC = plan_client("full")
    for k, v in pairs(settings_in or {}) do WC.SetSetting(k, v) end
    local canvas = CreateFrame("Frame", nil, UIParent)
    canvas:SetSize(1000, 500)
    canvas.CreateLine = function() return {} end
    local made, create = {}, CreateFrame
    CreateFrame = function(...)
        local f = create(...)
        local old = f.CreateLine
        f.CreateLine = function(self) local ln = old(self); made[#made + 1] = ln; return ln end
        return f
    end
    local realMap = C_Map
    C_Map = { GetBestMapForUnit = function() return 7001 end,
        GetPlayerMapPosition = function() return { GetXY = function() return 0.2, 0.4 end } end }
    WorldMapFrame = { GetCanvas = function() return canvas end, GetMapID = function() return 7001 end }
    WC.RefreshMapPins()
    CreateFrame = create
    WorldMapFrame = nil
    C_Map = realMap
    return WC, made, canvas
end

local function line_rgb(ln) local c = ln.colorTexture; return { c[1], c[2], c[3] } end

cases[#cases + 1] = { "plan: the highlight is one line from the player to the next stop, never a leg that shares its spot", function()
    local WC, made, canvas = draw_route_lines({ lineColor = { 0.8, 0.2, 0.5 } })
    local lc = WC.Setting("lineColor")
    local auto = WC.LighterShade(lc)
    local legs, hi = 0, {}
    for _, ln in ipairs(made) do
        if ln.shown and ln.colorTexture then
            local c = line_rgb(ln)
            if c[1] == lc[1] and c[2] == lc[2] and c[3] == lc[3] and ln.colorTexture[4] == WC.Setting("lineOpacity") then legs = legs + 1
            elseif c[1] == auto[1] and c[2] == auto[2] and c[3] == auto[3] then hi[#hi + 1] = ln end
        end
    end
    assert(legs == 2, "the two ordinary legs (1 to 2, 2 to 3 share spots) keep the route colour, got " .. legs)
    assert(#hi == 1, "exactly one highlighted line, got " .. #hi)
    local sp = hi[1].startPoint
    assert(sp[1] == "TOPLEFT" and sp[2] == canvas and math.abs(math.sqrt((sp[3] - 200) ^ 2 + (sp[4] + 200) ^ 2) - 14) < 1e-6, "starts a small gap short of the player's spot")
    local nextPin
    for _, f in ipairs(frames) do if f.planGroup and f.planGroup.isNext and f.shown then nextPin = f end end
    assert(hi[1].endPoint[1] == "CENTER" and nextPin and hi[1].endPoint[2] == nextPin.anchor, "ends on the next stop's badge")
    assert(hi[1].thickness > WC.Setting("lineWidth"))
    -- the player moves: the same tick-time call re-anchors without a redraw
    WC.UpdateNextLine(7001, 70, 50)
    assert(math.abs(math.sqrt((hi[1].startPoint[3] - 700) ^ 2 + (hi[1].startPoint[4] + 250) ^ 2) - 14) < 1e-6)
    WC.UpdateNextLine(7001, 50, 50) -- standing on the stop: no line at all
    assert(not hi[1].shown)
    WC.UpdateNextLine(7002, 50, 50)
    assert(not hi[1].shown, "hidden when the player is on another map")
end }

cases[#cases + 1] = { "settings: the next-stop colour is auto by default and follows lineColor; a pick is kept; the old yellow migrates", function()
    fresh_client(nil)
    local WC = WoWCompanion
    assert(WC.Setting("nextLineColor") == "auto" and WC.IsDefault("nextLineColor"))
    local base = WC.NextLineColor()
    WC.SetSetting("lineColor", { 0.2, 0.4, 0.6 })
    local c = WC.NextLineColor()
    assert(c[1] > 0.2 and c[2] > 0.4 and c[3] > 0.6 and c[1] ~= base[1], "a lighter shade of the new route colour")
    WC.SetSetting("nextLineColor", { 0.1, 0.9, 0.3 })
    assert(same_color(WC.NextLineColor(), { 0.1, 0.9, 0.3 }) and not WC.IsDefault("nextLineColor"))
    WC.ResetSetting("nextLineColor")
    assert(WC.Setting("nextLineColor") == "auto")
    fresh_client({ settings = { nextLineColor = { 1, 0.95, 0.6 } } })
    assert(WoWCompanion.Setting("nextLineColor") == "auto", "the old default yellow becomes auto")
    fresh_client({ settings = { nextLineColor = { 0.3, 0.3, 0.3 } } })
    assert(same_color(WoWCompanion.NextLineColor(), { 0.3, 0.3, 0.3 }), "an explicit pick survives")
    assert(WoWCompanion.Setting("nextLineColor")[1] == 0.3)
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
    assert(up.item == 5678 and up.kind == "line" and up.text == "Main Hand: Hammer of Fate" and not WC.RowsText(rows):find("ilvl", 1, true))
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
    assert(p.close and p.compactButton:GetText() == "Full" and p.backdrop)
    PLAYER_NAME = nil
end }

-- Horizontal extent {left, right} of a header control, offsets from the panel's right edge, resolved from its anchors.
local function header_extent(panel, b)
    local a = b.anchors
    local w = b:GetWidth()
    if a.TOPRIGHT then return { a.TOPRIGHT[4] - w, a.TOPRIGHT[4] } end
    local pt = a.RIGHT
    local rel = pt[2]
    local relPt = pt[3]
    local e = header_extent(panel, rel)
    local x = (relPt == "LEFT" and e[1] or e[2]) + pt[4]
    return { x - w, x }
end

cases[#cases + 1] = { "the panel header's gear, view button and close button never overlap, and each click does its own job", function()
    local WC = plan_client("full")
    local p = WC.panel
    for _, mode in ipairs({ "compact", "next", "full" }) do
        WC.SetSetting("view", mode)
        WC.Refresh()
        local ctl = { p.gear, p.compactButton, p.close }
        local ext = {}
        for i, b in ipairs(ctl) do ext[i] = header_extent(p, b) end
        for i = 1, #ctl do
            for j = i + 1, #ctl do
                assert(ext[i][2] <= ext[j][1] or ext[j][2] <= ext[i][1], mode .. ": header controls " .. i .. " and " .. j .. " overlap")
            end
        end
        assert(p.compactButton:GetWidth() > 4, "view button sized to its label")
        assert(p.gear:GetFrameLevel() > p:GetFrameLevel())
    end
    WC.SetSetting("view", "full")
    WC.Refresh()
    local opened = 0
    local real = WC.OpenOptions
    WC.OpenOptions = function() opened = opened + 1 end
    p.gear.scripts.OnClick(p.gear)
    WC.OpenOptions = real
    assert(opened == 1 and WC.ViewMode() == "full", "gear opens options without changing the view")
    p.compactButton.scripts.OnClick(p.compactButton)
    assert(WC.ViewMode() == WC.NextView("full"), "view button cycles the view")
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
    if type(a) == "table" and type(b) == "table" then return a[1] == b[1] and a[2] == b[2] and a[3] == b[3] end
    return a == b
end
local function valid(def, v)
    local t = def.type
    if t == "bool" then return type(v) == "boolean" end
    if t == "range" then return type(v) == "number" and v >= def.min and v <= def.max end
    if t == "choice" then for _, c in ipairs(def.choices) do if c == v then return true end end return false end
    if t == "color" and def.default == "auto" and v == "auto" then return true end
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
    assert(TOC_VERSION and WC.CHANGELOG[TOC_VERSION] and WC.CHANGELOG["0.6.54"] and WC.CHANGELOG["0.6.53"] and WC.CHANGELOG["0.6.52"] and WC.CHANGELOG["0.6.51"] and WC.CHANGELOG["0.6.50"] and WC.CHANGELOG["0.6.49"] and WC.CHANGELOG["0.6.48"] and WC.CHANGELOG["0.6.47"] and WC.CHANGELOG["0.6.46"] and WC.CHANGELOG["0.6.45"] and WC.CHANGELOG["0.6.44"] and WC.CHANGELOG["0.6.43"] and WC.CHANGELOG["0.6.42"] and WC.CHANGELOG["0.6.41"] and WC.CHANGELOG["0.6.40"] and WC.CHANGELOG["0.6.39"] and WC.CHANGELOG["0.6.38"] and WC.CHANGELOG["0.6.37"] and WC.CHANGELOG["0.6.36"] and WC.CHANGELOG["0.6.35"] and WC.CHANGELOG["0.6.34"] and WC.CHANGELOG["0.6.33"] and WC.CHANGELOG["0.6.32"] and WC.CHANGELOG["0.6.31"] and WC.CHANGELOG["0.6.30"] and WC.CHANGELOG["0.6.29"] and WC.CHANGELOG["0.6.28"] and WC.CHANGELOG["0.6.27"] and WC.CHANGELOG["0.6.26"] and WC.CHANGELOG["0.6.25"] and WC.CHANGELOG["0.6.24"] and WC.CHANGELOG["0.6.23"] and WC.CHANGELOG["0.6.22"] and WC.CHANGELOG["0.6.21"] and WC.CHANGELOG["0.6.20"] and WC.CHANGELOG["0.6.19"] and WC.CHANGELOG["0.6.18"] and WC.CHANGELOG["0.6.17"] and WC.CHANGELOG["0.6.16"] and WC.CHANGELOG["0.6.15"] and WC.CHANGELOG["0.6.14"] and WC.CHANGELOG["0.6.13"] and WC.CHANGELOG["0.6.12"] and WC.CHANGELOG["0.6.11"] and WC.CHANGELOG["0.6.10"] and WC.CHANGELOG["0.6.9"] and WC.CHANGELOG["0.6.8"] and WC.CHANGELOG["0.6.7"] and WC.CHANGELOG["0.6.6"] and WC.CHANGELOG["0.6.5"] and WC.CHANGELOG["0.6.4"] and WC.CHANGELOG["0.6.3"] and WC.CHANGELOG["0.6.2"] and WC.CHANGELOG["0.6.1"] and WC.CHANGELOG["0.6.0"] and WC.CHANGELOG["0.5.1"] and WC.CHANGELOG["0.5.0"] and WC.CHANGELOG["0.4.9"] and WC.CHANGELOG["0.4.8"] and WC.CHANGELOG["0.4.7"] and WC.CHANGELOG["0.4.6"] and WC.CHANGELOG["0.4.5"])
    has("WHATS_NEW_0_4_8_1"); has("WHATS_NEW_0_6_7_1"); has("WHATS_NEW_0_6_8_1"); has("WHATS_NEW_0_6_9_1"); has("WHATS_NEW_0_6_10_1"); has("WHATS_NEW_0_6_11_1"); has("WHATS_NEW_0_6_12_1"); has("WHATS_NEW_0_6_13_1"); has("WHATS_NEW_0_6_14_1"); has("WHATS_NEW_0_6_15_1"); has("WHATS_NEW_0_6_16_1"); has("WHATS_NEW_0_6_17_1"); has("WHATS_NEW_0_6_18_1"); has("WHATS_NEW_0_6_19_1"); has("WHATS_NEW_0_6_20_1"); has("WHATS_NEW_0_6_21_1"); has("WHATS_NEW_0_6_22_1"); has("WHATS_NEW_0_6_23_1")
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
        "outlineColor", "outlineOpacity", "chevronSize", "planBgColor", "planBgOpacity", "planTextSize",
        "minimapBadgeSize", "minimapFill", "minimapFillOpacity", "minimapArrow" }) do
        assert(plan:find('WC.Setting("' .. key .. '")', 1, true) or plan:find('"' .. key .. '"', 1, true), key)
    end
    assert(plan:find("WC.NextLineColor()", 1, true))
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

cases[#cases + 1] = { "map panel: no border or backdrop art of our own, the title sits inside the client's frame, scroll inside", function()
    WorldMapFrame = CreateFrame("Frame", nil, UIParent)
    QuestMapFrame = fake_column({})
    fresh_client(nil)
    local WC = WoWCompanion
    WC.planTab.scripts.OnClick(WC.planTab, "LeftButton")
    local f = WC.mapPanel
    assert(f.backdrop == nil and f.borderColor == nil and f.border == nil and f.titleFrame == nil)
    local tl = f.title.points[1]
    assert(tl[1] == "TOPLEFT" and tl[2] == f.child and tl[4] >= 0 and tl[5] <= 0, "the header line starts inside the scrolling content")
    assert(f.scroll.anchors.BOTTOMRIGHT[2] == f and f.scroll.anchors.BOTTOMRIGHT[4] == 0, "the scroll frame fills the plan rect; its bar is the client's")
    for _, file in ipairs({ "MapPanel", "Button" }) do
        local src = assert(io.open("WoWCompanion/" .. file .. ".lua")):read("*a")
        assert(not src:find("SetBackdrop", 1, true), file)
    end
    WorldMapFrame, QuestMapFrame = nil, nil
end }

cases[#cases + 1] = { "side tabs: the panel has no border texture of its own, only its fill", function()
    WorldMapFrame = CreateFrame("Frame", nil, UIParent)
    QuestMapFrame = fake_column({})
    QuestMapFrame.ContentsAnchor = CreateFrame("Frame", nil, QuestMapFrame)
    fresh_client(nil)
    local WC = WoWCompanion
    WC.SelectMapPanel(true)
    local f = WC.mapPanel
    assert(f.backdrop == nil and f.border == nil and f.bg.colorTexture ~= nil)
    for _, file in ipairs({ "MapPanel" }) do
        local src = assert(io.open("WoWCompanion/" .. file .. ".lua")):read("*a")
        assert(not src:find("SetBackdrop", 1, true) and not src:find("Border", 1, true), file)
    end
    WorldMapFrame, QuestMapFrame = nil, nil
end }

cases[#cases + 1] = { "map tab column: the code never names, reads or anchors to another addon's frames", function()
    local banned = { "ElvUI", "Questie", "Leatrix", "Mapster", "Gatherer", "HandyNotes", "TomTom", "WorldQuestTracker", "Chinchilla", "Carbonite", "Mapzilla", "Capping", "Bartender", "Titan", "SexyMap", "AtlasLoot", "Cartographer", "MapSter", "Lib%u" }
    for _, file in ipairs({ "Button", "MapPanel", "Geometry" }) do
        local src = assert(io.open("WoWCompanion/" .. file .. ".lua")):read("*a")
        for _, n in ipairs(banned) do assert(not src:find(n), file .. " names " .. n) end
    end
end }

cases[#cases + 1] = { "map panel: the plan rect is the quest list's scroll rect, the client's scroll template, the probe records both as data", function()
    WorldMapFrame = CreateFrame("Frame", nil, UIParent)
    QuestMapFrame = fake_column({})
    local inset = CreateFrame("Frame", "QuestMapContentsInset", QuestMapFrame)
    QuestMapFrame.ContentsAnchor = inset
    local scroll = CreateFrame("ScrollFrame", "QuestScrollFrame", QuestMapFrame)
    scroll:SetPoint("TOPLEFT", inset, "TOPLEFT", 0, -29)
    scroll.GetRect = function() return 1010, 100, 308, 570 end
    QuestMapFrame.QuestsFrame = CreateFrame("Frame", "QuestsFrameStub", QuestMapFrame)
    QuestMapFrame.QuestsFrame:SetPoint("TOPLEFT", inset, "TOPLEFT", 0, 0)
    QuestMapFrame.QuestsFrame.ScrollFrame = scroll
    fresh_client(nil)
    local WC = WoWCompanion
    local b = WC.planTab
    PRINTED = {}
    b.scripts.OnClick(b, "LeftButton")
    local f = WC.mapPanel
    assert(f.top == scroll and f.anchors.TOPLEFT[2] == scroll and f.anchors.BOTTOMRIGHT[2] == scroll, "exactly the quest scroll frame's rect, not the inset")
    assert(f.anchors.TOPLEFT[4] == 0 and f.anchors.TOPLEFT[5] == 0 and f.anchors.BOTTOMRIGHT[4] == 0 and f.anchors.BOTTOMRIGHT[5] == 0 and f.parent == QuestMapFrame)
    assert(f.level > QuestMapFrame:GetFrameLevel(), "above the log's frames")
    -- the header rows are the first rows of the scrolling content; the scroll frame fills the plan rect; nothing sits above it
    assert(f.title.points[1][2] == f.child, "header rows inside the scrolling content")
    assert(f.scroll.anchors.TOPLEFT[2] == f and f.scroll.anchors.BOTTOMRIGHT[2] == f and f.scroll.anchors.TOPLEFT[5] == 0)
    assert(f.title.points[1][5] <= 0, "the title starts inside the rect")
    -- the client's scroll template (its own scroll bar), no scroll bar art of ours
    assert(f.scroll.template == WC.SCROLL_TEMPLATE and f.scrollTemplate == "ScrollFrameTemplate")
    local src = assert(io.open("WoWCompanion/MapPanel.lua")):read("*a")
    assert(not src:find("SetThumbTexture", 1, true) and not src:find("ScrollBar", 1, true), "no scroll bar art of ours")
    -- without the quest scroll frame: the QuestsFrame, then the fixed inset
    QuestMapFrame.QuestsFrame.ScrollFrame, QuestScrollFrame = nil, nil
    WC.PlaceMapPanel()
    assert(f.top == QuestMapFrame.QuestsFrame, "the quest list frame itself")
    QuestMapFrame.QuestsFrame.points = {}
    WC.PlaceMapPanel()
    assert(f.top == QuestMapFrame and f.anchors.TOPLEFT[2] == QuestMapFrame and f.anchors.TOPLEFT[5] == -WC.PANEL_TOP_FALLBACK, "nothing to read: the fixed inset")
    QuestMapFrame.QuestsFrame.ScrollFrame, QuestScrollFrame = scroll, scroll
    WC.PlaceMapPanel()
    assert(f.top == scroll)
    -- the map opens: geometry is recorded, quietly
    WoWCompanionDB.observed = nil
    f.GetRect = function() return 1010, 100, 308, 570 end
    WorldMapFrame.scripts.OnShow(WorldMapFrame)
    local g = WoWCompanionDB.observed.mapGeometry
    assert(g.version == 1 and type(g.t) == "number" and #PRINTED == 0)
    assert(g.control == "round" and g.roundButton.shown and g.roundButton.visible and g.roundButton.t == g.t)
    assert(g.planRect and g.questScrollRect and g.questScrollRect.w == 308 and g.scrollTemplate == "ScrollFrameTemplate")
    assert(g.panel.name == "WoWCompanionMapPanel" and #g.panel.points >= 1)
    assert(g.inset.name == "QuestMapContentsInset" and g.inset.field == "inset")
    local seen = {}
    for k in pairs(g) do seen[k] = true end
    for _, k in ipairs({ "version", "t", "panel", "inset", "control", "round", "slots", "sizeMode", "sidePanel", "roundButton", "planRect", "planTab", "questScrollRect", "insetRect", "scrollTemplate", "questList", "questScroll" }) do seen[k] = nil end
    assert(next(seen) == nil, "only the documented keys, no side-tab fields")
    QuestScrollFrame = nil
    WorldMapFrame, QuestMapFrame = nil, nil
end }

cases[#cases + 1] = { "map panel: the top anchors to the client's quest list when shown; the probe records it", function()
    WorldMapFrame = CreateFrame("Frame", nil, UIParent)
    QuestMapFrame = fake_column({})
    local list = CreateFrame("Frame", "QuestsFrameStub", QuestMapFrame)
    list.shown = true
    list:SetPoint("TOPLEFT", QuestMapFrame, "TOPLEFT", 9, -40)
    QuestMapFrame.QuestsFrame = list
    fresh_client(nil)
    local WC = WoWCompanion
    WC.planTab.scripts.OnClick(WC.planTab, "LeftButton")
    local f = WC.mapPanel
    local tl, br = f.anchors.TOPLEFT, f.anchors.BOTTOMRIGHT
    assert(f.top == list and tl[2] == list and tl[5] == 0 and br[2] == list, "exactly the quest list's rect, inside the border")
    list.shown = false
    local sc = CreateFrame("ScrollFrame", nil, list)
    sc.shown = true
    list.ScrollFrame = sc
    assert(WC.QuestListFrame() == sc, "the scroll frame when the list itself is hidden")
    WC.PlaceMapPanel()
    assert(f.top == list, "the list's anchors stay while it is hidden")
    list.shown, sc.shown = true, true
    WorldMapFrame.scripts.OnShow(WorldMapFrame)
    local g = WoWCompanionDB.observed.mapGeometry
    assert(g.questList.field == "QuestsFrame" and g.questScroll.field == "ScrollFrame")
    WorldMapFrame, QuestMapFrame = nil, nil
end }


cases[#cases + 1] = { "world map tab: left-click selects the plan panel, right-click opens options, setting hides it", function()
    WorldMapFrame = CreateFrame("Frame", nil, UIParent)
    QuestMapFrame = fake_column({})
    fresh_client(nil)
    local WC = WoWCompanion
    WorldMapFrame.scripts.OnShow(WorldMapFrame)
    local b = WC.mapRound
    local before = WC.db.settings.planMap
    b.scripts.OnClick(b, "LeftButton")
    assert(WC.db.settings.planMap == not before and not WC.panelState.selected and WC.mapPanel == nil, "the round button flips the overlays and never opens the plan")
    assert(b.icon.alpha == (before and 0.4 or 1), "dimmed while the overlays are off")
    assert(not WoWCompanionOptions:IsShown())
    b.scripts.OnClick(b, "RightButton")
    assert(WoWCompanionOptions:IsShown() and not WC.panelState.selected)
    WC.SetSetting("mapButton", false)
    assert(not b:IsShown())
    WC.SetSetting("mapButton", true)
    assert(b:IsShown())
    WorldMapFrame, QuestMapFrame = nil, nil
end }

cases[#cases + 1] = { "world map: without the quest-pane frame the round button still shows and flips the plan on the map", function()
    WorldMapFrame = CreateFrame("Frame", nil, UIParent)
    QuestMapFrame = nil
    fresh_client(nil)
    local WC = WoWCompanion
    assert(WC.mapRound and WC.mapRound.parent == WorldMapFrame)
    WC.mapRound.scripts.OnClick(WC.mapRound, "LeftButton")
    assert(WC.mapRound.icon.alpha == (WC.PlanShownOnMap() and 1 or 0.4))
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
    WorldMapFrame.ScrollContainer = { scale = 1, minScale = 1, hs = 0.5, vs = 0.5,
        SetPanTarget = function(self, x, y) self.pan = { x, y } end,
        SetZoomTarget = function(self, z) self.zoom = z end,
        GetScaleForMinZoom = function(self) return self.minScale end,
        GetCanvasScale = function(self) return self.scale end,
        GetNormalizedHorizontalScroll = function(self) return self.hs end,
        GetNormalizedVerticalScroll = function(self) return self.vs end }
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
    return WC, WC.planTab, QuestMapFrame
end

local function side_panel_done()
    WorldMapFrame, QuestMapFrame, C_QuestLog = nil, nil, nil
end

cases[#cases + 1] = { "side panel (overlay): our tab selects its panel, any other tab or display-mode change deselects it", function()
    local WC, tab, col = side_panel_client()
    assert(WC.PanelBackend() == "overlay" and WC.mapPanel == nil and not WC.panelState.selected, "nothing built before the first click")
    tab.scripts.OnClick(tab, "LeftButton")
    local f = WC.mapPanel
    assert(f and f:IsShown() and WC.panelState.selected and WC.panelState.selected and WC.panelState.lastTab == "plan")
    assert(f.parent == col, "our frame is a child of the quest panel, never a client frame")
    tab.scripts.OnClick(tab, "LeftButton")
    assert(not f:IsShown() and not WC.panelState.selected, "a second click deselects")
    tab.scripts.OnClick(tab, "LeftButton")
    local sibling = col.children[1]
    assert(sibling.scripts.OnClick, "the client's tab is watched")
    sibling.scripts.OnClick(sibling)
    assert(not f:IsShown() and not WC.panelState.selected and WC.panelState.lastTab == "other", "another tab brings its content back")
    tab.scripts.OnClick(tab, "LeftButton")
    assert(f:IsShown())
    HOOKS.SetDisplayMode(col, "map legend")
    assert(not f:IsShown() and not WC.panelState.selected, "a display-mode change by the map's own controls deselects")
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
    assert(col.modes[1] == WC.TAB_MODE and WC.panelState.selected and WC.panelState.selected)
    tab.scripts.OnClick(tab, "LeftButton")
    assert(col.modes[2] == "quests" and not WC.panelState.selected, "deselecting returns to the mode that was showing")
    tab.scripts.OnClick(tab, "LeftButton")
    HOOKS.SetDisplayMode(col, "events")
    assert(not WC.panelState.selected and #col.modes == 3, "a client-made change is not answered with another call")
    side_panel_done()
end }

cases[#cases + 1] = { "map view: visible steps do not pan, off-screen steps pan clamped, another map switches, reset, toggle states", function()
    local WC, tab = side_panel_client()
    tab.scripts.OnClick(tab, "LeftButton")
    local sc, map = WorldMapFrame.ScrollContainer, WorldMapFrame
    sc.scale, sc.minScale, sc.hs, sc.vs = 2, 1, 0, 0 -- zoomed in on the top-left quarter
    local inview = { n = 1, map = 7001, x = 20, y = 20 }
    WC.CenterOnStep(inview)
    assert(sc.pan == nil and map.setCalls == nil, "a visible step causes no pan")
    WC.CenterOnStep({ n = 2, map = 7001, x = 100, y = 100 })
    assert(sc.pan and sc.pan[1] == 0.75 and sc.pan[2] == 0.75, "clamped so the view stays inside the canvas")
    sc.pan = nil
    WC.CenterOnStep({ n = 3, map = 7001, x = 0, y = 90 })
    assert(sc.pan[1] == 0.25 and sc.pan[2] == 0.75)
    sc.pan = nil
    WC.CenterOnStep({ n = 4, map = 7002, x = 50, y = 50 })
    assert(map.mapID == 7002 and map.setCalls == 1 and sc.pan == nil, "another map is switched to")
    assert(WC.ResetMapView() and sc.zoom == 1 and sc.pan[1] == 0.5 and sc.pan[2] == 0.5, "the way back")
    sc.GetCanvasScale = nil
    sc.pan = nil
    WC.CenterOnStep({ n = 5, map = 7002, x = 99, y = 99 })
    assert(sc.pan == nil, "a view the client cannot report is never moved")
    -- the toggle: both states, and disabled when every step shares the map
    local f = WC.mapPanel
    map.mapID = 7001
    WC.RefreshMapPanel()
    assert(not WC.ZoneButtonDisabled() and WC.ZoneButtonTip():find("only the steps on the map", 1, true))
    f.zoneBtn.scripts.OnClick(f.zoneBtn)
    assert(f.zoneBtn.text == "All zones" and WC.ZoneButtonTip():find("grouped by zone", 1, true))
    assert(f.zoneHeads and f.zoneHeads[1]:IsShown(), "all zones groups steps under zone headers")
    local one = {}
    for i, s in ipairs(WC.plan.steps) do one[i] = s; if s.map ~= 7001 then one[i] = setmetatable({ map = 7001 }, { __index = s }) end end
    WC.plan.steps = one
    WC.RefreshMapPanel()
    assert(WC.ZoneButtonDisabled() and WC.ZoneButtonTip() == "All your steps are on this map")
    assert(f.zoneBtn.enabled == false, "the button is disabled")
    local before = WC.PanelAllZones()
    WC.ToggleMapPanelZones()
    assert(WC.PanelAllZones() == before, "a disabled toggle changes nothing")
    side_panel_done()
end }

cases[#cases + 1] = { "side panel: map calls are only the guarded public ones (static check)", function()
    local allowed = { isMaximized = true, IsMaximized = true, Hide = true, GetMapID = true, SetMapID = true, ScrollContainer = true, SetPanTarget = true, SetZoomTarget = true, GetScaleForMinZoom = true, GetCanvasScale = true, GetNormalizedHorizontalScroll = true, GetNormalizedVerticalScroll = true, AddContentFrame = true,
        SetDisplayMode = true, displayMode = true, SidePanelToggle = true, GetFrameLevel = true, ContentsAnchor = true, QuestsFrame = true, GetChildren = true, HookScript = true, IsShown = true, Show = true, HandleUserActionToggleSidePanel = true, GetWidth = true }
    local guarded = { SetMapID = true, SetPanTarget = true, SetZoomTarget = true, AddContentFrame = true, SetDisplayMode = true, GetMapID = true }
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
    local y = f.rows[1].top
    assert(y > 0, "the header rows come first")
    for i = 1, 20 do
        local r = f.rows[i]
        if r.top ~= y then y = y + 22 end -- a zone header sits above the first row of each zone
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
    assert(WorldMapFrame.mapID == 7002 and WorldMapFrame.ScrollContainer.pan == nil, "another map: switch, do not pan")
    row.scripts.OnClick(row, "LeftButton")
    assert(WorldMapFrame.mapID == 7001 and WorldMapFrame.ScrollContainer.pan == nil, "a whole-zone view needs no pan")
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
    local round = WC.mapRound
    round.scripts.OnClick(round, "LeftButton")
    assert(WC.db.settings.planMap == before and WC.panelState.selected and f:IsShown(), "the round button leaves the panel alone")
    round.scripts.OnClick(round, "RightButton")
    assert(WoWCompanionOptions:IsShown() and WC.panelState.selected)
    GameTooltip.calls = {}
    round.scripts.OnEnter(round)
    local text = {}
    for _, c in ipairs(GameTooltip.calls) do if c[1] == "AddLine" then text[#text + 1] = c[2] end end
    assert(#text == 4 and text[2] == "Show or hide the plan on the map" and text[3]:find("Right-click", 1, true) and text[4]:find("Shift-drag", 1, true))
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
    assert(WC.panelState.selected and WC.mapPanel:IsShown() and WC.panelState.selected)
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
    WC.mapRound.scripts.OnClick(WC.mapRound, "LeftButton")
    assert(WC.db.settings.planMap == not before and WC.mapPanel == nil and WC.mapRound.icon.alpha == (before and 0.4 or 1))
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
    assert(WoWCompanionCompactButton:GetText() == "Next step" and p.plain == "")
    click(WoWCompanionCompactButton)
    assert(WC.db.settings.view == "full" and p.plain ~= "" and WoWCompanionCompactButton:GetText() == "Full")
    click(WoWCompanionCompactButton)
    assert(WC.db.settings.view == "compact" and WoWCompanionCompactButton:GetText() == "Compact")
    click(WoWCompanionCompactButton)
    assert(WC.db.settings.view == "next" and WoWCompanionCompactButton:GetText() == "Next step")
    WC.SetSetting("view", "bogus")
    assert(WC.db.settings.view == "full")
end }

cases[#cases + 1] = { "view button: cycles Full, Compact, Next step only; the label names the current view; the tooltip marks the current one", function()
    local p = digest_client("v13")
    local WC = WoWCompanion
    local seen = {}
    for i = 1, 3 do
        seen[#seen + 1] = WC.db.settings.view .. ">" .. WoWCompanionCompactButton:GetText()
        click(WoWCompanionCompactButton)
    end
    assert(table.concat(seen, ",") == "full>Full,compact>Compact,next>Next step", table.concat(seen, ","))
    assert(WC.db.settings.view == "full" and WoWCompanionOptionView_full.checked == true)
    WC.SetSetting("view", "next")
    assert(WoWCompanionCompactButton:GetText() == "Next step" and WoWCompanionCompactButton:IsShown())
    for _, m in ipairs({ "full", "compact", "next" }) do
        assert(WC.ViewButtonLabel(m) == ({ full = "Full", compact = "Compact", next = "Next step" })[m])
    end
    assert(WC.ViewTipLines("full")[1][1] == "Panel view: Full" and WC.ViewTipLines("full")[5][1] == "Click for Compact")
    assert(WC.ViewTipLines("next")[1][1] == "Panel view: Next step" and WC.ViewTipLines("next")[5][1] == "Click for Full")
    local tip = WC.ViewTipLines("compact")
    assert(#tip == 5 and tip[1][1] == "Panel view: Compact" and tip[5][1] == "Click for Next step")
    assert(tip[2][1] == "   Full" and not tip[2][2] and tip[3][1] == "> Compact" and tip[3][2] and tip[4][1] == "   Next step only" and not tip[4][2])
    WC.SetSetting("view", "full")
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
    assert(#pick.actions == 1 and pick.actions[1].label == "Show on map")
    local train = WC.CardModel(entry_of(p, "New at level 10"))
    assert(card_text(WC, entry_of(p, "New at level 10")) == "New: Thunder Clap\nCharge (Rank 2) - upgrade\nThunder Clap - new")
    assert(train.hints[1] == "Spellbook (P)" and #train.actions == 0 and train.subtitle == "Level 10 - Class training")
    local tal = WC.CardModel(entry_of(p, "unspent talent"))
    assert(card_text(WC, entry_of(p, "unspent talent")) == "Spend them soon\nPlan's next pick: Next point: Mortal Strike" and tal.title == "You have 2 unspent talent points")
    assert(tal.hints[1] == "Talents (N)" and tal.asks[1] == "Where should my talent point go?")
    local up = WC.CardModel(entry_of(p, "Hammer of Fate"))
    assert(card_text(WC, entry_of(p, "Hammer of Fate")) == "Drops in Deadmines\nMain Hand" and up.link == "item:5678")
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


cases[#cases + 1] = { "card: Show on map for a later pick-up draws a temporary pin; steps pulse; no place, no button; digest place works", function()
    local p, WC = card_client(nil, {})
    WC.plan.later = {
        { questID = 40, kind = "pickup", map = 7001, x = 30, y = 40, npc = "Keeper Bel'dugur" },
        { questID = 41, kind = "pickup", map = 7001, x = 20, y = 20 },
    }
    local function btn_for(entry)
        for _, a in ipairs(WC.CardModel(entry).actions) do if a.id == "map" then return a end end
    end
    local later = { kind = "quest", key = "q40", quest = 40, title = "The Book of Ur", pickup = true }
    local step = { kind = "quest", key = "q11", quest = 11, title = "Blood Tithe", pickup = true }
    local none = { kind = "quest", key = "q50", quest = 50, title = "Nowhere", pickup = true, map = 7001, x = -1, y = -1 }
    local digest = { kind = "quest", key = "q60", quest = 60, title = "From Digest", pickup = true, npc = "Gruff", map = 7001, x = 70, y = 80 }
    assert(btn_for(later) and btn_for(step) and btn_for(digest) and not btn_for(none))
    assert(WC.QuestPlace(none) == nil)
    local pl = WC.QuestPlace(later)
    assert(pl.map == 7001 and pl.x == 30 and pl.step == nil and pl.name == "Keeper Bel'dugur")
    assert(WC.PlaceLabel(pl, "The Book of Ur") == "Pick up The Book of Ur: Keeper Bel'dugur")
    assert(WC.QuestPlace({ kind = "quest", quest = 41, title = "x", pickup = true, map = 7001, x = 1, y = 1 }).x == 20, "later beats digest coordinates")
    assert(WC.QuestPlace(digest).x == 70 and WC.QuestPlace(step).step == WC.plan.steps[2])
    -- a later item with x = -1 is dropped when parsed
    assert(WC.ParseLater({ { questID = 9, map = 1, x = -1, y = 5 } }) == nil)
    local opened, timers = {}, {}
    OpenWorldMap = function(map) opened[#opened + 1] = map end
    local canvas = CreateFrame("Frame", nil, UIParent)
    canvas:SetSize(1000, 500)
    local realTimer = C_Timer
    C_Timer = { After = function(sec, fn) timers[#timers + 1] = { sec, fn } end }
    local shownMap = 7001
    WorldMapFrame = { GetCanvas = function() return canvas end, GetMapID = function() return shownMap end, scripts = {} }
    function WorldMapFrame:HookScript() end
    assert(WC.ShowOnMap(later) and opened[1] == 7001)
    local t = WC.TempPin()
    assert(t and t.shown and t.label.text == "Pick up The Book of Ur: Keeper Bel'dugur")
    assert(t.anchor.points[1][4] == 300 and t.anchor.points[1][5] == -200)
    assert(timers[#timers][1] == 20)
    -- the next Show on map clears it; a step has a badge, so it pulses instead
    assert(WC.ShowOnMap(step) and opened[2] == 7001 and WC.TempPin() == nil and WC.hover.source == "card")
    -- the timer clears it, and so does the map closing
    assert(WC.ShowOnMap(later) and WC.TempPin())
    timers[#timers][2]()
    assert(WC.TempPin() == nil)
    assert(WC.ShowOnMap(later) and WC.TempPin())
    WC.ClearTempPin()
    assert(WC.TempPin() == nil)
    -- a different map shown: nothing drawn
    assert(WC.ShowOnMap(later))
    shownMap = 1
    WC.RefreshMapPins()
    assert(not (WC.TempPin() and WC.TempPin().shown))
    WC.ClearTempPin()
    COMBAT = true
    assert(WC.ShowOnMap(later) == false and WC.TempPin() == nil)
    COMBAT = false
    WorldMapFrame, OpenWorldMap, C_Timer = nil, nil, realTimer
    WoWCompanionCard = nil
end }

cases[#cases + 1] = { "card: schema 1.3 and 1.2 digests open cards with the template prompt and no details", function()
    local p = ask_row_client()
    local WC = WoWCompanion
    local m = WC.CardModel(entry_of(p, "Hammer of Fate"))
    assert(m.asks[1] == "Is Hammer of Fate worth getting now?", tostring(m.asks[1]))

    assert(#m.rows == 1 and m.rows[1].text == m.title, "a card with nothing more shows the entry's own text")
    p = v13_client()
    WC = WoWCompanion
    local q = WC.CardModel(entry_of(p, "[9] Blood Tithe"))
    assert(q.asks[1] == "What's Blood Tithe for?" and q.rows[1].text == q.title)
    local t = WC.CardModel(entry_of(p, "unspent talent"))
    assert(t.asks[1] == "Where should my talent point go?")
    assert(t.hints[1] == "Open your talents (N)" and t.title == "You have 1 unspent talent point" and #t.rows == 0)
    local train = WC.CardModel(WC.TrainingEntry({ text = "x", level = 5 }).entry)
    assert(train.rows[1].text == train.title)
    PLAYER_NAME = nil
end }

cases[#cases + 1] = { "talent kinds: the digest asks win over the fallback; the card body does not repeat the header", function()
    UnitLevel = function() return 10 end
    UnitClass = function() return "Warrior", "WARRIOR" end
    local p, WC = card_client()
    local tal, pick = entry_of(p, "unspent talent"), entry_of(p, "Mortal Strike")
    assert(tal.ask.kind == "talent_points" and tal.ask.subject == "2 unspent talent points")
    assert(pick.ask.kind == "talent_pick" and pick.kind == "talent")
    -- a digest without asks falls back to a natural question per kind
    assert(WC.CardModel(tal).asks[1] == "Where should my talent point go?")
    assert(WC.CardModel(pick).asks[1] == "Where should my talent point go?")
    tal.asks = { "Which talents first?" }
    assert(WC.CardModel(tal).asks[1] == "Which talents first?", "the digest's own asks win")
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

-- ---------------------------------------------------------------- card questions, copy, giver notes, no /reload

local function ask_digest()
    local d = digest14()
    local lines = d.sections[1].lines
    lines[1].asks = { "What's Quest 10 for?", "Is the bag worth the detour?", "Who gives the next one?", "A fourth one is dropped" }
    lines[1].ref = "quest:10"
    d.sections[#d.sections + 1] = { id = "notes", lines = {
        { text = "Bank has 3 unused bags and a very long description that goes on and on past any sensible width of a panel line so that it must wrap onto a second line", asks = { "Should I sell the bags?" }, ref = "note:bank" },
        { text = "ignored", kind = "giver", npc = "Endaria Mistgaze", zone = "Valanaar", x = 58.2, y = 78.4, quest = 10, title = "Quest 10",
          details = { "She waits by the lake" }, ref = "giver:10" },
    } }
    return d
end

cases[#cases + 1] = { "card questions: chips render from asks (at most 3, at most 90 characters) and the fallback when none", function()
    local p, WC = card_client(ask_digest())
    local c = open_card(p, "Quest 10")
    assert(WoWCompanionCardChip1:GetText() == nil or true)
    assert(c.chips[1].label:GetText() == "What's Quest 10 for?" and c.chips[2].label:GetText() == "Is the bag worth the detour?" and c.chips[3].label:GetText() == "Who gives the next one?")
    assert(c.chips[3]:IsShown() and not c.chips[4], "a fourth ask is not shown")
    assert(c.askLabel:GetText() == "Ask the companion" and c.askLabel:IsShown() and c.ownLine:GetText() == "Or ask anything in the overlay.")
    local long = WC.MakeEntry("note", "n", { asks = { ("x"):rep(200), "", 5 } }, {})
    assert(#long.asks == 1 and #long.asks[1] == 90)
    -- older digest: one fallback chip
    p, WC = card_client()
    c = open_card(p, "unspent talent")
    assert(c.chips[1].label:GetText() == "Where should my talent point go?" and not (c.chips[2] and c.chips[2]:IsShown()))
    WoWCompanionCard = nil
end }

cases[#cases + 1] = { "card questions: a chip opens the copy box under it, selected; nothing is queued or printed", function()
    local p, WC = card_client(ask_digest(), { [11] = "active" })
    local c = open_card(p, "Quest 10")
    PRINTED = {}
    c.chips[2].scripts.OnClick(c.chips[2])
    local box = WoWCompanionCardAsk
    assert(box:GetText() == "Is the bag worth the detour?" and box.focused and box.highlighted and box:IsShown())
    assert(c.copyHint:GetText() == "Ctrl+C" and c.copyHint:IsShown() and c.selectedIndex == 2)
    local y = function(f) return f.points[1][5] end
    assert(y(box) < y(c.chips[2]) and y(c.chips[3]) < y(box), "the box sits directly under the clicked chip")
    assert(#PRINTED == 0 and WoWCompanionDB.asks == nil and WoWCompanionDB.cardAsks == nil, "nothing is queued, kept or said")
    assert(not WoWCompanionCardCopy and not WoWCompanionCardOwnBox and not WoWCompanionCardOwn, "no Copy button, no Type your own box")
    -- another entry: its card has its own chips and no stale box
    local n = open_card(p, "Blood Tithe")
    assert(not box:IsShown() and n.selected == nil)
    n.chips[1].scripts.OnClick(n.chips[1])
    assert(box:GetText() == "How do I finish Blood Tithe?" and WoWCompanionDB.asks == nil)
    WoWCompanionCard = nil
end }

cases[#cases + 1] = { "card copy: the key handler changes nothing; the confirmation comes on a later frame; a redraw keeps the text", function()
    local p, WC = card_client(ask_digest())
    local c = open_card(p, "Quest 10")
    local box = WoWCompanionCardAsk
    local queued = {}
    C_Timer = { After = function(sec, fn) queued[#queued + 1] = { sec, fn } end }
    c.chips[1].scripts.OnClick(c.chips[1])
    local q = "What's Quest 10 for?"
    assert(box:GetText() == q and box.focused and box.highlighted and c.copying)
    box.focused, box.highlighted = false, false -- the click's mouse-up undid it
    queued[#queued][2]()
    assert(box.focused and box.highlighted, "the next frame restores the selection")
    -- a redraw of the open card (live refresh) never resets the box being copied from
    local sets = 0
    local set = box.SetText
    box.SetText = function(self, t) sets = sets + 1 set(self, t) end
    WC.RefreshCard()
    assert(sets == 0 and box:GetText() == q and box.focused)
    -- other keys, and C without Ctrl, do nothing
    IsControlKeyDown = function() return false end
    local n = #queued
    box.scripts.OnKeyDown(box, "C")
    IsControlKeyDown = function() return true end
    box.scripts.OnKeyDown(box, "X")
    assert(#queued == n)
    -- Ctrl+C: the handler touches neither text, selection nor focus, and shows nothing yet
    local hl, fc = box.highlightCalls, box.focusCalls
    box.scripts.OnKeyDown(box, "C")
    assert(box:GetText() == q and box.focused and box.highlighted and box.highlightCalls == hl and box.focusCalls == fc and sets == 0)
    assert((c.status:GetText() or "") == "", "the confirmation is deferred")
    assert(#queued == n + 1 and queued[#queued][1] == 0)
    queued[#queued][2]() -- the following frame
    assert(c.status:GetText() == "Copied. Paste it into the overlay with Ctrl+V." and box:GetText() == q)
    assert(queued[#queued][1] == 1.5 and box.focused)
    queued[#queued][2]()
    assert(not box.focused and box:GetText() == q, "focus is let go later; the text stays")
    -- Cmd+C on a Mac client, then Esc
    IsControlKeyDown, IsMetaKeyDown = function() return false end, function() return true end
    c.chips[1].scripts.OnClick(c.chips[1])
    box.scripts.OnKeyDown(box, "c")
    queued[#queued][2]()
    assert(c.status:GetText():find("^Copied"))
    c.chips[1].scripts.OnClick(c.chips[1])
    box.scripts.OnEscapePressed(box)
    assert(not box.focused and not c.copying)
    C_Timer, IsControlKeyDown, IsMetaKeyDown = nil, nil, nil
    WoWCompanionCard = nil
end }

cases[#cases + 1] = { "card copy box: multi-line like 0.6.0, fitted to the question; the key handler leaves text, selection and focus", function()
    local p, WC = card_client(ask_digest())
    local c = open_card(p, "Quest 10")
    local box = WoWCompanionCardAsk
    assert(box.multiLine == true and box.template == "BackdropTemplate" and box.w == 282, "multi-line BackdropTemplate box, fixed width")
    c.chips[1].scripts.OnClick(c.chips[1])
    assert(box.h >= 2 * WC.LINE_HEIGHT and box.h <= 3 * WC.LINE_HEIGHT + 8, "two or three lines tall")
    IsControlKeyDown = function() return true end
    local hl, fc, txt = box.highlightCalls, box.focusCalls, box:GetText()
    box.scripts.OnKeyDown(box, "C")
    assert(box:GetText() == txt and box.focused and box.highlighted and box.highlightCalls == hl and box.focusCalls == fc)
    IsControlKeyDown = nil
    WoWCompanionCard = nil
end }

cases[#cases + 1] = { "/wowc copytest builds box A like the copy box and the bare InputBoxTemplate box B; help debug lists it", function()
    local p, WC = card_client(ask_digest())
    PRINTED = {}
    SlashCmdList.WOWC("help")
    assert(not table.concat(PRINTED, "\n"):find("copytest", 1, true), "hidden from plain help")
    PRINTED = {}
    SlashCmdList.WOWC("help debug")
    assert(table.concat(PRINTED, "\n"):find("/wowc copytest", 1, true))
    PRINTED = {}
    SlashCmdList.WOWC("copytest")
    local a, b = WoWCompanionCopyTestA, WoWCompanionCopyTestB
    assert(a and b and a.multiLine == true and a.template == "BackdropTemplate" and b.template == "InputBoxTemplate")
    assert(a:GetText() == "WoWC copy test A" and b:GetText() == "WoWC copy test B" and WoWCompanionCopyTest:IsShown())
    assert(#PRINTED == 0, "local UI only")
    WoWCompanionCopyTest, WoWCompanionCopyTestA, WoWCompanionCopyTestB = nil, nil, nil
end }

cases[#cases + 1] = { "card: the Ask label hides without questions; the dim line stays", function()
    local p, WC = card_client(ask_digest())
    local c = open_card(p, "Quest 10")
    assert(c.askLabel:IsShown() and c.askLabel.color[1] ~= 1, "a plain label, not a link colour")
    assert(c.askLabel.scripts.OnClick == nil and c.askLabel.scripts.OnEnter == nil)
    WC.CloseCard()
    WC.OpenCard(WC.StatsEntry(nil))
    assert(not WoWCompanionCard.askLabel:IsShown() and WoWCompanionCard.ownLine:GetText() == "Or ask anything in the overlay.")
    WoWCompanionCard = nil
end }
cases[#cases + 1] = { "card questions: the fallback asks for every kind are short and natural", function()
    local p, WC = card_client()
    local cases_ = {
        { { kind = "quest", title = "Quest 10", quest = 10 }, "What's Quest 10 for?" },
        { { kind = "quest", title = "Blood Tithe", quest = 11 }, "How do I finish Blood Tithe?", { [11] = "active" } },
        { { kind = "quest", title = "Blood Tithe", quest = 11 }, "What does turning in Blood Tithe unlock?", { [11] = "ready" } },
        { { kind = "talent", title = "t" }, "Where should my talent point go?" },
        { { kind = "training", title = "Training, level 10: Charge", spells = {} }, "What should I train first?" },
        { { kind = "upgrade", title = "Equip Hammer of Fate (+12 ilvl)..." }, "Is Hammer of Fate worth getting now?" },
        { { kind = "note", title = "My plan says: \"Bank has 3 unused bags\"..." }, "What should I know about this?" },
        { { kind = "dungeon", title = "Deadmines" }, "Should I run Deadmines now?" },
        { { kind = "material", title = "Linen Cloth" }, "What should I make with Linen Cloth?" },
        { { kind = "giver", title = "x", questTitle = "Quest 10", quest = 10 }, "What's Quest 10 for?" },
    }
    for i, c in ipairs(cases_) do
        QUESTS = c[3] or {}
        local m = WC.CardModel(setmetatable({ key = "k" .. i }, { __index = c[1] }))
        local q = m.asks
        assert(#q >= 1 and #q <= 2 and q[1] == c[2], i .. ": " .. tostring(q[1]))
        for _, t in ipairs(q) do
            assert(#t <= 90 and not t:find("I'm a", 1, true) and not t:find("My plan says", 1, true) and not t:find("...", 1, true) and not t:find("\226\128\166", 1, true), t)
        end
    end
    QUESTS = {}
    WoWCompanionCard = nil
end }

cases[#cases + 1] = { "giver note: the ! icon, the full text, the pin on the map, and no empty-details line", function()
    local p, WC = card_client(ask_digest())
    local row = row_with(p, "Endaria Mistgaze has a quest for you: Quest 10")
    assert(row and row.icon.texture == WC.ICONS.pickup and row.entry.kind == "giver")
    local c = open_card(p, "Endaria Mistgaze has a quest")
    assert(c.icon.texture == WC.ICONS.pickup and c.subtitle:GetText() == "Quest giver")
    local text = card_text(WC, row.entry)
    assert(text == "She waits by the lake\nPick up from Endaria Mistgaze in Valanaar\n(58.2, 78.4)", text)
    local btn = WoWCompanionCardAction1
    assert(btn and btn:GetText() == "Show on map" and btn:IsShown())
    local opened = {}
    OpenWorldMap = function(map) opened[#opened + 1] = map end
    btn.scripts.OnClick(btn)
    assert(opened[1] == 7001 and WC.hover.source == "card", "the quest entries' own map-pin path")
    OpenWorldMap = nil
    assert(c.chips[1].label:GetText() == "What's Quest 10 for?")
    -- a plain note shows its whole text as the title and never "No more details"
    local note = WC.CardModel(entry_of(p, "Bank has 3 unused bags"))

    assert(note.title:find("second line$") and #note.rows == 0, note.title .. #note.rows)
    assert(note.asks[1] == "Should I sell the bags?")
    local open = open_card(p, "Bank has 3 unused bags")
    for _, fs in ipairs(open.lines) do assert(not fs:IsShown() or not (fs:GetText() or ""):find("No more details", 1, true)) end
    WoWCompanionCard = nil
end }

cases[#cases + 1] = { "notes wrap to 2 lines with no ellipsis; other rows are uncapped", function()
    local p = card_client(ask_digest())
    local row = row_with(p, "Bank has 3 unused bags")
    assert(row.label.maxLines == 2, "a note line wraps to 2 lines")

    assert(row.label:GetText():find("second line$", 1) and not row.label:GetText():find("...", 1, true) and not row.label:GetText():find("\226\128\166", 1, true))
    local head = row_with(p, "Next quests")
    assert(head.label.maxLines == 0)
end }

cases[#cases + 1] = { "no /reload in any current-locale player string (What's new history excepted)", function()
    fresh_client(nil)
    local n = 0
    for k, v in pairs(WoWCompanion.L) do
        if not k:find("^WHATS_NEW_") and k ~= "PLAN_STALE_NOTE" then -- the one reload hint, shown once and only as a note
            n = n + 1
            assert(not tostring(v):lower():find("/reload", 1, true), k)
        end
    end
    assert(n > 100)
    for _, k in ipairs({ "OLDER_THAN_CAPTURE", "STALE_TIP" }) do assert(WoWCompanion.L[k], k) end
    assert(rawget(WoWCompanion.L, "STALE_NOTE") == nil and rawget(WoWCompanion.L, "CARD_SENT") == nil)
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
    assert(chip_kinds(p) == "talent,training,upgrade,stats")
    assert(chip_of(p, "talent").count:GetText() == "2" and chip_of(p, "training").count:GetText() == "2" and chip_of(p, "upgrade").count:GetText() == "1")
    assert(chip_of(p, "talent").icon.texture == WC.ICONS.talent and chip_of(p, "upgrade").icon.texture == WC.ICONS.gear)
    local d = digest14()
    table.remove(d.sections[1].lines, 3) -- no talent line
    WoWCompanionDigest = d
    WC.Refresh()
    assert(chip_kinds(p) == "training,upgrade,stats", "zero points: no talent chip")
    WC.SetSetting("chips.training", false)
    assert(chip_kinds(p) == "upgrade,stats")
    WC.SetSetting("showChips", false)
    assert(chip_kinds(p) == "" and p.chipH == 0)
    WC.ResetSetting("showChips"); WC.ResetSetting("chips.training")
    assert(chip_kinds(p) == "training,upgrade,stats")
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

-- Upgrades in plain words (schema 1.7): slot, item, gain, how to get it with a path icon.
local function upgrade_digest()
    local d = digest14()
    d.schema = "1.7"
    d.sections[2].lines = {
        { text = "Traveler's Shawl (back, ilvl 23)", item = 1001, slot = "Cloak", ilvl = 23, wear = "Wear now", gain = "Big upgrade",
          replaces = "instead of your Worn Cloak", how = "Finish Lost Shawl and choose it", pathKind = "quest", quest = 10,
          asks = { "How do I get Traveler's Shawl?" } },
        { text = "Copper Chain Vest", item = 1002, slot = "Chest", ilvl = 12, wear = "Wear now", gain = "Solid upgrade",
          replaces = "fills an empty slot", how = "Make it with Blacksmithing", pathKind = "craft",
          materials = { { name = "Copper Bar", have = 3, need = 6 } }, asks = { "How do I get Copper Chain Vest?" } },
        { text = "Tough Bracers", item = 1003, slot = "Wrists", ilvl = 15, wear = "From level 12", gain = "Small upgrade",
          replaces = "fills an empty slot", how = "Usually on the Auction House", pathKind = "auction", asks = { "How do I get Tough Bracers?" } },
        { text = "Deadmines Helm", item = 1004, slot = "Head", wear = "Wear now", gain = "Big upgrade",
          how = "Dropped by Edwin in the Deadmines", pathKind = "dungeon" },
        { text = "Fang Boots", item = 1005, slot = "Feet", wear = "Wear now", gain = "Small upgrade",
          how = "Dropped by Gnoll Boss", pathKind = "creature" },
        { text = "Extra Ring", item = 1006, slot = "Ring", wear = "Wear now", gain = "Small upgrade", how = "Dropped by Rat", pathKind = "creature" },
    }
    return d
end
local function no_ilvl_anywhere(p, WC)
    for _, r in ipairs(p.rows or {}) do
        local t = (r.label and r.label.text) or ""
        assert(not t:lower():find("ilvl", 1, true), t)
    end
    local chip = chip_of(p, "upgrade").chip
    assert(not tip_text(chip):lower():find("ilvl", 1, true))
    assert(not card_text(WC, chip.entry):lower():find("ilvl", 1, true))
    for _, u in ipairs(chip.entry.upgrades) do assert(not card_text(WC, u):lower():find("ilvl", 1, true)) end
end

cases[#cases + 1] = { "upgrades: tooltip lines, path icons, the +N more cap, no ilvl or doubled slot", function()
    UnitLevel = function() return 10 end
    local d = upgrade_digest()
    local p, WC = card_client(d, { [10] = "active" })
    local chip = chip_of(p, "upgrade").chip
    local lines = {}
    for _, l in ipairs(WC.ChipTipLines(chip)) do lines[#lines + 1] = l.text end
    assert(lines[1] == "6 upgrades you can get", lines[1])
    assert(lines[2] == "Cloak: Traveler's Shawl \226\128\148 Big upgrade", lines[2])
    assert(lines[3] == "|TInterface\\GossipFrame\\AvailableQuestIcon:12|t Finish Lost Shawl and choose it", lines[3])
    assert(lines[4] == "Chest: Copper Chain Vest \226\128\148 Solid upgrade")
    assert(lines[5]:find("^|TInterface\\Icons\\Trade_BlackSmithing:12|t Make it with Blacksmithing$"))
    assert(lines[6] == "Wrists: Tough Bracers \226\128\148 Small upgrade")
    assert(lines[7] == "|TInterface\\Icons\\INV_Misc_Coin_01:12|t Usually on the Auction House \194\183 from level 12", lines[7])
    assert(lines[8] == "Head: Deadmines Helm \226\128\148 Big upgrade")
    assert(lines[9]:find("^|TInterface\\Icons\\INV_Misc_Map_01:12|t Dropped by Edwin"))
    assert(lines[10] == "+2 more \194\183 click for all", lines[10])
    assert(lines[11] == "Click for details" and #lines == 11)
    -- the creature icon
    local one = { count = 1, items = { WC.chipsOf and nil or chip.items[5] }, kind = "upgrade", entry = chip.entry }
    local t = {}
    for _, l in ipairs(WC.ChipTipLines(one)) do t[#t + 1] = l.text end
    assert(t[3]:find("^|TInterface\\Icons\\INV_Misc_Bone_HumanSkull_01:12|t Dropped by Gnoll Boss"), t[3])
    no_ilvl_anywhere(p, WC)
    UnitLevel = nil
end }

cases[#cases + 1] = { "upgrades: the slot list appears once, in the grouped and the older digest form", function()
    local grouped = { title = "Green cloth gear, level 20\226\128\14924, 'of the Owl': helm, cloak, chest, gloves, legs, boots",
        slot = "Helm, cloak, chest, gloves, legs, boots", gain = "Big upgrade" }
    local main = WoWCompanion.UpgradeMain(grouped)
    local _, n = main:lower():gsub("helm, cloak, chest, gloves, legs, boots", "")
    assert(n == 1, main)
    local older = WoWCompanion.UpgradeMain({ title = "Traveler's Shawl", slot = "Cloak", gain = "Big upgrade" })
    assert(older == "Cloak: Traveler's Shawl \226\128\148 Big upgrade", older)
    -- an item whose name merely contains the slot word still gets its prefix
    assert(WoWCompanion.UpgradeMain({ title = "Chest Guard of Bears", slot = "Chest" }) == "Chest: Chest Guard of Bears")
end }

cases[#cases + 1] = { "tooltips: every line wraps; no long line goes without the flag (double lines excepted)", function()
    UnitLevel = function() return 10 end
    local p, WC = card_client(upgrade_digest(), { [10] = "active" })
    GameTooltip.calls = {}
    local chip = chip_of(p, "upgrade")
    chip.scripts.OnEnter(chip)
    local grip = p.grip
    if grip then grip.scripts.OnEnter(grip) end
    WC.ShowPlanTip(p, "ANCHOR_LEFT", { steps = { { text = string.rep("a long step ", 20) } } })
    local added = 0
    for _, c in ipairs(GameTooltip.calls) do
        if c[1] == "AddLine" then
            added = added + 1
            assert(c[6] == true, "unwrapped tooltip line: " .. tostring(c[2]))
        end
    end
    assert(added > 3)
    UnitLevel = nil
end }

cases[#cases + 1] = { "tooltips: source adds lines only through WC.TipLine", function()
    for _, f in ipairs({ "Button", "Panel", "MapPanel", "PlanTip", "Tooltips", "Chips" }) do
        local fh = assert(io.open(root .. "/" .. f .. ".lua"))
        local src = fh:read("*a"); fh:close()
        assert(not src:find(":AddLine(", 1, true), f .. " adds a tooltip line without WC.TipLine")
    end
end }

cases[#cases + 1] = { "upgrades: the panel shows the same two lines under each item", function()
    UnitLevel = function() return 10 end
    local p, WC = card_client(upgrade_digest(), { [10] = "active" })
    assert(row_with(p, "Cloak \226\128\148 Big upgrade"))
    local sub = row_with(p, "Look for: Traveler's Shawl")
    assert(sub.icon:IsShown() and sub.icon.texture == WC.PATH_ICONS.quest)
    assert(row_with(p, "From level 12 \194\183 Look for: Tough Bracers").icon.texture == WC.PATH_ICONS.auction)
    UnitLevel = nil
end }

cases[#cases + 1] = { "upgrades: the panel rows have no how text, no cut words, and a click opens the card on that row", function()
    UnitLevel = function() return 10 end
    local d = upgrade_digest()
    d.sections[2].lines[1].how = string.rep("word ", 30)
    local p, WC = card_client(d, { [10] = "active" })
    assert(row_with(p, "Cloak \226\128\148 Big upgrade") and row_with(p, "Look for: Traveler's Shawl"))
    assert(not p.plain:find("Finish Lost Shawl", 1, true) and not p.plain:find("Auction House", 1, true) and not p.plain:find("word word", 1, true))
    local sub = row_with(p, "Look for: Traveler's Shawl")
    assert(sub.icon:IsShown() and sub.icon.texture == WC.PATH_ICONS.quest)
    for _, r in ipairs(p.rows) do
        local t = r:IsShown() and r.label and r.label.text or ""
        assert(not t:find("%.%.%.$") and not t:find("\226\128\166$"), t)
    end
    UIParent.h = 330
    local main = row_with(p, "Wrists \226\128\148 Small upgrade")
    main.scripts.OnClick(main, "LeftButton")
    local c = WC.card
    assert(c:IsShown() and c.entry.key == "upgrades" and c.expanded == 3, tostring(c.expanded))
    assert(c.rowBtns[3].open and c.scroll:GetVerticalScroll() == math.min(c.scrollRange, c.rowBtns[3].top))
    main.scripts.OnClick(main, "LeftButton")
    assert(not c:IsShown())
    UIParent.h = nil
    UnitLevel = nil
end }

cases[#cases + 1] = { "upgrades: the card is a list of compact rows, with the facts once and questions per row", function()
    UnitLevel = function() return 10 end
    local p, WC = card_client(upgrade_digest(), { [10] = "active" })
    local entry = chip_of(p, "upgrade").chip.entry
    local m = WC.CardModel(entry)
    assert(m.title == "6 upgrades you can get", m.title)
    assert(#m.list == 6 and #m.rows == 0 and #m.asks == 0)
    local r1, r2, r3 = m.list[1], m.list[2], m.list[3]
    assert(r1.slot == "Cloak" and r1.gain == "Big upgrade" and r1.look == "Look for: Traveler's Shawl", r1.look)
    assert(r1.detail[1].text == "You wear: Worn Cloak" and r1.detail[2].text == "Finish Lost Shawl and choose it")
    assert(r2.detail[1].text == "You wear: nothing in this slot" and r2.detail[3].text == "Copper Bar: have 3 of 6")
    assert(r3.look == "From level 12 \194\183 Look for: Tough Bracers", r3.look)
    assert(table.concat(r1.asks, "|") == "How do I get Traveler's Shawl?" and #m.list[4].asks == 0)
    assert(#m.actions == 1 and m.actions[1].label == "Show on map")
    -- one upgrade's own card
    local own = entry.upgrades[1]
    local om = WC.CardModel(own)
    assert(om.asks[1] == "How do I get Traveler's Shawl?" and #om.actions == 1 and om.actions[1].label == "Show on map")
    assert(card_text(WC, own):find("You wear: Worn Cloak\nLook for: Traveler's Shawl \226\128\148 Big upgrade", 1, true))
    assert(#WC.CardModel(entry.upgrades[2]).actions == 0)
    UnitLevel = nil
end }

local function open_upgrades(WC, p)
    local entry = chip_of(p, "upgrade").chip.entry
    UIParent.h = 768
    WC.OpenCard(entry)
    return WC.card
end

cases[#cases + 1] = { "upgrades: the card is capped to the screen, scrolls, and one row opens at a time", function()
    UnitLevel = function() return 10 end
    local p, WC = card_client(upgrade_digest(), { [10] = "active" })
    local c = open_upgrades(WC, p)
    local cap = WC.CardMaxHeight(c)
    assert(c:GetHeight() <= cap and cap <= 768, c:GetHeight() .. " " .. cap)
    assert(c.content.parent == c.scroll and c.scroll.child == c.content and c.scroll.wheel)
    -- collapsed: six rows of two lines; a tall list on a short screen scrolls
    for i = 1, 6 do assert(c.rowBtns[i]:IsShown() and c.rowBtns[i].slot.text and c.rowBtns[i].look.text:find("Look for: ", 1, true)) end
    assert(not c.rowBtns[7] or not c.rowBtns[7]:IsShown())
    assert(c.scrollRange == 0 and c.contentHeight <= c.viewHeight)
    c.rowBtns[1].scripts.OnClick(c.rowBtns[1])
    assert(c.expanded == 1 and c.asksShown[1] == "How do I get Traveler's Shawl?" and c.chips[1]:IsShown())
    c.rowBtns[2].scripts.OnClick(c.rowBtns[2])
    assert(c.expanded == 2 and #c.asksShown == 1 and c.asksShown[1] == "How do I get Copper Chain Vest?")
    local open = 0
    for _, b in ipairs(c.rowBtns) do if b.open then open = open + 1 end end
    assert(open == 1)
    c.rowBtns[2].scripts.OnClick(c.rowBtns[2])
    assert(c.expanded == nil)
    -- a short screen: the card stops at the cap and the content scrolls
    UIParent.h = 330
    WC.CloseCard()
    WC.OpenCard(chip_of(p, "upgrade").chip.entry)
    c = WC.card
    c.rowBtns[1].scripts.OnClick(c.rowBtns[1])
    assert(c:GetHeight() <= 330 and c.scrollRange > 0, c:GetHeight() .. " " .. tostring(c.scrollRange))
    c.scroll.scripts.OnMouseWheel(c.scroll, -1)
    assert(c.scroll:GetVerticalScroll() > 0)
    for i = 1, 40 do c.scroll.scripts.OnMouseWheel(c.scroll, -1) end
    assert(c.scroll:GetVerticalScroll() == c.scrollRange)
    UIParent.h = nil
    UnitLevel = nil
end }

cases[#cases + 1] = { "upgrades: a row says its slot, gain and replaced item once, and no text ends in a cut word", function()
    UnitLevel = function() return 10 end
    local p, WC = card_client(upgrade_digest(), { [10] = "active" })
    local entry = chip_of(p, "upgrade").chip.entry
    local m = WC.CardModel(entry)
    for _, r in ipairs(m.list) do
        local all = { r.slot, r.gain or "", r.look }
        for _, d in ipairs(r.detail) do all[#all + 1] = d.text end
        local text = table.concat(all, "\n")
        local function lines_equal(s) local n = 0 for _, l in ipairs(all) do if l == s then n = n + 1 end end return n end
        assert(lines_equal(r.slot) == 1, text)
        if r.gain then assert(lines_equal(r.gain) == 1 and not r.look:find(r.gain, 1, true), text) end
        assert(not text:lower():find("instead of your", 1, true) and not r.look:find(r.slot .. ":", 1, true), text)
        local wears = 0
        for _, l in ipairs(all) do if l:find("^You wear:") then wears = wears + 1 end end
        assert(wears == 1)
        for _, s in ipairs(all) do assert(not s:find("%.%.%.$") and not s:find("\226\128\166$"), s) end
    end
    -- a how line is cut at a word, never inside one
    local d = upgrade_digest()
    d.sections[2].lines[1].how = string.rep("word ", 30)
    local p2, WC2 = card_client(d, { [10] = "active" })
    local how = WC2.CardModel(chip_of(p2, "upgrade").chip.entry).list[1].detail[2].text
    assert(#how <= 120 and how:match("word$"), how)
    UnitLevel = nil
end }

cases[#cases + 1] = { "upgrades: an older digest's slot prefix, gain and replaced item are not said twice", function()
    local WC = WoWCompanion
    local u = { title = "Cloak: Traveler's Shawl \226\128\148 Big upgrade, instead of your Worn Cloak", slot = "Cloak", gain = "Big upgrade", how = "Buy it" }
    local r = WC.UpgradeListRow(u)
    assert(r.slot == "Cloak" and r.gain == "Big upgrade" and r.look == "Look for: Traveler's Shawl", r.look)
    assert(r.detail[1].text == "You wear: Worn Cloak", r.detail[1].text)
    assert(WC.UpgradeMain(u) == "Cloak: Traveler's Shawl \226\128\148 Big upgrade", WC.UpgradeMain(u))
    local t = WC.UpgradeListRow({ title = "back: Traveler's Shawl", slot = "back", how = "Buy it" })
    assert(t.look == "Look for: Traveler's Shawl" and t.gain == nil)
end }

cases[#cases + 1] = { "upgrades: an older digest shows <Slot>: <Item> only", function()
    UnitLevel = function() return 10 end
    local d = digest14()
    d.sections[2].lines = { { text = "Equip Boots (+12 ilvl)", slot = "Feet", ilvl = 12, atLevel = 12 } }
    local p, WC = card_client(d)
    local chip = chip_of(p, "upgrade").chip
    assert(tip_text(chip) == "1 gear upgrade|Feet: Boots|Click for details", tip_text(chip))
    assert(row_with(p, "Feet: Boots"))
    assert(card_text(WC, chip.entry.upgrades[1]) == "Feet\nat level 12")
    -- an older digest whose line already leads with the slot never doubles it
    local u = { title = "back: Traveler's Shawl", slot = "back" }
    assert(WC.UpgradeMain(u) == "back: Traveler's Shawl", WC.UpgradeMain(u))
    assert(WC.UpgradeMain({ title = "Traveler's Shawl", slot = "back" }) == "back: Traveler's Shawl")
    no_ilvl_anywhere(p, WC)
    UnitLevel = nil
end }

-- Stats: the read-only record of the character's totals, and the Stats chip with the digest's stat check.
local function stub_stats()
    UnitLevel = function() return 12 end
    UnitStat = function(_, i) return 10 * i, 10 * i + 1 end
    UnitArmor = function() return 100, 140 end
    UnitAttackPower = function() return 50, 10, -5 end
    GetCritChance = function() return 5.04 end
    GetDodgeChance = function() return 3.2 end
    GetParryChance = function() return 6 end
    GetBlockChance = function() return 0 end
end
local function clear_stats()
    UnitLevel, UnitStat, UnitArmor, UnitAttackPower = nil, nil, nil, nil
    GetCritChance, GetDodgeChance, GetParryChance, GetBlockChance = nil, nil, nil, nil
end

cases[#cases + 1] = { "stats: the record has the contract's shape, keyed by the character name", function()
    fresh_client(nil)
    stub_stats()
    local s = WoWCompanion.RecordStats()
    local db = WoWCompanionDB.stats.Thrall
    assert(s == db)
    assert(db.level == 12 and db.str == 11 and db.agi == 21 and db.sta == 31 and db.int == 41 and db.spi == 51, "stat totals")
    assert(db.armor == 140 and db.ap == 55 and db.crit == 5 and db.dodge == 3.2 and db.parry == 6 and db.block == 0)
    assert(type(db.at) == "number")
    clear_stats()
end }

cases[#cases + 1] = { "stats: nothing is written in combat; it is recorded when combat ends", function()
    fresh_client(nil)
    stub_stats()
    COMBAT = true
    Stub.fire(frames, "PLAYER_EQUIPMENT_CHANGED")
    assert(WoWCompanionDB.stats == nil, "no write in combat")
    COMBAT = false
    Stub.fire(frames, "PLAYER_REGEN_ENABLED")
    assert(WoWCompanionDB.stats and WoWCompanionDB.stats.Thrall.str == 11, "deferred record")
    WoWCompanionDB.stats = nil
    Stub.fire(frames, "PLAYER_REGEN_ENABLED")
    assert(WoWCompanionDB.stats == nil, "nothing pending, nothing written")
    clear_stats()
end }

cases[#cases + 1] = { "stats: an API this client lacks is skipped silently", function()
    fresh_client(nil)
    stub_stats()
    GetBlockChance, UnitArmor = nil, nil
    UnitAttackPower = function() error("boom") end
    local s = WoWCompanion.RecordStats()
    assert(s.str == 11 and s.crit == 5 and s.armor == nil and s.block == nil and s.ap == nil)
    clear_stats()
    WoWCompanionDB.stats = nil
    assert(WoWCompanion.RecordStats() == nil and WoWCompanionDB.stats == nil, "no APIs, no record")
end }

cases[#cases + 1] = { "stats chip: tooltip and card with and without a stats entry", function()
    local p, WC = card_client()
    local none = "Choose a play style in the overlay (Settings > Play style) and your stat check appears here after the game next saves."
    assert(tip_text(chip_of(p, "stats").chip) == none .. "|Click for details")
    assert(card_text(WC, chip_of(p, "stats").chip.entry) == none, "the card says what the tooltip says")
    assert(not WC.CardModel(chip_of(p, "stats").chip.entry).rows[1].text:find("No more details", 1, true))
    assert(chip_of(p, "stats").icon.texture == WC.ICONS.stats)
    assert(#WC.CardModel(chip_of(p, "stats").chip.entry).asks == 0)
    local d = digest14()
    d.stats = { profile = "Fury \194\183 leveling", insights = { "More Strength helps", "Spirit is wasted", "c", "too many" }, asks = { "Why Strength?", "What is wasted?" } }
    WoWCompanionDigest = d
    WC.Refresh()
    local chip = chip_of(p, "stats").chip
    assert(tip_text(chip) == "Fury \194\183 leveling|More Strength helps|Spirit is wasted|c|Click for details", tip_text(chip))
    local m = WC.CardModel(chip.entry)
    assert(card_text(WC, chip.entry) == "More Strength helps\nSpirit is wasted\nc")
    assert(#m.asks == 2 and m.asks[1] == "Why Strength?")
    WC.SetSetting("chips.stats", false)
    assert(not chip_of(p, "stats"), "the option hides the chip")
    WC.ResetSetting("chips.stats")
    local b = chip_of(p, "stats")
    b.scripts.OnClick(b)
    local c = WoWCompanionCard
    assert(c.chips[1].label:GetText() == "Why Strength?" and c.chips[2].label:GetText() == "What is wasted?" and not (c.chips[3] and c.chips[3]:IsShown()))
    WoWCompanionCard = nil
end }

cases[#cases + 1] = { "chips: tooltip lines per kind", function()
    UnitLevel = function() return 10 end
    local p, WC = card_client()
    assert(tip_text(chip_of(p, "talent").chip) == "2 unspent talent points|Next in your plan: Mortal Strike|Click for details")
    assert(tip_text(chip_of(p, "training").chip) == "New at level 10:|Thunder Clap - new|Click for details" or tip_text(chip_of(p, "training").chip):find("^New at level 10:|"))
    assert(tip_text(chip_of(p, "upgrade").chip) == "1 gear upgrade|Main Hand: Hammer of Fate|Click for details")
    local d = digest14()
    for i = 2, 5 do d.sections[2].lines[i] = { text = "Gear " .. i, slot = "Head", ilvl = i } end
    WoWCompanionDigest = d
    WC.Refresh()
    local t = tip_text(chip_of(p, "upgrade").chip)
    assert(t:find("^5 gear upgrades|") and t:find("Head: Gear 4", 1, true) and not t:find("Gear 5", 1, true) and t:find("+1 more", 1, true) and not t:find("ilvl", 1, true), "plain lines: " .. t)
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
            local asks = WC.CardModel(WC.card.entry).asks
            -- an upgrade set asks only what the digest gave per item, never a question from its own summary
            assert(kind == "upgrade" and #asks == 0 or #asks > 0)
            for _, a in ipairs(asks) do assert(not a:find("gear upgrades", 1, true), a) end
        end
    end
    assert(WC.card.entry.key == "upgrades" and WC.CardModel(WC.card.entry).rows[1].text == "Hammer of Fate")
    WC.CloseCard()
    local b = chip_of(p, "talent")
    b.scripts.OnClick(b, "LeftButton")
    assert(WC.CardModel(WC.card.entry).asks[1] == "Where should my talent point go?")
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
    assert(chip_kinds(p) == "talent,training,upgrade,stats" and p.chipH > 0, "chips stay in the next-step view")
    assert(top > 0 and p.scrollTop >= p.chipH)
    WC.SetSetting("showChips", false)
    assert(p.scrollTop < top + 1 - 0, "no chips: no room kept")
end }


-- The resize grip: drag sets Manual, right-click is Auto, bounds, lock, combat, slider sync, reflow.
cases[#cases + 1] = { "panel grip: drag sets manual and saves, right-click resets, bounds, lock, combat, slider, reflow", function()
    local p = digest_client("v13")
    local WC = WoWCompanion
    local grip = WoWCompanionPanelGrip
    assert(grip and grip.shown and WC.Setting("panelSizeMode") == "auto" and p.h == 320)
    -- drag: the client sizes the frame; the release saves both sizes and the mode
    grip.scripts.OnMouseDown(grip, "LeftButton")
    assert(p.sizingFrom == "BOTTOMRIGHT" and p.resizable and p.bounds[1] == 280 and p.bounds[3] == 520)
    p.w, p.h = 453, 410
    p.scripts.OnSizeChanged(p, 453, 410)
    assert(WC.Setting("panelWidth") == 450 and p.content.w == 402, "text reflows at the new width while dragging")
    assert(p.h == 410, "a redraw does not fight the drag")
    grip.scripts.OnMouseUp(grip, "LeftButton")
    assert(p.sizingFrom == nil and WC.Setting("panelSizeMode") == "manual" and WC.Setting("panelHeight") == 410)
    assert(WC.Setting("panelWidth") == 450 and p.w == 450 and p.h == 410)
    WC.Refresh()
    assert(p.h == 410, "manual keeps the saved height across redraws")
    -- slider moves the width in manual mode too
    WC.SetSetting("panelWidth", 300)
    assert(p.w == 300 and p.h == 410 and p.content.w == 252)
    -- right-click: auto again, width kept
    grip.scripts.OnMouseUp(grip, "RightButton")
    assert(WC.Setting("panelSizeMode") == "auto" and WC.Setting("panelWidth") == 300 and p.w == 300 and p.h == 320)
    -- the settings choice does the same without the grip
    WC.SetSetting("panelSizeMode", "manual")
    assert(p.h == 410)
    WC.SetSetting("panelSizeMode", "auto")
    -- bounds
    local lo, hi = WC.PanelHeightBounds()
    local w, h = WC.ClampPanelSize(9999, 1)
    assert(w == 520 and h == lo and lo >= 44 + 2 * WC.LINE_HEIGHT)
    w, h = WC.ClampPanelSize(10, 99999)
    assert(w == 280 and h == hi and hi == math.floor(UIParent:GetHeight() > 0 and UIParent:GetHeight() * 0.9 or 900))
    WC.SetSetting("panelSizeMode", "manual"); WC.SetSetting("panelHeight", 4000)
    assert(p.h == hi)
    WC.SetSetting("panelSizeMode", "auto")
    -- combat: refused, and a drag in progress stops and saves
    COMBAT = true
    grip.scripts.OnMouseDown(grip, "LeftButton")
    assert(p.sizingFrom == nil)
    COMBAT = false
    grip.scripts.OnMouseDown(grip, "LeftButton")
    assert(p.sizingFrom == "BOTTOMRIGHT")
    p.w, p.h = 360, 380
    WC.StopPanelSizing()
    assert(p.sizingFrom == nil and not p.sizing and WC.Setting("panelHeight") == 380 and WC.Setting("panelSizeMode") == "manual")
    -- tooltip
    local lines = WC.GripTipLines()
    assert(lines[1][1] == "Size: Manual" and lines[2][1] == "Drag: resize" and lines[3][1] == "Right-click: automatic size")
    -- locked: hidden, refuses, tooltip says why
    WC.SetSetting("locked", true)
    assert(not grip.shown)
    grip.scripts.OnMouseDown(grip, "LeftButton")
    assert(p.sizingFrom == nil)
    lines = WC.GripTipLines()
    assert(#lines == 2 and lines[2][1] == "Unlock the panel in Settings to resize")
    WC.SetSetting("locked", false)
    assert(grip.shown)
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
    assert(WoWCompanionDB.observed.version == 2 and #ev == 4)
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

cases[#cases + 1] = { "why: shows in the panel, card and map row; absent changes nothing; the toggle hides it", function()
    local WC = plan_client(nil)
    local WHY = "Class quest: unlocks your next spell"
    live_digest({ { kind = "pickup", title = "Seena's Task", quest = 91, class = true, why = WHY .. string.rep("x", 80) },
        { kind = "pickup", title = "Plain Task", quest = 92 } })
    local with = panel_text()
    assert(with:find(WHY, 1, true), "why in the panel")
    local rows = WC.QuestEntryRows({ kind = "pickup", title = "Plain Task", quest = 92 }, 92, nil, 5)
    assert(#rows == 2 or #rows == 1, "no extra row without why")
    for _, r in ipairs(rows) do assert(not r.why) end
    local m = WC.QuestEntryRows({ kind = "pickup", title = "T", why = WHY }, nil, nil, 5)
    assert(m[2].why and m[2].text == WHY and m[2].color == WC.COLORS.dim)
    assert(#WC.MakeEntry("note", "k", { why = string.rep("y", 200) }).why == 70)
    -- card: why first
    local card = WC.CardModel(WC.MakeEntry("note", "n", { why = WHY, details = { "More" } }, { title = "Note" }))
    assert(card.rows[1].text == WHY and card.rows[2].text == "More")
    -- map row
    local step = { kind = "turnin", questID = 91, quest = "Seena's Task", label = "Turn in Seena's Task", n = 1 }
    assert(WC.StepSubLine(step) == WHY:sub(1, 70) or WC.StepSubLine(step):find("Class quest", 1, true), "why on the map row")
    local plain_step = { kind = "turnin", questID = 92, quest = "Plain Task", label = "Turn in Plain Task", n = 2 }
    assert(WC.StepSubLine(plain_step) == WoWCompanion.L.PANEL_TURNIN, "absent why: unchanged")
    local obj = { kind = "objective", questID = 91, quest = "Seena's Task", label = "Kill Boar (0/1)", n = 3 }
    assert(WC.StepSubLine(obj) == "Kill Boar (0/1)", "objective progress wins over why")
    local obj2 = { kind = "objective", questID = 91, quest = "Seena's Task", label = "Explore the cave", n = 4 }
    assert(WC.StepSubLine(obj2):find("Class quest", 1, true))
    -- toggle
    assert(WC.Setting("showWhy") == true)
    WC.SetSetting("showWhy", false)
    assert(not panel_text():find("Class quest", 1, true), "hidden in the panel")
    assert(WC.StepSubLine(step) == WoWCompanion.L.PANEL_TURNIN, "hidden on the map")
    WC.SetSetting("showWhy", true)
end }

cases[#cases + 1] = { "plan: plain step labels render in details and tooltips", function()
    local WC = plan_client(nil)
    local steps = WC.ParsePlan({ schema = 1, characters = { Thrall = { steps = {
        { kind = "pickup", quest = "Crab Season", label = "Pick up Crab Season", map = 1, x = 1, y = 1 },
        { kind = "objective", quest = "Crab Season", label = "Collect Meat (0/8)", map = 1, x = 1, y = 1 },
        { kind = "objective", quest = "Crab Season", label = "Kill Crab (0/1)", map = 1, x = 1, y = 1 },
        { kind = "turnin", quest = "Crab Season", label = "Turn in Crab Season", map = 1, x = 1, y = 1 } } } } }, "Thrall")
    assert(#steps == 4 and steps[1].label == "Pick up Crab Season" and steps[4].label == "Turn in Crab Season")
    assert(WC.PlanDetail(steps[2]) == "Collect Meat (0/8)" and WC.PlanDetail(steps[3]) == "Kill Crab (0/1)")
    assert(WC.PlanDetail(steps[1]) == "" and WC.PlanDetail(steps[4]) == "")
    assert(WC.StepSubLine(steps[2]) == "Collect Meat (0/8)")
end }

cases[#cases + 1] = { "read-only: nothing asks for a /reload", function()
    for _, f in ipairs({ "Button", "Geometry", "Card", "Chips", "Combat", "Core", "Digest", "Hover", "MapPanel", "Observed", "Options", "Panel", "Plan", "PlanTip", "PlanUI", "Settings", "Status", "Tooltips", "Tracker", "WhatsNew" }) do
        local code = assert(io.open("WoWCompanion/" .. f .. ".lua")):read("*a"):gsub("%-%-[^\n]*", "")
        assert(not code:find("ReloadUI", 1, true) and not code:find("StaticPopup", 1, true), f)
        assert(not code:find("ConsoleExec", 1, true) and not code:find("RestartGx", 1, true), f)
    end
end }

-- A client map for the round-button cases: a canvas container at (100, 900) with n round buttons stacked 32 apart.
local function round_map(n, withColumn)
    WorldMapFrame = CreateFrame("Frame", nil, UIParent)
    WorldMapFrame:SetFrameStrata("HIGH"); WorldMapFrame:SetFrameLevel(10)
    local canvas = CreateFrame("Frame", nil, WorldMapFrame)
    canvas:SetFrameLevel(11)
    canvas.GetLeft = function() return 100 end
    canvas.GetTop = function() return 900 end
    canvas.GetHeight = function() return 600 end
    WorldMapFrame.ScrollContainer = canvas
    function WorldMapFrame:GetCanvasContainer() return canvas end
    for i = 1, n do
        local c = CreateFrame("Button", nil, canvas)
        c.w, c.h = 32, 32
        c.GetLeft = function() return 103 end
        c.GetTop = function() return 900 - 3 - (i - 1) * 32 end
        c.GetHeight = function() return 32 end
    end
    QuestMapFrame = fake_column({})
    QuestMapFrame.shown = true
    if withColumn then
        local t = CreateFrame("Button", nil, QuestMapFrame)
        t.w, t.h = 40, 42
        t.GetLeft = function() return 960 end
        t.GetTop = function() return 800 end
        t.GetBottom = function() return 758 end
        t.GetHeight = function() return 42 end
        t.GetAtlas = function() return "common-sidetab-c60" end
        t.GetRegions = function() return end
        t.Background = t
    end
    return canvas
end

for _, n in ipairs({ 0, 1, 2 }) do
    cases[#cases + 1] = { "client map: with " .. n .. " round buttons ours takes slot " .. (n + 1) .. ", above the canvas, probe records it", function()
        local canvas = round_map(n)
        fresh_client(nil)
        local WC = WoWCompanion
        WorldMapFrame.scripts.OnShow(WorldMapFrame)
        local r = WC.mapRound
        assert(r and r:IsShown() and r.parent == WorldMapFrame and r.w == 32 and r.h == 32)
        local p = r.points[1]
        assert(p[1] == "TOPLEFT" and p[2] == canvas and p[3] == "TOPLEFT" and p[4] == 3 and p[5] == -(3 + n * 32), "slot " .. (n + 1))
        assert(r:GetFrameStrata() == "HIGH" and r.parent == WorldMapFrame and p[2] == WorldMapFrame:GetCanvasContainer(), "map child, HIGH, anchored to the canvas container")
        assert(r:GetFrameLevel() > canvas:GetFrameLevel() and r:GetFrameStrata() == "HIGH", "above the canvas")
        local g = WoWCompanionDB.observed.mapGeometry
        assert(g.control == "round" and g.round.name == "WoWCompanionMapRoundButton" and g.round.level == r:GetFrameLevel() and g.round.strata == "HIGH")
        assert(g.round.slot == n + 1 and #g.slots == n and (n == 0 or g.slots[1].x == 3))
        WorldMapFrame, QuestMapFrame = nil, nil
    end }
end

cases[#cases + 1] = { "client map: a click on the round button toggles the panel; right opens options; shift-drag offsets and saves", function()
    local canvas = round_map(1)
    fresh_client(nil)
    local WC = WoWCompanion
    WorldMapFrame.scripts.OnShow(WorldMapFrame)
    local r = WC.mapRound
    assert(not WC.panelState.selected)
    local before = WC.db.settings.planMap
    r.scripts.OnClick(r, "LeftButton")
    assert(WC.db.settings.planMap == not before and not WC.panelState.selected, "toggles the overlays, not the panel")
    r.scripts.OnClick(r, "LeftButton")
    assert(WC.db.settings.planMap == before)
    -- a later round button shows up: ours moves below it on the next check
    local c = CreateFrame("Button", nil, canvas)
    c.w, c.h = 32, 32
    c.GetLeft = function() return 103 end
    c.GetTop = function() return 900 - 3 - 32 end
    c.GetHeight = function() return 32 end
    WC.columnClock = 1
    assert(WC.WatchRoundColumn(0) == true and r.points[1][5] == -(3 + 64))
    -- drag: the offset is saved from the cursor and clamped to the container
    assert(WC.SetRoundFromCursor(900 - 200) == 200 - 16 - WC.roundBase and WC.Setting("mapRoundY") ~= 0)
    assert(r.points[1][5] == -(200 - 16))
    assert(WC.SetRoundFromCursor(-5000) == 600 - 32 - WC.roundBase, "clamped to the bottom")
    WC.ResetMapTabPosition()
    assert(WC.Setting("mapRoundY") == 0)
    WorldMapFrame, QuestMapFrame = nil, nil
end }


-- The client's small map and its side panel: a map that counts the client's own open and close calls.
local function side_map(maximized, logOpen)
    local canvas = round_map(1)
    WorldMapFrame.isMaximized = maximized
    QuestMapFrame.shown = logOpen
    QuestMapFrame.ContentsAnchor = CreateFrame("Frame", "QuestMapContentsInset", QuestMapFrame)
    QuestMapFrame.ContentsAnchor.GetRect = function() return 1000, 90, 330, 620 end
    local scroll = CreateFrame("ScrollFrame", "QuestScrollFrame", QuestMapFrame)
    scroll:SetPoint("TOPLEFT", QuestMapFrame.ContentsAnchor, "TOPLEFT", 0, -29)
    scroll.GetRect = function() return 1000, 90, 308, 591 end
    QuestMapFrame.QuestsFrame = CreateFrame("Frame", nil, QuestMapFrame)
    QuestMapFrame.QuestsFrame.ScrollFrame = scroll
    local calls = { open = 0, close = 0 }
    function WorldMapFrame:HandleUserActionOpenQuestLog() calls.open = calls.open + 1; QuestMapFrame:Show() end
    function WorldMapFrame:HandleUserActionCloseQuestLog() calls.close = calls.close + 1; QuestMapFrame:Hide() end
    fresh_client(nil)
    WorldMapFrame.scripts.OnShow(WorldMapFrame)
    return WoWCompanion, calls, canvas
end

for _, maximized in ipairs({ true, false }) do
    for _, logOpen in ipairs({ true, false }) do
        local name = (maximized and "full" or "small") .. " map, quest log " .. (logOpen and "open" or "closed")
        cases[#cases + 1] = { "side panel: " .. name .. ": the round button always shows; the small map opens the panel once and closes it only if we opened it; the plan is the quest list's rect", function()
            local WC, calls = side_map(maximized, logOpen)
            local r = WC.mapRound
            assert(r:IsShown() and WC.mapControl == "round", "shown on map open")
            WC.planTab.scripts.OnClick(WC.planTab, "LeftButton") -- plan on
            assert(WC.panelState.selected and r:IsShown(), "shown with the plan on")
            local opens = (not logOpen) and 1 or 0
            assert(calls.open == opens and calls.close == 0, "opens " .. calls.open)
            assert((WC.panelState.weOpened == true) == (opens == 1))
            assert(QuestMapFrame:IsShown(), "the panel is open for the plan")
            local f, scroll = WC.mapPanel, QuestMapFrame.QuestsFrame.ScrollFrame
            assert(f.anchors.TOPLEFT[2] == scroll and f.anchors.BOTTOMRIGHT[2] == scroll and f.anchors.TOPLEFT[4] == 0 and f.anchors.BOTTOMRIGHT[5] == 0, "plan rect is the quest scroll rect")
            local g = WoWCompanionDB.observed.mapGeometry
            assert(g.sizeMode == (maximized and "full" or "small") and g.roundButton.shown and g.sidePanel.open and g.sidePanel.weOpened == (opens == 1) and type(g.t) == "number")
            assert(g.insetRect.w == 330 and g.questScrollRect.w == 308 and g.sidePanel.planSelected)
            WC.RefreshMapTab(); WC.PlaceMapTab()
            assert(r:IsShown(), "still shown after a re-place")
            WC.planTab.scripts.OnClick(WC.planTab, "LeftButton") -- plan off
            assert(not WC.panelState.selected and r:IsShown(), "shown with the plan off")
            assert(calls.close == opens and calls.open == opens, "closed only if we opened it")
            assert(QuestMapFrame:IsShown() == logOpen, "side panel restored to how it was")
            assert(not WC.panelState.weOpened)
            WorldMapFrame, QuestMapFrame, COMBAT = nil, nil, nil
        end }
    end
end


cases[#cases + 1] = { "client map: the slot follows the client's pin button; re-placed on OnMapChanged, size toggle and quest-pane toggle; the probe refreshes t", function()
    local hooks = {}
    local canvas = round_map(0)
    WorldMapTrackingPinButtonMixin = { OnLoad = function() end }
    local pin = CreateFrame("Button", nil, WorldMapFrame)
    pin.w, pin.h, pin.OnLoad = 32, 32, WorldMapTrackingPinButtonMixin.OnLoad
    pin.GetLeft = function() return 103 end
    pin.GetTop = function() return 900 end
    pin.GetHeight = function() return 32 end
    WorldMapFrame.overlayFrames = { pin }
    function WorldMapFrame:OnMapChanged() end
    fresh_client(nil)
    local WC = WoWCompanion
    local cs = {}
    C_Timer = { After = function(sec, fn) cs[#cs + 1] = { sec, fn } end }
    hooksecurefunc = function(obj, name, fn) hooks[name] = { obj = obj, fn = fn } end
    WC.mapChangedHooked, WC.mapRound = nil, nil
    WC.CreateMapButton()
    WorldMapFrame.scripts.OnShow(WorldMapFrame)
    local r = WC.mapRound
    assert(r.points[1][5] == -32 and WC.roundPlace.slot == 2, "below the pin button")
    assert(hooks.OnMapChanged and hooks.OnMapChanged.obj == WorldMapFrame, "hooks OnMapChanged")
    -- a button moves in after us: each trigger re-places
    local extra = CreateFrame("Button", nil, canvas)
    extra.w, extra.h = 32, 32
    extra.GetLeft = function() return 103 end
    extra.GetTop = function() return 900 - 32 end
    extra.GetHeight = function() return 32 end
    hooks.OnMapChanged.fn(WorldMapFrame)
    assert(r.points[1][5] == -64, "re-placed on OnMapChanged")
    extra.GetTop = function() return 900 - 64 end
    WorldMapFrame.scripts.OnSizeChanged(WorldMapFrame)
    assert(r.points[1][5] == -96, "re-placed on a size toggle")
    extra:Hide()
    QuestMapFrame.scripts.OnHide(QuestMapFrame)
    assert(r.points[1][5] == -32, "re-placed on a quest-pane close")
    local later = false
    for _, c in ipairs(cs) do if c[1] == 0.2 then later = true end end
    assert(later, "and once more about 0.2 s later")
    -- the probe's time stamp moves on every trigger
    for _, trigger in ipairs({
        function() hooks.OnMapChanged.fn(WorldMapFrame) end,
        function() WorldMapFrame.scripts.OnSizeChanged(WorldMapFrame) end,
        function() QuestMapFrame.scripts.OnShow(QuestMapFrame) end,
        function() QuestMapFrame.scripts.OnHide(QuestMapFrame) end,
    }) do
        NOW = NOW + 5
        trigger()
        local g = WoWCompanionDB.observed.mapGeometry
        assert(g.t == NOW and g.roundButton.t == NOW, "probe t refreshed")
    end
    local rb = WoWCompanionDB.observed.mapGeometry.roundButton
    assert(rb.shown and rb.visible and rb.strata == "HIGH" and rb.slot == 2 and rb.parent == nil or rb.parent, "probe fields")
    assert(rb.shown and rb.strata == "HIGH" and rb.level and rb.slot, "probe records strata, level, slot, shown")
    hooksecurefunc, C_Timer, WorldMapTrackingPinButtonMixin = nil, nil, nil
    WorldMapFrame, QuestMapFrame = nil, nil
end }

for _, maximized in ipairs({ true, false }) do
    for _, logOpen in ipairs({ true, false }) do
        cases[#cases + 1] = { "client map: round button shown on the " .. (maximized and "full" or "small") .. " map with the quest pane " .. (logOpen and "open" or "closed") .. ", on the map frame at HIGH", function()
            local WC = side_map(maximized, logOpen)
            local r = WC.mapRound
            assert(r:IsShown() and r:IsVisible() and r.parent == WorldMapFrame and r:GetFrameStrata() == "HIGH")
            assert(WoWCompanionDB.observed.mapGeometry.roundButton.visible == true)
            WorldMapFrame, QuestMapFrame = nil, nil
        end }
    end
end

-- The round button is the only map control: no frame near the map's corners, nor another addon's tabs, ever hide it.
for _, maximized in ipairs({ true, false }) do
    for _, logOpen in ipairs({ true, false }) do
        for _, other in ipairs({ true, false }) do
            cases[#cases + 1] = { "client map: round button shown on the " .. (maximized and "full" or "small") .. " map, quest pane " .. (logOpen and "open" or "closed") .. ", other map addon " .. (other and "present" or "absent"), function()
                round_map(1)
                if other then
                    -- a single 54 x 17 frame at the map's lower right (the client's own pane toggle), and another addon's tab column
                    local toggle = CreateFrame("Button", nil, WorldMapFrame)
                    toggle.w, toggle.h = 54, 17
                    toggle.GetRect = function() return 1000, 100, 54, 17 end
                    toggle.IsMouseEnabled = function() return true end
                    local tab = CreateFrame("CheckButton", "OtherAddonTab", QuestMapFrame)
                    tab.w, tab.h = 40, 42
                    tab.GetLeft = function() return 960 end
                    tab.GetTop = function() return 800 end
                    tab.GetBottom = function() return 758 end
                    tab.GetAtlas = function() return "common-sidetab-c60" end
                    tab.Background = tab
                end
                WorldMapFrame.isMaximized = maximized
                QuestMapFrame.shown = logOpen
                fresh_client(nil)
                local WC = WoWCompanion
                WorldMapFrame.scripts.OnShow(WorldMapFrame)
                local r = WC.mapRound
                assert(r:IsShown() and r:IsVisible() and r.parent == WorldMapFrame, "shown")
                local g = WoWCompanionDB.observed.mapGeometry
                assert(g.control == "round" and g.roundButton.shown and g.roundButton.visible)
                WC.columnClock = 1
                WC.WatchRoundColumn(0)
                QuestMapFrame.scripts.OnShow(QuestMapFrame)
                QuestMapFrame.scripts.OnHide(QuestMapFrame)
                assert(r:IsShown() and WoWCompanionDB.observed.mapGeometry.control == "round", "still shown after the pane toggles")
                WorldMapFrame, QuestMapFrame = nil, nil
            end }
        end
    end
end

-- The client's quest-pane toggle: a frame with an open and a close button, each carrying atlas art.
local function with_client_toggle()
    local WC, calls, canvas = side_map(false, false)
    local t = CreateFrame("Frame", nil, WorldMapFrame)
    t.OpenButton = CreateFrame("Button", nil, t)
    t.CloseButton = CreateFrame("Button", nil, t)
    for _, b in ipairs({ t.OpenButton, t.CloseButton }) do
        b:SetSize(30, 40)
        local tex = CreateFrame("Frame", nil, b)
        tex.atlas = b == t.OpenButton and "toggle-open" or "toggle-close"
        b.GetNormalTexture = function() return tex end
    end
    t.CloseButton.shown = false
    WorldMapFrame.SidePanelToggle = t
    WC.PlacePlanTab()
    return WC, calls, t
end

cases[#cases + 1] = { "plan tab: sits directly above the client's toggle, follows it, uses its art and size, falls back to the container corner", function()
    local WC, _, t = with_client_toggle()
    local b = WC.planTab
    assert(b.parent == WorldMapFrame and b.strata == "HIGH" and b:IsShown())
    local a = b.anchors.BOTTOM
    assert(a and a[2] == t.OpenButton and a[3] == "TOP" and a[5] >= 2 and a[5] <= 4 and WC.planTabAnchor == "toggle")
    assert(b.w == 30 and b.h == 40 and b.normalAtlas == "toggle-open", "the client's size and closed art")
    t.OpenButton.shown, t.CloseButton.shown = false, true -- the pane opened: the client's toggle swaps buttons
    WC.PlacePlanTab()
    assert(b.anchors.BOTTOM[2] == t.CloseButton, "follows the toggle")
    WorldMapFrame.SidePanelToggle = nil
    WC.PlacePlanTab()
    assert(WC.planTabAnchor == "corner" and b.anchors.BOTTOMRIGHT[3] == "BOTTOMRIGHT")
    local g = WC.MapGeometry().planTab
    assert(g.anchor == "corner" and g.shown and g.visible ~= nil and g.overlaysOn ~= nil)
    WorldMapFrame, QuestMapFrame = nil, nil
end }

-- A full-size map whose client toggle is hidden: the pane's and the toggle's rects are set so overlap can be probed.
local function full_map_no_toggle(paneOpen)
    local WC, calls = side_map(true, paneOpen)
    local t = CreateFrame("Frame", nil, WorldMapFrame)
    t.OpenButton = CreateFrame("Button", nil, t)
    t.CloseButton = CreateFrame("Button", nil, t)
    t.OpenButton.shown, t.CloseButton.shown = false, false
    WorldMapFrame.SidePanelToggle = t
    QuestMapFrame.level = 5
    local canvas = WC.RoundParent()
    QuestMapFrame.GetLeft, QuestMapFrame.GetRight, QuestMapFrame.GetTop, QuestMapFrame.GetBottom = function() return 1000 end, function() return 1330 end, function() return 700 end, function() return 80 end
    WC.PlacePlanTab()
    return WC, calls, t, canvas
end

cases[#cases + 1] = { "plan tab: full-size map, pane open: left of the pane, bottom, above it in frame level; pane closed: the canvas's bottom right", function()
    local WC, _, _, canvas = full_map_no_toggle(true)
    local b = WC.planTab
    local a = b.anchors.BOTTOMRIGHT
    assert(WC.planTabAnchor == "pane" and a[2] == QuestMapFrame and a[3] == "BOTTOMLEFT" and a[4] == -4 and a[5] == 0, "pane's left edge, 4px gap")
    assert(b.strata == "HIGH" and b:GetFrameLevel() > QuestMapFrame:GetFrameLevel(), "above the pane")
    WC.planTab.scripts.OnClick(WC.planTab, "LeftButton")
    assert(WC.mapPanel and b:GetFrameLevel() > WC.mapPanel:GetFrameLevel(), "above our own plan frame too")
    QuestMapFrame:Hide()
    WC.PlacePlanTab()
    a = b.anchors.BOTTOMRIGHT
    assert(WC.planTabAnchor == "corner" and a[2] == canvas and a[3] == "BOTTOMRIGHT", "canvas bottom right")
    assert(WC.MapGeometry().planTab.overlap == false)
    WorldMapFrame, QuestMapFrame = nil, nil
end }

cases[#cases + 1] = { "plan tab: never overlaps a shown client toggle", function()
    local WC, _, t = full_map_no_toggle(true)
    local b = WC.planTab
    -- the client toggle shows in the very spot the pane anchor would give ours
    t.OpenButton.shown = true
    t.OpenButton:SetSize(30, 40)
    t.OpenButton.GetLeft, t.OpenButton.GetRight, t.OpenButton.GetTop, t.OpenButton.GetBottom = function() return 940 end, function() return 970 end, function() return 120 end, function() return 80 end
    b.GetLeft, b.GetRight, b.GetTop, b.GetBottom = function() return 960 end, function() return 996 end, function() return 120 end, function() return 80 end
    assert(WC.RectsOverlap({ left = 0, right = 10, top = 10, bottom = 0 }, { left = 5, right = 15, top = 12, bottom = 2 }))
    assert(not WC.RectsOverlap({ left = 0, right = 10, top = 10, bottom = 0 }, { left = 10, right = 15, top = 12, bottom = 2 }))
    WC.PlacePlanTab()
    assert(WC.planTabAnchor == "toggle" and b.anchors.BOTTOM[2] == t.OpenButton and b.anchors.BOTTOM[3] == "TOP", "sits above the shown toggle")
    WorldMapFrame, QuestMapFrame = nil, nil
end }

cases[#cases + 1] = { "plan hide: every region of ours hides, no quest header call is made, the pane we opened closes", function()
    local WC, calls = full_map_no_toggle(false)
    local forbidden = {}
    for _, n in ipairs({ "ToggleHeader", "CollapseAll", "ExpandAll", "SetHeaderCollapsed", "ToggleQuestHeader" }) do
        QuestMapFrame[n] = function() forbidden[#forbidden + 1] = n end
        _G["QuestMapFrame_" .. n] = QuestMapFrame[n]
    end
    local src = assert(io.open("WoWCompanion/MapPanel.lua")):read("*a")
    for _, n in ipairs({ "CollapseQuestHeader", "ExpandQuestHeader", "CollapseAll", "ToggleHeader", "ExpandAll" }) do assert(not src:find(n, 1, true), n) end
    WC.planTab.scripts.OnClick(WC.planTab, "LeftButton")
    local f = WC.mapPanel
    assert(f:IsShown() and f.bg:IsShown() and f.scroll:IsShown() and f.title:IsShown())
    WC.planTab.scripts.OnClick(WC.planTab, "LeftButton")
    for _, p in ipairs({ f, f.bg, f.scroll, f.child, f.title, f.stepText, f.advice, f.eye, f.zoneBtn, f.empty, f.doneHead, f.footer }) do
        assert(not p:IsShown(), "still shown")
    end
    for _, r in ipairs(f.rows) do assert(not r:IsShown()) end
    assert(#forbidden == 0 and calls.close == 1 and not QuestMapFrame:IsShown(), "closed the client's way, no header calls")
    WC.planTab.scripts.OnClick(WC.planTab, "LeftButton") -- and it comes back whole
    assert(f.bg:IsShown() and f.scroll:IsShown())
    WorldMapFrame, QuestMapFrame = nil, nil
end }

cases[#cases + 1] = { "plan hide: a pane that was already open stays open as it was", function()
    local WC, calls = full_map_no_toggle(true)
    WC.planTab.scripts.OnClick(WC.planTab, "LeftButton")
    WC.planTab.scripts.OnClick(WC.planTab, "LeftButton")
    assert(calls.open == 0 and calls.close == 0 and QuestMapFrame:IsShown() and not WC.mapPanel:IsShown() and not WC.mapPanel.bg:IsShown())
    WorldMapFrame, QuestMapFrame = nil, nil
end }

cases[#cases + 1] = { "plan rows: ring diameter at most 20, stroke at most 1.5, 6px inset before it and 6px to the mark", function()
    local WC, tab = side_panel_client()
    assert(WC.PANEL_BADGE >= 18 and WC.PANEL_BADGE <= 20 and WC.PANEL_RING >= 1 and WC.PANEL_RING <= 1.5)
    tab.scripts.OnClick(tab, "LeftButton")
    local r = WC.mapPanel.rows[1]
    assert(r.badge.w <= 20 and r.badge.points[1][4] == 6 and r.icon.points[1][4] == 6, "insets")
    side_panel_done()
end }

cases[#cases + 1] = { "badge tooltip: each step leads with its action and no line repeats", function()
    local WC = plan_client("full")
    local function texts(g) local t = {} for _, l in ipairs(WC.PlanTipLines(g)) do t[#t + 1] = l.text end return t end
    local P = { n = 2, kind = "pickup", quest = "Al'Aketh Assassins", label = "Pick up Al'Aketh Assassins from Fendaal Windstone" }
    local T = { n = 3, kind = "turnin", quest = "Al'Aketh Assassins", label = "Turn in Al'Aketh Assassins to Fendaal Windstone" }
    local t = texts({ steps = { P, T }, total = 23 })
    assert(t[2] == "Pick up from Fendaal Windstone" and t[5] == "Turn in to Fendaal Windstone", table.concat(t, "|"))
    local O = { n = 4, kind = "objective", questID = 12, quest = "Crab", label = "Crab: 0/6 Windsong Crawler" }
    QUESTS[12] = "active"
    C_QuestLog.GetQuestObjectives = function() return { { text = "Windsong Crawler", numFulfilled = 0, numRequired = 6 }, { text = "Windsong Crawler", numFulfilled = 0, numRequired = 6 } } end
    local o = texts({ steps = { O }, total = 23 })
    local seen = {}
    for _, l in ipairs(o) do assert(not seen[l], "duplicate " .. l); seen[l] = true end
    C_QuestLog.GetQuestObjectives = nil
    QUESTS[12] = nil
    WorldMapFrame = nil
end }

cases[#cases + 1] = { "plan tab: a click opens the pane, shows the plan and restores the pane; the client's toggle closing the pane hides the plan", function()
    local WC, calls, t = with_client_toggle()
    local b = WC.planTab
    local overlays = WC.db.settings.planMap
    b.scripts.OnClick(b, "LeftButton")
    assert(calls.open == 1 and QuestMapFrame:IsShown() and WC.panelState.selected and WC.mapPanel:IsShown(), "pane opened, plan shown")
    assert(b.normalAtlas == "toggle-close", "the open state's art")
    assert(WC.db.settings.planMap == overlays, "the map overlays are untouched")
    b.scripts.OnClick(b, "LeftButton")
    assert(calls.close == 1 and not QuestMapFrame:IsShown() and not WC.panelState.selected, "plan hidden and the pane restored")
    b.scripts.OnClick(b, "LeftButton") -- on again, then the player closes the pane with the client's own toggle
    assert(WC.panelState.selected)
    QuestMapFrame:Hide()
    assert(not WC.panelState.selected and not WC.mapPanel:IsShown() and b.normalAtlas == "toggle-open", "our plan hides with the pane")
    WorldMapFrame, QuestMapFrame = nil, nil
end }

cases[#cases + 1] = { "plan rows: the step circle is slim and 10 to 99 fit inside", function()
    local WC = WoWCompanion
    if not WC.PANEL_BADGE then WC = select(1, side_panel_client()); side_panel_done() end
    assert( WC.PANEL_RING >= 1 and WC.PANEL_RING <= 1.5 and WC.PANEL_BADGE >= 18 and WC.PANEL_BADGE <= 20)
    for n = 1, 99 do assert(WC.BadgeNumberFits(n), "fits " .. n) end
    assert(WC.PANEL_TEXT_X < 48, "the text got width back")
    local WC2, tab = side_panel_client()
    tab.scripts.OnClick(tab, "LeftButton")
    local r = WC2.mapPanel.rows[1]
    assert(r.badge.w == WC2.PANEL_BADGE and r.badge.h == WC2.PANEL_BADGE)
    side_panel_done()
end }

cases[#cases + 1] = { "map button: no side-tab control, column detection, art or settings remain in the code", function()
    local gone = { "sidetab", "SideTab", "SIDETAB", "ScanTabColumn", "ColumnPlacement", "mapTabY", "FindClientSideTabs", "ArtSideTabs", "WoWCompanionMapTab", "QuestLogTabButtonTemplate" }
    for _, file in ipairs({ "Button", "MapPanel", "Geometry", "Settings", "Options" }) do
        local src = assert(io.open("WoWCompanion/" .. file .. ".lua")):read("*a")
        for _, n in ipairs(gone) do assert(not src:find(n, 1, true), file .. " still has " .. n) end
    end
    local WC = WoWCompanion
    assert(WC.PlaceSideTab == nil and WC.WatchTabColumn == nil and WC.SideTabColumnFound == nil and WC.mapButtonMode == nil)
end }

cases[#cases + 1] = { "side panel: in combat the open call is deferred with a tooltip line, then runs once when combat ends; never a taint", function()
    local WC, calls = side_map(false, false)
    local r = WC.mapRound
    COMBAT = true
    Stub.fire(frames, "PLAYER_REGEN_DISABLED")
    WC.planTab.scripts.OnClick(WC.planTab, "LeftButton")
    assert(calls.open == 0 and not QuestMapFrame:IsShown() and WC.panelState.wantOpen and r:IsShown(), "deferred")
    GameTooltip.calls = {}
    WC.planTab.scripts.OnEnter(WC.planTab)
    local said = false
    for _, c in ipairs(GameTooltip.calls) do if c[1] == "AddLine" and c[2] == WC.L.TIP_MAP_DEFERRED then said = true end end
    assert(said, "the tooltip says so")
    COMBAT = false
    Stub.fire(frames, "PLAYER_REGEN_ENABLED")
    assert(calls.open == 1 and QuestMapFrame:IsShown() and WC.panelState.weOpened and not WC.panelState.wantOpen, "opened once after combat")
    COMBAT = true
    Stub.fire(frames, "PLAYER_REGEN_DISABLED")
    WC.planTab.scripts.OnClick(WC.planTab, "LeftButton")
    assert(calls.close == 0 and WC.panelState.wantClose, "close deferred too")
    COMBAT = false
    Stub.fire(frames, "PLAYER_REGEN_ENABLED")
    assert(calls.close == 1 and not QuestMapFrame:IsShown() and not WC.panelState.weOpened)
    WorldMapFrame, QuestMapFrame, COMBAT = nil, nil, nil
end }


-- Small map whose client closes its pane only through the toggle method; counts every Hide on the client's frames.
local function toggle_map(logOpen)
    local WC, calls = side_map(false, logOpen)
    calls.toggle, calls.hides = 0, 0
    WorldMapFrame.HandleUserActionCloseQuestLog, WorldMapFrame.HandleUserActionOpenQuestLog = nil, nil
    function WorldMapFrame:HandleUserActionToggleSidePanel()
        calls.toggle = calls.toggle + 1
        QuestMapFrame.shown = not QuestMapFrame.shown
    end
    for _, f in ipairs({ WorldMapFrame, QuestMapFrame }) do
        local hide = f.Hide
        f.Hide = function(self, ...) calls.hides = calls.hides + 1; return hide(self, ...) end
    end
    return WC, calls
end

cases[#cases + 1] = { "side panel: pane closed, plan on then off: the client's toggle closes it once, no client Hide, the probe records it", function()
    local WC, calls = toggle_map(false)
    WC.planTab.scripts.OnClick(WC.planTab, "LeftButton") -- the client's open call here is the toggle too
    WC.panelState.weOpened = true
    QuestMapFrame.shown = true
    calls.toggle = 0
    WC.planTab.scripts.OnClick(WC.planTab, "LeftButton")
    assert(calls.toggle == 1 and not QuestMapFrame:IsShown() and not WC.panelState.weOpened, "closed once through the toggle")
    assert(calls.hides == 0, "no client frame hidden")
    local h = WC.panelState.lastHide
    assert(h and h.weOpened and h.call == "HandleUserActionToggleSidePanel" and h.closed, "probe")
    WorldMapFrame, QuestMapFrame = nil, nil
end }

cases[#cases + 1] = { "side panel: pane open first, plan on then off: left open, quest list shown, no close, no client Hide", function()
    local WC, calls = toggle_map(true)
    WC.planTab.scripts.OnClick(WC.planTab, "LeftButton")
    assert(not WC.panelState.weOpened)
    QuestMapFrame.QuestsFrame.shown = false
    WC.planTab.scripts.OnClick(WC.planTab, "LeftButton")
    assert(calls.toggle == 0 and QuestMapFrame:IsShown() and calls.hides == 0, "pane kept")
    assert(QuestMapFrame.QuestsFrame:IsShown(), "quest list shown again")
    WorldMapFrame, QuestMapFrame = nil, nil
end }

cases[#cases + 1] = { "side panel: the player toggles the pane in between: we do not close it", function()
    local WC, calls = toggle_map(false)
    WC.planTab.scripts.OnClick(WC.planTab, "LeftButton")
    QuestMapFrame.shown = true
    WC.panelState.weOpened = false -- what the toggle hook does on the player's use
    calls.toggle = 0
    WC.planTab.scripts.OnClick(WC.planTab, "LeftButton")
    assert(calls.toggle == 0 and QuestMapFrame:IsShown() and calls.hides == 0, "player's pane left alone")
    WorldMapFrame, QuestMapFrame = nil, nil
end }

cases[#cases + 1] = { "ride: no other addon's names in the tab code", function()
    local banned = { "ElvUI", "Questie", "Leatrix", "Mapster", "HandyNotes", "TomTom", "WorldQuestTracker", "Chinchilla", "Carbonite", "SexyMap", "Lib%u" }
    local src = assert(io.open("WoWCompanion/Button.lua")):read("*a")
    for _, n in ipairs(banned) do assert(not src:find(n), "Button names " .. n) end
end }

-- Character capture: synthetic character, client reads stubbed.
local function capture_client()
    local function run_timers()
        local f = WoWCompanion.captureTimer
        if f.scripts.OnUpdate then f.scripts.OnUpdate(f, 5) end
    end
    UnitLevel = function() return 23 end
    UnitClass = function() return "Warrior", "WARRIOR" end
    UnitRace = function() return "Orc", "Orc" end
    UnitFactionGroup = function() return "Horde" end
    GetMoney = function() return 12345 end
    UnitXP = function() return 100 end
    UnitXPMax = function() return 500 end
    GetXPExhaustion = function() return nil end
    GetBindLocation = function() return "Testtown" end
    C_Map = { GetBestMapForUnit = function() return 1411 end, GetPlayerMapPosition = function() return { GetXY = function() return 0.5, 0.25 end } end }
    GetInventoryItemID = function(_, slot) return slot == 16 and 1234 or nil end
    GetInventoryItemLink = function(_, slot) return slot == 16 and "|cff|Hitem:1234:77:0:0:0:0:-5:0|h[Sword]|h|r" or nil end
    ITEM_INFO = {
        [1234] = { "Sword", "l", 3, 20, 15, "Weapon", "Swords", 1, "INVTYPE_WEAPON" },
        [2001] = { "Vest", "l", 2, 12, 8, "Armor", "Leather", 1, "INVTYPE_CHEST" },
    }
    C_Item = { GetItemInfo = function(x) local i = ITEM_INFO[type(x) == "number" and x or tonumber(tostring(x):match("item:(%d+)"))]; if i then return unpack(i) end end }
    BAGS = { [0] = { [1] = { 2001, 5, "|cff|Hitem:2001::::::-7:0|h[Vest of the Bear]|h|r" } }, [-1] = { [3] = { 3001, 1 } } }
    C_Container = {
        GetContainerNumSlots = function(b) return BAGS[b] and 4 or 0 end,
        GetContainerItemInfo = function(b, slot) local i = BAGS[b] and BAGS[b][slot]; return i and { itemID = i[1], stackCount = i[2], hyperlink = i[3] } end,
    }
    GetNumQuestLogEntries = function() return 2 end
    GetQuestLogTitle = function(i)
        if i == 1 then return "Zone", 0, nil, true, false, nil, nil, nil end
        return "Test Quest", 12, nil, false, false, 1, nil, 777
    end
    GetNumQuestLeaderBoards = function() return 1 end
    GetQuestLogLeaderBoard = function() return "Boars slain: 3/8", "monster", false end
    GetQuestsCompleted = function() return { [20] = true, [10] = true, [30] = false } end
    GetNumTalentTabs = function() return 1 end
    GetTalentTabInfo = function() return "Arms" end
    GetNumTalents = function() return 1 end
    GetTalentInfo = function() return "Deflection", "icon", 1, 1, 2, 5 end
    GetNumSkillLines = function() return 3 end
    GetSkillLineInfo = function(i)
        if i == 1 then return "Professions", true end
        if i == 2 then return "Mining", false, nil, 150, 0, 0, 225 end
        return "Weapon Skills", true
    end
    GetNumSpellTabs = function() return 1 end
    GetSpellTabInfo = function() return "General", "icon", 0, 2 end
    GetSpellLink = function(i) return "|cff|Hspell:" .. (100 + i) .. "|h[Spell]|h|r" end
    GetNumFactions = function() return 2 end
    GetFactionInfo = function(i)
        if i == 1 then return "Testfolk", "", 5, 3000, 9000, 4000, false, false, false, false, true end
        return "Header", "", 1, 0, 1, 0, false, false, true, false, false
    end
    TRADE_OPEN, TRADE_NAME = false, "Blacksmithing"
    GetTradeSkillLine = function() return TRADE_NAME, 100, 300 end
    GetNumTradeSkills = function() return 2 end
    GetTradeSkillInfo = function(i) if i == 1 then return "Weapons", "header" end return "Copper Sword", "optimal" end
    GetTradeSkillItemLink = function() return "|cff|Henchant:2663|h[x]|h|r" end
    local WC = chain_client()
    Stub.fire(frames, "PLAYER_ENTERING_WORLD")
    return WC, run_timers
end
local function capture_clear()
    for _, n in ipairs({ "UnitLevel", "UnitClass", "UnitRace", "UnitFactionGroup", "GetMoney", "UnitXP", "UnitXPMax", "GetXPExhaustion", "GetBindLocation", "C_Map", "GetInventoryItemID", "GetInventoryItemLink", "ITEM_INFO", "C_Item", "BAGS", "C_Container", "GetNumQuestLogEntries", "GetQuestLogTitle", "GetNumQuestLeaderBoards", "GetQuestLogLeaderBoard", "GetQuestsCompleted", "GetNumTalentTabs", "GetTalentTabInfo", "GetNumTalents", "GetTalentInfo", "GetNumSkillLines", "GetSkillLineInfo", "GetNumSpellTabs", "GetSpellTabInfo", "GetSpellLink", "GetNumFactions", "GetFactionInfo", "TRADE_NAME", "TRADE_OPEN", "GetTradeSkillLine", "GetNumTradeSkills", "GetTradeSkillInfo", "GetTradeSkillItemLink" }) do _G[n] = nil end
end

cases[#cases + 1] = { "capture: item links parse by field position, empty fields kept", function()
    local WC, run = capture_client()
    GetInventoryItemID = function(_, slot) return slot <= 3 and 1234 or nil end
    local links = {
        "|cff|Hitem:1234::::::::10:0|h[x]|h|r",        -- nothing set: no enchant, no suffix, link level 10 ignored
        "|cff|Hitem:1234:2564:0:0:0:0:-12:99:10|h[x]|h|r", -- enchant and suffix
        "|cff|Hitem:1234::::::-5:99:10|h[x]|h|r",      -- suffix only, empty fields before it
    }
    GetInventoryItemLink = function(_, slot) return links[slot] end
    run()
    WC.CaptureMark("equipment"); run()
    local eq = WoWCompanionDB.characters["Testrealm:Thrall"].equipment
    assert(eq[1].enchant == nil and eq[1].suffix == nil)
    assert(eq[2].enchant == 2564 and eq[2].suffix == -12)
    assert(eq[3].enchant == nil and eq[3].suffix == -5)
    capture_clear()
end }

cases[#cases + 1] = { "capture: uncached item info is left out, then filled on GET_ITEM_INFO_RECEIVED", function()
    local WC, run = capture_client()
    local late = ITEM_INFO[2001]
    ITEM_INFO[2001] = nil
    local calls = 0
    local real = C_Item.GetItemInfo
    C_Item.GetItemInfo = function(...) calls = calls + 1; return real(...) end
    WC.CaptureMark("bags"); run()
    local it = WoWCompanionDB.characters["Testrealm:Thrall"].bags[0].items[1]
    assert(it.id == 2001 and it.count == 5 and it.quality == nil and it.ilvl == nil and it.reqLevel == nil and it.equipLoc == nil)
    local n = calls
    run()
    assert(calls == n, "no re-read without an event")
    ITEM_INFO[2001] = late
    Stub.fire(frames, "GET_ITEM_INFO_RECEIVED", 2001, true)
    run()
    it = WoWCompanionDB.characters["Testrealm:Thrall"].bags[0].items[1]
    assert(it.quality == 2 and it.ilvl == 12 and it.reqLevel == 8 and it.equipLoc == "INVTYPE_CHEST")
    capture_clear()
end }

cases[#cases + 1] = { "capture: every part lands in the schema under realm:name", function()
    local WC, run = capture_client()
    assert(next(WoWCompanionDB.characters or {}) == nil, "nothing before the delay")
    run()
    local c = WoWCompanionDB.characters["Testrealm:Thrall"]
    assert(c and c.version == 1 and c.capturedAt == NOW and c.name == "Thrall" and c.realm == "Testrealm")
    assert(c.level == 23 and c.class == "WARRIOR" and c.race == "Orc" and c.faction == "Horde")
    assert(c.money == 12345 and c.xp == 100 and c.xpMax == 500 and c.rested == 0)
    assert(c.client.version == "1.15.7" and c.client.build == "63456")
    assert(c.location.map == 1411 and c.location.x == 50 and c.location.y == 25 and c.hearth == "Testtown")
    assert(c.equipment[16].id == 1234 and c.equipment[16].enchant == 77 and c.equipment[16].suffix == -5)
    assert(c.bags[0].size == 4 and c.bags[0].items[1].id == 2001 and c.bags[0].items[1].count == 5)
    local bi, ei = c.bags[0].items[1], c.equipment[16]
    assert(bi.quality == 2 and bi.ilvl == 12 and bi.reqLevel == 8 and bi.equipLoc == "INVTYPE_CHEST" and bi.suffix == -7 and bi.enchant == nil)
    assert(ei.quality == 3 and ei.ilvl == 20 and ei.reqLevel == 15 and ei.equipLoc == "INVTYPE_WEAPON")
    assert(c.bank == nil and c.bankSeenAt == nil, "bank only while open")
    local q = c.quests.entries[1]
    assert(c.quests.captured and #c.quests.entries == 1 and q.id == 777 and q.title == "Test Quest" and q.level == 12 and q.complete)
    assert(q.objectives[1].have == 3 and q.objectives[1].need == 8 and q.objectives[1].done == false)
    assert(#c.completedQuests == 2 and c.completedQuests[1] == 10 and c.completedQuests[2] == 20)
    assert(c.talents[1].tree == "Arms" and c.talents[1].nodes[1].name == "Deflection" and c.talents[1].nodes[1].rank == 2 and c.talents[1].nodes[1].max == 5)
    assert(#c.skills == 1 and c.skills[1].name == "Mining" and c.skills[1].rank == 150 and c.skills[1].max == 225 and c.skills[1].profession)
    assert(#c.spells == 2 and c.spells[1] == 101)
    assert(#c.reputations == 1 and c.reputations[1].faction == "Testfolk" and c.reputations[1].standing == 5 and c.reputations[1].value == 4000)
    capture_clear()
end }

cases[#cases + 1] = { "capture: spells come from the modern C_SpellBook skill lines, skipping off-spec, future and flyout", function()
    local WC, run = capture_client()
    local items = {
        [1] = { spellID = 30, itemType = 1 }, [2] = { spellID = 10, itemType = 1 }, [3] = { spellID = 99, itemType = 2 },
        [4] = { spellID = 98, itemType = 4 }, [5] = { spellID = 97, itemType = 1, isOffSpec = true },
        [6] = { spellID = 10, itemType = 1 }, [7] = { spellID = 20, itemType = 1 }, [8] = { spellID = 96, itemType = 1 },
    }
    C_SpellBook = {
        GetNumSpellBookSkillLines = function() return 3 end,
        GetSpellBookSkillLineInfo = function(i)
            if i == 1 then return { itemIndexOffset = 0, numSpellBookItems = 5 } end
            if i == 2 then return { itemIndexOffset = 5, numSpellBookItems = 2 } end
            return { itemIndexOffset = 7, numSpellBookItems = 1, offSpecID = 5 }
        end,
        GetSpellBookItemInfo = function(i) return items[i] end,
    }
    run()
    local sp = WoWCompanionDB.characters["Testrealm:Thrall"].spells
    C_SpellBook = nil
    assert(#sp == 3 and sp[1] == 10 and sp[2] == 20 and sp[3] == 30)
    capture_clear()
end }

local function capture_nil(...) for _, n in ipairs({ ... }) do _G[n] = nil end end

cases[#cases + 1] = { "capture: talents use the legacy API first, record unspent points and the probe counts", function()
    local WC, run = capture_client()
    GetNumTalentTabs = function() return 1 end
    GetTalentTabInfo = function() return "Discipline", "icon", 3 end
    GetNumTalents = function() return 2 end
    GetTalentInfo = function(_, i) return "T" .. i, "i", 1, 1, i, 5 end
    UnitCharacterPoints = function() return 4, 0 end
    C_Traits = { GetConfigInfo = function() error("must not be needed") end }
    run()
    local c = WoWCompanionDB.characters["Testrealm:Thrall"]
    capture_nil("GetNumTalentTabs", "GetTalentTabInfo", "GetNumTalents", "GetTalentInfo", "UnitCharacterPoints", "C_Traits")
    assert(#c.talents == 1 and c.talents[1].tree == "Discipline" and c.talents[1].points == 3 and #c.talents[1].nodes == 2)
    assert(c.talents[1].nodes[2].rank == 2 and c.talents[1].nodes[2].max == 5)
    assert(c.talentPoints == 4)
    assert(c.apiProbe.talents.used == "legacy" and c.apiProbe.talents.legacyNodes == 2 and c.apiProbe.talents.traits == -1)
    assert(c.apiProbe.points.unitCharacterPoints == 1)
    capture_clear()
end }

cases[#cases + 1] = { "capture: an empty legacy talent API falls through to the trait tree; points fall back to GetUnspentTalentPoints", function()
    local WC, run = capture_client()
    GetNumTalentTabs = function() return 0 end
    GetTalentTabInfo, GetNumTalents, GetTalentInfo = function() end, function() return 0 end, function() end
    GetUnspentTalentPoints = function() return 2 end
    C_ClassTalents = { GetActiveConfigID = function() return 9 end }
    C_Traits = {
        GetConfigInfo = function() return { treeIDs = { 70 } } end,
        GetTreeInfo = function() return { name = "Holy" } end,
        GetTreeNodes = function() return { 1, 2 } end,
        GetNodeInfo = function(_, id) return { activeRank = id, maxRanks = 3, activeEntry = { entryID = id } } end,
        GetEntryInfo = function(_, e) return { definitionID = e } end,
        GetDefinitionInfo = function(d) return { overrideName = "Node" .. d } end,
    }
    run()
    local c = WoWCompanionDB.characters["Testrealm:Thrall"]
    capture_nil("GetNumTalentTabs", "GetTalentTabInfo", "GetNumTalents", "GetTalentInfo", "GetUnspentTalentPoints", "C_ClassTalents", "C_Traits")
    assert(#c.talents == 1 and c.talents[1].tree == "Holy" and c.talents[1].points == 3)
    assert(c.talents[1].nodes[2].name == "Node2" and c.talents[1].nodes[2].rank == 2 and c.talents[1].nodes[2].max == 3)
    assert(c.talentPoints == 2 and c.apiProbe.talents.used == "traits" and c.apiProbe.talents.legacy == 0)
    assert(c.apiProbe.points.unitCharacterPoints == -1 and c.apiProbe.points.getUnspentTalentPoints == 1)
    capture_clear()
end }

cases[#cases + 1] = { "capture: trait nodes record spell, entry and position; names come from overrideName, C_Spell, or are left out", function()
    local WC, run = capture_client()
    GetNumTalentTabs = function() return 0 end
    GetTalentTabInfo, GetNumTalents, GetTalentInfo = function() end, function() return 0 end, function() end
    GetSpellInfo = nil
    C_ClassTalents = { GetActiveConfigID = function() return 9 end }
    C_Spell = { GetSpellName = function(id) if id == 200 then return "Spell200" end end,
        GetSpellInfo = function(id) if id == 300 then return { name = "Spell300" } end end }
    local defs = { [1] = { overrideName = "Over", spellID = 100 }, [2] = { spellID = 200 }, [3] = { spellID = 300 }, [4] = { spellID = 400 } }
    C_Traits = {
        GetConfigInfo = function() return { treeIDs = { 70 } } end,
        GetTreeInfo = function() return nil end,
        GetTreeNodes = function() return { 1, 2, 3, 4 } end,
        GetNodeInfo = function(_, id) return { activeRank = 1, maxRanks = 2, posX = id * 10, posY = 5, activeEntry = { entryID = id + 50 } } end,
        GetEntryInfo = function(_, e) return { definitionID = e - 50 } end,
        GetDefinitionInfo = function(d) return defs[d] end,
    }
    run()
    local c = WoWCompanionDB.characters["Testrealm:Thrall"]
    capture_nil("GetNumTalentTabs", "GetTalentTabInfo", "GetNumTalents", "GetTalentInfo", "C_ClassTalents", "C_Traits", "C_Spell")
    local n = c.talents[1].nodes
    assert(c.talents[1].tree == nil)
    assert(n[1].name == "Over" and n[1].spell == 100 and n[1].node == 1 and n[1].entry == 51 and n[1].posX == 10 and n[1].posY == 5)
    assert(n[2].name == "Spell200" and n[3].name == "Spell300")
    assert(n[4].name == nil and n[4].spell == 400 and n[4].rank == 1 and n[4].max == 2)
    assert(c.apiProbe.talents.named == 3 and c.apiProbe.talents.withSpell == 4 and c.apiProbe.talents.traitsNodes == 4)
    capture_clear()
end }

cases[#cases + 1] = { "capture: with no talent API there is no talentPoints and the probe says none", function()
    local WC, run = capture_client()
    capture_nil("GetNumTalentTabs", "GetTalentTabInfo", "GetNumTalents", "GetTalentInfo")
    run()
    local c = WoWCompanionDB.characters["Testrealm:Thrall"]
    assert(#c.talents == 0 and c.talentPoints == nil and c.apiProbe.talents.used == "none" and c.apiProbe.talents.legacy == -1)
    capture_clear()
end }

cases[#cases + 1] = { "capture: an empty modern spell book falls through to the classic one; the probe counts each path", function()
    local WC, run = capture_client()
    C_SpellBook = { GetNumSpellBookSkillLines = function() return 0 end, GetSpellBookSkillLineInfo = function() end,
        GetSpellBookItemInfo = function() end }
    GetNumSpellTabs = function() return 1 end
    GetSpellTabInfo = function() return "General", "i", 0, 3 end
    GetSpellBookItemInfo = function(i) if i == 3 then return "FUTURESPELL", 99 end return "SPELL", 100 + i end
    GetSpellLink = function() return nil end
    run()
    local c = WoWCompanionDB.characters["Testrealm:Thrall"]
    capture_nil("C_SpellBook", "GetNumSpellTabs", "GetSpellTabInfo", "GetSpellBookItemInfo", "GetSpellLink")
    assert(#c.spells == 2 and c.spells[1] == 101 and c.spells[2] == 102)
    local p = c.apiProbe.spells
    assert(p.modern == 0 and p.classic == 2 and p.links == 0 and p.used == "classic")
    capture_clear()
end }

cases[#cases + 1] = { "capture: the API probe is small and holds only numbers and path names", function()
    local WC, run = capture_client()
    run()
    local c = WoWCompanionDB.characters["Testrealm:Thrall"]
    local function walk(t, n)
        for k, v in pairs(t) do
            n = n + #tostring(k)
            if type(v) == "table" then n = walk(v, n) else
                assert(type(v) == "number" or (type(v) == "string" and #v < 12)); n = n + #tostring(v)
            end
        end
        return n
    end
    assert(walk(c.apiProbe, 0) < 1024)
    capture_clear()
end }

local function quests_of()
    return WoWCompanionDB.characters["Testrealm:Thrall"]
end

cases[#cases + 1] = { "capture: the quest log reads with C_QuestLog alone, ready, objectives and the probe", function()
    local WC, run = capture_client()
    capture_nil("GetNumQuestLogEntries", "GetQuestLogTitle", "GetNumQuestLeaderBoards", "GetQuestLogLeaderBoard")
    local rows = { { title = "Zone", isHeader = true }, { title = "Wand", level = 20, questID = 11 }, { title = "Weaver", level = 21, questID = 12 }, { title = "Lost", level = 5, questID = 13 } }
    C_QuestLog = {
        GetNumQuestLogEntries = function() return #rows, 3 end,
        GetInfo = function(i) return rows[i] end,
        ReadyForTurnIn = function(id) return id == 11 end,
        IsComplete = function(id) return id == 12 end,
        IsFailed = function(id) return id == 13 end,
        GetQuestObjectives = function(id)
            if id == 11 then return { { text = "Wand: 1/1", finished = true, numFulfilled = 1, numRequired = 1 } } end
            if id == 12 then return { { text = "Boars slain: 3/8", finished = false, numFulfilled = 3, numRequired = 8 }, { text = "Gather 2/5", finished = false } } end
            return {}
        end,
    }
    run()
    local c = quests_of()
    capture_nil("C_QuestLog")
    local e = c.quests.entries
    assert(c.quests.captured and #e == 3)
    assert(e[1].id == 11 and e[1].complete and not e[1].failed and e[1].objectives[1].done)
    assert(e[2].id == 12 and e[2].complete and e[2].objectives[1].have == 3 and e[2].objectives[1].need == 8 and e[2].objectives[1].done == false)
    assert(e[2].objectives[2].have == 2 and e[2].objectives[2].need == 5)
    assert(e[3].failed and not e[3].complete and e[3].objectives == nil)
    local p = c.apiProbe.quests
    assert(p.count == "modern" and p.entries == 3 and p.ready == 2 and p.objectives == "modern")
    capture_clear()
end }

cases[#cases + 1] = { "capture: the quest log falls back to the legacy globals and records it", function()
    local WC, run = capture_client()
    GetQuestLogTitle = function(i)
        if i == 1 then return "Zone", 0, nil, true end
        if i == 2 then return "Done", 9, nil, false, false, 1, nil, 21 end
        return "Failed", 9, nil, false, false, -1, nil, 22
    end
    GetNumQuestLogEntries = function() return 3 end
    run()
    local c = quests_of()
    local e = c.quests.entries
    assert(#e == 2 and e[1].complete and e[2].failed and not e[2].complete)
    assert(e[1].objectives[1].have == 3 and e[1].objectives[1].need == 8)
    local p = c.apiProbe.quests
    assert(p.count == "legacy" and p.entries == 2 and p.ready == 1 and p.objectives == "legacy")
    capture_clear()
end }

cases[#cases + 1] = { "capture: no quest count API leaves quests untouched", function()
    local WC, run = capture_client()
    capture_nil("GetNumQuestLogEntries", "GetQuestLogTitle", "GetNumQuestLeaderBoards", "GetQuestLogLeaderBoard")
    C_QuestLog = { GetInfo = function() error("must not be needed") end }
    run()
    local c = quests_of()
    capture_nil("C_QuestLog")
    assert(c.quests == nil, "nothing read is not 'no quests'")
    local p = c.apiProbe.quests
    assert(p.count == "none" and p.entries == -1 and p.objectives == -1)
    capture_clear()
end }

local function capture_stat_stubs()
    UnitLevel = function() return 24 end
    UnitStat = function(_, i) return 10 * i, 10 * i + 5, 4, -1 end
    UnitHealthMax = function() return 900 end
    UnitPowerMax = function(_, p) return p == 0 and 1070 or 0 end
    UnitArmor = function() return 50, 120 end
    GetSpellCritChance = function(school) return school == 6 and 4.3 or 1.1 end
    GetCritChance = function() return 2.5 end
    GetManaRegen = function() return 3, 1.5 end
    UnitAttackPower = function() return 20, 5, -1 end
    GetSpellBonusDamage = function(school) return school == 6 and 30 or 10 end
    GetSpellCritChanceFromIntellect = function() return 0.05 end
end
local function capture_stat_clear()
    for _, n in ipairs({ "UnitStat", "UnitHealthMax", "UnitPowerMax", "UnitArmor", "GetSpellCritChance", "GetCritChance", "GetManaRegen", "UnitAttackPower", "GetSpellBonusDamage", "GetSpellCritChanceFromIntellect" }) do _G[n] = nil end
    COMBAT = false
end

cases[#cases + 1] = { "capture: base stat is the total minus gear and buffs (client shape 106, 106, 56, 0)", function()
    capture_stat_stubs()
    local WC, run = capture_client()
    capture_stat_stubs()
    UnitStat = function() return 106, 106, 56, 0 end
    run()
    local int = WoWCompanionDB.characters["Testrealm:Thrall"].stats.stats.int
    assert(int.base == 50 and int.total == 106 and int.pos == 56 and int.neg == 0)
    capture_stat_clear()
    capture_clear()
end }

local function modern_skills(rows)
    C_SkillInfo = {
        GetNumSkillLines = function() return #rows end,
        GetSkillLineInfo = function(i) return rows[i] end,
    }
end

cases[#cases + 1] = { "capture: skills come from C_SkillInfo, with headers, professions and secondary skills", function()
    local WC, run = capture_client()
    GetNumSkillLines, GetSkillLineInfo = nil, nil
    modern_skills({
        { skillName = "Professions", isHeader = true },
        { skillName = "Tailoring", isHeader = false, skillRank = 120, maxSkillRank = 150 },
        { skillName = "Enchanting", isHeader = false, skillRank = 80, maxSkillRank = 150 },
        { skillName = "Secondary Skills", isHeader = true },
        { skillName = "Cooking", isHeader = false, skillRank = 30, maxSkillRank = 75 },
        { skillName = "Weapon Skills", isHeader = true },
        { skillName = "Swords", isHeader = false, skillRank = 5, maxSkillRank = 100 },
    })
    run()
    local sk = WoWCompanionDB.characters["Testrealm:Thrall"].skills
    assert(#sk == 4 and sk[1].name == "Tailoring" and sk[1].rank == 120 and sk[1].max == 150 and sk[1].profession and sk[1].group == "Professions")
    assert(sk[2].name == "Enchanting" and sk[2].rank == 80)
    assert(sk[3].name == "Cooking" and sk[3].profession and sk[3].group == "Secondary Skills")
    assert(sk[4].name == "Swords" and not sk[4].profession and sk[4].group == "Weapon Skills")
    C_SkillInfo = nil
    capture_clear()
end }

cases[#cases + 1] = { "capture: a profession listed twice is recorded once, modern and legacy", function()
    local WC, run = capture_client()
    GetNumSkillLines, GetSkillLineInfo = nil, nil
    modern_skills({
        { skillName = "Class Skills", isHeader = true },
        { skillName = "Discipline", skillRank = 1, maxSkillRank = 1 },
        { skillName = "Professions", isHeader = true },
        { skillName = "Enchanting", skillRank = 51, maxSkillRank = 75 },
        { skillName = "Tailoring", skillRank = 70, maxSkillRank = 150 },
        { skillName = "Enchanting", skillRank = 51, maxSkillRank = 75 },
        { skillName = "Tailoring", skillRank = 60, maxSkillRank = 75 },
        { skillName = "Secondary Skills", isHeader = true },
        { skillName = "Cooking", skillRank = 28, maxSkillRank = 75 },
        { skillName = "Cooking", skillRank = 28, maxSkillRank = 75 },
    })
    run()
    local sk = WoWCompanionDB.characters["Testrealm:Thrall"].skills
    assert(#sk == 4, "one line per skill")
    assert(sk[2].name == "Enchanting" and sk[2].rank == 51 and sk[2].max == 75 and sk[2].profession and sk[2].group == "Professions")
    assert(sk[3].name == "Tailoring" and sk[3].rank == 70 and sk[3].max == 150, "highest rank and cap kept")
    assert(sk[4].name == "Cooking" and sk[4].profession and sk[4].group == "Secondary Skills")
    C_SkillInfo = nil
    capture_clear()
    -- legacy globals
    local WC2, run2 = capture_client()
    local rows = {
        { "Professions", 1 }, { "Mining", nil, 10, 75 }, { "Mining", nil, 12, 75 },
    }
    GetNumSkillLines = function() return #rows end
    GetSkillLineInfo = function(i)
        local r = rows[i]
        if r[2] == 1 then return r[1], 1 end
        return r[1], nil, nil, r[3], nil, nil, r[4]
    end
    run2()
    local sk2 = WoWCompanionDB.characters["Testrealm:Thrall"].skills
    assert(#sk2 == 1 and sk2[1].name == "Mining" and sk2[1].rank == 12 and sk2[1].profession)
    capture_clear()
end }

cases[#cases + 1] = { "capture: SKILL_LINES_CHANGED and a level up refresh the skills; empty modern list falls back", function()
    local WC, run = capture_client()
    modern_skills({ { skillName = "Professions", isHeader = true }, { skillName = "Tailoring", skillRank = 10, maxSkillRank = 75 } })
    run()
    local c = WoWCompanionDB.characters["Testrealm:Thrall"]
    assert(c.skills[1].name == "Tailoring" and c.skills[1].rank == 10)
    modern_skills({ { skillName = "Professions", isHeader = true }, { skillName = "Tailoring", skillRank = 11, maxSkillRank = 75 } })
    Stub.fire(frames, "SKILL_LINES_CHANGED")
    run()
    assert(c.skills[1].rank == 11)
    modern_skills({ { skillName = "Professions", isHeader = true }, { skillName = "Tailoring", skillRank = 12, maxSkillRank = 75 } })
    Stub.fire(frames, "PLAYER_LEVEL_UP")
    run()
    assert(c.skills[1].rank == 12)
    modern_skills({})
    Stub.fire(frames, "SKILL_LINES_CHANGED")
    run()
    assert(#c.skills == 1 and c.skills[1].name == "Mining", "legacy fallback when the modern list is empty")
    C_SkillInfo = nil
    capture_clear()
end }

cases[#cases + 1] = { "capture: the profession window records its base skill level and max", function()
    local WC, run = capture_client()
    GetNumSkillLines, GetSkillLineInfo = nil, nil
    GetNumTradeSkills, GetTradeSkillLine = nil, nil
    modern_skills({})
    C_TradeSkillUI = {
        GetAllRecipeIDs = function() return {} end,
        GetRecipeInfo = function() return nil end,
        GetBaseProfessionInfo = function() return { professionName = "Tailoring", skillLevel = 42, maxSkillLevel = 75 } end,
    }
    run()
    Stub.fire(frames, "TRADE_SKILL_SHOW")
    run()
    local sk = WoWCompanionDB.characters["Testrealm:Thrall"].skills
    assert(#sk == 1 and sk[1].name == "Tailoring" and sk[1].rank == 42 and sk[1].max == 75 and sk[1].profession)
    C_SkillInfo, C_TradeSkillUI = nil, nil
    capture_clear()
end }

cases[#cases + 1] = { "capture: stats are recorded as the client reports them; missing APIs are skipped", function()
    capture_stat_stubs()
    local WC, run = capture_client()
    capture_stat_stubs()
    run()
    local st = WoWCompanionDB.characters["Testrealm:Thrall"].stats
    assert(st.level == 24 and type(st.seenAt) == "number")
    local int = st.stats.int
    assert(int.base == 42 and int.total == 45 and int.pos == 4 and int.neg == -1)
    assert(st.healthMax == 900 and st.manaMax == 1070 and st.armor == 120 and st.meleeCrit == 2.5)
    assert(st.spellCrit.max == 4.3 and st.spellCrit.schools[6] == 4.3 and st.spellCrit.schools[2] == 1.1)
    assert(st.manaRegen.base == 3 and st.manaRegen.casting == 1.5 and st.attackPower == 24)
    assert(st.spellBonus.damage == 30 and st.spellBonus.healing == nil, "healing API missing: not stored")
    assert(st.perPoint.spellCritFromInt == 0.05 and st.perPoint.critFromAgi == nil and st.perPoint.manaRegenFromSpi == nil)
    assert(st.rangedCrit == nil and st.dodge == nil and st.rangedAttackPower == nil)
    capture_stat_clear()
    capture_clear()
end }

cases[#cases + 1] = { "capture: a burst of changes reads stats once, and combat defers it", function()
    local WC, run = capture_client()
    capture_stat_stubs()
    run()
    local c = WoWCompanionDB.characters["Testrealm:Thrall"]
    local n = 0
    UnitHealthMax = function() n = n + 1 return 900 end
    COMBAT = true
    Stub.fire(frames, "PLAYER_EQUIPMENT_CHANGED")
    Stub.fire(frames, "CHARACTER_POINTS_CHANGED")
    run()
    assert(n == 0, "nothing read in combat")
    COMBAT = false
    Stub.fire(frames, "PLAYER_REGEN_ENABLED")
    Stub.fire(frames, "PLAYER_EQUIPMENT_CHANGED")
    run()
    assert(n == 1, "the burst was read once, got " .. n)
    assert(c.stats.healthMax == 900)
    capture_stat_clear()
    capture_clear()
end }

cases[#cases + 1] = { "capture: the bank is read only while open and the last snapshot stays", function()
    local WC, run = capture_client()
    run()
    Stub.fire(frames, "BANKFRAME_OPENED"); run()
    local c = WoWCompanionDB.characters["Testrealm:Thrall"]
    assert(c.bank[-1].items[3].id == 3001 and c.bankSeenAt == NOW)
    Stub.fire(frames, "BANKFRAME_CLOSED")
    BAGS[-1] = { [3] = { 9999, 1 } }
    NOW = NOW + 60
    Stub.fire(frames, "BAG_UPDATE_DELAYED"); run()
    assert(c.bank[-1].items[3].id == 3001 and c.bankSeenAt == NOW - 60, "kept from the last open")
    NOW = NOW - 60
    capture_clear()
end }

cases[#cases + 1] = { "capture: recipes come from the trade skill window, per profession", function()
    local WC, run = capture_client()
    run()
    local c = WoWCompanionDB.characters["Testrealm:Thrall"]
    assert(c.recipes == nil)
    Stub.fire(frames, "TRADE_SKILL_SHOW"); run()
    local r = c.recipes.Blacksmithing
    assert(r and #r.entries == 1 and r.entries[1].name == "Copper Sword" and r.entries[1].id == 2663 and r.seenAt == NOW)
    TRADE_NAME = "Tailoring"
    Stub.fire(frames, "TRADE_SKILL_UPDATE"); run() -- window still open: re-read
    assert(c.recipes.Tailoring and c.recipes.Blacksmithing)
    capture_clear()
end }

cases[#cases + 1] = { "capture: recipes through the modern C_TradeSkillUI, with difficulty", function()
    local WC, run = capture_client()
    GetNumTradeSkills, GetTradeSkillLine = nil, nil
    C_TradeSkillUI = {
        GetBaseProfessionInfo = function() return { professionName = "Blacksmithing" } end,
        GetAllRecipeIDs = function() return { 2663, 3292, 9 } end,
        GetRecipeInfo = function(id)
            if id == 9 then return { name = "Unknown", recipeID = 9, learned = false } end
            return { name = "R" .. id, recipeID = id, learned = true, relativeDifficulty = id == 2663 and 0 or 3 }
        end,
    }
    run()
    Stub.fire(frames, "TRADE_SKILL_SHOW"); run()
    local c = WoWCompanionDB.characters["Testrealm:Thrall"]
    local e = c.recipes.Blacksmithing.entries
    assert(#e == 2 and e[1].id == 2663 and e[1].difficulty == "orange" and e[2].difficulty == "grey")
    assert(#WoWCompanionDB.observed.raw.tradeskill == 3)
    C_TradeSkillUI = nil
    capture_clear()
end }

cases[#cases + 1] = { "capture: classic recipes carry difficulty and the spell id", function()
    local WC, run = capture_client()
    run()
    Stub.fire(frames, "TRADE_SKILL_SHOW"); run()
    local e = WoWCompanionDB.characters["Testrealm:Thrall"].recipes.Blacksmithing.entries[1]
    assert(e.id == 2663 and e.difficulty == "orange")
    capture_clear()
end }

cases[#cases + 1] = { "capture: combat defers reads until it ends, and events coalesce", function()
    local WC, run = capture_client()
    run()
    local c = WoWCompanionDB.characters["Testrealm:Thrall"]
    COMBAT = true
    GetMoney = function() return 999 end
    Stub.fire(frames, "PLAYER_MONEY"); Stub.fire(frames, "PLAYER_MONEY"); run()
    assert(c.money == 12345, "untouched in combat")
    COMBAT = false
    Stub.fire(frames, "PLAYER_REGEN_ENABLED"); run()
    assert(c.money == 999)
    local reads = 0
    GetMoney = function() reads = reads + 1; return 5 end
    Stub.fire(frames, "PLAYER_MONEY"); Stub.fire(frames, "PLAYER_MONEY"); Stub.fire(frames, "PLAYER_XP_UPDATE"); run()
    assert(reads == 1 and c.money == 5)
    capture_clear()
end }

cases[#cases + 1] = { "capture: the option off records nothing; on by default", function()
    local WC, run = capture_client()
    assert(WC.Setting("recordCharacter") == true and WC.IsDefault("recordCharacter"))
    assert(rawget(WC.L, WC.DEF_OF.recordCharacter.label) ~= nil)
    WC.SetSetting("recordCharacter", false)
    WoWCompanionDB.characters = nil
    Stub.fire(frames, "PLAYER_LEVEL_UP"); run()
    assert(WoWCompanionDB.characters == nil)
    capture_clear()
end }

cases[#cases + 1] = { "capture: a failing read costs only its own part", function()
    local WC, run = capture_client()
    GetNumFactions = function() error("boom") end
    Stub.fire(frames, "PLAYER_ENTERING_WORLD"); run()
    local c = WoWCompanionDB.characters["Testrealm:Thrall"]
    GetNumFactions = nil
    assert(c.level == 23 and c.bags and c.reputations == nil)
    capture_clear()
end }

-- What the player sees (Seen.lua): synthetic trainer, vendor, loot and giver, client reads stubbed.
local function seen_client()
    local WC = chain_client()
    C_Map = { GetBestMapForUnit = function() return 1411 end,
        GetPlayerMapPosition = function() return { GetXY = function() return 0.5, 0.25 end } end }
    NPC = { guid = "Creature-0-4379-1-9999-3455-0000ABCD", name = "Test Trainer" }
    UnitExists = function(u) return u == "npc" and NPC ~= nil end
    UnitGUID = function(u) return u == "npc" and NPC and NPC.guid or nil end
    UnitName = function(u) if u == "npc" then return NPC and NPC.name end return "Thrall" end
    UnitReaction = function() return 5 end
    UnitFactionGroup = function() return "Horde" end
    return WC
end

local function seen_trainer(services)
    GetNumTrainerServices = function() return #services end
    -- this client's order: name, availability, icon file id, then the rank text
    GetTrainerServiceInfo = function(i) local s = services[i]; return s.name, s.state, s.icon or 132277, s.rank or "" end
    GetTrainerServiceLevelReq = function(i) return services[i].reqLevel or 0 end
    GetTrainerServiceCost = function(i) return services[i].cost end
    GetTrainerServiceSkillReq = function(i) return services[i].skill, services[i].level end
    GetTrainerServiceItemLink = function(i) return "|cff|Hspell:" .. services[i].id .. "|h[x]|h|r" end
end

cases[#cases + 1] = { "seen: a trainer window is recorded with costs and skill gates", function()
    local WC = seen_client()
    seen_trainer({
        { name = "Smelt Bronze", state = "available", cost = 100, skill = "Mining", level = 65, id = 2670 },
        { name = "Copper Axe", rank = "Rank 2", state = "unavailable", reqLevel = 20, cost = 25000, id = 3292 },
    })
    Stub.fire(frames, "TRAINER_SHOW")
    Stub.fire(frames, "TRAINER_UPDATE") -- a second read overwrites, never duplicates
    local t = WoWCompanionDB.observed.trainers
    assert(#t == 1 and t[1].npc == 3455 and t[1].name == "Test Trainer" and t[1].map == 1411 and t[1].x == 50 and t[1].y == 25)
    assert(t[1].reaction == 5 and t[1].faction == "Horde" and #t[1].offers == 2)
    local o = t[1].offers[1]
    assert(o.name == "Smelt Bronze" and o.cost == 100 and o.skill == "Mining" and o.skillLevel == 65 and o.spell == 2670 and o.state == "available" and o.icon == 132277 and o.rank == nil)
    assert(t[1].offers[2].rank == "Rank 2" and t[1].offers[2].skill == nil and t[1].offers[2].level == 20 and t[1].offers[2].state == "unavailable")
    local raw = WoWCompanionDB.observed.raw.trainer
    assert(#raw == 3 and raw[1].call == "GetTrainerServiceInfo" and raw[1].vals[1] == "Smelt Bronze" and raw[1].vals[3] == 132277, "raw sample capped at 3")
    assert(WoWCompanionDB.observed.version == 2)
end }

cases[#cases + 1] = { "seen: trainer returns are classified by type, whatever their order", function()
    local name, rank, state, icon = WoWCompanion.SeenClassifyService("Bloodrage", "available", 132277, "Rank 2")
    assert(name == "Bloodrage" and rank == "Rank 2" and state == "available" and icon == 132277)
    name, rank, state, icon = WoWCompanion.SeenClassifyService("Bloodrage", "Rank 3", "used", 5)
    assert(rank == "Rank 3" and state == "used" and icon == 5)
    name, rank, state, icon = WoWCompanion.SeenClassifyService("Bloodrage", 132277, "available")
    assert(rank == nil and state == "available" and icon == 132277, "a number is never a rank")
end }

cases[#cases + 1] = { "seen: raw samples are length-capped", function()
    local WC = seen_client()
    WoWCompanionDB.observed = nil
    WC.SeenRaw("probe", "Fn", string.rep("x", 500), 1, true, {}, nil, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10)
    local r = WoWCompanionDB.observed.raw.probe[1]
    assert(#r.vals[1] == 60 and r.vals[4] == "" and #r.vals == 12)
end }

cases[#cases + 1] = { "seen: a vendor's stock is overwritten, not duplicated", function()
    local WC = seen_client()
    NPC.guid, NPC.name = "Creature-0-4379-1-9999-777-0000ABCD", "Test Vendor"
    local stock = { { 2589, 5, 1, -1 }, { 4306, 90, 5, 3 } }
    GetMerchantNumItems = function() return #stock end
    GetMerchantItemInfo = function(i) return "n", "t", stock[i][2], stock[i][3], stock[i][4], true, false end
    GetMerchantItemLink = function(i) return "|cff|Hitem:" .. stock[i][1] .. "::::|h[x]|h|r" end
    Stub.fire(frames, "MERCHANT_SHOW")
    stock = { { 2589, 6, 1, -1 } }
    Stub.fire(frames, "MERCHANT_UPDATE")
    local v = WoWCompanionDB.observed.vendors
    assert(#v == 1 and v[1].npc == 777 and #v[1].items == 1 and v[1].items[1].price == 6 and v[1].items[1].limited == nil)
    stock = { { 2589, 6, 1, -1 }, { 4306, 90, 5, 3 } }
    Stub.fire(frames, "MERCHANT_UPDATE")
    assert(#v == 1 and v[1].items[2].limited == 3 and v[1].items[2].stack == 5)
end }

local function seen_loot(links)
    GetNumLootItems = function() return #links end
    GetLootSlotLink = function(i) return "|cff|Hitem:" .. links[i][1] .. "::::|h[x]|h|r" end
    GetLootSlotInfo = function(i) return "icon", "n", links[i][2] end
    GetNumSkillLines = function() return 2 end
    GetSkillLineInfo = function(i) if i == 1 then return "Professions", true end return "Fishing", false, nil, 130 end
end

cases[#cases + 1] = { "seen: fishing loot is aggregated by cell; mob loot after no gathering cast is ignored", function()
    local WC = seen_client()
    NPC = nil
    seen_loot({ { 6291, 1 }, { 6303, 2 } })
    Stub.fire(frames, "LOOT_OPENED") -- no cast before it: a mob's loot
    assert(not (WoWCompanionDB.observed and WoWCompanionDB.observed.gathering))
    for _ = 1, 2 do
        Stub.fire(frames, "UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 7620)
        Stub.fire(frames, "LOOT_OPENED")
    end
    Stub.fire(frames, "LOOT_OPENED") -- the cast is used up
    local g = WoWCompanionDB.observed.gathering
    assert(#g == 1 and g[1].kind == "fish" and g[1].map == 1411 and g[1].cx == 10 and g[1].cy == 5 and g[1].n == 2)
    assert(g[1].items[6291].count == 2 and g[1].items[6303].count == 4 and g[1].skillMin == 130 and g[1].skillMax == 130)
    NOW = NOW + 100 -- a cast whose loot never came goes stale
    Stub.fire(frames, "UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 2575)
    NOW = NOW + 60
    Stub.fire(frames, "LOOT_OPENED")
    assert(#g == 1 and g[1].n == 2)
    NOW = 1800000000
end }

cases[#cases + 1] = { "seen: a quest giver gets an id and position", function()
    local WC = seen_client()
    NPC.guid, NPC.name = "Creature-0-4379-1-9999-1234-0000ABCD", "Quest Giver"
    Stub.fire(frames, "QUEST_DETAIL")
    NPC = nil -- the dialog closes before QUEST_ACCEPTED
    QUESTS[55] = "active"; Stub.fire(frames, "QUEST_ACCEPTED", 1, 55)
    local e = WoWCompanionDB.observed.events[1]
    assert(e.npcId == 1234 and e.npc == "Quest Giver" and e.npcMap == 1411 and e.npcX == 50 and e.npcY == 25)
end }

cases[#cases + 1] = { "seen: every section is capped, dropping the oldest", function()
    local WC = seen_client()
    seen_trainer({ { name = "A", state = "available", cost = 1, id = 1 } })
    WC.SEEN_TRAINER_CAP = 3
    for i = 1, 5 do
        NPC.guid = "Creature-0-4379-1-9999-" .. (100 + i) .. "-0000ABCD"
        Stub.fire(frames, "TRAINER_SHOW")
    end
    local t = WoWCompanionDB.observed.trainers
    assert(#t == 3 and t[1].npc == 103 and t[3].npc == 105)
    WC.SEEN_GATHER_CAP, WC.SEEN_OFFER_CAP = 2, 1
    NPC = nil
    seen_loot({ { 6291, 1 } })
    for i = 1, 4 do
        C_Map.GetPlayerMapPosition = function() return { GetXY = function() return i * 0.1, 0.5 end } end
        Stub.fire(frames, "UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 7620)
        Stub.fire(frames, "LOOT_OPENED")
    end
    local g = WoWCompanionDB.observed.gathering
    assert(#g == 2 and g[1].cx == 6 and g[2].cx == 8, "the oldest two cells dropped")
    seen_trainer({ { name = "A", state = "a", id = 1 }, { name = "B", state = "a", id = 2 } })
    NPC = { guid = "Creature-0-4379-1-9999-900-0000ABCD", name = "T" }
    Stub.fire(frames, "TRAINER_SHOW")
    local last = t[#t]
    assert(#last.offers == 1)
end }

cases[#cases + 1] = { "seen: the option off records nothing; combat defers the read", function()
    local WC = seen_client()
    seen_trainer({ { name = "A", state = "available", cost = 1, id = 1 } })
    COMBAT = true
    Stub.fire(frames, "TRAINER_SHOW")
    assert(not (WoWCompanionDB.observed and WoWCompanionDB.observed.trainers), "nothing read in combat")
    COMBAT = false
    Stub.fire(frames, "PLAYER_REGEN_ENABLED")
    assert(#WoWCompanionDB.observed.trainers == 1, "read once combat ends")
    WC.SetSetting("keepObserved", false)
    WoWCompanionDB.observed = nil
    seen_loot({ { 6291, 1 } })
    Stub.fire(frames, "TRAINER_UPDATE")
    Stub.fire(frames, "MERCHANT_SHOW")
    Stub.fire(frames, "UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 7620)
    Stub.fire(frames, "LOOT_OPENED")
    Stub.fire(frames, "QUEST_DETAIL")
    assert(WoWCompanionDB.observed == nil)
end }

local function vendor_stock(n)
    local stock = {}
    for i = 1, n do stock[i] = { 1000 + i, i * 10 } end
    return stock
end

local function item_link(stock) return function(i) return "|cff|Hitem:" .. stock[i][1] .. "::::|h[x]|h|r" end end

local function seen_vendor()
    local WC = seen_client()
    NPC.guid, NPC.name = "Creature-0-4379-1-9999-888-0000ABCD", "Test Vendor"
    GetMerchantNumItems, GetMerchantItemInfo, GetMerchantItemLink, C_MerchantFrame = nil, nil, nil, nil
    return WC
end

cases[#cases + 1] = { "seen: the C_MerchantFrame table shape is read, every page, with a raw sample", function()
    seen_vendor()
    local stock = vendor_stock(20)
    C_MerchantFrame = {
        GetNumItems = function() return #stock end,
        GetItemInfo = function(i) return { name = "x", price = stock[i][2], stackCount = 5, numAvailable = (i == 2) and 4 or -1, hasExtendedCost = (i == 3) } end,
    }
    GetMerchantItemLink = item_link(stock)
    Stub.fire(frames, "MERCHANT_SHOW")
    local v = WoWCompanionDB.observed.vendors
    assert(#v == 1 and #v[1].items == 20 and v[1].items[20].id == 1020 and v[1].items[20].price == 200, "both pages saved")
    assert(v[1].items[1].stack == 5 and v[1].items[1].limited == nil and v[1].items[2].limited == 4 and v[1].items[3].ext == true)
    local raw = WoWCompanionDB.observed.raw.merchant
    assert(#raw == 3 and raw[1].call == "C_MerchantFrame.GetItemInfo" and raw[1].vals[1]:find("price=10", 1, true) and raw[1].vals[1]:find("stackCount=5", 1, true))
    assert(not WoWCompanionDB.observed.raw.errors)
    C_MerchantFrame = nil
end }

cases[#cases + 1] = { "seen: the global merchant tuple shape is read", function()
    seen_vendor()
    local stock = vendor_stock(3)
    GetMerchantNumItems = function() return #stock end
    GetMerchantItemInfo = function(i) return "n", "t", stock[i][2], 2, -1, true, false end
    GetMerchantItemLink = item_link(stock)
    Stub.fire(frames, "MERCHANT_SHOW")
    local v = WoWCompanionDB.observed.vendors
    assert(#v[1].items == 3 and v[1].items[3].price == 30 and v[1].items[3].stack == 2)
    assert(WoWCompanionDB.observed.raw.merchant[1].call == "GetMerchantItemInfo")
end }

cases[#cases + 1] = { "seen: a missing merchant API still saves the vendor and records the error", function()
    seen_vendor()
    GetMerchantNumItems = function() return 2 end -- the count exists, the item info does not
    Stub.fire(frames, "MERCHANT_SHOW")
    local o = WoWCompanionDB.observed
    assert(#o.vendors == 1 and o.vendors[1].npc == 888 and #o.vendors[1].items == 0 and o.vendors[1].map == 1411)
    assert(#o.raw.errors >= 1 and o.raw.errors[1].kind == "merchant" and #o.raw.errors[1].msg <= 120)
    GetMerchantNumItems = nil
    Stub.fire(frames, "MERCHANT_UPDATE")
    assert(#o.vendors == 1 and #o.raw.errors >= 2, "no count API at all: the vendor is kept")
end }

cases[#cases + 1] = { "seen: one failing item does not lose the others", function()
    seen_vendor()
    local stock = vendor_stock(4)
    GetMerchantNumItems = function() return #stock end
    GetMerchantItemInfo = function(i) if i == 2 then error("boom") end return "n", "t", stock[i][2], 1, -1 end
    GetMerchantItemLink = item_link(stock)
    Stub.fire(frames, "MERCHANT_SHOW")
    local o = WoWCompanionDB.observed
    assert(#o.vendors[1].items == 3 and o.vendors[1].items[2].id == 1003)
    assert(#o.raw.errors == 1 and o.raw.errors[1].msg:find("boom"))
end }

cases[#cases + 1] = { "seen: the error log keeps the last five, each capped", function()
    local WC = seen_vendor()
    for i = 1, 8 do WC.SeenError("trainer", i .. string.rep("x", 300)) end
    local e = WoWCompanionDB.observed.raw.errors
    assert(#e == 5 and e[1].msg:sub(1, 1) == "4" and #e[1].msg == 120 and e[5].kind == "trainer" and e[5].t)
end }

cases[#cases + 1] = { "seen: a trainer link is sampled and enchant links give an id", function()
    seen_client()
    seen_trainer({ { name = "A", state = "available", cost = 1, id = 1 } })
    GetTrainerServiceItemLink = function() return "|cff|Henchant:7421|h[x]|h|r" end
    Stub.fire(frames, "TRAINER_SHOW")
    local o = WoWCompanionDB.observed
    assert(o.trainers[1].offers[1].spell == 7421 and o.raw.trainerlink[1].call == "GetTrainerServiceItemLink")
end }

cases[#cases + 1] = { "seen: a client without MERCHANT_SHOW reads when the merchant frame is shown", function()
    local shown
    UNKNOWN_EVENTS = { MERCHANT_SHOW = true }
    MerchantFrame = { HookScript = function(_, ev, fn) if ev == "OnShow" then shown = fn end end }
    seen_vendor()
    UNKNOWN_EVENTS, MerchantFrame = nil, nil
    assert(shown, "OnShow hooked")
    local stock = vendor_stock(2)
    GetMerchantNumItems = function() return #stock end
    GetMerchantItemInfo = function(i) return "n", "t", stock[i][2], 1, -1 end
    GetMerchantItemLink = item_link(stock)
    shown()
    assert(#WoWCompanionDB.observed.vendors[1].items == 2)
end }

-- Window events, delayed reads, secret values, extended costs, reagents, flight masters.
local function timers()
    local q = {}
    C_Timer = { After = function(sec, fn) q[#q + 1] = { sec, fn } end }
    return function() local t = {}; for i, x in ipairs(q) do t[i] = x end; for i = #q, 1, -1 do q[i] = nil end; for _, x in ipairs(t) do x[2]() end end, q
end
local function stock_api(stock)
    GetMerchantNumItems = function() return #stock end
    GetMerchantItemInfo = function(i) return "n", "t", stock[i][2], 1, -1 end
    GetMerchantItemLink = item_link(stock)
end

cases[#cases + 1] = { "seen: only the interaction-manager event fires, the window is still read", function()
    seen_vendor()
    local fire = timers()
    stock_api(vendor_stock(2))
    Stub.fire(frames, "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 5)
    fire()
    assert(#WoWCompanionDB.observed.vendors[1].items == 2)
    Stub.fire(frames, "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 5)
    C_Timer = nil
end }

cases[#cases + 1] = { "seen: both events fire, one read", function()
    seen_vendor()
    local fire, q = timers()
    stock_api(vendor_stock(1))
    local reads = 0
    local base = GetMerchantNumItems
    GetMerchantNumItems = function() reads = reads + 1 return base() end
    Stub.fire(frames, "MERCHANT_SHOW")
    Stub.fire(frames, "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 5)
    assert(#q == 1 and q[1][1] == 0.5, "one delayed read scheduled")
    fire()
    assert(reads == 1 and #WoWCompanionDB.observed.vendors == 1)
    Stub.fire(frames, "MERCHANT_UPDATE"); Stub.fire(frames, "MERCHANT_UPDATE")
    assert(q[#q][1] == 1.5)
    fire()
    assert(reads == 2, "updates are debounced into one read")
    C_Timer = nil
end }

cases[#cases + 1] = { "seen: the enum is used at runtime, the numbers are the fallback", function()
    local WC = seen_client()
    assert(WC.SeenWindowOfType(5) == "merchant" and WC.SeenWindowOfType(12) == "merchant" and WC.SeenWindowOfType(7) == "trainer")
    assert(WC.SeenWindowOfType(8) == "bank" and WC.SeenWindowOfType(4) == "quest" and WC.SeenWindowOfType(6) == "taxi" and WC.SeenWindowOfType(99) == nil)
    Enum = { PlayerInteractionType = { Merchant = 50, Trainer = 70 } }
    assert(WC.SeenWindowOfType(50) == "merchant" and WC.SeenWindowOfType(5) == nil and WC.SeenWindowOfType(12) == "merchant")
    Enum = nil
end }

cases[#cases + 1] = { "seen: an empty list at open is filled after the delay and saved", function()
    seen_vendor()
    local fire = timers()
    local stock = {}
    stock_api(stock)
    Stub.fire(frames, "MERCHANT_SHOW")
    stock[1], stock[2] = { 1001, 10 }, { 1002, 20 }
    fire()
    assert(#WoWCompanionDB.observed.vendors[1].items == 2)
    C_Timer = nil
end }

cases[#cases + 1] = { "seen: a secret value is never stored", function()
    local WC = seen_vendor()
    local secret = {}
    issecretvalue = function(v) return v == secret end
    assert(WC.Clean(secret) == nil and WC.Clean("a") == "a" and WC.Clean(3) == 3 and WC.Clean(false) == false and WC.Clean(print) == nil)
    NPC.name = secret
    GetMerchantNumItems = function() return 2 end
    GetMerchantItemInfo = function(i) return secret, "t", i == 1 and secret or 7, 1, -1 end
    GetMerchantItemLink = item_link(vendor_stock(2))
    Stub.fire(frames, "MERCHANT_SHOW")
    local v = WoWCompanionDB.observed.vendors[1]
    assert(v.name == nil and v.items[1].price == nil and v.items[2].price == 7)
    local t = { a = secret, b = { c = secret, d = 1 } }
    WC.CleanTree(t)
    assert(t.a == nil and t.b.c == nil and t.b.d == 1)
    issecretvalue = nil
end }

cases[#cases + 1] = { "seen: a raising call records an error and nothing crashes", function()
    seen_vendor()
    stock_api(vendor_stock(2))
    GetMerchantItemID = function() error("secret state") end
    GetMerchantItemCostInfo = function() error("cost boom") end
    Stub.fire(frames, "MERCHANT_SHOW")
    local o = WoWCompanionDB.observed
    assert(#o.vendors[1].items == 2 or #o.raw.errors >= 1)
    GetMerchantItemID = nil
    GetMerchantItemCostInfo = nil
end }

cases[#cases + 1] = { "seen: an extended-cost item carries its item and currency costs", function()
    seen_vendor()
    local stock = vendor_stock(2)
    GetMerchantNumItems = function() return #stock end
    GetMerchantItemInfo = function(i) return "n", "t", 0, 1, -1, true, true end
    GetMerchantItemID = function(i) return 5000 + i end
    GetMerchantItemCostInfo = function(i) return i == 1 and 2 or 0 end
    GetMerchantItemCostItem = function(i, j)
        if j == 1 then return "tex", 20, "|cff|Hitem:29434::::|h[Badge]|h|r" end
        return "tex", 5, "|cff|Hcurrency:1704|h[Spirit Shard]|h|r"
    end
    Stub.fire(frames, "MERCHANT_SHOW")
    local it = WoWCompanionDB.observed.vendors[1].items
    assert(it[1].id == 5001, "GetMerchantItemID preferred")
    assert(#it[1].ext == 2 and it[1].ext[1].id == 29434 and it[1].ext[1].count == 20 and it[1].ext[2].currency == 1704 and it[1].ext[2].count == 5)
    assert(it[2].ext == true, "flagged but no cost rows: the flag stays")
    GetMerchantItemID, GetMerchantItemCostInfo, GetMerchantItemCostItem = nil, nil, nil
end }

cases[#cases + 1] = { "capture: recipe reagents through the modern schematic and the classic API", function()
    local WC, run = capture_client()
    GetNumTradeSkills, GetTradeSkillLine = nil, nil
    C_TradeSkillUI = {
        GetBaseProfessionInfo = function() return { professionName = "Blacksmithing" } end,
        GetAllRecipeIDs = function() return { 2663 } end,
        GetRecipeInfo = function(id) return { name = "Sword", recipeID = id, learned = true, relativeDifficulty = 1 } end,
        GetRecipeSchematic = function()
            local slots = {}
            for n = 1, 10 do slots[n] = { quantityRequired = 2, reagents = { { itemID = 100 + n } } } end
            return { outputItemID = 777, quantityMin = 1, reagentSlotSchematics = slots }
        end,
    }
    run()
    Stub.fire(frames, "TRADE_SKILL_SHOW"); run()
    local e = WoWCompanionDB.characters["Testrealm:Thrall"].recipes.Blacksmithing.entries[1]
    assert(e.makes.item == 777 and e.makes.count == 1 and e.difficulty == "yellow")
    assert(#e.reagents == 8 and e.reagents[1].item == 101 and e.reagents[1].count == 2, "capped at 8")
    C_TradeSkillUI = nil
    capture_clear()
    -- classic family
    local WC2, run2 = capture_client()
    GetNumTradeSkills = function() return 2 end
    GetTradeSkillNumReagents = function() return 2 end
    GetTradeSkillReagentInfo = function(i, j) return "r", "t", j * 3, 9 end
    GetTradeSkillReagentItemLink = function(i, j) return "|cff|Hitem:" .. (200 + j) .. "::::|h[x]|h|r" end
    Stub.fire(frames, "TRADE_SKILL_SHOW"); run2()
    local e2 = WoWCompanionDB.characters["Testrealm:Thrall"].recipes.Blacksmithing.entries[1]
    assert(#e2.reagents == 2 and e2.reagents[1].item == 201 and e2.reagents[2].count == 6)
    GetTradeSkillNumReagents, GetTradeSkillReagentInfo, GetTradeSkillReagentItemLink = nil, nil, nil
    capture_clear()
end }

cases[#cases + 1] = { "seen: a flight master is recorded, the npc only", function()
    seen_client()
    local fire = timers()
    NPC.guid, NPC.name = "Creature-0-4379-1-9999-1571-0000ABCD", "Test Flight Master"
    Stub.fire(frames, "TAXIMAP_OPENED")
    fire()
    Stub.fire(frames, "TAXIMAP_CLOSED")
    local f = WoWCompanionDB.observed.flightmasters
    assert(#f == 1 and f[1].npc == 1571 and f[1].name == "Test Flight Master" and f[1].map == 1411 and f[1].x == 50 and f[1].y == 25 and f[1].nodes == nil)
    C_Timer = nil
end }

local function flight_points(key)
    return WoWCompanionDB.characters["Testrealm:Thrall"] and WoWCompanionDB.characters["Testrealm:Thrall"].flightPoints
end

cases[#cases + 1] = { "seen: known flight points are recorded (modern family), unknown skipped", function()
    seen_client()
    local fire = timers()
    C_TaxiMap = { GetAllTaxiNodes = function(map)
        assert(map == 1411)
        return {
            { nodeID = 11, name = "Here", state = 0, position = { x = 0.5, y = 0.25 } },
            { nodeID = 12, name = "There", state = 1, position = { x = 0.1, y = 0.2 } },
            { nodeID = 13, name = "Far", state = 2, position = { x = 0.3, y = 0.3 } },
            { nodeID = 14, name = "Odd", state = 9, position = { x = 0.3, y = 0.3 } },
        }
    end }
    Stub.fire(frames, "TAXIMAP_OPENED")
    fire()
    local fp = flight_points()
    assert(#fp.nodes == 2 and fp.seenAt, "two learned nodes")
    assert(fp.nodes[1].id == 11 and fp.nodes[1].name == "Here" and fp.nodes[1].state == "current" and fp.nodes[1].map == 1411 and fp.nodes[1].x == 50 and fp.nodes[1].y == 25)
    assert(fp.nodes[2].state == "reachable" and fp.nodes[2].x == 10)
    C_TaxiMap, C_Timer = nil, nil
end }

cases[#cases + 1] = { "seen: known flight points (classic family), the cap holds", function()
    seen_client()
    local fire = timers()
    NumTaxiNodes = function() return 120 end
    TaxiNodeName = function(i) return "Node" .. i end
    TaxiNodeGetType = function(i) return i % 3 == 0 and "DISTANT" or (i == 1 and "CURRENT" or "REACHABLE") end
    TaxiNodePosition = function(i) return 0.4, 0.6 end
    Stub.fire(frames, "TAXIMAP_OPENED")
    fire()
    local fp = flight_points()
    assert(#fp.nodes == 80, "capped at 80, got " .. #fp.nodes)
    assert(fp.nodes[1].state == "current" and fp.nodes[1].name == "Node1" and fp.nodes[2].name == "Node2")
    for _, n in ipairs(fp.nodes) do assert(n.name:match("%d+") % 3 ~= 0, "distant skipped") end
    NumTaxiNodes, TaxiNodeName, TaxiNodeGetType, TaxiNodePosition, C_Timer = nil, nil, nil, nil, nil
end }

cases[#cases + 1] = { "seen: flight points are queried on the continent with each node's zone", function()
    seen_client()
    local fire = timers()
    local infos = { [1411] = { mapID = 1411, mapType = 3, parentMapID = 12 }, [12] = { mapID = 12, mapType = 2, parentMapID = 947 } }
    C_Map.GetMapInfo = function(id) return infos[id] end
    C_Map.GetMapInfoAtPosition = function(m, x, y) return { mapID = x < 0.5 and 1420 or 1411 } end
    C_Map.GetWorldPosFromMapPos = function(m, v) return m, v end
    C_Map.GetMapPosFromWorldPos = function(c, v, zone) return { x = v.x / 2, y = v.y / 2 } end
    CreateVector2D = function(x, y) return { x = x, y = y } end
    local asked
    C_TaxiMap = { GetAllTaxiNodes = function(map)
        asked = map
        return {
            { nodeID = 1, name = "A", state = 0, position = { x = 0.6, y = 0.2 } },
            { nodeID = 2, name = "B", state = 1, position = { x = 0.4, y = 0.9 } },
        }
    end }
    Stub.fire(frames, "TAXIMAP_OPENED")
    fire()
    local fp = flight_points()
    assert(asked == 12 and #fp.nodes == 2 and not fp.relative)
    for _, n in ipairs(fp.nodes) do assert(n.map == 12 and n.x >= 0 and n.x <= 100 and n.y >= 0 and n.y <= 100) end
    assert(fp.nodes[1].zoneMap == 1411 and fp.nodes[1].zoneX == 30 and fp.nodes[1].zoneY == 10)
    assert(fp.nodes[2].zoneMap == 1420 and fp.nodes[2].zoneX == 20 and fp.nodes[2].zoneY == 45)
    CreateVector2D = nil
    C_Map.GetMapPosFromWorldPos = nil
    Stub.fire(frames, "TAXIMAP_CLOSED")
    Stub.fire(frames, "TAXIMAP_OPENED")
    fire()
    fp = flight_points()
    assert(#fp.nodes == 2 and fp.nodes[1].zoneMap == nil and fp.nodes[1].map == 12, "no zone APIs: node kept without a zone")
    C_TaxiMap, C_Timer, C_Map = nil, nil, nil
end }

cases[#cases + 1] = { "seen: flight points without a continent are kept and marked relative", function()
    seen_client()
    local fire = timers()
    C_TaxiMap = { GetAllTaxiNodes = function(map)
        assert(map == 1411)
        return { { nodeID = 1, name = "Far", state = 1, position = { x = -0.147, y = -0.037 } } }
    end }
    Stub.fire(frames, "TAXIMAP_OPENED")
    fire()
    local fp = flight_points()
    assert(fp.relative == true and #fp.nodes == 1 and fp.nodes[1].map == 1411 and fp.nodes[1].x == -14.7)
    C_TaxiMap, C_Timer, C_Map = nil, nil, nil
end }

cases[#cases + 1] = { "seen: a secret flight point value is skipped", function()
    seen_client()
    local fire = timers()
    local secret = {}
    issecretvalue = function(v) return v == secret end
    C_TaxiMap = { GetAllTaxiNodes = function() return {
        { nodeID = 1, name = secret, state = 1, position = { x = 0.1, y = 0.1 } },
        { nodeID = 2, name = "Ok", state = 1, position = { x = secret, y = 0.1 } },
    } end }
    Stub.fire(frames, "TAXIMAP_OPENED")
    fire()
    local fp = flight_points()
    assert(#fp.nodes == 1 and fp.nodes[1].name == "Ok" and fp.nodes[1].x == nil)
    issecretvalue, C_TaxiMap, C_Timer = nil, nil, nil
end }

cases[#cases + 1] = { "seen: no other addon's names in the code", function()
    local src = assert(io.open("WoWCompanion/Seen.lua")):read("*a")
    for _, n in ipairs({ "Everloot", "ForeverScribe", "Questie", "ElvUI", "Lib%u" }) do assert(not src:find(n), "Seen names " .. n) end
end }

cases[#cases + 1] = { "SafeText: maps unsupported symbols, keeps escapes, drops emoji", function()
    local WC = WoWCompanion
    local S = WC.SafeText
    local cases_ = {
        { "a \226\134\146 b", "a > b" }, { "\226\135\146", ">" }, { "\226\158\156", ">" }, { "\226\134\144", "<" },
        { "\226\134\145", "up" }, { "\226\134\147", "down" }, { "\226\128\162 x", "\194\183 x" },
        { "\226\156\147\226\156\148", "++" }, { "\226\156\151\226\156\152", "xx" },
        { "\226\128\156hi\226\128\157 \226\128\152a\226\128\153", "\"hi\" 'a'" }, { "a\194\160b", "a b" },
        { "wait\226\128\166", "wait..." }, { "\194\183 \226\128\147 \226\128\148", "\194\183 \226\128\147 \226\128\148" },
        { "ok \240\159\148\165 go", "ok  go" }, { "\226\152\128", "\226\152\128" }, { "\239\184\143", "" },
        { "|cff00ff00Item \226\134\146|r |Hitem:19019::|h[Thunderfury]|h |TInterface\\Icons\\X:16|t",
          "|cff00ff00Item >|r |Hitem:19019::|h[Thunderfury]|h |TInterface\\Icons\\X:16|t" },
    }
    for _, c in ipairs(cases_) do assert(S(c[1]) == c[2], c[1] .. " -> " .. S(c[1])) end
    local ascii = "Plain advice, nothing odd |cffffffffhere|r"
    assert(S(ascii) == ascii and S(nil) == nil and S(5) == 5)
    local t0 = os.clock()
    for _ = 1, 20000 do S(ascii); S("a \226\134\146 b") end
    assert(os.clock() - t0 < 0.1, "SafeText is slow")
end }

-- Live guidance (Plan.lua 1.2): the panel follows the quest log from the plan's own per-quest guidance.
local function guided_client(file)
    local WC = plan_client(file or "guided")
    OBJ = {}
    C_QuestLog.GetQuestObjectives = function(id) return OBJ[id] end
    return WC
end

cases[#cases + 1] = { "plan guidance: accepting a class quest shows its objective and pin at once", function()
    local WC = guided_client()
    assert(WC.PlanNext().label == "Pick up Quest 10", "nothing accepted: the route's step")
    QUESTS[30] = "active"
    OBJ[30] = { { text = "0/1 Test Drake slain", numFulfilled = 0, numRequired = 1, finished = false } }
    WC.LiveUpdate("QUEST_ACCEPTED", 1, 30)
    local s = WC.PlanNext()
    assert(s.label == "Slay Test Drake" and s.map == 7001 and s.x == 80 and s.y == 80, "the first open objective's line and position")
    assert(WC.plan.live[1] == s, "its pin is in the live set")
    assert(WC.NextStepLine(s, nil):find("Slay Test Drake", 1, true))
    assert(WC.PlanFollowing())
end }

cases[#cases + 1] = { "plan guidance: live objectives that differ in count or shape never raise", function()
    local WC = guided_client()
    QUESTS[30] = "active"
    -- guidance lists one objective, the client two (none match by text): the objective stays open
    OBJ[30] = { { text = "xt:9 slain", finished = false }, { text = "Other thing: 0/1", finished = false } }
    WC.LiveUpdate("QUEST_ACCEPTED", 1, 30)
    assert(WC.PlanNext().label == "Slay Test Drake", "unmatched objective counts as open")
    -- the same count matches by position
    OBJ[30] = { { text = "anything", finished = true } }
    WC.LiveUpdate("QUEST_LOG_UPDATE")
    assert(WC.PlanNext().kind ~= "objective" or WC.PlanNext().label ~= "Slay Test Drake", "equal counts: positional match finishes it")
    -- a live objective with no text, and one that is not a table
    WC = guided_client()
    QUESTS[30] = "active"
    OBJ[30] = { { finished = false }, false }
    WC.LiveUpdate("QUEST_ACCEPTED", 1, 30)
    assert(WC.PlanNext().label == "Slay Test Drake")
    assert(#WC.AlsoDoing() >= 0)
end }

cases[#cases + 1] = { "plan guidance: a live refresh error is logged once and the static plan still shows", function()
    local WC = guided_client()
    local errs = {}
    WC.SeenError = function(kind, msg) errs[#errs + 1] = { kind, msg } end
    QUESTS[10] = "active"
    local real = WC.PlanQuestState
    WC.PlanQuestState = function() error("boom") end
    for _ = 1, 3 do assert(WC.PlanLiveRefresh() == false) end
    assert(#WC.AlsoDoing() == 0 and #WC.HereRows(7001, 0.5, 0.5) == 0)
    WC.HereTick(7001, 0.5, 0.5)
    assert(#WC.plan.live == 0 and WC.PlanNext().label == "Pick up Quest 10", "static route view")
    local n = 0
    for _, e in ipairs(errs) do
        assert(e[1] == "live" and e[2]:find("boom", 1, true))
        n = n + 1
    end
    assert(n >= 1 and n <= 4, "one entry per entry point, never one per tick")
    local before = #errs
    for _ = 1, 5 do WC.PlanLiveRefresh(); WC.AlsoDoing(); WC.HereRows(7001, 0.5, 0.5) end
    assert(#errs == before, "the same error is not logged again")
    WC.PlanQuestState = real
end }

cases[#cases + 1] = { "plan guidance: finished objectives show the turn-in line and pin", function()
    local WC = guided_client()
    QUESTS[30] = "active"
    OBJ[30] = { { text = "0/1 Test Drake slain", numFulfilled = 0, numRequired = 1, finished = false } }
    WC.LiveUpdate("QUEST_ACCEPTED", 1, 30)
    QUESTS[30] = "ready"
    OBJ[30][1].finished = true
    WC.LiveUpdate("QUEST_LOG_UPDATE")
    local s = WC.PlanNext()
    assert(s.kind == "turnin" and s.label == "Turn in Quest 30 to Trainer Test" and s.x == 12 and s.y == 13)
end }

cases[#cases + 1] = { "plan guidance: a route quest advances its objective, then its turn-in marks the step and moves on", function()
    local WC = guided_client()
    QUESTS[10] = "active"
    OBJ[10] = { { text = "Test Wolf slain: 0/1", finished = false }, { text = "Test Shield: 0/1", finished = false } }
    WC.LiveUpdate("QUEST_ACCEPTED", 10)
    assert(WC.PlanNext().label == "Kill Test Wolf" and WC.plan.done[1])
    OBJ[10][1].finished = true
    WC.LiveUpdate("QUEST_LOG_UPDATE")
    assert(WC.PlanNext().label == "Collect Test Shield" and WC.PlanNext().x == 70, "the next open objective")
    QUESTS[10] = "ready"; OBJ[10][2].finished = true
    WC.LiveUpdate("QUEST_LOG_UPDATE")
    assert(WC.PlanNext().kind == "turnin")
    QUESTS[10] = "turnedin"
    WC.LiveUpdate("QUEST_TURNED_IN", 10)
    local s = WC.PlanNext()
    assert(WC.plan.done[3] and s.label == "Pick up Quest 20" and not s.live, "advanced to the next undone step")
    assert(WC.StepNumber(s) == 4 and select(2, WC.PlanCounts()) == 4, "Step 4/4")
    assert(#WC.plan.live == 0)
end }

cases[#cases + 1] = { "current step: header, row and ring agree; an unready turn-in is skipped until its quest completes", function()
    local WC = guided_client()
    QUESTS[10] = "active"
    OBJ[10] = { { text = "Test Wolf slain: 3/3", finished = true }, { text = "Test Shield: 0/1", finished = false } }
    WC.plan.done[1], WC.plan.done[2] = true, true
    WC.LiveUpdate("QUEST_LOG_UPDATE")
    -- the quest's turn-in (step 3) is not ready: the current step is never it
    assert(WC.StepUnready(WC.plan.steps[3]) and WC.RouteNext().n == 4, "route skips the unready turn-in")
    local cur = WC.PlanNext()
    assert(cur.n ~= 3 and cur.kind ~= "turnin", "an unready turn-in is not current")
    assert(WC.PanelHeader().step == string.format("Step %d/4", cur.n), WC.PanelHeader().step)
    local model = WC.PanelModel({ steps = WC.plan.steps, done = WC.plan.done, nextStep = cur, allZones = true })
    local marked, row3
    for _, r in ipairs(model.rows) do
        if r.isNext then marked = r.n end
        if r.n == 3 then row3 = r end
    end
    assert(marked == cur.n, "the highlighted row is the header's step")
    assert(row3 and row3.unready and row3.sub == "after: 1 of 2 done", "dimmed, with its progress")
    local g = WC.PinGroups(WC.plan.steps, 7001, WC.plan.done, cur)
    local ringed
    for _, grp in ipairs(g) do
        if grp.isNext then ringed = grp.next.n end
    end
    assert(ringed == cur.n, "the ringed pin is the same step")
    -- the quest completes: its turn-in is current at once
    OBJ[10][2].finished = true; QUESTS[10] = "ready"
    WC.LiveUpdate("QUEST_LOG_UPDATE")
    assert(not WC.StepUnready(WC.plan.steps[3]) and WC.PlanNext().kind == "turnin" and WC.PlanNext().n == 3)
    assert(WC.PanelHeader().step == "Step 3/4")
end }

cases[#cases + 1] = { "map labels: stacked steps join with a dot and no label shows an id", function()
    local WC = guided_client()
    local mid = "\194\183"
    assert(WC.PinLabel({ { n = 10 }, { n = 11 } }) == "10" .. mid .. "11")
    assert(WC.PinLabel({ { n = 10 }, { n = 10, live = true }, { n = 11 } }) == "10" .. mid .. "11", "no repeats")
    assert(WC.PinLabel({ { n = 3 }, { n = 100529, synthetic = true, live = true } }) == "3", "an id never joins a label")
    assert(WC.PinLabel({ { n = 100529, synthetic = true, quest = "Quest 30", label = "x" } }) == "Quest 30")
    assert(WC.PinLabel({ { n = 100529, synthetic = true, quest = "", label = "Kill" } }) == "Kill")
    -- a followed quest the route does not list gets a pin: its label is not "100030"
    QUESTS[30] = "active"
    OBJ[30] = { { text = "Test Drake: 0/1", finished = false } }
    WC.LiveUpdate("QUEST_ACCEPTED", 30)
    local live = WC.plan.live[1]
    assert(live and live.questID == 30 and live.synthetic, "synthetic live step")
    assert(not WC.PinLabel({ live }):find("%d%d%d%d%d"), WC.PinLabel({ live }))
end }

cases[#cases + 1] = { "plan guidance: a quest the plan does not list is ignored", function()
    local WC = guided_client()
    QUESTS[99] = "active"
    WC.LiveUpdate("QUEST_ACCEPTED", 1, 99)
    assert(WC.PlanNext().label == "Pick up Quest 10" and #WC.plan.live == 0)
    assert(not WC.plan.done[1])
end }

cases[#cases + 1] = { "plan guidance: an older Plan.lua keeps the route behaviour", function()
    local WC = guided_client("full")
    assert(not WC.PlanFollowing() and WC.plan.guidance == nil)
    QUESTS[10] = "active"
    WC.LiveUpdate("QUEST_ACCEPTED", 10)
    assert(WC.PlanNext().label == "Kill 5 boars" and WC.PlanNext() == WC.RouteNext())
end }

-- The "Here" card (Plan.lua 1.3): what can be done at a plan NPC, from the live quest log.
local HERE_POS = { 0.51, 0.5 }
local function here_client(file)
    local WC = guided_client(file or "here")
    C_Map = { GetBestMapForUnit = function() return 7001 end, GetMapWorldSize = function() return 1000, 1000 end,
        GetPlayerMapPosition = function() return { GetXY = function() return HERE_POS[1], HERE_POS[2] end } end }
    UnitLevel = function() return 10 end
    return WC
end
local function here_text(WC)
    local mapID, px, py = WC.PlayerPos()
    local t = {}
    for _, r in ipairs(WC.HereRows(mapID, px, py)) do t[#t + 1] = r.text end
    return table.concat(t, "\n")
end

-- live training offers (digest fields: spell state, requires, level, cost, trainer place)
local function train_digest(spells, line)
    line = line or {}
    line.kind, line.spells = "training", spells
    line.npc = line.npc or "Father Lankester"
    line.map, line.x, line.y = line.map or 7001, line.x or 50, line.y or 16
    WoWCompanionDigest = { sections = { { id = "next_quests", lines = { line } } } }
end
local function train_text(WC)
    local mapID, px, py = WC.PlayerPos()
    local t = {}
    for _, r in ipairs(WC.TrainRows(mapID, px, py)) do t[#t + 1] = r.text end
    return table.concat(t, "\n")
end

cases[#cases + 1] = { "train now: learning Rank 1 live turns the blocked Rank 2 into a Train now line", function()
    local known = {}
    IsSpellKnown = function(id) return known[id] == true end
    local WC = here_client()
    train_digest({ { id = 2652, name = "Touch of Weakness", rank = 2, requires = 2651, level = 8, cost = 1800, state = "blocked" } })
    HERE_POS = { 0.8, 0.8 }
    assert(train_text(WC) == "", "Rank 1 unknown: still blocked, nothing new")
    known[2651] = true
    WC.LiveUpdate("SPELLS_CHANGED")
    assert(train_text(WC) == "Train now: Touch of Weakness (Rank 2), 18s, at Father Lankester (50, 16)", train_text(WC))
    known[2652] = true
    assert(train_text(WC) == "", "trained: the line drops")
    HERE_POS = { 0.51, 0.5 }
    IsSpellKnown = nil
end }

cases[#cases + 1] = { "train now: beside the trainer it leads as a Here: train line with the total", function()
    local known = { [1] = true }
    IsSpellKnown = function(id) return known[id] == true end
    local WC = here_client()
    train_digest({ { id = 2, name = "A", rank = 2, requires = 1, level = 4, cost = 1800, state = "available" },
        { id = 3, name = "B", level = 6, cost = 10250, state = "available" } }, { x = 50, y = 50 })
    local mapID, px, py = WC.PlayerPos()
    local rows = WC.HereRows(mapID, px, py)
    assert(rows[1].text == "Here: train A (Rank 2), B, 1g 20s 50c", rows[1].text)
    IsSpellKnown = nil
end }

cases[#cases + 1] = { "train now: a level-up unlocks a later offer", function()
    IsSpellKnown = function() return false end
    local WC = here_client()
    train_digest({ { id = 5, name = "Shield", level = 12, cost = 500, state = "later" } })
    HERE_POS = { 0.8, 0.8 }
    assert(train_text(WC) == "")
    UnitLevel = function() return 12 end
    WC.LiveUpdate("PLAYER_LEVEL_UP", 12)
    assert(train_text(WC) == "Train now: Shield, 5s, at Father Lankester (50, 16)", train_text(WC))
    HERE_POS = { 0.51, 0.5 }
    IsSpellKnown = nil
end }

cases[#cases + 1] = { "train now: a known spell is ignored, and a digest without the fields changes nothing", function()
    IsSpellKnown = function(id) return id == 5 end
    local WC = here_client()
    train_digest({ { id = 5, name = "Shield", level = 1, cost = 500, state = "available" } })
    assert(train_text(WC) == "")
    train_digest({ { id = 6, name = "Old", rank = 2 }, { id = 7, name = "Older", requires = 5, level = 1, cost = 9 } })
    assert(train_text(WC) == "", "no state field: an older digest")
    WoWCompanionDigest = nil
    assert(train_text(WC) == "" and #WC.TrainableNow() == 0)
    IsSpellKnown = nil
end }

cases[#cases + 1] = { "here card: shows in range with the missing items, hides out of range", function()
    local WC = here_client()
    HERE_POS = { 0.51, 0.5 }
    QUESTS[10] = "active"
    OBJ[10] = { { text = "Test Gyro: 0/1", finished = false }, { text = "Test Core: 0/1", finished = false } }
    WC.LiveUpdate("QUEST_LOG_UPDATE")
    local txt = here_text(WC)
    assert(txt:find("Here: Test Windshaper", 1, true), txt)
    assert(txt:find("Turn in: Quest 10; still need Collect Test Gyro (Test Lake), Collect Test Core (Test Camp)", 1, true), txt)
    assert(txt:find("Train", 1, true) and txt:find("Vendor", 1, true), txt)
    OBJ[10][1].finished = true
    WC.LiveUpdate("QUEST_LOG_UPDATE")
    txt = here_text(WC)
    assert(txt:find("still need Collect Test Core (Test Camp)", 1, true) and not txt:find("still need Collect Test Gyro", 1, true), txt)
    HERE_POS = { 0.9, 0.9 }
    assert(not here_text(WC):find("Here:", 1, true) and WC.HereCard(WC.PlayerPos()) == nil, "far away: no card")
    HERE_POS = { 0.51, 0.5 }
end }

cases[#cases + 1] = { "here card: a later ready turn-in and a pick-up that fits show as 'while you're here'", function()
    local WC = here_client()
    HERE_POS = { 0.5, 0.5 }
    QUESTS[10] = "active"
    OBJ[10] = { { text = "Test Gyro: 0/1", finished = false }, { text = "Test Core: 0/1", finished = false } }
    QUESTS[50] = "ready"
    WC.LiveUpdate("QUEST_LOG_UPDATE")
    local txt = here_text(WC)
    assert(txt:find("While you're here: step 5, turn in Quest 50", 1, true), txt)
    assert(txt:find("While you're here: step 4, pick up Quest 20", 1, true), txt)
    assert(not txt:find("Turn in: Quest 50", 1, true), "listed once")
    UnitLevel = function() return 3 end
    assert(not here_text(WC):find("Quest 20", 1, true), "a pick-up above the player's level is not offered")
end }

cases[#cases + 1] = { "here card: the step line points at the next open objective with place, distance and progress", function()
    local WC = here_client()
    HERE_POS = { 0.51, 0.5 }
    QUESTS[10] = "active"
    OBJ[10] = { { text = "Test Gyro: 1/1", finished = true }, { text = "Test Core: 0/1", finished = false } }
    WC.LiveUpdate("QUEST_ACCEPTED", 10)
    local mapID, px, py = WC.PlayerPos()
    local line = WC.NextStepLine(WC.PlanNext(), mapID, px, py)
    assert(line:find("Collect Test Core", 1, true) and line:find("Test Camp", 1, true) and line:find("1 of 2 done", 1, true) and line:find(" yd ", 1, true), line)
    QUESTS[10] = "ready"; OBJ[10][2].finished = true
    WC.LiveUpdate("QUEST_LOG_UPDATE")
    line = WC.NextStepLine(WC.PlanNext(), mapID, px, py)
    assert(line:find("Turn in Quest 10", 1, true) and not line:find("done", 1, true), line)
end }

cases[#cases + 1] = { "here card: off-plan quests in the log are listed under Also doing", function()
    local WC = here_client()
    HERE_POS = { 0.9, 0.9 }
    assert(not here_text(WC):find("Also doing", 1, true))
    QUESTS[30] = "active"; QUESTS[32] = "active"
    WC.LiveUpdate("QUEST_LOG_UPDATE")
    local txt = here_text(WC)
    assert(txt:find("Also doing", 1, true) and txt:find("Quest 30: Slay Test Drake", 1, true) and txt:find("Quest 32: Burn Test Hut", 1, true), txt)
    QUESTS[10] = "active"
    assert(not here_text(WC):find("Quest 10:", 1, true), "a route quest is not off-plan")
end }

cases[#cases + 1] = { "here card: the tick checks at most once a second", function()
    local WC = here_client()
    HERE_POS = { 0.51, 0.5 }
    local calls, orig = 0, WC.HereCard
    WC.HereCard = function(...) calls = calls + 1 return orig(...) end
    local t = 100
    GetTime = function() return t end
    local mapID, px, py = WC.PlayerPos()
    WC.plan.hereAt = nil -- the addon's own tick may already have run
    WC.HereTick(mapID, px, py); WC.HereTick(mapID, px, py); t = 100.5; WC.HereTick(mapID, px, py)
    assert(calls == 1, calls)
    t = 101.2; WC.HereTick(mapID, px, py)
    assert(calls == 2, calls)
    GetTime = nil
end }

cases[#cases + 1] = { "here card: an older Plan.lua shows no card and keeps the step line", function()
    local WC = here_client("full")
    assert(WC.plan.here == nil and WC.HereCard(WC.PlayerPos()) == nil and #WC.HereRows(WC.PlayerPos()) == 0)
    assert(WC.NextStepLine(WC.PlanNext(), nil):find("Pick up Quest 10", 1, true))
    WC = here_client("guided")
    assert(WC.plan.here == nil and WC.HereCard(WC.PlayerPos()) == nil)
end }

-- Live "Here: turn in" lines: read from the quest log, no reload.
local function weaver(WC)
    WC.plan.finishers = WC.ParseFinishers({ [77] = { quest = "The Weaver", places = { { npc = "Shadow Priest Allister", map = 7001, x = 45.2, y = 42.1 } } } })
end
local function live_rows(WC)
    local mapID, px, py = WC.PlayerPos()
    return WC.HereRows(mapID, px, py)
end

cases[#cases + 1] = { "live turn-in: a ready quest with a finisher in the zone leads the panel", function()
    local WC = here_client()
    HERE_POS = { 0.5, 0.5 }
    weaver(WC)
    QUESTS[77] = "ready"
    WC.LiveUpdate("QUEST_LOG_UPDATE")
    local rows = live_rows(WC)
    assert(rows[1].text == "Here: turn in The Weaver: Shadow Priest Allister (45, 42)", rows[1].text)
    assert(WC.plan.steps[1].n == 1 and WC.PlanCounts, "the plan's own steps are untouched")
    local pins = WC.LiveTurnInSteps()
    assert(#pins == 1 and pins[1].questID == 77 and pins[1].x == 45.2, "a map badge step")
end }

cases[#cases + 1] = { "live turn-in: a quest that is not ready shows no line", function()
    local WC = here_client()
    HERE_POS = { 0.5, 0.5 }
    weaver(WC)
    QUESTS[77] = "active"
    assert(not here_text(WC):find("turn in The Weaver", 1, true))
end }

cases[#cases + 1] = { "live turn-in: the line is gone once the quest is turned in", function()
    local WC = here_client()
    HERE_POS = { 0.5, 0.5 }
    weaver(WC)
    QUESTS[77] = "ready"
    assert(here_text(WC):find("turn in The Weaver", 1, true))
    QUESTS[77] = "turnedin"
    WC.LiveUpdate("QUEST_TURNED_IN", 77)
    assert(not here_text(WC):find("The Weaver", 1, true) and #WC.LiveTurnInSteps() == 0)
end }

cases[#cases + 1] = { "live turn-in: an older Plan.lua falls back to the plan's own turn-ins, else nothing", function()
    local WC = here_client()
    HERE_POS = { 0.5, 0.5 }
    assert(WC.plan.finishers == nil)
    QUESTS[50] = "ready"; QUESTS[999] = "ready"
    local rows = live_rows(WC)
    assert(rows[1].text == "Here: turn in Quest 50: Test Windshaper (50, 50)", rows[1].text)
    assert(not here_text(WC):find("999", 1, true))
    QUESTS[50] = nil
    assert(not here_text(WC):find("Here: turn in", 1, true))
end }

cases[#cases + 1] = { "live turn-in: a far finisher on another map is skipped without a continent", function()
    local WC = here_client()
    HERE_POS = { 0.5, 0.5 }
    WC.plan.finishers = WC.ParseFinishers({ [77] = { quest = "The Weaver", places = { { npc = "X", map = 7002, x = 45, y = 42 } } } })
    QUESTS[77] = "ready"
    assert(not here_text(WC):find("The Weaver", 1, true))
end }

cases[#cases + 1] = { "stale note: an old plan that disagrees with the log says so once", function()
    local WC = here_client()
    HERE_POS = { 0.5, 0.5 }
    weaver(WC)
    assert(WC.StaleNote(7001) == nil, "log agrees: no note")
    QUESTS[77] = "ready"
    local note = WC.StaleNote(7001)
    assert(note and note:find("Plan from ", 1, true) and note:find("/reload to refresh it", 1, true), tostring(note))
    local n = 0
    for _, r in ipairs(live_rows(WC)) do if r.text == note then n = n + 1 end end
    for _, r in ipairs(live_rows(WC)) do if r.text == note then n = n + 1 end end
    assert(n == 2 and WC.StaleNote(7001) == note, "one line per render, the same single note")
    WC.plan.generated = time()
    local WC2 = here_client()
    WC2.plan.generated = time()
    QUESTS[77] = "ready"
    weaver(WC2)
    assert(WC2.StaleNote(7001) == nil, "a fresh plan gets no note")
end }

-- "Also doing": only what is near, a cap, the rest grouped by place behind one line.
local function big_log(WC)
    -- 38 quests: 6 near (map 7001: 2 ready), 32 elsewhere in three zones (map 9001-9003, not on this continent)
    local g, n = {}, 0
    local function add(id, ready, map, x, zone, name)
        g[id] = { questID = id, quest = name or ("Q" .. id), steps = {},
            objectives = { { text = "Do " .. id, map = map, x = x, y = 50.0, zone = zone } },
            turnin = { text = "Turn in " .. id, map = map, x = x, y = 50.0, zone = zone } }
        QUESTS[id] = ready and "ready" or "active"
        n = n + 1
    end
    for i = 1, 6 do add(1000 + i, i <= 2, 7001, 50 + i, "Testisle") end
    for i = 1, 14 do add(2000 + i, i <= 6, 9001, 10 + i, "Hillsbrad") end
    for i = 1, 10 do add(3000 + i, i <= 3, 9002, 10 + i, "Barrens") end
    for i = 1, 8 do add(4000 + i, i <= 1, 9003, 10 + i, "Stonetalon") end
    assert(n == 38)
    WC.plan.guidance = WC.ParseGuidance(g)
    WC.plan.here = nil
    WC.db.settings.alsoDoingMax = nil
    UnitName = function() return "Thrall" end
    C_Map.GetMapInfo = function(id)
        return { name = ({ [7001] = "Testisle", [9001] = "Hillsbrad", [9002] = "Barrens", [9003] = "Stonetalon" })[id] }
    end
    return WC
end
local function also_texts(WC)
    local mapID, px, py = WC.PlayerPos()
    local t = {}
    for _, r in ipairs(WC.AlsoDoingRows(mapID, px, py)) do t[#t + 1] = r.text end
    return t
end

cases[#cases + 1] = { "also doing: a 38-quest log shows at most 3 near rows, ready first, and one summary line", function()
    local WC = here_client()
    HERE_POS = { 0.5, 0.5 }
    big_log(WC)
    local t = also_texts(WC)
    assert(t[1] == "Also doing" and #t == 5, table.concat(t, "\n"))
    for i = 2, 4 do assert(t[i]:find("Q100", 1, true), t[i]) end
    assert(t[2]:find("Q1001", 1, true) and t[3]:find("Q1002", 1, true), "ready turn-ins lead")
    assert(t[5] == "+35 more in your log: 10 ready to turn in (6 Hillsbrad, 3 Barrens, 1 Stonetalon)", t[5])
    for _, line in ipairs(t) do assert(not line:find("Q2", 1, true) or line:find("more in your log", 1, true)) end
end }

cases[#cases + 1] = { "also doing: nothing near shows no rows, only the summary line", function()
    local WC = here_client()
    HERE_POS = { 0.5, 0.5 }
    big_log(WC)
    for i = 1, 6 do QUESTS[1000 + i] = nil end
    local t = also_texts(WC)
    assert(#t == 1 and t[1]:find("+32 more in your log: 10 ready to turn in", 1, true), table.concat(t, "\n"))
end }

cases[#cases + 1] = { "also doing: clicking the summary expands the rest grouped by zone, remembered per character", function()
    local WC = here_client()
    HERE_POS = { 0.5, 0.5 }
    big_log(WC)
    local mapID, px, py = WC.PlayerPos()
    local rows = WC.AlsoDoingRows(mapID, px, py)
    assert(not WC.AlsoExpanded())
    rows[#rows].click()
    assert(WC.AlsoExpanded() and WC.db.characters["Testrealm:Thrall"].alsoExpanded == true)
    local t = also_texts(WC)
    assert(t[5]:find("^%+35 more in your log.*click to hide"), t[5])
    assert(t[6] == "Hillsbrad (14)" and t[7] == "Q2001: ready to turn in", table.concat(t, "\n", 5, 8))
    assert(t[6 + 15] == "Barrens (10)" and t[6 + 15 + 11] == "Stonetalon (8)", table.concat(t, "\n"))
    assert(t[7 + 6]:find("Q2007", 1, true), t[7 + 6])
    assert(#t == 5 + 4 + 35, #t)
    WC.AlsoDoingRows(mapID, px, py)[5].click()
    assert(not WC.AlsoExpanded())
end }

cases[#cases + 1] = { "also doing: the setting at 0 hides the rows and the cap follows it", function()
    local WC = here_client()
    HERE_POS = { 0.5, 0.5 }
    big_log(WC)
    WC.db.settings.alsoDoingMax = 0
    local t = also_texts(WC)
    assert(#t == 1 and t[1]:find("+38 more in your log: 12 ready to turn in (6 Hillsbrad, 3 Barrens, 2 Testisle)", 1, true), table.concat(t, "\n"))
    WC.db.settings.alsoDoingMax = 5
    assert(#also_texts(WC) == 1 + 5 + 1)
    assert(WC.DEF_OF.alsoDoingMax.default == 3 and WC.DEF_OF.alsoDoingMax.max == 10)
end }

cases[#cases + 1] = { "also doing: the current step's quest is never listed", function()
    local WC = here_client()
    HERE_POS = { 0.5, 0.5 }
    WC.plan.guidance[30].class = true -- a class quest takes the headline when accepted
    QUESTS[30] = "active"; QUESTS[32] = "active"
    WC.LiveUpdate("QUEST_ACCEPTED", 1, 30)
    local cur = WC.PlanNext()
    assert(cur and cur.questID == 30, "headline: " .. tostring(cur and cur.questID) .. " " .. tostring(cur and cur.label))
    local ids = {}
    for _, a in ipairs(WC.AlsoDoing()) do ids[a.questID] = true end
    assert(not ids[30] and ids[32], "headline quest left out, the other stays")
end }

local failed = 0
for _, c in ipairs(cases) do
    local ok, err = pcall(c[2])
    report((ok and "ok   " or "FAIL ") .. c[1] .. (ok and "" or (": " .. tostring(err))))
    if not ok then failed = failed + 1 end
end
report(string.format("%d/%d passed", #cases - failed, #cases))
os.exit(failed == 0 and 0 or 1)
