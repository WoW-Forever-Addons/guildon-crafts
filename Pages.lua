local _, ns = ...
local L = ns.L
local Kit = ns.Kit

---------------------------------------------------------------------------
-- Guildon Crafts's tabs and the overview in the Don style (StyleKit 2 step 4, 02.11.2026, docs/layout_2026-11-02/guildon/
-- part 3): the guild as a hero, the numbers as tiles that share the width, a button for the website export. The window
-- itself is Shared/Window.lua (GuildShared, DonCore's Kit.Window); the other tabs are built in their own files
-- (ns.PAGE_BUILDERS). Every option is in DonCore's options window (Options.lua), the cog in the header opens it.
---------------------------------------------------------------------------
local S = Kit.SIZE
local AgeText = ns.UI.AgeText

ns.TABS = {
  { key = "overview", title = "Overview", icon = "Interface\\Icons\\INV_Misc_Book_09" },
  { key = "professions", title = "Professions", icon = "Interface\\Icons\\Trade_BlackSmithing" },
  { key = "recipes", title = "Recipes", icon = "Interface\\Icons\\INV_Scroll_03" },
  { key = "wishes", title = "Wish list", icon = "Interface\\Icons\\INV_Letter_15" },
  -- (Discord 30.10.: "warum muss das in einem Gildenaddon sein?") off by default, switched on in the options
  { key = "profit", title = "Profitable", icon = "Interface\\Icons\\INV_Misc_Coin_02", optional = "showProfit" },
}

ns.PANEL_NAME = "GuildonCraftsPanel"
ns.OPTIONS_ID = "Guildon Crafts"
ns.SLASH = "/gnc options"
-- (mockup 02.11.2026) the window's title; the guild's name follows as the subtitle
function ns.TitleText() return "Crafts & Recipes" end

local function N(v) return ns.Style.Number and ns.Style.Number(v) or tostring(v or 0) end

---------------------------------------------------------------------------
-- Overview
---------------------------------------------------------------------------
local TILE_MIN, TILE_H = 210, 72

-- own characters of this account with their professions (the overview without a guild)
local function CharItems()
  local names = {}
  for owner in pairs(ns.db.prof or {}) do names[#names + 1] = owner end
  for owner in pairs(ns.db.chars or {}) do if not (ns.db.prof or {})[owner] then names[#names + 1] = owner end end
  table.sort(names)
  local items = { { kind = "group", static = true, text = L["Your characters"] } }
  local any = false
  for _, owner in ipairs(names) do
    local parts = {}
    for _, pr in ipairs(ns.PROFS) do
      local e = ns.db.prof[owner] and ns.db.prof[owner][pr.id]
      if e then parts[#parts + 1] = ("%s %d/%d"):format(ns.ProfName(pr.id), e.rank or 0, e.max or 0) end
    end
    if #parts > 0 then
      any = true
      local c = ns.db.chars and ns.db.chars[owner]
      local cls = c and c.class or nil
      items[#items + 1] = { kind = "table", key = owner, class = cls,
        cells = { Kit.ClassText(cls, ns.ShortName(owner)), { text = table.concat(parts, ", "), color = Kit.C.muted } } }
    end
  end
  if not any then
    items[#items + 1] = { kind = "table", key = "none",
      cells = { "", { text = L["Open your profession window once so that Guildon Crafts can read your recipes."], color = Kit.C.quiet } } }
  end
  return items
end

local function BuildOverview(p)
  p.hero = Kit.Hero(p, { height = 72 })
  p.hero:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
  p.tiles = {
    members = Kit.Tile(p, { label = L["Members"] }),
    guildon = Kit.Tile(p, { label = L["With Guildon Crafts"] }),
    sets = Kit.Tile(p, { label = L["Data sets"] }),
    last = Kit.Tile(p, { label = L["Last data from the guild"] }),
    game = Kit.Tile(p, { label = L["Game version"] }),
    -- the wishes the player can craft: the tile opens the wish list
    open = Kit.Tile(p, { label = L["Open wishes for you"], onClick = function() ns.OpenTab("wishes") end }),
  }
  p.order = { "members", "guildon", "open", "sets", "last", "game" }
  p.tiles.open:SetTooltip(L["Wish list"], { L["Wishes of the guild that you can craft."] }, L["Click: open the wish list"])
  -- without a guild: the player's own characters with their professions
  p.chars = Kit.List(p, {})
  p.chars.columns = { { width = 140 }, { width = 120, grow = true } }
  p.chars.tableIcon = true
  p.chars:Hide()
  -- bottom: a note, the website export and the example guild (layout review 25.10.: without a guild the page was empty)
  p.note = Kit.Text(p, "sub", Kit.C.muted)
  p.export = Kit.Button(p, L["Export for the guild website"], { small = true, onClick = function() if ns.ShowExport then ns.ShowExport() end end })
  p.export:SetTooltip(L["Export for the guild website"], { L["Your characters' professions and recipes as one text to copy."] }, L["Also: /gnc export"])
  p.demo = Kit.Button(p, "", { small = true, onClick = function()
    if ns.SetDemo then ns.SetDemo(not ns.demo) end
    if p:IsShown() then p:Refresh() p:Layout(p._w, p._h, p._mode) end
  end })
  p.Layout = function(self, w, h, mode)
    self._w, self._h, self._mode = w, h, mode
    local x0, inner = S.pad, w - 2 * S.pad
    self.hero:ClearAllPoints()
    self.hero:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
    self.hero:Layout(w)
    local y = 72 + S.pad
    local cols = math.max(1, math.min(3, math.floor((inner + S.gap) / (TILE_MIN + S.gap))))
    local tw = math.floor((inner - (cols - 1) * S.gap) / cols)
    local i = 0
    for _, k in ipairs(self.order) do
      local t = self.tiles[k]
      if t:IsShown() then
        local c, r = i % cols, math.floor(i / cols)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", self, "TOPLEFT", x0 + c * (tw + S.gap), -(y + r * (TILE_H + S.gap)))
        t:Layout(tw)
        i = i + 1
      end
    end
    self.chars:ClearAllPoints()
    self.chars:SetPoint("TOPLEFT", self, "TOPLEFT", x0, -y)
    self.chars:Resize(inner, math.max(40, h - y - 44))
    -- the buttons bottom right (the export button cut first when the window is narrow), the note left of them
    local bx = w - S.pad
    self.demo:ClearAllPoints()
    if self.demo:IsShown() then
      self.demo:SetPoint("BOTTOMRIGHT", self, "BOTTOMLEFT", bx, S.gap)
      bx = bx - self.demo:GetWidth() - S.gap
    end
    local ew = math.min(self.export.natural or 160, math.max(60, math.floor(inner * 0.4)))
    self.export:Layout(ew)
    self.export:ClearAllPoints()
    self.export:SetPoint("BOTTOMRIGHT", self, "BOTTOMLEFT", bx, S.gap)
    bx = bx - ew - S.gap
    self.note:ClearAllPoints()
    self.note:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", x0, S.gap + 6)
    Kit.Fit(self.note, math.max(40, bx - x0))
  end
  p.Refresh = function(self)
    local g, rank = ns.GuildInfo()
    self.demo:SetText(ns.demo and L["Hide the example guild"] or L["Show an example guild"])
    self.demo:SetShown(ns.demo or not ns.InGuild())
    for _, t in pairs(self.tiles) do t:SetShown(g ~= nil) end
    self.chars:SetShown(g == nil)
    if not g then
      self.hero:SetData({ kicker = L["Your guild"], title = L["You are not in a guild."] })
      self.hero._tipFn = function() return L["You are not in a guild."], { L["Guildon Crafts shows your guild once you join one."] } end
      self.chars:SetItems(CharItems(), true)
      self.note:SetText(L["How it works: 1. Join a guild. 2. Members with Guildon Crafts show up by themselves. 3. Open your profession window once, then the guild sees your recipes."])
      if self._w then self:Layout(self._w, self._h, self._mode) end
      return
    end
    local total, online, guildon, guildonOnline = ns.MemberCounts()
    self.hero:SetData({ kicker = L["Your guild"], title = g, value = N(total), label = L["online: %d"]:format(online),
      progress = total > 0 and online / total or nil })
    self.hero._tipFn = function() return g, { L["Your rank: %s"]:format(rank or "?") } end
    local sets, newest, mine = 0, nil, nil
    for _, s in pairs(ns.db.sets) do
      sets = sets + 1
      if s.o ~= ns.MyName() then
        if not newest or s.t > newest then newest = s.t end
      elseif not mine or s.t > mine then
        mine = s.t
      end
    end
    local t = self.tiles
    t.members:SetData(L["Members"], N(total), L["online: %d"]:format(online))
    t.guildon:SetData(L["With Guildon Crafts"], N(guildon), L["online: %d"]:format(guildonOnline))
    t.sets:SetData(L["Data sets"], N(sets), L["Your rank: %s"]:format(rank or "?"))
    t.last:SetData(L["Last data from the guild"], newest and AgeText(newest) or L["No data from the guild yet."],
      -- (Daniel 26.10.: "sollte nicht stehen, dass welche von mir da sind?") the player's own data
      mine and L["Yours: %s"]:format(AgeText(mine)) or L["Yours: nothing yet"])
    t.game:SetData(L["Game version"], ns.ERA and L["Classic Era"] or L["WoW Forever"], "Guildon Crafts " .. tostring(ns.VERSION or ""))
    local open = ns.OpenWishesForMe and ns.OpenWishesForMe() or 0
    t.open:SetData(L["Open wishes for you"], N(open), L["Click: open the wish list"], open > 0 and Kit.C.txGold or Kit.C.muted)
    if ns.demo then
      self.note:SetText(L["Example guild is on: the members ending in -Demo are made up and only on your screen. /gnc demo off removes them."])
    else
      self.note:SetText(L["Every member who has Guildon Crafts shows up here."])
    end
    if self._w then self:Layout(self._w, self._h, self._mode) end
  end
end

ns.PAGE_BUILDERS.overview = BuildOverview

-- open the recipe book (optionally on one profession)
function ns.OpenRecipes(prof, spell)
  if ns.RecipeBookShow then ns.RecipeBookShow(prof, spell) end
  ns.OpenTab("recipes")
end
