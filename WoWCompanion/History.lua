-- WoW Companion: the per-character history of answered questions.
-- Plain data in WoWCompanionDB.history[character], oldest first; display only.

local WC = WoWCompanion
local L = WC.L

WC.MAX_HISTORY = 20

local function plain(s)
    return (tostring(s):gsub("|", "||"))
end

-- Which history view the panel is in: off, paging at index (nil = newest), or confirming a clear.
WC.view = { history = false, index = nil, confirming = false }

-- Copies an answered ask into the character's history once (the ask is flagged, so a cleared entry stays cleared); the oldest entry is dropped past the cap.
function WC.CaptureHistory(db, ask, answer)
    local who = ask.character
    if ask.captured or type(who) ~= "string" then return end
    ask.captured = true
    db.history = type(db.history) == "table" and db.history or {}
    local list = type(db.history[who]) == "table" and db.history[who] or {}
    db.history[who] = list
    local sources
    if type(answer.sources) == "table" then
        sources = {}
        for i, v in ipairs(answer.sources) do sources[i] = tostring(v) end
    end
    list[#list + 1] = {
        id = ask.id, question = ask.text, asked_at = ask.asked_at,
        answer = answer.text, answered_at = tonumber(answer.answered_at), sources = sources,
    }
    while #list > WC.MAX_HISTORY do table.remove(list, 1) end
end

function WC.HistoryList(db, character)
    local h = type(db.history) == "table" and db.history[character]
    return type(h) == "table" and h or {}
end

function WC.ClearHistory(db, character)
    if type(db.history) == "table" then db.history[character] = nil end
end

-- Clamps the selected index into 1..n; defaults to the newest entry.
function WC.HistoryIndex(n)
    local i = WC.view.index or n
    return math.max(1, math.min(n, i))
end

-- The answer text and sources of one entry as the copyable plain text.
function WC.HistoryCopyText(e)
    local t = e.answer
    if type(e.sources) == "table" and #e.sources > 0 then t = t .. "\n" .. string.format(L.COPY_SOURCES, table.concat(e.sources, ", ")) end
    return t
end

-- Returns the rows for the selected history entry (or a note when there are none).
function WC.RenderHistory(list, index, now, confirming)
    local n = #list
    if n == 0 then return { { kind = "text", text = L.NO_HISTORY } } end
    local e = list[index]
    local out = {
        { kind = "text", text = string.format(L.HISTORY_ENTRY, index, n) },
        { kind = "line", text = string.format(L.ASK_LINE_Q, plain(e.question)) },
        { kind = "line", text = string.format(L.HISTORY_ASKED, WC.FormatAge(math.max(0, now - (tonumber(e.asked_at) or now)))) },
        { kind = "line", text = string.format(L.HISTORY_ANSWER, plain(e.answer)) },
    }
    if type(e.sources) == "table" and #e.sources > 0 then
        local s = {}
        for i, v in ipairs(e.sources) do s[i] = plain(v) end
        out[#out + 1] = { kind = "line", text = string.format(L.ASK_SOURCES, table.concat(s, ", ")) }
    end
    if confirming then out[#out + 1] = { kind = "text", text = string.format(L.HISTORY_CLEAR_ASK, n) } end
    return out
end

-- Moves the selection by step (-1 older, +1 newer) and redraws.
function WC.HistoryPage(step)
    local n = #WC.HistoryList(WC.db, UnitName("player"))
    if n == 0 then return end
    WC.view.index = math.max(1, math.min(n, WC.HistoryIndex(n) + step))
    WC.view.confirming = false
    WC.Refresh()
end

function WC.ShowHistory(on, confirming)
    WC.view.history, WC.view.confirming = on, confirming and true or false
    if on then WC.view.index = nil end
    WC.ShowPanel()
    WC.Refresh()
end

-- Step one of /wowc history clear: asks for confirmation in the panel.
function WC.RequestClearHistory()
    if #WC.HistoryList(WC.db, UnitName("player")) == 0 then
        WC.ShowHistory(true, false)
    else
        WC.ShowHistory(true, true)
    end
end

function WC.ConfirmClearHistory()
    WC.ClearHistory(WC.db, UnitName("player"))
    WC.view.confirming, WC.view.index = false, nil
    WC.Refresh()
end

function WC.CancelClearHistory()
    WC.view.confirming = false
    WC.Refresh()
end
