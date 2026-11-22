local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- The window of a Guildon part in the Don style (StyleKit 2 step 4, 02.11.2026, docs/layout_2026-11-02/guildon/): DonCore's
-- Kit.Window with the book tabs in the header, the guild's emblem in the logo square, the cog of the shared options window
-- (DonCore.Options, every option of the part is there), a footer for the hints of the page, the grip (720x420 to 1300x900).
-- The addon sets ns.TABS ({ key, title, icon, optional = db key }), ns.TitleText() (the part's name), ns.PANEL_NAME,
-- ns.OPTIONS_ID (its id in the options window), ns.SLASH (the hint at the cog) and registers its pages in
-- ns.PAGE_BUILDERS[key] = function(page) ... end. A page sets page:Layout(width, height, mode) (mode "full", "overlay"
-- under 960 px, "rail" under 800 px) and page:Refresh(); page:Hint() may return the footer text.
-- Place and size of the window: ns.db.window (Kit.Window's store).
-- (16.11.2026, Daniel: the Blizzard look as the default for all Don addons) the window and its pages take their blocks
-- from a kit picked when the window is built: the addon's ns.LookKit() returns kit, isBlizzard, reason (DonCore Kit, or
-- DonCore Blizz's kit with the addon's option blizzLook; no ns.LookKit: the Kit). The pages take it through ns.PageKit()
-- (ns.UI.kit, set before the first page is built). A build of the window or of a page that fails with Blizzard's blocks
-- hides the half-built window and builds it again with the Kit (one chat line per session). ns.WindowLook() says which
-- look runs and why (diag), ns.WindowReset() builds the window again after the option changed (open: at once, same tab).
---------------------------------------------------------------------------
local Kit = LibStub("DonCore-1.0"):Get("Kit", 4)
ns.Kit = Kit
ns.UI = ns.UI or {}
ns.PAGE_BUILDERS = ns.PAGE_BUILDERS or {}

local win, current
local pages, tabs = {}, {}
local UI, lookNote = Kit, "kit"
ns.UI.kit = Kit
-- the kit the pages build with (the window's)
function ns.PageKit() return ns.UI.kit or ns.Kit end

local function AgeText(stamp)
  local age = math.max(0, time() - (stamp or 0))
  if age < 3600 then return L["%d min ago"]:format(math.floor(age / 60)) end
  if age < 86400 then return L["%d h ago"]:format(math.floor(age / 3600)) end
  return L["%d days ago"]:format(math.floor(age / 86400))
end
ns.UI.AgeText = AgeText

function ns.GetPanel() return win end

local function Store()
  if type(ns.db.window) ~= "table" then ns.db.window = {} end
  return ns.db.window
end

local function TabShown(key)
  for _, t in ipairs(ns.TABS) do
    if t.key == key then return not t.optional or ns.db[t.optional] == true end
  end
  return false
end

-- the guild's emblem in the logo square: the addon's own (Libra Vivendi), the game's tabard (Forever), else the part's icon
local function PaintLogo()
  if not (win and win.logo) then return end -- (16.11.2026: the game's frame has win.logo over its round portrait too)
  local tex = win.logo.tex
  local file, r, g, b, br, bgc, bb
  if ns.GuildEmblem then file, r, g, b, br, bgc, bb = ns.GuildEmblem() end
  if not win.logo.crestBg then
    win.logo.crestBg = win.logo:CreateTexture(nil, "BORDER")
    win.logo.crestBg:SetPoint("TOPLEFT", 2, -2)
    win.logo.crestBg:SetPoint("BOTTOMRIGHT", -2, 2)
    win.logo.crestBg:SetTexture("Interface\\Buttons\\WHITE8x8")
    -- (16.11.2026, Daniel: Wappen im Porträt) round like the portrait in the game's frame
    if win.logo.mask and win.logo.crestBg.AddMaskTexture then win.logo.crestBg:AddMaskTexture(win.logo.mask) end
  end
  if file then
    tex:SetTexture(file)
    pcall(tex.SetTexCoord, tex, 0, 1, 0, 1)
    tex:SetVertexColor(r or 1, g or 1, b or 1, 1)
    if br then win.logo.crestBg:SetVertexColor(br, bgc, bb, 0.9) win.logo.crestBg:Show() else win.logo.crestBg:Hide() end
  else
    tex:SetTexture(ns.MODULE and ns.MODULE.icon or "Interface\\Icons\\INV_Misc_GroupNeedMore")
    pcall(tex.SetTexCoord, tex, 0.07, 0.93, 0.07, 0.93)
    tex:SetVertexColor(1, 1, 1, 1)
    win.logo.crestBg:Hide()
  end
end

local function Front()
  if win and win.Raise then win:Raise() end
end

-- while a window in the game's look is built or a page in it is built and drawn for the first time, an error goes up to
-- the pcall around it (and the Kit builds the window); otherwise it is caught and kept for the diag
local strict = false
local function Run(context, fn, ...)
  if strict then return fn(...) end
  return ns.SafeCall(context, fn, ...)
end

local function SetHint(p)
  if not (win and win.SetStatus) then return end
  local text = p and p.Hint and Run("hint", p.Hint, p) or ""
  win:SetStatus(text or "")
end

local function LayoutPage(p)
  if not (win and p) then return end
  local w, h, mode = win._bw or 720, win._bh or 380, win._mode or "full"
  p:ClearAllPoints()
  p:SetPoint("TOPLEFT", win.body, "TOPLEFT", 0, 0)
  p:SetSize(w, h)
  if p.Layout then Run("page layout", p.Layout, p, w, h, mode) end
end

local function Page(key)
  if pages[key] then return pages[key] end
  local build = ns.PAGE_BUILDERS[key]
  if not build then return nil end
  local p = CreateFrame("Frame", nil, win.body)
  p.key = key
  p:Hide()
  build(p)
  pages[key] = p
  return p
end

local function SelectNow(key)
  if not TabShown(key) or not ns.PAGE_BUILDERS[key] then key = ns.TABS[1].key end
  Front()
  current = key
  ns.db.tab = key
  for k, p in pairs(pages) do if k ~= key then p:Hide() end end
  for _, t in ipairs(tabs) do t:SetSelected(t.key == key) end
  local p = Page(key)
  p:Show()
  LayoutPage(p)
  if p.Refresh then Run("page refresh", p.Refresh, p) end
  SetHint(p)
end

local Fallback -- (below) the Kit builds the window after a failed build in the game's look
local function Select(key)
  if UI == Kit then SelectNow(key) return end
  local k = (TabShown(key) and ns.PAGE_BUILDERS[key]) and key or ns.TABS[1].key
  if pages[k] then SelectNow(key) return end
  -- a page built for the first time in the game's look: an error builds the window again with the Kit
  strict = true
  local ok, err = pcall(SelectNow, key)
  strict = false
  if not ok then Fallback(err, key) end
end
ns.SelectTab = Select

-- the shown tabs are the window's tabs (an optional tab that is off is hidden)
local function PlaceTabs()
  if not win then return end
  local shown = {}
  for _, t in ipairs(tabs) do
    if TabShown(t.key) then shown[#shown + 1] = t t:Show() else t:Hide() end
  end
  if win.blizz then
    -- the game's tabs hang one after the other under the frame (its own list stays whole for the game's tab code)
    for i, t in ipairs(shown) do
      t:ClearAllPoints()
      if i == 1 then t:SetPoint("TOPLEFT", win, "BOTTOMLEFT", 11, 2) else t:SetPoint("TOPLEFT", shown[i - 1], "TOPRIGHT", 3, 0) end
    end
  else
    win.tabs = shown
  end
  win:Layout()
end

-- switching an optional tab on or off (options)
function ns.RefreshTabs()
  if not win then return end
  PlaceTabs()
  if current and not TabShown(current) then Select(ns.TABS[1].key) end
end

-- the kit for the window: the addon's look (ns.LookKit), else the Kit
local function PickUI()
  UI, lookNote = Kit, "kit"
  if ns.LookKit then
    local ok, kit, blizz, why = pcall(ns.LookKit)
    if ok and blizz and kit then UI, lookNote = kit, "blizzard"
    elseif ok and why then lookNote = "kit (" .. tostring(why) .. ")"
    elseif not ok then lookNote = "kit (error: " .. tostring(kit) .. ")" end
  end
  ns.UI.kit = UI
end

local function Build()
  local blizz = UI ~= Kit
  win = UI.Window(blizz and (ns.PANEL_NAME .. "Blizz") or ns.PANEL_NAME, {
    title = ns.TitleText(), subtitle = ns.GuildInfo and ns.GuildInfo() or nil,
    logo = ns.MODULE and ns.MODULE.icon, options = ns.OPTIONS_ID, hint = ns.SLASH and L["%s opens them too."]:format(ns.SLASH) or nil,
    -- (02.11.2026, Daniel: "den kopfbereich schon seeehr groß") the flat head of the kit
    compact = true, footer = true, store = Store(),
    -- (16.11.2026) the Kit's windows show at 80 %, the game's frame at 100 %: about the same size on the screen
    width = blizz and 860 or 980, height = blizz and 580 or 640, min = blizz and { 600, 380 } or nil, max = blizz and { 1300, 900 } or nil,
    onLayout = function(w, bw, bh, mode)
      w._bw, w._bh, w._mode = bw, bh, mode
      local p = current and pages[current]
      if p and p:IsShown() then LayoutPage(p) end
    end,
  })
  for _, t in ipairs(ns.TABS) do
    local tab = win:AddTab(t.key, L[t.title])
    tabs[#tabs + 1] = tab
  end
  win.opts.onTab = function(key) Select(key) end
  PlaceTabs()
  PaintLogo()
  if blizz then SelectNow(ns.db.tab) else Select(ns.db.tab) end
end

local function Forget()
  if win and win.Hide then pcall(win.Hide, win) end
  for _, p in pairs(pages) do if p.Hide then pcall(p.Hide, p) end end
  win, current = nil, nil
  pages, tabs = {}, {}
end

local said
local function SayLook(err)
  -- the addon may gather every fallback of its windows into one chat line per session
  if ns.LookFailed then ns.LookFailed("window", err) return end
  if said then return end
  said = true
  local diag = ns.SLASH and ns.SLASH:gsub("options$", "diag") or "diag"
  ns.Print(L["The window could not be built in the game's look, it opens in the Don look. %s says why."]:format(diag))
end

Fallback = function(err, key)
  Forget()
  UI, lookNote = Kit, "kit (error: " .. tostring(err) .. ")"
  ns.UI.kit = Kit
  SayLook(err)
  Build()
  if key then Select(key) end
  win:Show()
  Front()
end

local function Create()
  PickUI()
  if UI == Kit then Build() return end
  strict = true
  local ok, err = pcall(Build)
  strict = false
  if not ok then Fallback(err) end
end

function ns.Refresh()
  if not win then return end
  if win.title and win.title.SetText then win.title:SetText(Kit.Upper(ns.TitleText())) end
  if win.opts then win.opts.title = ns.TitleText() end
  win:SetSubtitle(ns.GuildInfo and ns.GuildInfo() or "")
  PaintLogo()
  local p = current and pages[current]
  if p and p:IsShown() and p.Refresh then
    ns.SafeCall("page refresh", p.Refresh, p)
    SetHint(p)
  end
end

-- the page's footer text changed (page:Hint() says something else now)
function ns.RefreshHint()
  local p = current and pages[current]
  if p and p:IsShown() then SetHint(p) end
end

-- a page changed something its layout depends on (the census open, a detail picked): place it again
function ns.Relayout()
  local p = current and pages[current]
  if p and p:IsShown() then LayoutPage(p) end
end

function ns.ToggleWindow()
  if (not win or not win:IsShown()) and ns.ReadKnown then ns.ReadKnown() end -- Era: the recipes the character knows, without the profession window
  -- (22.11.2026, Ruckler) ns.RosterWanted: roster updates skipped while the windows were closed are caught up
  if not win then Create() win:Show() Front() ns.RequestRoster() ns.RosterWanted() return end
  if win:IsShown() then win:Hide() else win:Show() Front() ns.RequestRoster() ns.RosterWanted() ns.Refresh() end
end

function ns.OpenTab(key)
  if ns.ReadKnown and (not win or not win:IsShown()) then ns.ReadKnown() end
  if not win then Create() end
  if not win:IsShown() then win:Show() end
  Front()
  Select(key)
  ns.RequestRoster()
  ns.RosterWanted()
end

-- (options) the window back to the middle of the screen at its first size
function ns.ResetWindow()
  local st = Store()
  for k in pairs(st) do st[k] = nil end
  if not win then return end
  win:ClearAllPoints()
  win:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  if win.blizz then win:SetSize(860, 580) else win:SetSize(980, 640) end
  win:Save()
end

-- (16.11.2026) the option blizzLook changed: the window is built again in the other look the next time it opens (it was
-- open: now, on the same tab)
function ns.WindowReset()
  if not win then return end
  local open, tab = win:IsShown(), current
  Forget()
  if open then ns.OpenTab(tab) end
end
-- "blizzard" or "kit", with the reason when the addon's look asked for the game's and the Kit had to build (diag)
function ns.WindowLook() return lookNote end

function ns.WindowState() return win, current, pages, tabs end -- (tests)
function ns.WindowOpen() return win ~= nil and win:IsShown() end

-- roster or data changed: repaint the open page (once per half second at most)
local queued = false
local function Later()
  if queued or not win or not win:IsShown() then return end
  queued = true
  ns.After(0.5, function() queued = false ns.Refresh() end)
end
ns.OnRosterChanged = Later
ns.OnDataChanged = Later

-- while the window is open, the roster is asked for every 60 s (online states)
ns.OnInit(function()
  ns.NewTicker(60, function() if win and win:IsShown() then ns.RequestRoster() end end)
end)
