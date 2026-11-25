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

-- The client APIs the character capture (Capture.lua) may call. Every one only READS state: none is
-- protected, none acts, none sends anything. Any other client API called there fails the guard until it is
-- reviewed as read-only and added here. (Local helpers are lower-case and WC.* members are ours.)
local capture_allowed = {}
for name in ([[
    UnitName GetRealmName UnitLevel UnitClass UnitRace UnitFactionGroup GetBuildInfo time InCombatLockdown
    GetMoney UnitXP UnitXPMax GetXPExhaustion GetBindLocation
    GetInventoryItemID GetInventoryItemLink
    GetContainerNumSlots GetContainerItemID GetContainerItemInfo
    C_Container.GetContainerNumSlots C_Container.GetContainerItemInfo
    GetNumQuestLogEntries GetQuestLogTitle GetNumQuestLeaderBoards GetQuestLogLeaderBoard
    C_QuestLog.GetInfo C_QuestLog.IsComplete C_QuestLog.GetAllCompletedQuestIDs GetQuestsCompleted
    GetNumTalentTabs GetTalentTabInfo GetNumTalents GetTalentInfo
    GetNumSkillLines GetSkillLineInfo GetNumSpellTabs GetSpellTabInfo GetSpellLink C_SpellBook.GetSpellBookItemInfo
    GetNumFactions GetFactionInfo
    IsTradeSkillLinked GetTradeSkillLine GetNumTradeSkills GetTradeSkillInfo GetTradeSkillItemLink
    GetCraftDisplaySkillLine GetCraftName GetNumCrafts GetCraftInfo GetCraftItemLink
    CreateFrame
]]):gmatch("%S+") do capture_allowed[name] = true end

-- The client APIs the observation of what the player sees (Seen.lua) may call, on top of the ones above that
-- it shares. Each only READS: the trainer, merchant and loot windows' contents, who the player is talking to,
-- the spell a cast was, and the skill ranks. None is protected, none buys, learns, loots or acts.
local seen_allowed = {}
for name in ([[
    UnitGUID UnitExists UnitReaction
    GetNumTrainerServices GetTrainerServiceInfo GetTrainerServiceCost GetTrainerServiceSkillReq GetTrainerServiceItemLink
    GetMerchantNumItems GetMerchantItemInfo GetMerchantItemLink
    GetNumLootItems GetLootSlotLink GetLootSlotInfo
    GetSpellInfo
]]):gmatch("%S+") do seen_allowed[name] = true end
for name in pairs(capture_allowed) do seen_allowed[name] = true end

local handle = assert(io.popen('find "' .. root .. '" -name "*.lua" | sort'))
local files = {}
for f in handle:lines() do files[#files + 1] = f end
handle:close()

local bad = 0
local function report(file, n, msg, line)
    bad = bad + 1
    print(string.format("%s:%d: %s: %s", file, n, msg, (line:gsub("^%s+", ""))))
end

local function check_capture(file, n, code, line)
    local allowed
    if file:find("Capture%.lua$") then allowed = capture_allowed
    elseif file:find("Seen%.lua$") then allowed = seen_allowed
    else return end
    for name in code:gmatch("%f[%w_.:]([%u][%w_]*)%s*%(") do
        local before = code:match("([%.:]?)" .. name .. "%s*%(")
        if before == "" and not allowed[name] then report(file, n, "API not on the read-only allowlist: " .. name, line) end
    end
    for name in code:gmatch("(C_%a+%.[%a_]+)%s*%(") do
        if not allowed[name] then report(file, n, "API not on the read-only allowlist: " .. name, line) end
    end
end

for _, file in ipairs(files) do
    local in_slash = false
    local n = 0
    for line in io.lines(file) do
        n = n + 1
        local code = line:gsub("%-%-.*$", "")
        check_capture(file, n, code, line)
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
