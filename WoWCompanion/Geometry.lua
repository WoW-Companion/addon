-- WoW Companion: a read-only record of where the world map's side tabs and our tab and panel really sit.
-- Each time the map opens, the geometry is written to WoWCompanionDB.observed.mapGeometry as plain data (it leaves
-- the game only when the client saves). Nothing here changes a frame, prints or sends anything; only the client's
-- own frames and ours are recorded.

local WC = WoWCompanion

local function r1(v)
    return type(v) == "number" and math.floor(v * 10 + 0.5) / 10 or nil
end

local function frame_name(f)
    local ok, n = pcall(function() return type(f) == "table" and f.GetName and f:GetName() end)
    return ok and type(n) == "string" and n or nil
end

-- One frame as plain data: { name, w, h, scale, shown, points = { { point, rel, relPoint, x, y } } }.
local function frame_info(f, field)
    if type(f) ~= "table" then return nil end
    local info = { field = field, name = frame_name(f) }
    if f.GetSize then
        local w, h = f:GetSize()
        info.w, info.h = r1(w), r1(h)
    end
    if f.GetScale then info.scale = r1(f:GetScale()) end
    if f.IsShown then info.shown = f:IsShown() and true or false end
    info.points = {}
    local n = f.GetNumPoints and f:GetNumPoints() or 0
    for i = 1, n do
        local point, rel, relPoint, x, y = f:GetPoint(i)
        local relName = frame_name(rel) or (rel ~= nil and "(unnamed)" or nil)
        info.points[#info.points + 1] = { point = point, rel = relName, relPoint = relPoint, x = r1(x), y = r1(y) }
    end
    return info
end

-- Builds the record: our tab and panel, the client's own side tabs and the content inset.
function WC.MapGeometry()
    local g = { version = 1, t = time and time() or 0, tabs = {} }
    g.tab = frame_info(WC.mapButton, "WoWCompanionMapTab")
    g.tabArt = {}
    if WC.mapButton and WC.MapTabArt then
        for _, a in ipairs(WC.MapTabArt(WC.mapButton)) do
            local info = frame_info(a.region, a.field)
            if info then g.tabArt[#g.tabArt + 1] = info end
        end
    end
    -- our tab's computed placement, as numbers only (never a name of any frame in the column)
    local tp = WC.mapTabPlace
    if type(tp) == "table" then g.column = { n = tp.n, w = r1(tp.w), h = r1(tp.h), gap = r1(tp.gap), x = r1(tp.x), y = r1(tp.y), mode = tp.mode } end
    g.tabOffset = WC.db and WC.db.settings and tonumber(WC.db.settings.mapTabY) or 0
    g.panel = frame_info(WC.mapPanel, "WoWCompanionMapPanel")
    local col = QuestMapFrame
    if type(col) == "table" then
        for _, field in ipairs(WC.CLIENT_TAB_FIELDS) do
            local t = frame_info(col[field], field)
            if t then g.tabs[#g.tabs + 1] = t end
        end
        g.sideTabs = { n = 0, tabs = {} }
        if WC.FindClientSideTabs then
            for _, t in ipairs(WC.FindClientSideTabs(col)) do
                g.sideTabs.n = g.sideTabs.n + 1
                g.sideTabs.tabs[#g.sideTabs.tabs + 1] = frame_info(t, "sidetab")
            end
        end
        g.inset = frame_info(WC.MapInset and WC.MapInset() or nil, "inset")
        local q = col.QuestsFrame
        g.questList = frame_info(q, "QuestsFrame")
        g.questScroll = frame_info(type(q) == "table" and q.ScrollFrame or nil, "ScrollFrame")
    end
    return g
end

-- Called whenever the map opens (and once more a moment later).
function WC.RecordMapGeometry()
    if not WC.db or WC.mapButtonMode ~= "tab" then return end
    local ok, g = pcall(WC.MapGeometry)
    if not ok then return end
    if type(WC.db.observed) ~= "table" then WC.db.observed = { version = WC.OBSERVED_VERSION or 1, events = {} } end
    WC.db.observed.mapGeometry = g
end
