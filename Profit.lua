local _, ns = ...
local L = ns.L
local Kit = ns.Kit

---------------------------------------------------------------------------
-- Tab "Profitable" (GUILDON_PLAN.md step 5, "Bedienung"; Don style 02.11.2026, BAUSTEINE.md: the same table with column
-- heads and a card as the other pages): recipes by profit per craft. Columns revenue (auction price minus 5 percent fee),
-- reagent cost, profit, age of the prices; a click on a head sorts. The card on the right: the reagents with price and what
-- the player has, the crafters in the guild, wish and whisper. Switches: only my recipes, count my stock (reagents in bags
-- and bank cost nothing). Prices from Prices.lua; "Scan prices" at the auction house.
---------------------------------------------------------------------------
local S = Kit.SIZE
local DETAIL_W = 300
local FEE = 0.05

-- short money text for the columns: 12.3g, 45s, 7c
function ns.ShortMoney(c)
  if not c then return "?" end
  local neg = c < 0
  c = math.abs(c)
  local t
  if c >= 100000 then t = ("%dg"):format(math.floor(c / 10000 + 0.5))
  elseif c >= 10000 then t = ("%.1fg"):format(c / 10000)
  elseif c >= 100 then t = ("%ds"):format(math.floor(c / 100 + 0.5))
  else t = ("%dc"):format(c) end
  return (neg and "-" or "") .. t
end

local function AgeShort(t)
  if not t then return "" end
  local age = math.max(0, time() - t)
  if age < 3600 then return L["now"] end
  if age < 86400 then return ("%dh"):format(math.floor(age / 3600)) end
  return ("%dd"):format(math.floor(age / 86400))
end

local function State()
  local db = ns.db
  db.profitProf = tonumber(db.profitProf) or 0
  -- "only my recipes" is on by default (Daniel 26.10.); a value saved before that is replaced once
  if db.profitMine == nil or not db.profitMineDefault then db.profitMine = true db.profitMineDefault = true end
  if db.profitStock == nil then db.profitStock = false end
  return db
end

-- all recipes with a price for the result and the reagents: list sorted by profit, and how many have no prices
function ns.ProfitRows()
  local db = State()
  local me = ns.MyName()
  local mine = ns.MyCrafts and ns.MyCrafts() or {}
  local rows, missing = {}, 0
  local idx = ns.CraftIndex()
  for spell, crafters in pairs(idx.crafters) do
    local info = ns.RecipeInfo(spell)
    local prof = info.prof
    if (db.profitProf == 0 or prof == db.profitProf) and (not db.profitMine or mine[spell]) and info.item and info.item > 0 then
      local p, tp = ns.Price(info.item)
      local cost, tc = ns.ReagentCost(spell, 1, db.profitStock)
      if p and cost then
        local revenue = math.floor(p * (info.count or 1) * (1 - FEE))
        rows[#rows + 1] = { spell = spell, info = info, revenue = revenue, cost = cost, profit = revenue - cost,
          oldest = math.min(tp or time(), tc or time()), crafters = ns.CraftersOf(spell) }
      else
        missing = missing + 1
      end
    end
  end
  table.sort(rows, function(a, b)
    if a.profit ~= b.profit then return a.profit > b.profit end
    return a.spell < b.spell
  end)
  return rows, missing
end

local page

local function SortRows(rows, key, desc)
  local function Val(r)
    if key == "name" then return (ns.SpellName(r.spell) or ""):lower() end
    if key == "revenue" then return r.revenue end
    if key == "cost" then return r.cost end
    if key == "age" then return r.oldest end
    return r.profit
  end
  table.sort(rows, function(a, b)
    local x, y = Val(a), Val(b)
    if x ~= y then if desc then return x > y end return x < y end
    return a.spell < b.spell
  end)
end

local function Entries()
  local rows, missing = ns.ProfitRows()
  local db = State()
  local key = db.profitSort or "profit"
  local desc = db.profitDesc ~= false
  if key ~= "profit" or not desc then SortRows(rows, key, desc) end
  local out = {}
  for i = 1, math.min(#rows, 300) do
    local r = rows[i]
    local name = ns.SpellName(r.spell) or L["Recipe %d"]:format(r.spell)
    -- (Daniel 11.11.2026) a recipe with a cooldown says so: its profit is not one per craft in a row
    local cdText = ns.RecipeCooldownText and ns.RecipeCooldownText(r.spell)
    if cdText then name = name .. " (" .. cdText .. ")" end
    local good = r.profit > 0
    local itemID, quality = ns.RecipeItemQuality(r.info)
    out[#out + 1] = { kind = "table", key = r.spell, spell = r.spell, row = r, icon = ns.RecipeIcon(r.spell, r.info), dim = #r.crafters == 0,
      itemID = itemID, quality = quality,
      cells = { { text = name, color = #r.crafters > 0 and Kit.C.title or Kit.C.quiet }, { text = ns.ShortMoney(r.revenue), color = Kit.C.body },
        { text = ns.ShortMoney(r.cost), color = Kit.C.body }, { text = ns.ShortMoney(r.profit), color = good and Kit.C.green or Kit.C.red },
        { text = AgeShort(r.oldest), color = Kit.C.quiet } } }
  end
  return out, #rows, missing
end

local function FillDetail(d, spell)
  local info = ns.RecipeInfo(spell)
  local p, t, _, flagged = ns.Price(info.item)
  local sale = p and (ns.MoneyText(p) .. ((info.count or 1) > 1 and (" x" .. info.count) or "")) or "?"
  local itemID, quality = ns.RecipeItemQuality(info)
  d:SetHead({ icon = ns.RecipeIcon(spell, info), title = ns.SpellName(spell) or L["Recipe %d"]:format(spell),
    itemID = itemID, titleColor = quality and Kit.QualityColor(quality) or nil,
    meta = L["Sells for %s"]:format(sale), pill = flagged and { L["(odd price)"], "warn" } or nil })
  local cr = ns.CraftersOf(spell)
  page.crafter = nil
  for _, o in ipairs(cr) do if o ~= ns.MyName() and ns.IsOnline(o) then page.crafter = o break end end
  local acts = { { text = L["Wish"], kind = "primary", onClick = function() ns.ShowWishForm(spell) end } }
  if page.crafter then
    local o = page.crafter
    acts[#acts + 1] = { text = L["Whisper %s"]:format(ns.ShortName(o)), onClick = function() ns.WhisperCrafter(o, spell) end }
  end
  d:SetActions(acts)
  d:Begin()
  if t then d:Line(L["Price from"], Kit.C.muted, ns.UI.AgeText(t), Kit.C.quiet) end
  local cdText = ns.RecipeCooldownText and ns.RecipeCooldownText(spell)
  if cdText then d:Line(L["Cooldown"], Kit.C.muted, cdText, Kit.C.title) end
  d:Section(L["Reagents: price and in your bags"])
  for _, rg in ipairs(info.reagents or {}) do
    local rp = ns.Price(rg[1])
    local have = ns.ItemCount(rg[1])
    d:Item(rg[1], rg[2] .. " x " .. (ns.ItemName(rg[1]) or ("#" .. rg[1])), Kit.C.body,
      (rp and ns.ShortMoney(rp * rg[2]) or "?") .. "  " .. have .. "/" .. rg[2], have >= rg[2] and Kit.C.green or Kit.C.red)
  end
  d:Section(L["Who can craft it"], #cr > 0 and tostring(#cr) or nil)
  for i = 1, math.min(#cr, 8) do
    local o = cr[i]
    local on = ns.IsOnline(o)
    d:Line(ns.ShortName(o), on and Kit.C.green or Kit.C.quiet, on and L["online"] or L["offline"], on and Kit.C.green or Kit.C.quiet)
  end
  if #cr > 8 then d:Line(L["and %d more"]:format(#cr - 8), Kit.C.quiet) end
  if #cr == 0 then d:Line(L["Nobody in the guild knows this recipe yet."], Kit.C.quiet) end
  d:End()
end

local function Placeholder(d, n)
  d.close:Hide()
  d:SetHead({ title = L["Profitable"], meta = L["Choose a recipe on the left."] })
  d:SetActions({})
  d:Begin()
  if n == 0 then
    d:Para(L["No prices yet. With Auctionator, Auctioneer or aux: scan at the auction house; Guildon Crafts shares the prices with the guild. Without: \"Scan prices\" at the auction house."], Kit.C.muted)
  else
    d:Para(L["Choose a recipe on the left."], Kit.C.muted)
  end
  d:End()
end

local function Info(n, missing)
  local addons = {}
  for _, a in ipairs(ns.PriceAddons()) do addons[#addons + 1] = a.name end
  return L["%d recipes with prices, %d without."]:format(n, missing) .. "  " ..
    (#addons > 0 and L["Prices from: %s and the guild"]:format(table.concat(addons, ", ")) or L["Prices from the guild and your own scans"])
end

local function Refresh()
  if not page then return end
  ns.InvalidatePrices()
  local db = State()
  page.prof:Update()
  page.mine:SetValue(db.profitMine)
  page.stock:SetValue(db.profitStock)
  local key, desc = db.profitSort or "profit", db.profitDesc ~= false
  if page.head.sortKey ~= key or page.head.desc ~= desc then page.head:SetSort(key, desc) end
  local data, n, missing = Entries()
  page.n = n
  page.list:SetItems(data)
  page.info = Info(n, missing)
  page.scan:SetShown(ns.AuctionHouseOpen and ns.AuctionHouseOpen() and true or false)
  local sel = page.selected
  if sel and not ns.RECIPES[sel] and not ns.CraftIndex().crafters[sel] then sel = nil end
  page.selected = sel
  local picked
  for _, e in ipairs(data) do if e.spell == sel then picked = e break end end
  page.list:Select(picked)
  -- the numbers and the source of the prices in the footer (p.Hint)
  if ns.RefreshHint then ns.RefreshHint() end
  if page._w then page:Layout(page._w, page._h, page._mode) end
end
ns.RefreshProfit = Refresh

ns.PAGE_BUILDERS.profit = function(p)
  page = p
  State()
  p.prof = Kit.Dropdown(p, {
    items = function()
      local out = { { value = 0, text = L["All professions"] } }
      for _, pr in ipairs(ns.PROFS) do if pr.craft then out[#out + 1] = { value = pr.id, text = ns.ProfName(pr.id) } end end
      return out
    end,
    get = function() return State().profitProf end,
    set = function(key) State().profitProf = key p.selected = nil Refresh() end,
  })
  p.prof:SetTooltip(L["Profession"], { L["Click: choose"] })
  p.mine = Kit.Toggle(p, { label = L["Only my recipes"], get = function() return State().profitMine end,
    set = function(v) ns.db.profitMine = v Refresh() end })
  p.stock = Kit.Toggle(p, { label = L["Count my stock"], get = function() return State().profitStock end,
    set = function(v) ns.db.profitStock = v Refresh() end })
  p.scan = Kit.Button(p, L["Scan prices"], { small = true, onClick = function()
    -- the reagents and results of the shown recipes whose price is older than a day or missing, up to 80
    local items, now = {}, time()
    for _, id in ipairs(ns.RelevantItems()) do
      local pr, t = ns.Price(id)
      if not pr or now - (t or 0) > 86400 then items[#items + 1] = id end
      if #items >= 80 then break end
    end
    ns.ScanPrices(items)
  end })
  p.scan:SetTooltip(L["Scan prices"], { L["Asks the auction house for missing or old prices, one item after the other (up to 80)."] })
  -- the table head: a click sorts by that column, a second click turns the order round
  p.head = Kit.TableHead(p, { icon = true, columns = {
    { key = "name", text = L["Recipe"], width = 110, grow = true, sort = true },
    { key = "revenue", text = L["Revenue"], width = 58, justify = "RIGHT", sort = true, desc = true },
    { key = "cost", text = L["Reagents"], width = 58, justify = "RIGHT", sort = true, desc = true },
    { key = "profit", text = L["Profit"], width = 62, justify = "RIGHT", sort = true, desc = true },
    { key = "age", text = L["Age"], width = 36, justify = "RIGHT", sort = true, desc = true } },
    onSort = function(key, desc)
      local db = State()
      db.profitSort, db.profitDesc = key, desc and true or false
      Refresh()
    end })
  p.list = Kit.List(p, {
    onClick = function(e)
      if not e.row then return end
      p.selected, p.overlay = e.key, true
      p.list:Select(e)
      ns.Relayout()
    end,
  })
  p.list:SetEmpty(L["No recipes with prices yet."])
  p.detail = Kit.Detail(p, { onClose = function()
    p.overlay = nil
    if p._mode ~= "full" then p.selected = nil p.list:Select(nil) end
    ns.Relayout()
  end })
  p.Hint = function(self) return self.info or "" end
  p.Layout = function(self, w, h, mode)
    self._w, self._h, self._mode = w, h, mode
    local narrow = mode ~= "full"
    local side = narrow and 0 or DETAIL_W + S.pad
    local lw = w - 2 * S.pad - side
    local y = S.gap
    local x = S.pad
    local dw = math.max(110, math.min(170, math.floor(lw * 0.3)))
    self.prof:ClearAllPoints() self.prof:SetPoint("TOPLEFT", self, "TOPLEFT", x, -y) self.prof:Layout(dw)
    x = x + dw + S.gap
    local sw = self.scan:IsShown() and math.min(self.scan.natural or 100, 120) or 0
    if sw > 0 then
      self.scan:Layout(sw)
      self.scan:ClearAllPoints()
      self.scan:SetPoint("TOPRIGHT", self, "TOPLEFT", S.pad + lw, -y - 2)
    end
    -- the two switches share what is left (their labels cut)
    local room = S.pad + lw - (sw > 0 and sw + S.gap or 0) - x
    local tw = math.floor((room - S.gap) / 2)
    for _, t in ipairs({ self.mine, self.stock }) do
      t:ClearAllPoints()
      t:SetPoint("TOPLEFT", self, "TOPLEFT", x, -y - 4)
      t:SetWidth(math.max(28, tw))
      if t.label then Kit.Fit(t.label, math.max(1, tw - 34)) end
      x = x + tw + S.gap
    end
    y = y + S.button + S.gap
    self.head:ClearAllPoints()
    self.head:SetPoint("TOPLEFT", self, "TOPLEFT", S.pad, -y)
    self.head:Bind(self.list)
    self.head:Layout(lw)
    y = y + S.chip
    self.list:ClearAllPoints()
    self.list:SetPoint("TOPLEFT", self, "TOPLEFT", S.pad, -y)
    self.list:Resize(lw, math.max(40, h - y - S.gap))
    local sel = self.selected
    if narrow and not self.overlay then sel = nil end
    local show = sel ~= nil or not narrow
    self.detail:SetShown(show)
    if show then
      local cwid = narrow and math.min(DETAIL_W, w - 2 * S.pad) or DETAIL_W
      self.detail:ClearAllPoints()
      self.detail:SetPoint("TOPRIGHT", self, "TOPRIGHT", -S.pad, -S.gap)
      self.detail:Layout(cwid, h - 2 * S.gap)
      if narrow then pcall(self.detail.SetFrameLevel, self.detail, (self.list:GetFrameLevel() or 1) + 20) end
      if sel then
        if narrow then self.detail.close:Show() else self.detail.close:Hide() end
        FillDetail(self.detail, sel)
      else
        Placeholder(self.detail, self.n or 0)
      end
    end
  end
  p.Refresh = function() Refresh() end
end

ns.On("AUCTION_HOUSE_SHOW", function() if page and page:IsVisible() then ns.After(0.3, Refresh) end end)
ns.On("AUCTION_HOUSE_CLOSED", function() if page and page:IsVisible() then ns.After(0.3, Refresh) end end)
