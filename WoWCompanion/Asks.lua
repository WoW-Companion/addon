-- WoW Companion: the /ask queue. The overlay reads it from SavedVariables and answers there.
-- A question is plain data in WoWCompanionDB.asks; it only leaves the game
-- through SavedVariables when the game saves. See docs/ask-format.md.

local WC = WoWCompanion
local L = WC.L

WC.ASK_SCHEMA = 1
WC.MAX_ASKS = 10
WC.MAX_ASK_LEN = 500

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Appends a question to the queue; returns the entry, or nil for empty text.
-- ref (optional) is the digest entry's reference, so the overlay files the answer under that entry.
function WC.QueueAsk(db, text, character, now, ref)
    text = trim(tostring(text or ""))
    if text == "" then return nil end
    if #text > WC.MAX_ASK_LEN then text = trim(text:sub(1, WC.MAX_ASK_LEN)) end
    db.asks = type(db.asks) == "table" and db.asks or {}
    db.ask_seq = (tonumber(db.ask_seq) or 0) + 1
    local entry = { id = now .. "-" .. db.ask_seq, asked_at = now, character = character, text = text }
    if type(ref) == "string" and ref ~= "" then entry.ref = ref:sub(1, 120) end
    db.asks[#db.asks + 1] = entry
    while #db.asks > WC.MAX_ASKS do table.remove(db.asks, 1) end
    return entry
end

-- The one entry point for /ask and Ask about this: queues for the current
-- character; returns the entry, or nil when there was nothing to queue.
function WC.SubmitAsk(text, ref)
    if not WC.db then return nil end
    return WC.QueueAsk(WC.db, text, UnitName("player"), time(), ref)
end
