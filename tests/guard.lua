-- Read-only guard: fails, naming file and line, on any call the addon must never make.
local root = (arg and arg[1]) or "WoWCompanion"

local denied = {
    "SendChatMessage", "SendMail", "SendAddonMessage", "PlaceAuctionBid", "PostAuction",
    "StartAuction", "CastSpell", "CastSpellByName", "CastSpellByID", "UseAction", "UseItem",
    "UseContainerItem", "RunMacro", "RunMacroText", "Screenshot", "loadstring", "RunScript",
    "SetBinding", "JumpOrAscendStart", "BuyMerchantItem", "SellCursorItem", "BuyGuildBankTab",
    "SendSystemMessage", "TargetUnit", "AcceptTrade", "InitiateTrade", "AutoLootMobCorpse",
    "SecureCmdOptionParse", "setfenv", "load", "dofile", "loadfile", "require",
}

local handle = assert(io.popen('find "' .. root .. '" -name "*.lua" | sort'))
local files = {}
for f in handle:lines() do files[#files + 1] = f end
handle:close()

local bad = 0
local function report(file, n, msg, line)
    bad = bad + 1
    print(string.format("%s:%d: %s: %s", file, n, msg, (line:gsub("^%s+", ""))))
end

for _, file in ipairs(files) do
    local in_slash = false
    local n = 0
    for line in io.lines(file) do
        n = n + 1
        local code = line:gsub("%-%-.*$", "")
        if code:find("SlashCmdList%s*%[.-%]%s*=%s*function") then in_slash = true end
        for _, name in ipairs(denied) do
            if code:find("%f[%w_]" .. name .. "%f[^%w_]") then report(file, n, "forbidden call " .. name, line) end
        end
        if code:find("%f[%w_]ReloadUI%f[^%w_]") and not in_slash then
            report(file, n, "ReloadUI outside a slash handler", line)
        end
        if code:find("^end") then in_slash = false end
    end
end

if bad > 0 then
    print(bad .. " read-only violation(s)")
    os.exit(1)
end
print("read-only guard: " .. #files .. " file(s) clean")
