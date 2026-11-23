-- WoW Companion: the tooltip for a plan badge (minimap, world map and corner tags), in the familiar quest-tracker
-- layout: [level] title (XP), who, live objective rows, a dim footer. Read-only; every client API is checked.

local WC = WoWCompanion
local L = WC.L

local WHITE, GREY, GREEN, DIM = { 1, 1, 1 }, { 0.7, 0.7, 0.7 }, { 0.25, 0.9, 0.25 }, { 0.55, 0.55, 0.55 }
local INDENT = "   "

-- True when badge tooltips may show now: switched on, and not in combat when the player asked for that.
function WC.BadgeTipsAllowed()
    if WC.Setting("badgeTips") == false then return false end
    if WC.Setting("badgeTipsHideCombat") then
        if WC.inCombat or (InCombatLockdown and InCombatLockdown()) then return false end
    end
    return true
end

-- The quest reward XP from the client for a quest in the log, or nil (never guessed).
function WC.QuestRewardXP(questID)
    if not questID or questID <= 0 or type(GetQuestLogRewardXP) ~= "function" then return nil end
    if WC.PlanQuestState(questID) == "none" or WC.PlanQuestState(questID) == "turnedin" then return nil end
    local ok, xp = pcall(GetQuestLogRewardXP, questID)
    xp = ok and tonumber(xp) or nil
    return xp and xp > 0 and xp or nil
end

-- The "who" for a step: the giver, "Turn in to <npc>", or the objective's target; levels only when the plan carries them.
function WC.PlanTipWho(s)
    local d = WC.PlanDetail(s)
    local who
    if s.kind == "pickup" then
        who = d:match("^from (.+)$") or d:match("^Pick up .- from (.+)$")
    elseif s.kind == "turnin" then
        local npc = d:match("^to (.+)$")
        who = npc and string.format(L.PLAN_TIP_TURNIN_TO, npc) or nil
    else
        who = d:gsub("^%d+/%d+%s*", "")
        if who == "" then who = nil end
    end
    if who and s.kind ~= "turnin" and s.npcLevel and tostring(s.npcLevel) ~= "" then who = who .. " (" .. tostring(s.npcLevel) .. ")" end
    if s.approx then who = (who and who .. " " or "") .. L.PLAN_TIP_APPROX end
    return who
end

-- Lines for one step; each is { text =, color =, right =, rightColor =, small = true }.
local function step_lines(lines, group, s, prevQuest, opts)
    local state = (s.questID or 0) > 0 and WC.PlanQuestState(s.questID) or "none"
    local q = s.quest or ""
    if q ~= "" and q ~= prevQuest then
        local level = tonumber(s.level) or (WC.QuestLevel and WC.QuestLevel(s.questID))
        local title = (level and ("[" .. level .. "] ") or "") .. q
        if s.class then title = title .. string.format(L.PLAN_TIP_CLASS, tostring(s.class)) end
        local line = { text = title, color = WC.DifficultyColor(level) }
        local xp = WC.Setting("badgeTipsXP") ~= false and WC.QuestRewardXP(s.questID)
        if xp then line.right, line.rightColor = string.format(L.PLAN_TIP_XP, xp), GREY end
        lines[#lines + 1] = line
    end
    local who = WC.PlanTipWho(s)
    if who then lines[#lines + 1] = { text = who, color = WHITE } end
    if state == "ready" and (s.kind == "objective" or s.kind == "turnin") then
        lines[#lines + 1] = { text = INDENT .. L.PLAN_TIP_READY, color = GREEN }
    elseif s.kind == "objective" and state == "active" then
        for _, o in ipairs(WC.QuestObjectives(s.questID) or {}) do
            local text = o.text
            if o.have and o.need and not text:find("%d+/%d+") then text = o.have .. "/" .. o.need .. " " .. text end
            lines[#lines + 1] = { text = INDENT .. text, color = o.finished and DIM or WHITE }
        end
    end
    local total = group.total or (WC.plan and WC.plan.steps and #WC.plan.steps)
    local foot = total and string.format(L.PLAN_TIP_STEP_OF, tostring(s.n), tostring(total)) or string.format(L.PLAN_TIP_STEP, tostring(s.n))
    if group.next == s then foot = foot .. L.PLAN_TIP_NEXT end
    if opts and opts.dist then foot = foot .. " \194\183 " .. string.format(L.PLAN_TIP_DIST, math.floor(opts.dist + 0.5), opts.dir or "") end
    lines[#lines + 1] = { text = foot, color = DIM, small = true }
end

-- The tooltip for a badge group. opts.dist / opts.dir (minimap only) add the distance and compass point to the footer.
function WC.PlanTipLines(group, opts)
    local lines, prevQuest = {}, nil
    for i, s in ipairs(group.steps) do
        if i > 1 then lines[#lines + 1] = { text = " ", color = GREY, small = true } end
        step_lines(lines, group, s, prevQuest, opts)
        local q = s.quest or ""
        prevQuest = q ~= "" and q or nil
    end
    if group.ghost then
        local s = group.steps[1]
        local from = (group.from and group.from.quest ~= "" and group.from.quest) or nil
        if not from and s.unlockedBy and s.unlockedBy[1] then from = WC.QuestTitle(s.unlockedBy[1]) end
        lines[#lines + 1] = { text = string.format(L.UNLOCKS_TIP, from or "?"), color = GREY, small = true }
    end
    return lines
end

-- Fills GameTooltip (already owned by the badge) from lines and shows it.
function WC.ShowPlanTip(owner, anchor, group, opts)
    if not WC.BadgeTipsAllowed() then return false end
    GameTooltip:SetOwner(owner, anchor)
    for _, line in ipairs(WC.PlanTipLines(group, opts)) do
        local c = line.color
        if line.right then
            local r = line.rightColor
            GameTooltip:AddDoubleLine(line.text, line.right, c[1], c[2], c[3], r[1], r[2], r[3])
        else
            GameTooltip:AddLine(line.text, c[1], c[2], c[3])
        end
    end
    GameTooltip:Show()
    return true
end
