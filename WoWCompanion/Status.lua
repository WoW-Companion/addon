-- WoW Companion: /wowc status, a local summary printed to the chat frame.
-- It only reads addon state; nothing is sent anywhere.

local WC = WoWCompanion
local L = WC.L

local SLOTS = { "WoWCompanion_Digest", "WoWCompanion_Answers" }

local function installed(name)
    if C_AddOns and C_AddOns.DoesAddOnExist then return C_AddOns.DoesAddOnExist(name) and true or false end
    local info = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
    if not info then return false end
    local found, _, _, _, reason = info(name)
    return found ~= nil and reason ~= "MISSING"
end

-- The newest answered_at across the asks queue and this character's history, or nil.
function WC.LastAnswer(db, player)
    local newest
    local function see(t)
        local n = type(t) == "table" and tonumber(t.answered_at)
        if n and (not newest or n > newest) then newest = n end
    end
    for _, a in ipairs(type(db.asks) == "table" and db.asks or {}) do see(a) end
    local h = type(db.history) == "table" and db.history[player]
    for _, e in ipairs(type(h) == "table" and h or {}) do see(e) end
    return newest
end

function WC.Unanswered(db)
    local n = 0
    for _, a in ipairs(type(db.asks) == "table" and db.asks or {}) do
        if not a.answered then n = n + 1 end
    end
    return n
end

-- Builds the status lines from plain values: info = { version, build, digest, db, player, now, installed }.
function WC.StatusLines(info)
    local out = { L.STATUS_TITLE }
    out[#out + 1] = string.format(L.STATUS_VERSION, tostring(info.version or L.STATUS_UNKNOWN), tostring(info.build or L.STATUS_UNKNOWN))
    local d = info.digest
    if type(d) ~= "table" or next(d) == nil then
        out[#out + 1] = L.STATUS_DIGEST_NONE
    else
        local gen = tonumber(d.generated)
        local age = gen and WC.FormatAge(math.max(0, info.now - gen)) or L.STATUS_UNKNOWN
        out[#out + 1] = string.format(L.STATUS_DIGEST, age, tostring(d.schema))
    end
    out[#out + 1] = string.format(L.STATUS_QUEUED, WC.Unanswered(info.db))
    local last = WC.LastAnswer(info.db, info.player)
    out[#out + 1] = last and string.format(L.STATUS_ANSWER, WC.FormatAge(math.max(0, info.now - last))) or L.STATUS_ANSWER_NONE
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
    })
    for _, line in ipairs(lines) do print(line) end
end
