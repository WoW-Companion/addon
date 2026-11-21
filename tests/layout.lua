-- Packaged layout check: the three addon folders each carry a valid TOC whose files exist.
-- With a zip path as arg[1], also checks the zip holds exactly those folders at its top level and no player-data file.
local FOLDERS = { "WoWCompanion", "WoWCompanion_Digest", "WoWCompanion_Answers" }
local DATA = { ["WoWCompanion_Digest/Digest.lua"] = true, ["WoWCompanion_Answers/Answers.lua"] = true }
local bad = 0
local function fail(msg) bad = bad + 1; print("layout: " .. msg) end

local function exists(path)
    local f = io.open(path)
    if f then f:close() end
    return f ~= nil
end

local versions = {}
for _, dir in ipairs(FOLDERS) do
    local toc = dir .. "/" .. dir .. ".toc"
    local f = io.open(toc)
    if not f then
        fail("missing " .. toc)
    else
        local meta, files = {}, {}
        for line in f:lines() do
            local k, v = line:match("^##%s*([%w%-]+):%s*(.-)%s*$")
            if k then meta[k] = v elseif line:match("%S") and not line:match("^#") then files[#files + 1] = line:match("^%s*(.-)%s*$") end
        end
        f:close()
        if not tonumber(meta.Interface) then fail(toc .. ": no numeric ## Interface") end
        if not meta.Title or meta.Title == "" then fail(toc .. ": no ## Title") end
        if not meta.Version then fail(toc .. ": no ## Version") end
        versions[meta.Version or "?"] = true
        if #files == 0 then fail(toc .. ": lists no files") end
        for _, file in ipairs(files) do
            if not exists(dir .. "/" .. file:gsub("\\", "/")) then fail(toc .. ": lists missing file " .. file) end
        end
    end
end
if next(versions, next(versions)) then fail("the TOCs disagree on ## Version") end

local zip = arg and arg[1]
if zip then
    local h = assert(io.popen('unzip -Z1 "' .. zip .. '"'))
    local seen = {}
    for name in h:lines() do
        local top = name:match("^([^/]+)/")
        if not top then fail("zip entry outside a folder: " .. name) else seen[top] = true end
        if DATA[name] then fail("zip ships player data: " .. name) end
    end
    h:close()
    for _, dir in ipairs(FOLDERS) do
        if not seen[dir] then fail("zip lacks " .. dir) end
        seen[dir] = nil
    end
    for top in pairs(seen) do fail("zip has an unexpected folder " .. top) end
end

if bad > 0 then os.exit(1) end
print("layout: " .. #FOLDERS .. " folders, TOCs valid" .. (zip and ", zip layout ok" or ""))
