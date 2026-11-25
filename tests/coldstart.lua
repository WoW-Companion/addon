-- Cold start: loads the whole TOC in order against the stub, then fires ADDON_LOADED and PLAYER_LOGIN the way the
-- client does, for each saved-variable shape a player can have. Each must build the panel without an error.
local Stub = dofile("tests/wow_stub.lua")
local out = io.write
local root = (arg and arg[1]) or "WoWCompanion"

local shapes = {
    { "fresh saved variables", nil },
    { "manual size with saved sizes", { settings = { panelSizeMode = "manual", panelWidth = 400, panelHeight = 348 } } },
    { "manual size, height below the minimum", { settings = { panelSizeMode = "manual", panelHeight = 10 } } },
    { "auto size", { settings = { panelSizeMode = "auto" } } },
    { "compact view", { settings = { view = "compact" } } },
    { "compact view in manual size", { settings = { view = "compact", panelSizeMode = "manual", panelHeight = 348 } } },
    { "locked", { settings = { locked = true } } },
    { "locked, manual size", { settings = { locked = true, panelSizeMode = "manual", panelHeight = 500 } } },
}

local function cold_start(saved)
    for k in pairs(WoWCompanion or {}) do WoWCompanion[k] = nil end
    WoWCompanion, WoWCompanionDB, SLASH_WOWC1, WoWCompanionPanel = nil, saved, nil, nil
    Stub.install(_G)
    local frames, create = {}, CreateFrame
    CreateFrame = function(...)
        local f = create(...)
        frames[#frames + 1] = f
        return f
    end
    local toc = assert(io.open(root .. "/WoWCompanion.toc"))
    for line in toc:lines() do
        local file = line:match("^([%w_\\]+%.lua)%s*$")
        if file then assert(loadfile(root .. "/" .. file:gsub("\\", "/")))() end
    end
    toc:close()
    Stub.fire(frames, "ADDON_LOADED", "WoWCompanion")
    Stub.fire(frames, "PLAYER_LOGIN")
    assert(WoWCompanion.panel, "the panel was not created")
    assert(WoWCompanionPanel == WoWCompanion.panel, "the panel is not the named frame")
end

local failed = 0
for _, s in ipairs(shapes) do
    local ok, err = pcall(cold_start, s[2])
    out((ok and "ok   " or "FAIL ") .. "cold start: " .. s[1] .. (ok and "" or (": " .. tostring(err))) .. "\n")
    if not ok then failed = failed + 1 end
end
out(string.format("%d/%d cold starts passed\n", #shapes - failed, #shapes))
os.exit(failed == 0 and 0 or 1)
