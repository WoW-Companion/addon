-- Undefined-global check: fails, naming file and line, on a read of a global that is neither Lua's own,
-- the WoW client's (the allow-list below), nor assigned as a global by an addon file.
-- It lists each file's bytecode with `luajit -bl` and reads the GGET/GSET names, so it sees what the
-- compiler resolved as a global: a function that reads a `local` declared further down the file shows
-- up as a GGET of that name (the login crash: SCROLL_TOP read before its local).
local M = {}

local allowed = {}
for name in ([[
    _G _VERSION print WoWCompanionCopyTest ForeverScribeDB assert collectgarbage error getmetatable ipairs next pairs pcall rawequal rawget rawset select
    setmetatable tonumber tostring type unpack xpcall math string table os bit coroutine debug jit
    format strsplit strjoin strtrim strlower strupper strfind strmatch strsub strlen wipe tinsert tremove tContains
    date time GetTime
    CreateFrame UIParent GameTooltip WorldMapFrame QuestMapFrame QuestScrollFrame QuestLogFrame MerchantFrame Minimap
    ColorPickerFrame AddonCompartmentFrame InterfaceOptionsFrame UISpecialFrames SlashCmdList STANDARD_TEXT_FONT
    C_Timer C_Map C_QuestLog C_Container C_Item C_AddOns C_SpellBook C_Spell C_TradeSkillUI C_SkillInfo C_TaxiMap C_MerchantFrame C_SpecializationInfo C_ClassTalents C_Traits
    Enum Settings TooltipDataProcessor WorldMapTrackingPinButtonMixin
    hooksecurefunc issecretvalue CreateVector2D ShowUIPanel
    UIDropDownMenu_SetWidth UIDropDownMenu_SetText UIDropDownMenu_Initialize UIDropDownMenu_CreateInfo UIDropDownMenu_AddButton
    ChatEdit_InsertLink InterfaceOptions_AddCategory InterfaceOptionsFrame_OpenToCategory
    QuestMapFrame_OpenToQuestDetails QuestLog_OpenToQuest SelectQuestLogEntry OpenWorldMap
    IsShiftKeyDown IsControlKeyDown IsMetaKeyDown IsIndoors InCombatLockdown GetCursorPosition GetScreenHeight GetCVar
    GetBuildInfo GetAddOnMetadata GetAddOnInfo GetRealmName GetZoneText GetMinimapShape GetPlayerFacing GetBindingKey GetBindLocation
    GetFileIDFromPath
    UnitName UnitLevel UnitClass UnitRace UnitFactionGroup UnitExists UnitGUID UnitReaction UnitXP UnitXPMax UnitStat UnitArmor UnitAttackPower
    UnitHealthMax UnitPowerMax UnitRangedAttackPower GetSpellCritChance GetCritChance GetRangedCritChance GetDodgeChance
    GetParryChance GetBlockChance GetManaRegen GetSpellBonusDamage GetSpellBonusHealing GetSpellCritChanceFromIntellect
    GetCritChanceFromAgility GetUnitManaRegenRateFromSpirit GetUnitHealthRegenRateFromSpirit
    GetMoney GetXPExhaustion GetUnspentTalentPoints
    GetItemInfo GetItemInfoInstant GetItemIcon GetItemQualityColor GetInventoryItemID GetInventoryItemLink
    GetContainerNumSlots GetContainerItemInfo GetContainerItemID
    GetNumQuestLogEntries GetQuestLogTitle GetNumQuestLeaderBoards GetQuestLogLeaderBoard GetQuestLogRewardXP GetQuestLink
    GetQuestsCompleted QuestPOIGetIconInfo GetQuestGreenRange GetQuestDifficultyColor
    GetNumTalentTabs GetTalentTabInfo GetNumTalents GetTalentInfo
    UnitCharacterPoints GetSpellBookItemInfo
    GetNumSkillLines GetSkillLineInfo GetNumSpellTabs GetSpellTabInfo GetSpellLink GetSpellInfo IsSpellKnown IsPlayerSpell
    GetNumFactions GetFactionInfo
    IsTradeSkillLinked GetTradeSkillLine GetNumTradeSkills GetTradeSkillInfo GetTradeSkillItemLink GetTradeSkillNumReagents
    GetTradeSkillReagentInfo GetTradeSkillReagentItemLink
    GetCraftDisplaySkillLine GetCraftName GetNumCrafts GetCraftInfo GetCraftItemLink GetCraftNumReagents GetCraftReagentInfo
    GetCraftReagentItemLink
    GetNumTrainerServices GetTrainerServiceInfo GetTrainerServiceCost GetTrainerServiceItemLink GetTrainerServiceLevelReq
    GetTrainerServiceSkillReq
    GetMerchantNumItems GetMerchantItemInfo GetMerchantItemLink GetMerchantItemID GetMerchantItemCostInfo GetMerchantItemCostItem
    GetNumLootItems GetLootSlotInfo GetLootSlotLink
    NumTaxiNodes TaxiNodePosition TaxiNodeName TaxiNodeGetType
    TRADE_SKILLS SECONDARY_SKILLS
]]):gmatch("%S+") do allowed[name] = true end

local function bytecode(file)
    local h = assert(io.popen('luajit -bl "' .. file .. '" 2>&1'))
    local out = h:read("*a")
    h:close()
    return out
end

-- Walks the listing of one file: calls visit(op, name, line) for every GGET/GSET. The listing carries no
-- source lines per op, so a name's line is found afterwards by searching the source.
local function globals_of(file)
    local reads, sets = {}, {}
    for op, name in bytecode(file):gmatch("\n%d+%s+=?>?%s*(G[GS]ET)%s+%d+%s+%d+%s+; \"([^\"]*)\"") do
        local t = op == "GGET" and reads or sets
        t[name] = true
    end
    return reads, sets
end

local function line_of(file, name)
    local n = 0
    for line in io.lines(file) do
        n = n + 1
        local code = line:gsub("%-%-.*$", "")
        if code:find("%f[%w_]" .. name .. "%f[^%w_]") then return n end
    end
    return 0
end

local function list(roots)
    local files = {}
    for _, root in ipairs(roots) do
        local h = assert(io.popen('find "' .. root .. '" -name "*.lua" | sort'))
        for f in h:lines() do files[#files + 1] = f end
        h:close()
    end
    return files
end

-- Returns "file:line: name" for every undefined global read in the files under the roots.
function M.scan(roots)
    local files, perfile, own = list(roots), {}, {}
    for _, f in ipairs(files) do
        local reads, sets = globals_of(f)
        perfile[f] = reads
        for name in pairs(sets) do own[name] = true end
    end
    local bad = {}
    for _, f in ipairs(files) do
        local names = {}
        for name in pairs(perfile[f]) do
            if not allowed[name] and not own[name] then names[#names + 1] = name end
        end
        table.sort(names)
        for _, name in ipairs(names) do bad[#bad + 1] = f .. ":" .. line_of(f, name) .. ": undefined global " .. name end
    end
    return bad
end

if arg and arg[0] and arg[0]:find("globals%.lua$") then
    local roots = {}
    for i = 1, #arg do roots[i] = arg[i] end
    if #roots == 0 then roots = { "WoWCompanion", "WoWCompanion_Digest" } end
    local bad = M.scan(roots)
    for _, b in ipairs(bad) do print(b) end
    if #bad > 0 then os.exit(1) end
    print("globals: clean")
end

return M
