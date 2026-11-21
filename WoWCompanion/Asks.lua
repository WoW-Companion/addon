-- WoW Companion: /ask queue and answer matching.
-- A question is plain data in WoWCompanionDB.asks; it only leaves the game
-- through SavedVariables on /reload or logout. See docs/ask-format.md.

local WC = WoWCompanion

WC.ASK_SCHEMA = 1
WC.MAX_ASKS = 10
WC.MAX_ASK_LEN = 500

local ANSWERS_ADDON = "WoWCompanion_Answers"

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function plain(s)
    return (tostring(s):gsub("|", "||"))
end

-- Appends a question to the queue; returns the entry, or nil for empty text.
function WC.QueueAsk(db, text, character, now)
    text = trim(tostring(text or ""))
    if text == "" then return nil end
    if #text > WC.MAX_ASK_LEN then text = trim(text:sub(1, WC.MAX_ASK_LEN)) end
    db.asks = type(db.asks) == "table" and db.asks or {}
    db.ask_seq = (tonumber(db.ask_seq) or 0) + 1
    local entry = { id = now .. "-" .. db.ask_seq, asked_at = now, character = character, text = text }
    db.asks[#db.asks + 1] = entry
    while #db.asks > WC.MAX_ASKS do table.remove(db.asks, 1) end
    return entry
end

-- Loads the load-on-demand answers addon; the client's API name differs by build.
function WC.LoadAnswers()
    local addon_loader = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
    if addon_loader then addon_loader(ANSWERS_ADDON) end
end

local function usable(a)
    return type(a) == "table" and type(a.text) == "string" and tonumber(a.answered_at) ~= nil
end

-- Marks answered asks in db and returns the lines to show plus an optional note.
function WC.MatchAnswers(db, answers)
    local note
    local list = {}
    if answers ~= nil and not (type(answers) == "table" and next(answers) == nil) then
        if type(answers) ~= "table" or answers.schema ~= WC.ASK_SCHEMA or type(answers.answers) ~= "table" then
            note = "The answers file is unreadable and was ignored."
        else
            list = answers.answers
        end
    end
    local bad = 0
    local out = {}
    for _, ask in ipairs(db.asks or {}) do
        local a = list[ask.id]
        if a ~= nil and not usable(a) then
            bad = bad + 1
            a = nil
        end
        if a then
            ask.answered, ask.answered_at = true, tonumber(a.answered_at)
        end
        out[#out + 1] = { ask = ask, answer = a }
    end
    if bad > 0 and not note then note = bad .. " malformed answer(s) were ignored." end
    return out, note
end

-- Returns the text block for the asks section ("" when there is nothing to show).
function WC.RenderAsks(items, note, now)
    local out = {}
    if #items > 0 then out[#out + 1] = "Questions" end
    for _, item in ipairs(items) do
        out[#out + 1] = "  Q: " .. plain(item.ask.text)
        local a = item.answer
        if a then
            out[#out + 1] = "  A: " .. plain(a.text) .. " (" .. WC.FormatAge(math.max(0, now - a.answered_at)) .. ")"
            if type(a.sources) == "table" and #a.sources > 0 then
                local s = {}
                for i, v in ipairs(a.sources) do s[i] = plain(v) end
                out[#out + 1] = "  sources: " .. table.concat(s, ", ")
            end
        else
            out[#out + 1] = "  queued; /reload to send"
        end
    end
    if note then out[#out + 1] = note end
    return table.concat(out, "\n")
end
