-- WoW Companion: /wowc status, a local summary printed to the chat frame.
-- It only reads addon state; nothing is sent anywhere.

local WC = WoWCompanion
local L = WC.L

local SLOTS = { "WoWCompanion_Digest" }

local function installed(name)
    if C_AddOns and C_AddOns.DoesAddOnExist then return C_AddOns.DoesAddOnExist(name) and true or false end
    local info = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
    if not info then return false end
    local found, _, _, _, reason = info(name)
    return found ~= nil and reason ~= "MISSING"
end

function WC.Unanswered(db)
    local n = 0
    for _, a in ipairs(type(db.asks) == "table" and db.asks or {}) do
        if not a.answered then n = n + 1 end
    end
    return n
end

-- The age of the oldest unanswered ask in seconds, or nil when there is none (or it has no time).
function WC.OldestAskAge(db, now)
    local oldest
    for _, a in ipairs(type(db.asks) == "table" and db.asks or {}) do
        local t = tonumber(a.asked_at)
        if not a.answered and t and (not oldest or t < oldest) then oldest = t end
    end
    return oldest and math.max(0, now - oldest) or nil
end

-- Drops the asks the app has answered (their ids in the digest's `answered_asks`, if it lists any) and the
-- asks older than 24 hours. Plain data only; returns how many were dropped.
WC.ASK_MAX_AGE = 24 * 3600
function WC.PruneAsks(db, file, now)
    if type(db) ~= "table" or type(db.asks) ~= "table" then return 0 end
    local done = {}
    if type(file) == "table" and type(file.answered_asks) == "table" then
        for _, id in ipairs(file.answered_asks) do done[tostring(id)] = true end
    end
    local keep, dropped = {}, 0
    for _, a in ipairs(db.asks) do
        local t = type(a) == "table" and tonumber(a.asked_at) or nil
        if type(a) ~= "table" or done[tostring(a.id)] or (t and now - t > WC.ASK_MAX_AGE) then
            dropped = dropped + 1
        else
            keep[#keep + 1] = a
        end
    end
    if dropped > 0 then db.asks = keep end
    return dropped
end

-- Builds the status lines from plain values: info = { version, build, digest, db, player, now, installed }.
function WC.StatusLines(info)
    local out = { L.STATUS_TITLE }
    out[#out + 1] = string.format(L.STATUS_VERSION, tostring(info.version or L.STATUS_UNKNOWN), tostring(info.build or L.STATUS_UNKNOWN))
    local file = info.digest
    local d = WC.EntryFor(file, info.player)
    if not d then
        out[#out + 1] = L.STATUS_DIGEST_NONE
    else
        local gen = tonumber(d.generated)
        local when = gen and string.format("%s (%s)", WC.FormatClock(gen), WC.FormatAge(math.max(0, info.now - gen))) or L.STATUS_UNKNOWN
        out[#out + 1] = string.format(L.STATUS_DIGEST, when, tostring(file.schema))
    end
    if d and WC.DigestOutdated(d, info.now, info.captured) then out[#out + 1] = "  " .. L.OUT_OF_DATE_SHORT end
    local waiting = WC.Unanswered(info.db)
    if waiting > 0 then
        local age = WC.OldestAskAge(info.db, info.now)
        out[#out + 1] = string.format(L.STATUS_QUEUED, waiting, age and WC.FormatAge(age) or L.STATUS_UNKNOWN)
    end
    for _, name in ipairs(SLOTS) do
        out[#out + 1] = string.format(L.STATUS_SLOT, name, info.installed[name] and L.STATUS_INSTALLED or L.STATUS_MISSING)
    end
    return out
end

function WC.PrintStatus()
    local build
    if GetBuildInfo then
        local v, b = GetBuildInfo()
        build = v and (b and (v .. " (" .. b .. ")") or v)
    end
    local have = {}
    for _, name in ipairs(SLOTS) do have[name] = installed(name) end
    local lines = WC.StatusLines({
        version = WC.Version(), build = build, digest = WoWCompanionDigest, db = WC.db or {},
        player = UnitName("player"), now = time(), installed = have,
        captured = WC.OwnCapturedAt(UnitName("player")),
    })
    for _, line in ipairs(lines) do print(line) end
end
