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
        self.anchors = self.anchors or {}
        self.anchors[point] = self.points[1] -- the latest anchor per point name
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
    function r:Hide()
        local was = self.shown
        self.shown = false
        if was and self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    function r:EnableKeyboard(v) self.keyboard = v end
    function r:SetPropagateKeyboardInput(v) self.propagate = v end
    function r:IsMouseOver() return self.mouseOver == true end
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
    function r:CreateTexture() return new_region("Texture") end
    function r:SetAllPoints() end
    function r:SetColorTexture() end
    function r:SetTexture(t) self.texture = t end
    function r:SetScale(v) self.scale = v end
    function r:SetFont(path, size) self.font, self.fontSize = path, size end
    function r:SetFrameLevel() end
    function r:RegisterForClicks() end
    function r:SetChecked(v) self.checked = v and true or false end
    function r:GetChecked() return self.checked end
    function r:SetMinMaxValues(lo, hi) self.min, self.max = lo, hi end
    function r:SetValueStep(v) self.step = v end
    function r:SetValue(v) self.value = v end
    function r:GetValue() return self.value end
    function r:GetCenter() return 0, 0 end
    function r:GetEffectiveScale() return 1 end
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
    for _, m in ipairs({ "SetOwner", "SetHyperlink", "AddLine", "Show", "Hide" }) do
        env.GameTooltip[m] = function(self, ...) self.calls[#self.calls + 1] = { m, ... } end
    end
    env.Minimap = new_region("Frame")
    env.CURSOR = { 0, 0 }
    env.GetCursorPosition = function() return env.CURSOR[1], env.CURSOR[2] end
    -- Optional client features, off unless a test sets the flag before loading the addon.
    env.AddonCompartmentFrame, env.Settings = nil, nil
    if env.WITH_COMPARTMENT then
        env.AddonCompartmentFrame = { registered = {} }
        function env.AddonCompartmentFrame:RegisterAddon(info) self.registered[#self.registered + 1] = info end
    end
    if env.WITH_SETTINGS_API then
        env.Settings = { opened = {} }
        function env.Settings.RegisterCanvasLayoutCategory(frame, name) return { ID = 42, frame = frame, name = name } end
        function env.Settings.RegisterAddOnCategory(c) env.Settings.registered = c end
        function env.Settings.OpenToCategory(id) env.Settings.opened[#env.Settings.opened + 1] = id end
    end
    env.COMBAT = false
    env.InCombatLockdown = function() return env.COMBAT end
    env.UnitName = function() return "Thrall" end
    env.GetRealmName = function() return "Testrealm" end
    env.GetBuildInfo = function() return "1.15.7", "63456" end
    -- Slot addons count as installed unless a test lists names in MISSING_ADDONS.
    env.MISSING_ADDONS = {}
    -- Load-on-demand addons: tests map an addon name to the file it would run.
    env.LOD_FILES, env.LOADED_ADDONS = {}, {}
    env.C_AddOns = { DoesAddOnExist = function(name) return not env.MISSING_ADDONS[name] end, GetAddOnMetadata = function() return env.TOC_VERSION end, LoadAddOn = function(name)
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
