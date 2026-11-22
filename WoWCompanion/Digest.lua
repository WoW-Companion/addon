-- WoW Companion: turns the digest table the companion wrote into panel text.
-- The table is only ever read as data; see docs/digest-format.md.

local WC = WoWCompanion
local L = WC.L

WC.SCHEMA = 1
WC.MAX_EXTRA = 3 -- dungeons and talents show at most this many entries
WC.STALE_SECONDS = 12 * 60 * 60
WC.LINE_HEIGHT = 14
WC.CAPTURE_GRACE = 15 * 60 -- a capture this much newer than the digest makes it out of date (a /reload right after a fresh digest re-saves the capture)

WC.STALE_NOTE = L.STALE_NOTE

-- Text colours ({ r, g, b }) and the client's own art the rows use.
WC.COLORS = {
    white = { 1, 1, 1 }, dim = { 0.55, 0.55, 0.55 }, grey = { 0.72, 0.72, 0.72 },
    green = { 0.25, 0.9, 0.25 }, gold = { 1, 0.82, 0 },
}
WC.ICONS = {
    pickup = "Interface\\GossipFrame\\AvailableQuestIcon",
    progress = "Interface\\GossipFrame\\IncompleteQuestIcon",
    turnin = "Interface\\GossipFrame\\ActiveQuestIcon",
    talent = "Interface\\Icons\\Ability_Marksmanship",
    open = "Interface\\Buttons\\UI-MinusButton-Up",
    closed = "Interface\\Buttons\\UI-PlusButton-Up",
}
local INDENT = 1 -- one indent step is 16 px; objective and status rows sit under the quest title (indent 2)

local TITLES = {
    next_quests = L.next_quests,
    upgrades = L.upgrades,
    keep_materials = L.keep_materials,
    notes = L.notes,
}

function WC.FormatAge(seconds)
    if seconds < 60 then return L.AGE_NOW end
    if seconds < 3600 then return string.format(L.AGE_MINUTES, math.floor(seconds / 60)) end
    if seconds < 86400 then return string.format(L.AGE_HOURS, math.floor(seconds / 3600)) end
    return string.format(L.AGE_DAYS, math.floor(seconds / 86400))
end

-- Local wall-clock time of a unix timestamp, in the client's 12- or 24-hour format. military overrides the CVar.
function WC.FormatClock(ts, military)
    if military == nil then military = GetCVar and GetCVar("timeMgrUseMilitaryTime") == "1" end
    local fmt = date or os.date
    if military then return fmt("%H:%M", ts) end
    local h = tonumber(fmt("%I", ts))
    return string.format("%d:%s %s", h, fmt("%M", ts), fmt("%p", ts))
end

local function plain(s)
    return (tostring(s):gsub("|", "||"))
end

-- The subject of an "ask about this" question: the line's own text, with the item id when it has one.
-- Pipes are dropped so a digest line cannot put escape codes into the Ask box.
local function ask_subject(text, id)
    local s = tostring(text):gsub("|", "")
    return id and string.format(L.ASK_ITEM_SUBJECT, s, id) or s
end

-- The client's live count of unspent talent points, or nil when it cannot say.
function WC.UnspentTalentPoints()
    local fns = { GetUnspentTalentPoints, C_SpecializationInfo and C_SpecializationInfo.GetUnspentTalentPoints }
    for i = 1, 2 do
        if type(fns[i]) == "function" then
            local ok, n = pcall(fns[i])
            if ok and type(n) == "number" then return math.max(0, math.floor(n)) end
        end
    end
end

-- The text a digest line should show now, or nil to drop it. Read-only; every client call is guarded
-- and when one is missing the stored text is returned. quest is the line's quest id, if it has one.
--  * quest turned in: dropped; ready to turn in: says so; in the log: the live objective counts.
--  * a stored "unspent talent point" line: the live count, dropped at zero.
function WC.LiveLineText(text, quest)
    text = tostring(text)
    if quest and WC.PlanQuestState then
        local st = WC.PlanQuestState(quest)
        if st == "turnedin" then return nil end
        local name = (WC.QuestTitle and WC.QuestTitle(quest)) or text:match("^(.-):%s") or text
        if st == "ready" then return string.format(L.QUEST_LIVE, name, L.READY_TO_TURN_IN) end
        if st == "active" and WC.QuestObjectives then
            local objs = WC.QuestObjectives(quest)
            if objs then
                local parts = {}
                for i, o in ipairs(objs) do parts[i] = o.text end
                return string.format(L.QUEST_LIVE, name, table.concat(parts, ", "))
            end
        end
    elseif text:lower():find("unspent talent point", 1, true) then
        local n = WC.UnspentTalentPoints()
        if n == 0 then return nil end
        if n then return string.format(n == 1 and L.UNSPENT_ONE or L.UNSPENT_MANY, n) end
    end
    return text
end

-- The quest title colour for a quest of the given level: the client's GetQuestDifficultyColor
-- when it has one (and no player level is given), else the same bands computed here.
function WC.DifficultyColor(level, playerLevel)
    level = tonumber(level)
    if not level then return WC.COLORS.gold end
    playerLevel = playerLevel or (UnitLevel and UnitLevel("player"))
    if not playerLevel and GetQuestDifficultyColor then
        local c = GetQuestDifficultyColor(level)
        if type(c) == "table" and c.r then return { c.r, c.g, c.b } end
    end
    if not playerLevel then return WC.COLORS.gold end
    local diff = level - playerLevel
    if diff >= 5 then return { 1, 0.1, 0.1 } end -- red: much harder
    if diff >= 3 then return { 1, 0.5, 0.25 } end -- orange
    if diff >= -2 then return { 1, 1, 0 } end -- yellow: even
    local green = (GetQuestGreenRange and GetQuestGreenRange()) or 8
    if -diff <= green then return { 0.25, 0.75, 0.25 } end
    return { 0.62, 0.62, 0.62 } -- grey: trivial
end

-- The level of a quest in the log from the client, or nil.
function WC.QuestLevel(questID)
    local q = C_QuestLog
    if not (q and type(q.GetLogIndexForQuestID) == "function" and type(q.GetInfo) == "function") then return nil end
    local ok, idx = pcall(q.GetLogIndexForQuestID, questID)
    if not ok or not idx then return nil end
    local ok2, info = pcall(q.GetInfo, idx)
    local lvl = ok2 and type(info) == "table" and tonumber(info.level)
    return lvl and lvl > 0 and lvl or nil
end

local function strip_count(text)
    text = tostring(text or ""):gsub("^%d+/%d+%s*", "")
    text = text:gsub(":?%s*%d+/%d+$", "")
    return text
end

local function is_optional(text)
    return tostring(text):lower():find("(optional)", 1, true) ~= nil
end

-- One objective line "have/need text" (white while open, dim when done); optional ones end " (Optional)".
local function objective_row(o, optional_names)
    local name = strip_count(o.text)
    local opt = o.optional == true or is_optional(name) or (optional_names and optional_names[name:lower()])
    if opt and not is_optional(name) then name = name .. " " .. L.OPTIONAL end
    local have, need = tonumber(o.have), tonumber(o.need)
    local text = (have and need) and string.format("%d/%d %s", have, need, name) or name
    local done = o.finished == true or (have ~= nil and need ~= nil and have >= need)
    return { kind = "obj", indent = 2, text = plain(text), color = done and WC.COLORS.dim or WC.COLORS.white, done = done }
end

-- The rows of one structured next-quest line: the title row (state icon, collapse button, [level]
-- Title, (Class), right-aligned (Elite)) and, unless collapsed, its objective and status rows.
-- Live quest state overrides the digest's. Returns nil when the quest is already turned in.
function WC.QuestEntryRows(line, quest, collapsed, playerLevel)
    local state = quest and WC.PlanQuestState and WC.PlanQuestState(quest) or "none"
    if state == "turnedin" then return nil end
    local title, level = tostring(line.title or line.text or ""), tonumber(line.level)
    if state ~= "none" then
        title = (WC.QuestTitle and WC.QuestTitle(quest)) or title
        level = (WC.QuestLevel and WC.QuestLevel(quest)) or level
    end
    local kind = line.kind
    if state == "ready" then kind = "turnin" elseif state == "active" then kind = "progress" end
    local id = "q" .. tostring(quest or title)
    local closed = collapsed and collapsed[id] == true
    local text = (level and string.format("[%d] ", math.floor(level)) or "") .. title
    if line.class then text = text .. " (" .. L.CLASS .. ")" end
    local head = {
        kind = "quest", id = id, quest = quest, closed = closed, icon = WC.ICONS[kind],
        text = plain(text), color = WC.DifficultyColor(level, playerLevel),
        right = line.elite and ("(" .. L.ELITE .. ")") or nil,
        ask = { kind = "quest", subject = ask_subject(title) },
    }
    local out = { head }
    if closed then return out end

    local digest_objs = type(line.objectives) == "table" and line.objectives or {}
    local optional_names = {}
    for _, o in ipairs(digest_objs) do
        if type(o) == "table" and (o.optional == true or is_optional(o.text)) then
            optional_names[(strip_count(o.text):lower():gsub("%s*%(optional%)%s*$", ""))] = true
        end
    end
    local objs = digest_objs
    if state == "active" or state == "ready" then
        objs = (WC.QuestObjectives and WC.QuestObjectives(quest)) or digest_objs
    end
    if kind == "progress" or kind == "turnin" then
        for _, o in ipairs(objs) do
            if type(o) == "table" and o.text then
                local r = objective_row(o, optional_names)
                if kind == "turnin" then r.color, r.done = WC.COLORS.dim, true end
                out[#out + 1] = r
            end
        end
    end
    local npc = line.npc and plain(line.npc) or nil
    if kind == "turnin" then
        out[#out + 1] = { kind = "status", indent = 2, text = L.READY_LINE, color = WC.COLORS.green }
        if npc then out[#out + 1] = { kind = "status", indent = 2, text = string.format(L.TURN_IN_TO, npc), color = WC.COLORS.grey } end
    elseif kind == "pickup" and npc then
        local zone = line.zone and plain(line.zone) or nil
        local here = GetZoneText and GetZoneText() or nil
        local t = (zone and zone ~= here) and string.format(L.PICK_UP_FROM_IN, npc, zone) or string.format(L.PICK_UP_FROM, npc)
        out[#out + 1] = { kind = "status", indent = 2, text = t, color = WC.COLORS.grey }
    end
    return out
end

-- The talent entry: the client's talent icon and "N unspent talent point(s)", live when the client can say.
-- Returns nil when no points are left.
function WC.TalentEntry(points, ask)
    local n = WC.UnspentTalentPoints() or tonumber(points)
    if not n or n < 1 then return nil end
    n = math.floor(n)
    return { kind = "line", indent = INDENT, icon = WC.ICONS.talent, ask = ask,
        text = string.format(n == 1 and L.UNSPENT_ONE or L.UNSPENT_MANY, n) }
end

-- The quality colour of an item, or nil when the client does not know the item yet.
local function quality_color(itemID)
    if not (itemID and GetItemInfo and GetItemQualityColor) then return nil end
    local ok, _, _, quality = pcall(GetItemInfo, itemID)
    if not ok or type(quality) ~= "number" then return nil end
    local r, g, b = GetItemQualityColor(quality)
    return r and { r, g, b } or nil
end

-- Which template a section's lines use, by section id.
local ASK_KIND = { next_quests = "quest", upgrades = "upgrade", keep_materials = "material" }

local function is_empty(d)
    return type(d) ~= "table" or next(d) == nil
end

local function text_rows(text)
    return { { kind = "text", text = text } }
end

-- A collapsible section header row followed by its lines (omitted when collapsed).
function WC.SectionRows(out, id, title, lines, collapsed)
    local closed = collapsed and collapsed[id] == true
    out[#out + 1] = { kind = "header", id = id, title = title, color = WC.COLORS.grey, text = string.format(closed and L.CLOSED_SECTION or L.OPEN_SECTION, title) }
    if closed then return end
    for _, line in ipairs(lines) do out[#out + 1] = line end
end

-- An item id is only ever used to build a tooltip link, so it must be a plain positive integer.
local function item_id(v)
    local n = tonumber(v)
    if n and n > 0 and n == math.floor(n) and n < 2 ^ 31 then return n end
end

-- Schema 1 digests are numbered 1, or "1", "1.0", "1.1", "1.2"; any other major version is refused.
function WC.SchemaOK(v)
    if v == WC.SCHEMA then return true end
    return type(v) == "string" and (v == "1" or v:match("^1%.%d+$") ~= nil)
end

-- Schema 2 digests hold one schema 1.x digest per character; "2" and "2.x" are accepted.
function WC.Schema2OK(v)
    return type(v) == "string" and (v == "2" or v:match("^2%.%d+$") ~= nil)
end

-- The digest table to show for player, and whether the file was schema 2. Returns nil when the file
-- has no entry for this character: no characters[player] (or a case-insensitive match) in a schema 2
-- file, or a schema 1 digest written for someone else. An unknown schema is returned as is, so the
-- caller can say so.
function WC.EntryFor(d, player)
    if is_empty(d) then return nil end
    if WC.Schema2OK(d.schema) then
        local chars = type(d.characters) == "table" and d.characters or {}
        local e = chars[player]
        if e == nil and type(player) == "string" then
            local want = player:lower()
            for name, c in pairs(chars) do
                if type(name) == "string" and name:lower() == want then e = c break end
            end
        end
        return type(e) == "table" and e or nil, true
    end
    if WC.SchemaOK(d.schema) and d.character ~= player then return nil end
    return d
end

-- The (up to 5) character names a schema 2 file holds digests for, sorted.
local function digest_names(d)
    local names = {}
    for name, c in pairs(WC.Schema2OK(d.schema) and type(d.characters) == "table" and d.characters or {}) do
        if type(name) == "string" and type(c) == "table" then names[#names + 1] = plain(name) end
    end
    table.sort(names)
    while #names > 5 do table.remove(names) end
    return names
end

-- The how-to-get-a-digest steps as text rows.
local function hint_rows(out)
    for _, key in ipairs({ "HINT_RELOAD", "HINT_ASK", "HINT_RELOAD_AGAIN" }) do
        out[#out + 1] = { kind = "text", text = L[key] }
    end
    return out
end

-- Rows for a missing or empty digest file.
local function empty_rows()
    return hint_rows(text_rows(WC.NO_ADVICE))
end

-- Rows for a file that has no digest for player.
local function miss_rows(d, player)
    local out = text_rows(string.format(L.NO_ENTRY, plain(player)))
    hint_rows(out)
    local names = digest_names(d)
    if #names > 0 then out[#out + 1] = { kind = "text", text = string.format(L.DIGESTS_HERE, table.concat(names, ", ")) } end
    return out
end

-- Builds the rows of the optional schema 1.2 lists: { text, id } per entry, at most MAX_EXTRA.
-- build(entry) returns the line text and the id to link, or nil to skip the entry.
local function extra_lines(list, kind, build)
    local lines = {}
    for _, e in ipairs(type(list) == "table" and list or {}) do
        if #lines >= WC.MAX_EXTRA then break end
        local text, id, ask = nil, nil, nil
        if type(e) == "table" and e.line then
            local live = WC.LiveLineText(e.line)
            if live == e.line then
                text, id, ask = build(e)
            elseif live then -- the live text replaces the stored one; the ask keeps the stored subject
                text, id, ask = build(setmetatable({ line = live }, { __index = e }))
                if ask then ask.subject = ask_subject(e.line) end
            end
        end
        if text then
            local row = { kind = "line", indent = INDENT, text = text, [kind] = id and item_id(id) or nil, ask = ask }
            local n = text:match("^(%d+) unspent talent point") or text:match("^You have (%d+) unspent talent point")
            if n then
                row = WC.TalentEntry(n, ask)
                if row then row[kind] = id and item_id(id) or nil end
            end
            if row then lines[#lines + 1] = row end
        end
    end
    return lines
end

-- The current character's last capture time from ForeverScribe's global (read only), or nil
-- when it is not loaded or has no capture for this character.
function WC.CapturedAt(fs, player, realm)
    local chars = type(fs) == "table" and type(fs.chars) == "table" and fs.chars or nil
    if not chars then return nil end
    local rec = realm and chars[realm .. ":" .. player]
    if type(rec) ~= "table" then
        rec = nil
        for _, c in pairs(chars) do
            local snap = type(c) == "table" and c.snapshot
            local id = type(snap) == "table" and snap.identity
            if type(id) == "table" and id.name == player then rec = c break end
        end
    end
    local snap = rec and rec.snapshot
    return type(snap) == "table" and tonumber(snap.capturedAt) or nil
end

-- True when advice from digest entry d may be out of date: the capture is more than CAPTURE_GRACE
-- newer than the digest, or the digest is older than STALE_SECONDS. The digest carries no level
-- field, so there is no level-up rule. captured may be nil.
function WC.DigestOutdated(d, now, captured)
    local gen = tonumber(d.generated) or 0
    if captured and captured - gen > WC.CAPTURE_GRACE then return true end
    return math.max(0, now - gen) > WC.STALE_SECONDS
end

-- The current character's last capture time, or nil.
function WC.OwnCapturedAt(player)
    return WC.CapturedAt(ForeverScribeDB, player, GetRealmName and GetRealmName())
end

-- Returns the header text and a list of rows for a digest.
-- Row kinds: "text", "header" (has id) and "line" (may carry item, the item id for a tooltip).
-- show (optional) maps a settings section id to false to hide that digest section.
-- captured (optional) is the character's last ForeverScribe capture time; see WC.CapturedAt.
function WC.RenderDigest(d, now, player, collapsed, show, captured)
    if is_empty(d) then return "", empty_rows() end
    local e = WC.EntryFor(d, player)
    if not e then return "", miss_rows(d, player) end
    d = e
    if not WC.SchemaOK(d.schema) then
        return "", text_rows(string.format(L.UNKNOWN_SCHEMA, plain(d.schema)))
    end
    local age = math.max(0, now - (tonumber(d.generated) or 0))
    local header = string.format(L.DIGEST_HEADER, plain(d.character or player), WC.FormatClock(tonumber(d.generated) or 0), WC.FormatAge(age))

    local plevel = UnitLevel and UnitLevel("player") or nil
    local out = {}
    for _, section in ipairs(type(d.sections) == "table" and d.sections or {}) do
        local title = TITLES[section.id]
        local hidden = show and show[WC.SECTION_OF[section.id]] == false
        local lines = {}
        if title and not hidden and type(section.lines) == "table" then
            for _, line in ipairs(section.lines) do
                local quest = item_id(line.quest)
                local id = item_id(line.item)
                if section.id == "next_quests" and line.kind == "talent" then
                    local t = WC.TalentEntry(line.points, { kind = "talent", subject = ask_subject(line.text) })
                    if t then lines[#lines + 1] = t end
                elseif section.id == "next_quests" and (line.kind == "pickup" or line.kind == "turnin" or line.kind == "progress") then
                    for _, r in ipairs(WC.QuestEntryRows(line, quest, collapsed, plevel) or {}) do lines[#lines + 1] = r end
                else
                    local live = WC.LiveLineText(line.text, quest)
                    if live then
                        local kind = ASK_KIND[section.id]
                        local ask = kind and { kind = kind, subject = ask_subject(line.text, kind ~= "quest" and id or nil) } or nil
                        local row = { kind = "line", indent = INDENT, text = plain(live), item = id, quest = quest, ask = ask }
                        if section.id == "upgrades" then
                            row.color = quality_color(id)
                            local meta = {}
                            if line.slot then meta[#meta + 1] = plain(line.slot) end
                            if tonumber(line.ilvl) then meta[#meta + 1] = string.format(L.ILVL, tonumber(line.ilvl)) end
                            if tonumber(line.atLevel) then meta[#meta + 1] = string.format(L.AT_LEVEL, tonumber(line.atLevel)) end
                            lines[#lines + 1] = row
                            if #meta > 0 then -- slot and item level sit dim on a line of their own, so nothing needs cutting
                                row = { kind = "status", indent = 2, text = table.concat(meta, ", "), color = WC.COLORS.dim }
                            else
                                row = nil
                            end
                        end
                        lines[#lines + 1] = row
                    end
                end
            end
            if #lines > 0 then WC.SectionRows(out, section.id, title, lines, collapsed) end
        end
    end
    local extras = {
        { "dungeons", d.dungeons, "item", function(e)
            local name = e.name and string.format(L.DUNGEON_NAME, plain(e.name)) or ""
            return name .. plain(e.line), e.item_id, { kind = "dungeon", subject = ask_subject(e.name or e.line) }
        end },
        { "talents", d.talents, "spell", function(e)
            return plain(e.line), e.spell_id, { kind = "talent", subject = ask_subject(e.line) }
        end },
    }
    for _, x in ipairs(extras) do
        local lines = extra_lines(x[2], x[3], x[4])
        if #lines > 0 and not (show and show[x[1]] == false) then
            WC.SectionRows(out, x[1], L[x[1]], lines, collapsed)
        end
    end
    if #out == 0 then out = text_rows(WC.NO_ADVICE) end
    if captured and captured - (tonumber(d.generated) or 0) > WC.CAPTURE_GRACE then
        table.insert(out, 1, { kind = "text", text = string.format(L.OLDER_THAN_CAPTURE, WC.FormatClock(captured)) })
    end
    if age > WC.STALE_SECONDS then table.insert(out, 1, { kind = "text", text = WC.STALE_NOTE }) end
    local meta = { name = plain(d.character or player), advice = string.format(L.ADVICE_FROM, WC.FormatClock(tonumber(d.generated) or 0), WC.FormatAge(age)) }
    return header, out, meta
end

-- Compact view: each section keeps its header and first line; a section listed in expanded
-- (a table) keeps all its lines. A header with hidden lines shows the closed marker. Returns new rows.
function WC.CompactRows(rows, expanded)
    local out, head, count, keep = {}, nil, 0, true
    for _, r in ipairs(rows) do
        if r.kind == "header" then
            head = { kind = "header", id = r.id, title = r.title, text = r.text, color = r.color }
            count = 0
            out[#out + 1] = head
        elseif (r.kind == "line" or r.kind == "quest") and head then
            count = count + 1
            keep = count == 1 or expanded[head.id]
            if keep then
                out[#out + 1] = r
            elseif count == 2 then
                head.text = string.format(L.CLOSED_SECTION, head.title)
            end
        elseif (r.kind == "obj" or r.kind == "status") and head then
            if keep then out[#out + 1] = r end -- the rest of a quest entry follows its title row
        else
            head = nil
            out[#out + 1] = r
        end
    end
    return out
end

-- Flattens rows to plain text, one row per line.
function WC.RowsText(rows)
    local t = {}
    for i, r in ipairs(rows) do t[i] = r.text end
    return table.concat(t, "\n")
end

-- The question "ask about this" pre-fills for a row, or nil when the row has none.
function WC.AskTemplate(row)
    local a = row and row.ask
    local tpl = a and rawget(L, "ASK_ABOUT_" .. a.kind)
    return tpl and string.format(tpl, a.subject) or nil
end
