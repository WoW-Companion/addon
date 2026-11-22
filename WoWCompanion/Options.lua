-- WoW Companion: the options window. A standalone, movable dialog built from the client's own widget
-- templates (see the rows in Settings.lua): a title bar, a page row, a subtitle, a scrolling body of boxed
-- groups with gold titles, a Defaults button per page and one Reset all. Every control saves through
-- WC.SetSetting, which repairs the value and applies it live, so nothing needs a /reload.

local WC = WoWCompanion
local L = WC.L

local WIDTH, HEIGHT = 480, 560
local BODY_W = 410 -- the scrolling body's width; boxes are a little narrower
local BOX_W, PAD = 396, 12
local COL_W = 186 -- a checkbox column
local ROW = { bool = 26, range = 44, choice = 28, color = 30 }
local PAGE_TOP = 28 -- room for the Defaults button above a page's first box

-- The text a range row shows next to its label.
local function show_value(def, v)
    local how = def.show
    if how == "pct" then return string.format("%d%%", math.floor(v * 100 + 0.5)) end
    if how == "num2" then return string.format("%.2f", v) end
    if how == "num1" then return string.format("%.1f", v) end
    if how == "limit" then return (v == "all" or v >= def.max) and L.ALL or tostring(v) end
    return tostring(math.floor(v + 0.5))
end

local function label_text(def, v)
    local text = L[def.label]
    if def.type == "range" or def.type == "limit" then return string.format(text, show_value(def, v)) end
    if def.type == "choice" then
        if not text:find("%s", 1, true) then return text end
        return string.format(text, L[def.choiceKey .. tostring(v)])
    end
    if def.labelArg then return string.format(text, def.labelArg) end
    return text
end

local function gold_title(parent, text)
    local t = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetText(text)
    return t
end

-- One checkbox bound to a bool row.
local function make_check(f, parent, def, x, y)
    local c = CreateFrame("CheckButton", "WoWCompanionOption" .. def.name, parent, "UICheckButtonTemplate")
    c:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    c.label = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    c.label:SetPoint("LEFT", c, "RIGHT", 2, 0)
    c.label:SetText(label_text(def))
    c.get = function() return WC.Setting(def.key) end
    c:SetScript("OnClick", function(self) WC.SetSetting(def.key, self:GetChecked() and true or false) end)
    c.sync = function() c:SetChecked(WC.Setting(def.key) and true or false) end
    f.checks[#f.checks + 1] = c
    f.widgets[#f.widgets + 1] = c
end

-- A slider with its label above; a limit row's top step means "all".
local function make_slider(f, parent, def, y)
    local name = "WoWCompanionOption" .. def.name
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD + 4, y)
    local s = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    s:SetSize(220, 16)
    s:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD + 6, y - 20)
    local lo, hi, step = def.min, def.max, def.step or 1
    s:SetMinMaxValues(lo, hi)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    for _, part in ipairs({ "Low", "High", "Text" }) do
        local r = _G[name .. part]
        if r and r.SetText then r:SetText("") end
    end
    local function current()
        local v = WC.Setting(def.key)
        if def.type == "limit" then return v == "all" and hi or math.min(v, hi - 1) end
        return v
    end
    s:SetScript("OnValueChanged", function(_, v)
        if f.syncing then return end
        if def.type == "limit" then v = (tonumber(v) or hi) >= hi and "all" or math.floor(v + 0.5) end
        local saved = WC.Repair(def, v)
        if saved == WC.Setting(def.key) then return end
        WC.SetSetting(def.key, saved)
    end)
    s.sync = function()
        lbl:SetText(label_text(def, WC.Setting(def.key)))
        s:SetValue(current())
    end
    f.widgets[#f.widgets + 1] = s
    return s
end

-- A radio group (or a dropdown when the row asks for one and the client has it) for a choice row.
local function make_choice(f, parent, def, y)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD + 4, y - 6)
    local name = "WoWCompanionOption" .. def.name
    local function pick(id) WC.SetSetting(def.key, id) end
    if def.widget == "dropdown" and UIDropDownMenu_Initialize and UIDropDownMenu_CreateInfo and UIDropDownMenu_AddButton then
        local dd = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")
        dd:SetPoint("TOPLEFT", parent, "TOPLEFT", 200, y)
        if UIDropDownMenu_SetWidth then UIDropDownMenu_SetWidth(dd, 150) end
        UIDropDownMenu_Initialize(dd, function()
            for _, id in ipairs(def.choices) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = L[def.choiceKey .. id]
                info.checked = WC.Setting(def.key) == id
                info.func = function() pick(id) end
                UIDropDownMenu_AddButton(info)
            end
        end)
        dd.sync = function()
            lbl:SetText(label_text(def, WC.Setting(def.key)))
            if UIDropDownMenu_SetText then UIDropDownMenu_SetText(dd, L[def.choiceKey .. WC.Setting(def.key)]) end
        end
        f.widgets[#f.widgets + 1] = dd
        return
    end
    local radios = {}
    local x = 200
    for _, id in ipairs(def.choices) do
        local r = CreateFrame("CheckButton", name .. "_" .. id, parent, "UIRadioButtonTemplate")
        r:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 2)
        r.label = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        r.label:SetPoint("LEFT", r, "RIGHT", 2, 0)
        r.label:SetText(L[def.choiceKey .. id])
        r:SetScript("OnClick", function() pick(id) end)
        r.id = id
        radios[#radios + 1] = r
        x = x + 62
    end
    local group = { sync = function()
        local cur = WC.Setting(def.key)
        lbl:SetText(label_text(def, cur))
        for _, r in ipairs(radios) do r:SetChecked(r.id == cur) end
    end }
    f.widgets[#f.widgets + 1] = group
end

-- Opens the client's colour picker on the current colour; each change is saved and drawn at once, and
-- cancelling puts the old colour back.
function WC.PickColor(def, onChange)
    local c = WC.Setting(def.key)
    local r, g, b = c[1], c[2], c[3]
    local picker = ColorPickerFrame
    if not picker then return end
    local function changed()
        local nr, ng, nb = picker:GetColorRGB()
        onChange({ nr, ng, nb })
    end
    local function cancelled() onChange({ r, g, b }) end
    if picker.SetupColorPickerAndShow then
        picker:SetupColorPickerAndShow({ r = r, g = g, b = b, hasOpacity = false, swatchFunc = changed, cancelFunc = cancelled })
    else
        picker.hasOpacity, picker.previousValues = false, { r, g, b }
        picker.func, picker.cancelFunc = changed, cancelled
        picker:SetColorRGB(r, g, b)
        picker:Hide()
        picker:Show()
    end
end

-- A colour swatch button that opens the picker.
local function make_color(f, parent, def, y)
    local b = CreateFrame("Button", "WoWCompanionOption" .. def.name, parent)
    b:SetSize(24, 18)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD + 6, y - 4)
    b.border = b:CreateTexture(nil, "BACKGROUND")
    b.border:SetAllPoints()
    b.border:SetColorTexture(0.8, 0.8, 0.8, 1)
    b.swatch = b:CreateTexture(nil, "ARTWORK")
    b.swatch:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -2)
    b.swatch:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.label:SetPoint("LEFT", b, "RIGHT", 8, 0)
    b.label:SetText(L[def.label])
    b:SetScript("OnClick", function()
        WC.PickColor(def, function(c) WC.SetSetting(def.key, c) end)
    end)
    b.sync = function()
        local c = WC.Setting(def.key)
        b.swatch:SetColorTexture(c[1], c[2], c[3], 1)
    end
    f.widgets[#f.widgets + 1] = b
end

local function make_button(name, parent, text, w, point, x, y, onclick)
    local b = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetPoint(point, parent, point, x, y)
    b:SetText(text)
    b:SetScript("OnClick", onclick)
    return b
end

-- Builds one page: its boxes in row order, a Defaults button, and returns the page frame.
local function build_page(f, page, body)
    local pf = CreateFrame("Frame", "WoWCompanionOptionsPage_" .. page, body)
    pf:SetSize(BODY_W, 100)
    pf:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
    pf.defaults = make_button("WoWCompanionOptionsDefaults_" .. page, pf, L.DEFAULTS, 96, "TOPRIGHT", -14, -2,
        function() WC.ResetPage(page) end)

    local boxes, order = {}, {}
    for _, def in ipairs(WC.DEFS) do
        if def.page == page and not def.hidden then
            if not boxes[def.box] then boxes[def.box] = {}; order[#order + 1] = def.box end
            local list = boxes[def.box]
            list[#list + 1] = def
        end
    end
    local top = -PAGE_TOP
    for _, id in ipairs(order) do
        local box = CreateFrame("Frame", nil, pf, "BackdropTemplate")
        box:SetPoint("TOPLEFT", pf, "TOPLEFT", 6, top)
        if box.SetBackdrop then
            box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
            box:SetBackdropColor(0, 0, 0, 0.25)
            box:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)
        end
        local title = gold_title(box, L["BOX_" .. page .. "_" .. id])
        title:SetPoint("TOPLEFT", box, "TOPLEFT", PAD, -8)
        local y, col = -30, 0
        for _, def in ipairs(boxes[id]) do
            if def.type == "bool" then
                make_check(f, box, def, PAD - 4 + col * COL_W, y)
                if col == 1 then y = y - ROW.bool end
                col = 1 - col
            else
                if col == 1 then y = y - ROW.bool; col = 0 end
                if def.type == "range" or def.type == "limit" then
                    make_slider(f, box, def, y)
                elseif def.type == "choice" then
                    make_choice(f, box, def, y)
                elseif def.type == "color" then
                    make_color(f, box, def, y)
                end
                y = y - ROW[def.type == "limit" and "range" or def.type]
            end
        end
        if col == 1 then y = y - ROW.bool end
        if page == "minimap" then
            make_button("WoWCompanionOptionsResetButton", box, L.RESET_BUTTON, 190, "TOPLEFT", PAD, y - 2, function() WC.ResetMinimapButton() end)
            y = y - 30
        end
        local h = -y + 8
        box:SetSize(BOX_W, h)
        top = top - h - 10
    end
    pf:SetHeight(-top + 4)
    return pf
end

function WC.ResetMinimapButton()
    WC.SetSetting("minimap.angle", WC.DEF_OF["minimap.angle"].default)
    if WC.PlaceMinimapButton then WC.PlaceMinimapButton() end
end

function WC.ShowOptionsPage(id)
    local f = WC.options
    if not f then return end
    f.page = id
    for _, p in ipairs(WC.PAGES) do
        local pf = f.pages[p]
        if p == id then pf:Show() else pf:Hide() end
        f.tabs[p]:SetEnabled(p ~= id)
    end
    local key = "PAGE_" .. id
    f.subtitle:SetText(L[key])
    f.content:SetHeight(f.pages[id]:GetHeight())
    if f.scroll.SetVerticalScroll then f.scroll:SetVerticalScroll(0) end
end

-- Redraws every control from the saved settings.
function WC.SyncOptions()
    local f = WC.options
    if not f then return end
    f.syncing = true
    for _, w in ipairs(f.widgets) do w.sync() end
    f.syncing = false
end

function WC.CreateOptions()
    local f = CreateFrame("Frame", "WoWCompanionOptions", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(WIDTH, HEIGHT)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    if f.SetFrameStrata then f:SetFrameStrata("DIALOG") end
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f.checks, f.widgets, f.pages, f.tabs = {}, {}, {}, {}

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOP", f, "TOP", 0, -5)
    f.title:SetText(L.ADDON_NAME)

    local x = 12
    for _, p in ipairs(WC.PAGES) do
        local b = CreateFrame("Button", "WoWCompanionOptionsTab_" .. p, f, "UIPanelButtonTemplate")
        b:SetSize(72, 22)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", x, -30)
        local key = "TAB_" .. p
        b:SetText(L[key])
        b:SetScript("OnClick", function() WC.ShowOptionsPage(p) end)
        f.tabs[p] = b
        x = x + 74
    end

    f.subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.subtitle:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -62)

    f.scroll = CreateFrame("ScrollFrame", "WoWCompanionOptionsScroll", f, "UIPanelScrollFrameTemplate")
    f.scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -82)
    f.scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -30, 44)
    f.content = CreateFrame("Frame", nil, f.scroll)
    f.content:SetSize(BODY_W, 100)
    f.scroll:SetScrollChild(f.content)

    for _, p in ipairs(WC.PAGES) do f.pages[p] = build_page(f, p, f.content) end

    f.resetAll = make_button("WoWCompanionOptionsResetAll", f, L.RESET_ALL, 110, "BOTTOMLEFT", 14, 12, function() WC.ResetPage(nil) end)
    f.close = make_button("WoWCompanionOptionsClose", f, L.CLOSE, 90, "BOTTOMRIGHT", -14, 12, function() f:Hide() end)

    f:SetScript("OnShow", function() WC.SyncOptions() end)
    f:Hide()
    if UISpecialFrames then table.insert(UISpecialFrames, "WoWCompanionOptions") end
    WC.options = f
    WC.ShowOptionsPage("panel")
    WC.SyncOptions()
end

-- Opens the options window; toggles it unless force is set.
function WC.OpenOptions(force)
    local f = WC.options
    if not f then return end
    if f:IsShown() and not force then f:Hide() else f:Show() end
end
