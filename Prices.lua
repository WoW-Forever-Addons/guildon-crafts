local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- Prices (GUILDON_PLAN.md step 5): auction prices from the AH addons the player has, shared with the guild; the
-- newest scan wins, outliers (more than a factor of 5 from the median of the reports) are marked and not used.
-- Adapters: one table each, every call protected (pcall). Names and calls as the addons document them; checked only
-- outside the game (OFFEN.md): Auctionator API v1 (GetAuctionPriceByItemID / GetAuctionAgeByItemID with a caller
-- name), Auctioneer (AucAdvanced.API.GetMarketValue with an item link), aux (its history module, if it can be reached).
-- Without an AH addon: a short own scan of chosen items while the auction house is open (Era QueryAuctionItems,
-- Forever C_AuctionHouse).
-- Shared set "price": 1;<item b36>,<copper b36>,<age in hours b36>[,<source letter>];...  (up to 900 items)
---------------------------------------------------------------------------
local CALLER = "Guildon Crafts"
local MAX_SHARE, FACTOR, SHARE_EVERY = 900, 5, 6 * 3600

local function DB()
  ns.db.prices = type(ns.db.prices) == "table" and ns.db.prices or {} -- own scans: item -> { p, t }
  return ns.db
end

---------------------------------------------------------------------------
-- Adapters: get(item) -> copper, scan time (unix) or nil
---------------------------------------------------------------------------
local function ItemLink(item)
  local _, link = ns.ItemName(item)
  return link or ("item:" .. item)
end

ns.PRICE_ADAPTERS = {
  { key = "a", name = "Auctionator",
    present = function() return type(Auctionator) == "table" and type(Auctionator.API) == "table" and type(Auctionator.API.v1) == "table" end,
    get = function(item)
      local api = Auctionator.API.v1
      local ok, p = pcall(api.GetAuctionPriceByItemID, CALLER, item)
      if not ok or type(p) ~= "number" or p <= 0 then return nil end
      local t = time()
      if type(api.GetAuctionAgeByItemID) == "function" then
        local okA, age = pcall(api.GetAuctionAgeByItemID, CALLER, item)
        if okA and type(age) == "number" then t = time() - math.floor(age * 86400) end
      end
      return p, t
    end },
  { key = "u", name = "Auctioneer",
    present = function() return type(AucAdvanced) == "table" and type(AucAdvanced.API) == "table" and type(AucAdvanced.API.GetMarketValue) == "function" end,
    get = function(item)
      local ok, p, seen = pcall(AucAdvanced.API.GetMarketValue, ItemLink(item))
      if not ok or type(p) ~= "number" or p <= 0 then return nil end
      return math.floor(p), time() - 86400 -- Auctioneer gives no scan time: counted as one day old
    end },
  { key = "x", name = "aux",
    present = function()
      if type(require) ~= "function" then return false end
      local ok, h = pcall(require, "aux.core.history")
      return ok and type(h) == "table" and type(h.value) == "function"
    end,
    get = function(item)
      local ok, h = pcall(require, "aux.core.history")
      if not ok or type(h) ~= "table" then return nil end
      local okV, p = pcall(h.value, item .. ":0")
      if not okV or type(p) ~= "number" or p <= 0 then return nil end
      return math.floor(p), time() - 86400
    end },
}

function ns.PriceAddons()
  local out = {}
  for _, a in ipairs(ns.PRICE_ADAPTERS) do
    local ok, on = pcall(a.present)
    if ok and on then out[#out + 1] = a end
  end
  return out
end

-- own price of an item: newest of the adapters and the own scans; adapters: the list of ns.PriceAddons() when the caller
-- asks for many items (24.11.2026, the share at login asked for the list again for every item)
function ns.LocalPrice(item, adapters)
  local best, bt, src
  for _, a in ipairs(adapters or ns.PriceAddons()) do
    local ok, p, t = pcall(a.get, item)
    if ok and p and (not bt or (t or 0) > bt) then best, bt, src = p, t or time(), a.key end
  end
  local own = DB().prices[item]
  if own and (not bt or own.t > bt) then best, bt, src = own.p, own.t, "s" end
  return best, bt, src
end

---------------------------------------------------------------------------
-- Shared sets
---------------------------------------------------------------------------
function ns.DecodePrices(d)
  if type(d) ~= "string" or #d > 16000 or d:sub(1, 1) ~= "1" then return nil end
  local out, first, now = {}, true, 0
  for piece in (d .. ";"):gmatch("([^;]*);") do
    if first then
      if piece ~= "1" then return nil end
      first = false
    else
      local item, p, age, src = piece:match("^(%w+),(%w+),(%w+),?(%l?)$")
      if not item then return nil end
      now = now + 1
      if now > MAX_SHARE then return nil end
      out[#out + 1] = { item = ns.UnB36(item), p = ns.UnB36(p), age = ns.UnB36(age) * 3600, src = src ~= "" and src or nil }
    end
  end
  return out
end

-- the items worth sharing: reagents and results of the recipes the guild knows, own recipes first
local function AddItems(st, spell)
  local info = ns.RecipeInfo(spell)
  local items, seen = st.items, st.seen
  local id = info.item
  if id and id > 0 and not seen[id] then seen[id] = true items[#items + 1] = id end
  for _, r in ipairs(info.reagents or {}) do
    id = r[1]
    if id and id > 0 and not seen[id] then seen[id] = true items[#items + 1] = id end
  end
end
local function RelevantItems()
  local st = { items = {}, seen = {} }
  for spell in pairs(ns.CraftIndex().crafters) do AddItems(st, spell) end
  return st.items
end
ns.RelevantItems = RelevantItems

-- (24.11.2026, Ruckler, DonMonitor on the laptop: timer Prices.lua:326 57.3 ms once at login) a share is made in steps:
-- the recipes the guild knows, their items, the own price of each item, then the set. ns.SharePrices does all at once
-- (tests, the button); after the login and after the auction house ns.SharePricesSoon does them SLICE_MS at a time, one
-- step a frame (SLICE_N where the client has no debugprofilestop).
local SLICE_MS, SLICE_N = 4, 100
local function NewShare(force, every)
  local db = DB()
  if not force and (db.priceShared or 0) > time() - (every or SHARE_EVERY) then return nil end
  local spells = {}
  for spell in pairs(ns.CraftIndex().crafters) do spells[#spells + 1] = spell end
  return { spells = spells, si = 1, items = {}, seen = {}, ii = 1, list = {}, now = time(), adapters = ns.PriceAddons() }
end
-- true when every item has its price
local function ShareSlice(st, whole)
  local clock = not whole and type(debugprofilestop) == "function" and debugprofilestop or nil
  local t0, k = clock and clock(), 0
  local function Full()
    k = k + 1
    if whole or k % 10 ~= 0 then return false end
    if clock then return clock() - t0 >= SLICE_MS end
    return k >= SLICE_N
  end
  local spells, items = st.spells, st.items
  while st.si <= #spells do
    AddItems(st, spells[st.si])
    st.si = st.si + 1
    if Full() then return false end
  end
  local list, now, adapters = st.list, st.now, st.adapters
  while st.ii <= #items do
    local item = items[st.ii]
    st.ii = st.ii + 1
    local p, t, src = ns.LocalPrice(item, adapters)
    if p and t and now - t < 14 * 86400 then list[#list + 1] = { item, p, t, src } end
    if Full() and st.ii <= #items then return false end
  end
  return true
end
local function FinishShare(st)
  -- the ages from now: the prices were asked for over several frames
  local list, now = st.list, time()
  -- (24.11.2026) the same prices give the same text (equal times by item): an unchanged list is not sent again
  table.sort(list, function(a, b) if a[3] ~= b[3] then return a[3] > b[3] end return a[1] < b[1] end)
  local parts = { "1" }
  for i = 1, math.min(#list, MAX_SHARE) do
    local e = list[i]
    parts[#parts + 1] = ("%s,%s,%s,%s"):format(ns.B36(e[1]), ns.B36(e[2]), ns.B36(math.floor((now - e[3]) / 3600)), e[4] or "")
  end
  -- (Daniel 26.10.: scanned right after installing Auctionator, nothing was shared) an empty list does not start the waiting time:
  -- the login check with no prices yet had blocked the share after the first scan for 6 hours
  if #parts == 1 then return false end
  DB().priceShared = now
  return ns.SetOwn("price", table.concat(parts, ";"))
end

function ns.SharePrices(force, every)
  local st = NewShare(force, every)
  if not st then return false end
  ShareSlice(st, true)
  return FinishShare(st)
end

-- in steps, one a frame; a second call while one runs is left out (one left behind by an error: after 10 s)
local sharing
function ns.SharePricesSoon(force, every)
  local t = GetTime()
  if sharing and sharing.at and t - sharing.at < 10 and t >= sharing.at then return end
  local st = NewShare(force, every)
  if not st then return end
  sharing = st
  local function Step()
    if sharing ~= st then return end
    st.at = GetTime()
    if not ShareSlice(st) then ns.After(0, Step) return end
    sharing = nil
    -- the set itself (sort, text, checksum) in a frame of its own
    ns.After(0, function() FinishShare(st) end)
  end
  Step()
end
function ns.PriceShareRunning() return sharing ~= nil end -- (tests)

ns.RegisterKind("price", {
  validate = function(d) return ns.DecodePrices(d) ~= nil end,
  onUpdate = function() ns.InvalidatePrices() end,
})

---------------------------------------------------------------------------
-- The guild's price of an item: newest report that is not an outlier
---------------------------------------------------------------------------
local cache

function ns.InvalidatePrices() cache = nil end

local function Build()
  cache = {}
  local me = ns.MyName()
  for _, set in ipairs(ns.SetsOf("price")) do
    if set.o ~= me then
      for _, e in ipairs(ns.DecodePrices(set.d) or {}) do
        local list = cache[e.item]
        if not list then list = {} cache[e.item] = list end
        list[#list + 1] = { p = e.p, t = set.t - e.age, who = set.o }
      end
    end
  end
  return cache
end

local function Median(list)
  local v = {}
  for _, r in ipairs(list) do v[#v + 1] = r.p end
  table.sort(v)
  local n = #v
  if n == 0 then return nil end
  if n % 2 == 1 then return v[(n + 1) / 2] end
  return (v[n / 2] + v[n / 2 + 1]) / 2
end

-- price, scan time, who ("me" or a name), outlier flag of the newest report
function ns.Price(item)
  if not item or item <= 0 then return nil end
  local reports = {}
  for _, r in ipairs((cache or Build())[item] or {}) do reports[#reports + 1] = r end
  local p, t = ns.LocalPrice(item)
  if p then reports[#reports + 1] = { p = p, t = t, who = "me" } end
  if #reports == 0 then return nil end
  table.sort(reports, function(a, b) return a.t > b.t end)
  local med = Median(reports)
  local flagged = false
  for _, r in ipairs(reports) do
    if #reports < 3 or (r.p <= med * FACTOR and r.p >= med / FACTOR) then return r.p, r.t, r.who, flagged end
    flagged = true
  end
  return reports[1].p, reports[1].t, reports[1].who, true
end

-- what the reagents of a recipe cost for "count" crafts; nil when a price is missing. With "stock", what the player
-- has in bags and bank is not bought (Bestand anrechnen).
function ns.ReagentCost(spell, count, stock)
  local info = ns.RecipeInfo(spell)
  if not info.reagents or #info.reagents == 0 then return nil end
  local sum, oldest = 0, nil
  for _, r in ipairs(info.reagents) do
    local need = r[2] * (count or 1)
    if stock then need = math.max(0, need - ns.ItemCount(r[1])) end
    if need > 0 then
      local p, t = ns.Price(r[1])
      if not p then return nil end
      sum = sum + p * need
      if t and (not oldest or t < oldest) then oldest = t end
    end
  end
  return math.floor(sum), oldest
end

---------------------------------------------------------------------------
-- Own short scan without an AH addon: one item after the other while the auction house is open
---------------------------------------------------------------------------
local scan = { queue = {}, current = nil, open = false, done = 0 }

local function Store(item, unit)
  if not unit or unit <= 0 then return end
  local old = DB().prices[item]
  DB().prices[item] = { p = math.floor(unit), t = time() }
  if not old or old.p ~= math.floor(unit) then ns.InvalidatePrices() end
end

local function NextQuery()
  if not scan.open then return end
  local item = table.remove(scan.queue, 1)
  if not item then
    scan.current = nil
    if scan.done > 0 then
      ns.Print(L["Price scan done: %d items."]:format(scan.done))
      ns.SharePrices(true)
      if ns.OnDataChanged then ns.OnDataChanged("price", ns.MyName()) end
    end
    return
  end
  scan.current, scan.started = item, GetTime()
  if C_AuctionHouse and C_AuctionHouse.SendSearchQuery and C_AuctionHouse.MakeItemKey then
    local key = ns.Call(C_AuctionHouse.MakeItemKey, item)
    if key then ns.Call(C_AuctionHouse.SendSearchQuery, key, {}, false) end
  elseif QueryAuctionItems then
    local name = ns.ItemName(item)
    if not name or (CanSendAuctionQuery and not ns.Call(CanSendAuctionQuery)) then
      table.insert(scan.queue, name and 1 or #scan.queue + 1, item)
      if not name then scan.skip = (scan.skip or 0) + 1 end
      if (scan.skip or 0) > 50 then scan.queue = {} end
      ns.After(0.5, NextQuery)
      return
    end
    ns.Call(QueryAuctionItems, name, nil, nil, 0, nil, nil, false, true)
  else
    scan.queue = {}
    return
  end
  -- nothing came back in time: the item has no auctions now
  local mine = item
  ns.After(4, function() if scan.current == mine and GetTime() - scan.started >= 3.9 then scan.current = nil NextQuery() end end)
end

-- Era: the list of the query
local function ReadEraList()
  local item = scan.current
  if not item then return end
  local n = ns.Num(ns.Call(GetNumAuctionItems, "list")) or 0
  local best
  for i = 1, math.min(n, 50) do
    local ok, _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, id = pcall(GetAuctionItemInfo, "list", i)
    if not ok then count = nil end
    count, buyout, id = ns.Num(count), ns.Num(buyout), ns.Num(id)
    if id == item and count and count > 0 and buyout and buyout > 0 then
      local unit = buyout / count
      if not best or unit < best then best = unit end
    end
  end
  Store(item, best)
  scan.done = scan.done + 1
  scan.current = nil
  ns.After(0.3, NextQuery)
end

-- Forever: commodities (reagents) and items
local function ReadRetail(item)
  if not item or item ~= scan.current then return end
  local best
  local first = ns.Call(C_AuctionHouse.GetCommoditySearchResultInfo, item, 1)
  if type(first) == "table" and ns.Num(first.unitPrice) then best = first.unitPrice end
  if not best and C_AuctionHouse.MakeItemKey then
    local key = ns.Call(C_AuctionHouse.MakeItemKey, item)
    local r = key and ns.Call(C_AuctionHouse.GetItemSearchResultInfo, key, 1)
    if type(r) == "table" and ns.Num(r.buyoutAmount) then best = r.buyoutAmount end
  end
  Store(item, best)
  scan.done = scan.done + 1
  scan.current = nil
  ns.After(0.3, NextQuery)
end

-- start a scan of these items (only while the auction house is open)
function ns.ScanPrices(items)
  if not scan.open then ns.Print(L["Open the auction house first."]) return false end
  scan.queue, scan.done, scan.skip = {}, 0, 0
  local seen = {}
  for _, id in ipairs(items or {}) do if not seen[id] then seen[id] = true scan.queue[#scan.queue + 1] = id end end
  ns.Print(L["Scanning %d items, one after the other."]:format(#scan.queue))
  NextQuery()
  return true
end

function ns.ScanState() return scan end -- (tests)
function ns.AuctionHouseOpen() return scan.open end

ns.On("AUCTION_HOUSE_SHOW", function() scan.open = true ns.InvalidatePrices() end)
ns.On("AUCTION_HOUSE_CLOSED", function()
  scan.open, scan.queue, scan.current = false, {}, nil
  ns.InvalidatePrices()
  -- after an AH addon's scan: share the new prices (at most every half hour; an unchanged list is not sent again anyway)
  ns.After(2, function() ns.SharePricesSoon(false, 1800) end)
end)
ns.On("AUCTION_ITEM_LIST_UPDATE", function() ns.After(0.2, ReadEraList) end)
ns.On("COMMODITY_SEARCH_RESULTS_UPDATED", function(_, item) ReadRetail(ns.Num(item)) end)
ns.On("ITEM_SEARCH_RESULTS_UPDATED", function(_, key) ReadRetail(type(key) == "table" and ns.Num(key.itemID) or scan.current) end)
ns.On("PLAYER_LOGIN", function() ns.After(20, function() DB() ns.SharePricesSoon() end) end)
ns.OnInit(function() DB() end)
