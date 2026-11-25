-- Fails, naming file, line and character, on any string character the game's default font may not draw.
-- Allowed: ASCII plus U+00B7, U+2013, U+2014. A line ending in "-- glyph-ok" is exempt (code that strips a glyph).
local allowed = { [0xB7] = true, [0x2013] = true, [0x2014] = true }
local bad = 0
for _, root in ipairs({ ... }) do
    local h = assert(io.popen('find "' .. root .. '" -name "*.lua" | sort'))
    for file in h:lines() do
        local n = 0
        for line in io.lines(file) do
            n = n + 1
            if not line:find("glyph%-ok") and not line:match("^%s*%-%-") then
                local text = line:gsub("\\\\", "\1"):gsub("\\(%d%d?%d?)", function(d) return string.char(tonumber(d) % 256) end)
                for ch in text:gmatch("[\192-\255][\128-\191]*") do
                    local b1, b2, b3, b4 = ch:byte(1, 4)
                    local cp
                    if b1 >= 240 then cp = (b1 - 240) * 262144 + ((b2 or 128) - 128) * 4096 + ((b3 or 128) - 128) * 64 + ((b4 or 128) - 128)
                    elseif b1 >= 224 then cp = (b1 - 224) * 4096 + ((b2 or 128) - 128) * 64 + ((b3 or 128) - 128)
                    else cp = (b1 - 192) * 64 + ((b2 or 128) - 128) end
                    if not allowed[cp] then
                        bad = bad + 1
                        print(string.format("%s:%d: character U+%04X (%s) may draw as a box", file, n, cp, ch))
                    end
                end
            end
        end
    end
    h:close()
end
if bad > 0 then os.exit(1) end
print("glyphs ok")
