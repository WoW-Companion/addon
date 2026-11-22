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
    out[#out + 1] = string.format(L.STATUS_QUEUED, WC.Unanswered(info.db))
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
