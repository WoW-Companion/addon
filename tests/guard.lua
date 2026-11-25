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
    C_QuestLog.GetInfo C_QuestLog.IsComplete C_QuestLog.GetNumQuestLogEntries C_QuestLog.ReadyForTurnIn C_QuestLog.IsFailed C_QuestLog.GetQuestObjectives C_QuestLog.GetAllCompletedQuestIDs GetQuestsCompleted
    GetNumTalentTabs GetTalentTabInfo GetNumTalents GetTalentInfo
    UnitCharacterPoints GetUnspentTalentPoints GetSpellInfo GetSpellBookItemInfo
    C_ClassTalents.GetActiveConfigID C_Traits.GetConfigInfo C_Traits.GetTreeInfo C_Traits.GetTreeNodes C_Traits.GetNodeInfo
    C_Traits.GetEntryInfo C_Traits.GetDefinitionInfo C_Traits.GetTreeCurrencyInfo C_SpecializationInfo.GetNumSpecializations
    GetNumSkillLines GetSkillLineInfo C_SkillInfo.GetNumSkillLines C_SkillInfo.GetSkillLineInfo GetNumSpellTabs GetSpellTabInfo GetSpellLink C_SpellBook.GetSpellBookItemInfo C_SpellBook.GetNumSpellBookSkillLines C_SpellBook.GetSpellBookSkillLineInfo
    GetNumFactions GetFactionInfo
    IsTradeSkillLinked GetTradeSkillLine GetNumTradeSkills GetTradeSkillInfo GetTradeSkillItemLink
    GetCraftDisplaySkillLine GetCraftName GetNumCrafts GetCraftInfo GetCraftItemLink
    C_TradeSkillUI.GetAllRecipeIDs C_TradeSkillUI.GetRecipeInfo C_TradeSkillUI.GetRecipeSchematic
    GetTradeSkillNumReagents GetTradeSkillReagentInfo GetTradeSkillReagentItemLink
    GetCraftNumReagents GetCraftReagentInfo GetCraftReagentItemLink C_Timer.After C_TradeSkillUI.GetBaseProfessionInfo
    C_TradeSkillUI.GetTradeSkillLine C_TradeSkillUI.IsTradeSkillLinked C_TradeSkillUI.IsTradeSkillGuild
    UnitHealthMax UnitPowerMax UnitArmor UnitStat UnitAttackPower UnitRangedAttackPower
    GetSpellCritChance GetCritChance GetRangedCritChance GetDodgeChance GetParryChance GetBlockChance GetManaRegen
    GetSpellBonusDamage GetSpellBonusHealing GetSpellCritChanceFromIntellect GetCritChanceFromAgility
    GetUnitManaRegenRateFromSpirit GetUnitHealthRegenRateFromSpirit
    CreateFrame
]]):gmatch("%S+") do capture_allowed[name] = true end

-- GetTradeSkill/GetCraft...Reagent* and C_TradeSkillUI.GetRecipeSchematic only READ a recipe's
-- reagents and what it makes; GetMerchantItemID/CostInfo/CostItem only READ one merchant item's id and extra costs;
-- C_Timer.After only delays our own read; issecretvalue (called through WC.Clean) only tests a value.
-- C_MerchantFrame.GetNumItems/GetItemInfo/GetItemLink only READ the open merchant window's stock (the modern
-- client's counterpart of GetMerchantNumItems/GetMerchantItemInfo); they buy nothing.
-- GetTrainerServiceLevelReq only READS the level a trainer offer needs; the C_TradeSkillUI reads (above) only READ
-- the open modern profession window's recipe ids and descriptions.
-- C_TaxiMap.GetAllTaxiNodes and the classic NumTaxiNodes/TaxiNodeName/TaxiNodeGetType/TaxiNodePosition only READ
-- the open flight map's nodes (name, position, whether the character knows them); TakeTaxiNode is never called.
-- C_Map.GetMapInfo/GetMapInfoAtPosition/GetWorldPosFromMapPos/GetMapPosFromWorldPos only READ the map tree and
-- convert a position between maps; CreateVector2D only builds the vector the conversion takes.
-- The client APIs the observation of what the player sees (Seen.lua) may call, on top of the ones above that
-- it shares. Each only READS: the trainer, merchant and loot windows' contents, who the player is talking to,
-- the spell a cast was, and the skill ranks. None is protected, none buys, learns, loots or acts.
local seen_allowed = {}
for name in ([[
    UnitGUID UnitExists UnitReaction
    GetNumTrainerServices GetTrainerServiceInfo GetTrainerServiceCost GetTrainerServiceSkillReq GetTrainerServiceItemLink
    GetTrainerServiceLevelReq
    GetMerchantNumItems GetMerchantItemInfo GetMerchantItemLink
    C_MerchantFrame.GetNumItems C_MerchantFrame.GetItemInfo C_MerchantFrame.GetItemLink
    GetNumLootItems GetLootSlotLink GetLootSlotInfo
    GetSpellInfo
    GetMerchantItemID GetMerchantItemCostInfo GetMerchantItemCostItem C_Timer.After
    C_TaxiMap.GetAllTaxiNodes NumTaxiNodes TaxiNodeName TaxiNodeGetType TaxiNodePosition
    C_Map.GetMapInfo C_Map.GetMapInfoAtPosition C_Map.GetWorldPosFromMapPos C_Map.GetMapPosFromWorldPos CreateVector2D
]]):gmatch("%S+") do seen_allowed[name] = true end
for name in pairs(capture_allowed) do seen_allowed[name] = true end

-- The map display APIs the world-map side panel (MapPanel.lua) may call on the client's map frame and its scroll
-- container. Each only READS the view (scale, scroll, scale limits, shown map) or asks the map to show something
-- (SetMapID, SetPanTarget, SetZoomTarget); none is protected, none acts for the player, none sends anything.
local map_allowed = {}
for name in ([[
    GetMapID SetMapID ScrollContainer SetPanTarget SetZoomTarget GetScaleForMinZoom GetCanvasScale
    GetNormalizedHorizontalScroll GetNormalizedVerticalScroll C_Map.GetMapInfo C_Map.GetMapWorldSize
    isMaximized IsMaximized HandleUserActionToggleSidePanel SidePanelToggle
]]):gmatch("%S+") do map_allowed[name] = true end

local handle = assert(io.popen('find "' .. root .. '" -name "*.lua" | sort'))
local files = {}
for f in handle:lines() do files[#files + 1] = f end
handle:close()

local bad = 0
local function report(file, n, msg, line)
    bad = bad + 1
    print(string.format("%s:%d: %s: %s", file, n, msg, (line:gsub("^%s+", ""))))
end

local function check_map(file, n, code, line)
    if not file:find("MapPanel%.lua$") then return end
    for _, obj in ipairs({ "WorldMapFrame", "map", "sc" }) do
        for name in code:gmatch("%f[%w_]" .. obj .. "[%.:]([%w_]+)") do
            if not map_allowed[name] and not ({ SetMapID = 1, HookScript = 1, IsShown = 1 })[name] then
                report(file, n, "map API not on the read-only allowlist: " .. name, line)
            end
        end
    end
    for name in code:gmatch("(C_Map%.[%a_]+)") do
        if not map_allowed[name] then report(file, n, "map API not on the read-only allowlist: " .. name, line) end
    end
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
        check_map(file, n, code, line)
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
