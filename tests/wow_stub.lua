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
    function r:StartMoving() self.moving = true end
    function r:StopMovingOrSizing() self.moving = false end
    function r:Show() self.shown = true end
    function r:Hide() self.shown = false end
    function r:IsShown() return self.shown end
    function r:SetText(t) self.text = t end
    function r:GetText() return self.text end
    function r:SetHeight(h) self.h = h end
    function r:GetHeight() return self.h or 0 end
    function r:SetJustifyH() end
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
    env.UnitName = function() return "Thrall" end
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
