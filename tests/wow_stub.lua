-- Smallest stub of the WoW client API the panel uses.
local Stub = {}

local function new_region(kind)
    local r = { kind = kind, shown = true, points = {}, scripts = {}, events = {}, text = nil }
    function r:SetSize(w, h) self.w, self.h = w, h end
    function r:SetWidth(w) self.w = w end
    function r:SetMovable(v) self.movable = v end
    function r:EnableMouse(v) self.mouse = v end
    function r:RegisterForDrag(...) self.drag = { ... } end
    function r:RegisterEvent(e) self.events[e] = true end
    function r:SetScript(name, fn) self.scripts[name] = fn end
    function r:SetPoint(point, rel, relPoint, x, y)
        self.points = { { point, rel, relPoint, x or 0, y or 0 } }
    end
    function r:GetPoint()
        local p = self.points[1]
        if not p then return end
        return p[1], p[2], p[3], p[4], p[5]
    end
    function r:ClearAllPoints() self.points = {} end
    function r:StartMoving() self.moving = true end
    function r:StopMovingOrSizing() self.moving = false end
    function r:Show()
        local was = self.shown
        self.shown = true
        if not was and self.scripts.OnShow then self.scripts.OnShow(self) end
    end
    function r:Hide() self.shown = false end
    function r:IsShown() return self.shown end
    function r:SetText(t) self.text = t end
    function r:GetText() return self.text end
    function r:SetHeight(h) self.h = h end
    function r:GetHeight() return self.h or 0 end
    function r:SetJustifyH() end
    function r:SetMaxLetters(n) self.maxLetters = n end
    function r:SetAutoFocus(v) self.autoFocus = v end
    function r:ClearFocus() self.focused = false end
    function r:HighlightText() self.highlighted = true end
    function r:SetScrollChild(c) self.child = c end
    function r:UpdateScrollChildRect() end
    function r:CreateFontString() return new_region("FontString") end
    return r
end

-- Installs the stub globals into env (default _G) and returns env.
function Stub.install(env)
    env = env or _G
    env.UIParent = new_region("Frame")
    env.SlashCmdList = {}
    env.NOW = 1800000000
    env.time = function() return env.NOW end
    env.PRINTED = {}
    env.print = function(s) env.PRINTED[#env.PRINTED + 1] = s end
    -- Records what the tooltip was asked to show; nothing else is modelled.
    env.GameTooltip = { calls = {} }
    for _, m in ipairs({ "SetOwner", "SetHyperlink", "Show", "Hide" }) do
        env.GameTooltip[m] = function(self, ...) self.calls[#self.calls + 1] = { m, ... } end
    end
    env.UnitName = function() return "Thrall" end
    -- Load-on-demand addons: tests map an addon name to the file it would run.
    env.LOD_FILES, env.LOADED_ADDONS = {}, {}
    env.C_AddOns = { LoadAddOn = function(name)
        env.LOADED_ADDONS[#env.LOADED_ADDONS + 1] = name
        local file = env.LOD_FILES[name]
        if not file then return false, "MISSING" end
        assert(loadfile(file))()
        return true
    end }
    env.CreateFrame = function(kind, name)
        local f = new_region(kind)
        if kind == "ScrollFrame" then f.h = 200 end
        if name then env[name] = f end
        return f
    end
    return env
end

-- Fires an event at every frame created so far that registered for it.
function Stub.fire(frames, event, ...)
    for _, f in ipairs(frames) do
        if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
    end
end

return Stub
