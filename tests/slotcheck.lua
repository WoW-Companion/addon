-- Static check: a slot file is one `WoWCompanion<Digest|Answers> = { ... }` assignment of literals.
-- Usage: luajit tests/slotcheck.lua <file>...   (or require it and call check(src))
local M = {}

-- Returns the source with comments dropped and every string replaced by "S".
local function strip(src)
    local out, i, n = {}, 1, #src
    local function long_end(pos)
        local eq = src:match("^%[(=*)%[", pos)
        if not eq then return nil end
        local _, e = src:find("]" .. eq .. "]", pos, true)
        return e or n
    end
    while i <= n do
        local c = src:sub(i, i)
        if src:sub(i, i + 1) == "--" then
            local e = long_end(i + 2)
            if e then i = e + 1 else
                local nl = src:find("\n", i, true)
                i = nl or n + 1
            end
        elseif c == '"' or c == "'" then
            local j = i + 1
            while j <= n and src:sub(j, j) ~= c do
                if src:sub(j, j) == "\\" then j = j + 1 end
                if src:sub(j, j) == "\n" then return nil, "unterminated string" end
                j = j + 1
            end
            if j > n then return nil, "unterminated string" end
            out[#out + 1] = "0"
            i = j + 1
        elseif c == "[" and long_end(i) then
            out[#out + 1] = "0"
            i = long_end(i) + 1
        else
            out[#out + 1] = c
            i = i + 1
        end
    end
    return table.concat(out)
end

function M.check(src, name)
    name = name or "WoWCompanionDigest"
    local code, err = strip(src)
    if not code then return false, err end
    if code:find("[()]") then return false, "call or parenthesis" end
    local body = code:match("^%s*" .. name .. "%s*=%s*(%b{})%s*;?%s*$")
    if not body then return false, "not a single " .. name .. " = {...} assignment" end
    for word, after in body:gmatch("([%a_][%w_]*)%s*(=?=?)") do
        if word ~= "true" and word ~= "false" and word ~= "nil" and after ~= "=" then
            return false, "identifier '" .. word .. "' is not a key"
        end
    end
    for word in body:gmatch("([%a_][%w_]*)%s*[{%[]") do
        return false, "call or index on '" .. word .. "'"
    end
    if body:find("%.%.") or body:find("[:#]") then return false, "operator" end
    return true
end

if arg and arg[0] and arg[0]:find("slotcheck%.lua$") then
    local bad = 0
    for _, file in ipairs(arg) do
        local f = assert(io.open(file, "rb"))
        local src = f:read("*a")
        f:close()
        local name = file:find("[Aa]nswers[^/]*$") and "WoWCompanionAnswers" or "WoWCompanionDigest"
        local ok, err = M.check(src, name)
        if not ok then bad = bad + 1; print(file .. ": " .. err) end
    end
    if bad > 0 then os.exit(1) end
    print("slot check: " .. #arg .. " file(s) data-only")
end

return M
