local _, ns = ...
local L = ns.L
local Style = ns.Style

---------------------------------------------------------------------------
-- (31.10.2026, Daniel: "alle Addons von Guildon: einen Minimap button teilen", "modulares System") One minimap button for every
-- Guildon module (Guildon: Map & Members, Guildon: Crafts & Recipes, later more). Each module carries this file (GuildShared/),
-- the first copy that loads makes the global GuildonLauncher, the others only sign in with their entry
-- (ns.MODULE = { id, title, icon, order }; open = ns.ToggleWindow; tip = ns.LauncherTip). A click shows the modules to choose
-- from; with one module it opens that one at once. Drag moves the button. Place and on/off are kept in every module's saved
-- table (minimapAngle, minimapButton) so that it stays when a module is switched off; the module with the lowest order leads.
-- (31.10.2026, minor 2) The button itself is DonCore's MinimapButton (Libs\DonCore\MinimapButton.lua in every toc), attached
-- once for all modules with a stand-in ns whose db reads the leading module and writes every module. Same frame name
-- (GuildonMinimapButton), same keys, so the saved place stays. A minor 1 copy of an older module only signs in.
-- (04.11.2026, Era-Test, minor 3) DonCore's MinimapButton minor 3 (gold ring, round own picture). Decided by Daniel 04.11.:
-- the button shows the Guildon crest (Guildon/Media/minimap); with only Crafts & Recipes installed the anvil
-- (Guildon_Crafts/Media/minimap): always the picture of the leading module. The choice shows each part's picture (16 px,
-- round) before its name and a row "Options" (the leading module's options); right click always shows the choice, so the
-- options are reachable with one part too. At login the leading module's on/off goes to every module once, so the parts
-- never disagree (a part switched off alone before stays in step). Default place 250 (the Don buttons do not overlap).
-- (04.11.2026, Era-Test, minor 4, Daniel: "bei jedem meiner addons soll mit rechtsklick und dem menü auch eine option sein,
-- dass man direkt dort den minimap knopf ausschalten kann") The choice keeps its look; below "Options" a thin line and
-- "Hide minimap button" (DonCore's word and chat line, MinimapButton minor 4): the shared switch of every part goes off and
-- the button hides. The tooltip says "Right click: menu." with one part.
---------------------------------------------------------------------------
local MINOR = 4
local ICON = "Interface\\AddOns\\Guildon\\Media\\minimap"
-- each part's picture (also for an older copy of a part that signs in without one)
local LOGOS = { map = "Interface\\AddOns\\Guildon\\Media\\minimap", crafts = "Interface\\AddOns\\Guildon_Crafts\\Media\\minimap" }
local GEAR = "Interface\\Icons\\INV_Misc_Gear_01"
local DEFAULT_ANGLE = 250
local ROW_H = 24
local ICON_SIZE = 16

local G = rawget(_G, "GuildonLauncher")
if not G or (G.minor or 0) < MINOR then
  G = G or { modules = {} }
  G.minor = MINOR
  GuildonLauncher = G
  local C = Style.COLORS

  local function Sorted()
    local list = {}
    for _, m in pairs(G.modules) do list[#list + 1] = m end
    table.sort(list, function(a, b) if a.order ~= b.order then return a.order < b.order end return a.id < b.id end)
    return list
  end
  G.Sorted = Sorted

  local function Lead() return Sorted()[1] end
  local function Get(key)
    local m = Lead()
    return m and m.db and m.db[key]
  end
  -- a setting goes to every module, so that it holds whichever modules are on
  local function SetAll(key, v)
    for _, m in pairs(G.modules) do if type(m.db) == "table" then m.db[key] = v end end
  end
  G.SetAll = SetAll

  local function Open(m)
    if m and type(m.open) == "function" then ns.SafeCall("launcher " .. m.id, m.open) end
  end
  local function Logo(m) return m and (m.logo or LOGOS[m.id]) or ICON end
  G.Logo = Logo
  -- (04.11.2026) the leading module's options; a module without them (older copy) is skipped
  local function OpenOptions()
    for _, m in ipairs(Sorted()) do
      if type(m.options) == "function" then ns.SafeCall("launcher options", m.options) return end
    end
  end
  -- a small round picture (the parts' pictures are round already; the mask also rounds a game icon)
  local function Round(owner, tex)
    if not owner.CreateMaskTexture then return end
    local ok, mask = pcall(owner.CreateMaskTexture, owner)
    if ok and mask then
      pcall(mask.SetTexture, mask, "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
      mask:SetAllPoints(tex)
      if tex.AddMaskTexture then pcall(tex.AddMaskTexture, tex, mask) end
    end
  end

  -- the choice: one row per module, closes on a choice, a second click or a click beside it
  local function Menu()
    if G.menu then return G.menu end
    local catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("DIALOG")
    catcher:Hide()
    local menu = CreateFrame("Frame", "GuildonLauncherMenu", UIParent)
    menu:SetFrameStrata("DIALOG")
    menu:SetFrameLevel((catcher:GetFrameLevel() or 1) + 5)
    menu:EnableMouse(true)
    local edge = menu:CreateTexture(nil, "BACKGROUND")
    edge:SetAllPoints()
    edge:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.8)
    local fill = menu:CreateTexture(nil, "BORDER")
    fill:SetPoint("TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", -1, 1)
    local low = Style.BOOK and Style.BOOK.cardLow or C.background
    fill:SetColorTexture(low[1], low[2], low[3], 0.99)
    menu.title = menu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    menu.title:SetPoint("TOPLEFT", menu, "TOPLEFT", 8, -6)
    menu.title:SetText(ns.Style.Wordmark("Guil", "don"))
    menu.rows = {}
    -- (04.11.2026, minor 4) below the rows: a thin line and "Hide minimap button"
    menu.line = menu:CreateTexture(nil, "ARTWORK")
    menu.line:SetHeight(1)
    menu.line:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.35)
    local hide = CreateFrame("Button", nil, menu)
    hide:SetHeight(ROW_H)
    hide.hover = hide:CreateTexture(nil, "BORDER")
    hide.hover:SetAllPoints()
    hide.hover:SetColorTexture(C.rowHover[1], C.rowHover[2], C.rowHover[3], C.rowHover[4] or 1)
    hide.hover:Hide()
    hide.text = hide:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hide.text:SetPoint("LEFT", hide, "LEFT", 7 + ICON_SIZE + 7, 0)
    hide.text:SetPoint("RIGHT", hide, "RIGHT", -4, 0)
    hide.text:SetJustifyH("LEFT")
    hide:SetScript("OnEnter", function(self) self.hover:Show() end)
    hide:SetScript("OnLeave", function(self) self.hover:Hide() end)
    hide:SetScript("OnClick", ns.Guard("launcher hide", function()
      menu:Close()
      G.HideByMenu()
    end))
    menu.hide = hide
    menu.catcher = catcher
    function menu:Close() self:Hide() catcher:Hide() end
    catcher:SetScript("OnClick", function() menu:Close() end)
    menu:Hide()
    G.menu = menu
    return menu
  end

  function G.ShowMenu()
    local menu = Menu()
    if menu:IsShown() then menu:Close() return end
    local list = Sorted()
    -- (04.11.2026) the last row: Options
    list[#list + 1] = { id = "options", title = L["Options"], logo = GEAR, isOptions = true }
    local w = 200
    -- (04.11.2026, minor 4) a long word for "Hide minimap button" (French, Russian) widens the choice instead of being cut
    menu.hide.text:SetText(G.HideWord())
    local tw = menu.hide.text.GetStringWidth and tonumber(menu.hide.text:GetStringWidth())
    if tw and tw + 7 + ICON_SIZE + 7 + 4 + 6 > w then w = math.ceil(tw + 7 + ICON_SIZE + 7 + 4 + 6) end
    for i, m in ipairs(list) do
      local r = menu.rows[i]
      if not r then
        r = CreateFrame("Button", nil, menu)
        r:SetHeight(ROW_H)
        r.hover = r:CreateTexture(nil, "BORDER")
        r.hover:SetAllPoints()
        r.hover:SetColorTexture(C.rowHover[1], C.rowHover[2], C.rowHover[3], C.rowHover[4] or 1)
        r.hover:Hide()
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(ICON_SIZE, ICON_SIZE)
        r.icon:SetPoint("LEFT", r, "LEFT", 7, 0)
        Round(r, r.icon)
        r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.text:SetPoint("LEFT", r, "LEFT", 7 + ICON_SIZE + 7, 0)
        r.text:SetPoint("RIGHT", r, "RIGHT", -4, 0)
        r.text:SetJustifyH("LEFT")
        r:SetScript("OnEnter", function(self) self.hover:Show() end)
        r:SetScript("OnLeave", function(self) self.hover:Hide() end)
        r:SetScript("OnClick", ns.Guard("launcher menu", function(self)
          menu:Close()
          if self.m and self.m.isOptions then OpenOptions() else Open(self.m) end
        end))
        menu.rows[i] = r
      end
      r.m = m
      r.icon:SetTexture(Logo(m))
      -- a game icon (the gear) has a dark border to cut off; the parts' pictures are shown whole
      if r.icon.SetTexCoord then
        if m.isOptions then r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) else r.icon:SetTexCoord(0, 1, 0, 1) end
      end
      r.text:SetText(m.title)
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", menu, "TOPLEFT", 3, -20 - (i - 1) * ROW_H)
      r:SetWidth(w - 6)
      r:Show()
    end
    for i = #list + 1, #menu.rows do menu.rows[i]:Hide() menu.rows[i].m = nil end
    -- (04.11.2026, minor 4) the line and the last row "Hide minimap button"
    local bottom = 20 + #list * ROW_H
    menu.line:ClearAllPoints()
    menu.line:SetPoint("TOPLEFT", menu, "TOPLEFT", 9, -bottom - 3)
    menu.line:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -9, -bottom - 3)
    menu.line:Show()
    local hide = menu.hide
    hide:ClearAllPoints()
    hide:SetPoint("TOPLEFT", menu, "TOPLEFT", 3, -bottom - 7)
    hide:SetWidth(w - 6)
    hide:Show()
    menu:SetSize(w, bottom + 7 + ROW_H + 3)
    menu:ClearAllPoints()
    menu:SetPoint("TOPRIGHT", G.button or UIParent, "BOTTOMLEFT", 8, 8)
    menu.catcher:Show()
    menu:Show()
  end

  -- a click: the only module at once, else the choice
  function G.Click()
    local list = Sorted()
    if #list == 1 then Open(list[1]) elseif #list > 1 then G.ShowMenu() end
  end

  local function TipLines()
    local lines = {}
    for _, m in ipairs(Sorted()) do
      lines[#lines + 1] = "|c" .. Style.Hex("gold") .. m.title .. "|r"
      if type(m.tip) == "function" then
        local ok, extra = pcall(m.tip)
        if ok and type(extra) == "table" then for _, l in ipairs(extra) do if type(l) == "string" then lines[#lines + 1] = "  " .. l end end end
      end
    end
    return lines
  end

  -- DonCore's button, once for all modules: the stand-in ns reads the leading module's db and writes every module's
  local MB = LibStub and LibStub("DonCore-1.0", true) and LibStub("DonCore-1.0"):Get("MinimapButton", 3)
  local nsButton = { Style = Style, L = L, Guard = ns.Guard,
    db = setmetatable({}, { __index = function(_, k) return Get(k) end, __newindex = function(_, k, v) SetAll(k, v) end }) }
  G.proxy = nsButton
  if MB then
    -- (04.11.2026, minor 3) the picture is the leading module's, set in G.Refresh before the button is built
    G.opts = {
      name = "GuildonMinimapButton", icon = ICON, addon = "Guildon", angleKey = "minimapAngle", defaultAngle = DEFAULT_ANGLE,
      enabled = function() return Get("minimapButton") ~= false end,
      title = function() return Style.Wordmark("Guil", "don") end,
      lines = TipLines,
      hint = function()
        if #Sorted() > 1 then return L["Click: choose a part. Drag: move."] end
        return L["Click: open the window. Drag: move."] .. "\n" .. L["Right click: menu."]
      end,
      onLeft = function() G.Click() end, onRight = function() G.ShowMenu() end,
    }
    MB:Attach(nsButton, G.opts)
  end

  -- (04.11.2026, minor 4) DonCore's word for the hide row, and the hide itself: DonCore's (the shared switch of every part
  -- off through the stand-in db, button hidden, chat line where it comes back); without minor 4 the shared switch alone
  local MB4 = LibStub and LibStub("DonCore-1.0", true) and LibStub("DonCore-1.0"):Get("MinimapButton", 4)
  function G.HideWord()
    return MB4 and MB4.Word and MB4.Word("Hide minimap button") or "Hide minimap button"
  end
  function G.HideByMenu()
    if nsButton.HideMinimapButtonByMenu then nsButton.HideMinimapButtonByMenu() else G.SetShown(false) end
  end

  -- (04.11.2026) the button's picture: the leading module's (Guildon's crest, or the anvil with only Crafts & Recipes)
  local function SetLogo()
    local file = Logo(Lead())
    if G.opts then G.opts.icon = file end
    local b = nsButton.MinimapButton and nsButton.MinimapButton()
    if b and b.icon and b.icon.guildonLogo ~= file then
      b.icon:SetTexture(file)
      if b.icon.SetTexCoord then b.icon:SetTexCoord(0, 1, 0, 1) end
      b.icon.guildonLogo = file
    end
  end

  -- shown when the leading module has it on; before PLAYER_LOGIN nothing is built (the other modules sign in first)
  function G.Refresh()
    if not G.ready or not next(G.modules) or not nsButton.RefreshMinimapButton then return end
    if Get("minimapButton") == false and G.menu then G.menu:Close() end
    SetLogo()
    nsButton.RefreshMinimapButton()
    G.button = nsButton.MinimapButton()
    SetLogo()
  end

  -- (04.11.2026) once at login: the leading module's on/off to every module (nil counts as on), so a part switched off
  -- alone earlier does not show "off" while the button is there, and the button does not jump with the order of loading
  function G.Align()
    if G.aligned or not next(G.modules) then return end
    G.aligned = true
    SetAll("minimapButton", Get("minimapButton") ~= false)
  end

  function G.Register(m)
    if type(m) ~= "table" or type(m.id) ~= "string" then return false end
    m.order = tonumber(m.order) or 9
    m.title = m.title or m.id
    G.modules[m.id] = m
    if G.ready then G.Refresh() end
    return true
  end

  function G.SetShown(on)
    SetAll("minimapButton", on ~= false and true or false)
    G.Refresh()
  end
end

-- every copy: sign in this module, build the button once all are in
local mod = ns.MODULE or {}
ns.OnInit(function()
  G.Register({ id = mod.id or ns.ADDON_TITLE or "?", title = mod.title or ns.ADDON_TITLE, icon = mod.icon or ICON, order = mod.order,
    db = ns.db, open = function() if ns.ToggleWindow then ns.ToggleWindow() end end, logo = mod.logo,
    options = function() if ns.OpenOptions then ns.OpenOptions() end end,
    tip = function() return ns.LauncherTip and ns.LauncherTip() or nil end })
end)
ns.On("PLAYER_LOGIN", function()
  G.ready = true
  if G.Align then G.Align() end
  ns.SafeCall("minimap button", G.Refresh)
end)

-- the module's own option "Minimap button" switches the shared one
function ns.RefreshMinimapButton() G.SetShown(ns.db.minimapButton ~= false) end
function ns.MinimapButton() return G.button end -- (tests)
-- (04.11.2026, Era-Test) the option item of DonCore's MinimapButton (minor 3), switching the shared button for every part;
-- o = { name, tip, parent } as there
function ns.MinimapOption(o)
  local it = G.proxy and G.proxy.MinimapOption and G.proxy.MinimapOption(o)
    or { key = "minimapButton", name = o and o.name, tip = o and o.tip, parent = o and o.parent }
  it.onChange = function() ns.RefreshMinimapButton() end
  return it
end
