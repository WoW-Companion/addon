-- Locale lint: a string literal with letters in it must not reach a UI text call without going
-- through L. Numbers, punctuation-only literals and formatted values ("%.2f") are allowed.
local M = {}

local sinks = { "SetText%(", "print%(", "%f[%w_]text%s*=[^=]", "%f[%w_]note%s*=[^=]" }

-- Returns true when the line passes. Everything after a sink on the line is inspected.
function M.check(line)
    local code = line:gsub("%-%-.*$", "")
    for _, sink in ipairs(sinks) do
        local from = code:find(sink)
        if from then
            for literal in code:sub(from):gmatch('"([^"]*)"') do
                if literal:gsub("\\.", ""):gsub("%%[%d.]*[sdf]", ""):find("%a") then return false end
            end
        end
    end
    return true
end

-- Returns "file:line: text" for every violation in the addon's Lua files, Locales/ excluded.
function M.scan(root)
    local bad = {}
    local handle = assert(io.popen('find "' .. root .. '" -name "*.lua" -not -path "*/Locales/*" | sort'))
    for file in handle:lines() do
        local n = 0
        for line in io.lines(file) do
            n = n + 1
            if not M.check(line) then bad[#bad + 1] = file .. ":" .. n .. ": " .. line:gsub("^%s+", "") end
        end
    end
    handle:close()
    return bad
end

if arg and arg[0] and arg[0]:find("lint%.lua$") then
    local bad = M.scan(arg[1] or "WoWCompanion")
    for _, b in ipairs(bad) do print(b) end
    if #bad > 0 then os.exit(1) end
    print("locale lint: clean")
end

return M
