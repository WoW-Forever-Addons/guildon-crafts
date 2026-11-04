local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- Trade and mail for wishes (GUILDON_PLAN.md step 4). A bar beside the game's trade window or mailbox (top right, 04.11.2026) shows the
-- orders with the other player and puts in what belongs to them: the wisher's reagents ("mats there"), the
-- crafter's goods. One stack per click (the game wants a click of the player for every item it moves; GUILDON_PLAN.md
-- "Grenzen"), never in combat. Accepting a trade and sending a letter stay with the player.
-- Mail: name, subject and the goods are filled in; cash on delivery for "I pay for the reagents" when Guildon knows
-- prices (Durchgang 5 Nr. 5, can be switched off). A completed trade or sent letter with the goods marks the job sent.
-- No hooks into the game's frames: our own frame, placed next to theirs.
---------------------------------------------------------------------------
local TRADE_SLOTS, MAIL_SLOTS = 6, 12

---------------------------------------------------------------------------
-- Bags
---------------------------------------------------------------------------
local function SlotInfo(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local info = ns.Call(C_Container.GetContainerItemInfo, bag, slot)
    if type(info) == "table" then return ns.Num(info.itemID), ns.Num(info.stackCount) or 1, info.isLocked end
    return nil
  end
  if GetContainerItemInfo then
    local ok, _, count, locked, _, _, _, link, _, _, id = pcall(GetContainerItemInfo, bag, slot)
    if not ok then return nil end
    id = ns.Num(id) or (type(link) == "string" and tonumber(link:match("item:(%d+)")))
    if id then return id, ns.Num(count) or 1, locked end
  end
end

local function NumSlots(bag)
  local fn = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
  return ns.Num(ns.Call(fn, bag)) or 0
end

-- the best stack of an item for "need" pieces: an exact stack, else the smallest bigger one, else the biggest
function ns.FindStack(item, need)
  local best
  for bag = 0, 4 do
    for slot = 1, NumSlots(bag) do
      local id, count, locked = SlotInfo(bag, slot)
      if id == item and not locked then
        local s = { bag = bag, slot = slot, count = count }
        if count == need then return s end
        if not best then best = s
        elseif count > need and (best.count < need or count < best.count) then best = s
        elseif best.count < need and count > best.count then best = s end
      end
    end
  end
  return best
end

-- take n pieces of a stack to the cursor (split when the stack is bigger)
local function Pick(stack, n)
  local C_ = C_Container
  if n < stack.count then
    local fn = (C_ and C_.SplitContainerItem) or SplitContainerItem
    return ns.Call(fn, stack.bag, stack.slot, n) ~= false
  end
  local fn = (C_ and C_.PickupContainerItem) or PickupContainerItem
  return ns.Call(fn, stack.bag, stack.slot) ~= false
end

local function CursorHasItem()
  local fn = CursorHasItem
  if type(fn) == "function" then return ns.Call(fn) and true or false end
  return false
end

---------------------------------------------------------------------------
-- Orders with a partner
---------------------------------------------------------------------------
-- what goes from me to the partner: { wish, kind = "mats" | "goods" | "enchant", items = { { item, n }, ... } }
function ns.OrdersWith(partner)
  local out = {}
  if not partner then return out end
  local me = ns.MyName()
  for _, e in ipairs(ns.Wishes()) do
    local info = ns.WishInfo(e)
    local enchant = not (info.item and info.item > 0)
    if e.owner == me and e.crafter == partner and e.state == "a" then
      local items = {}
      if e.pay == "m" then
        for _, rg in ipairs(info.reagents or {}) do items[#items + 1] = { rg[1], rg[2] * e.count } end
      end
      if #items > 0 then out[#out + 1] = { wish = e, kind = "mats", items = items, enchant = enchant }
      elseif enchant then out[#out + 1] = { wish = e, kind = "enchant", items = {} } end
    elseif e.crafter == me and e.owner == partner and (e.state == "a" or e.state == "m") then
      if enchant then out[#out + 1] = { wish = e, kind = "enchant", items = {} }
      else out[#out + 1] = { wish = e, kind = "goods", items = { { info.item, (info.count or 1) * e.count } } } end
    end
  end
  return out
end

-- how many of an item already sit in the trade / mail slots
local function TradeHas(item)
  local n = 0
  for i = 1, TRADE_SLOTS do
    local link = ns.Call(GetTradePlayerItemLink, i)
    if type(link) == "string" and tonumber(link:match("item:(%d+)")) == item then
      local _, _, qty = ns.Call(GetTradePlayerItemInfo, i)
      n = n + (ns.Num(qty) or 1)
    end
  end
  return n
end

local function TradeFree()
  for i = 1, TRADE_SLOTS do
    local name = ns.Call(GetTradePlayerItemInfo, i)
    if not ns.Str(name) then return i end
  end
end

local function MailHas(item)
  local n = 0
  for i = 1, MAIL_SLOTS do
    local _, id, _, count = ns.Call(GetSendMailItem, i)
    if ns.Num(id) == item then n = n + (ns.Num(count) or 1) end
  end
  return n
end

local function MailFree()
  for i = 1, MAIL_SLOTS do
    local name = ns.Call(GetSendMailItem, i)
    if not ns.Str(name) then return i end
  end
end

-- what is still missing of an order in the window: item, pieces (nil when everything is in)
local function Missing(order, has)
  for _, it in ipairs(order.items) do
    local left = it[2] - has(it[1])
    if left > 0 then return it[1], left end
  end
end
ns.OrderMissing = Missing

-- put the next stack of an order into the window. Returns "done", "put", "none" (not in the bags), "full", "combat"
local function PutNext(order, has, free, click)
  if InCombatLockdown and InCombatLockdown() then return "combat" end
  local item, left = Missing(order, has)
  if not item then return "done" end
  local slot = free()
  if not slot then return "full" end
  local stack = ns.FindStack(item, left)
  if not stack then return "none", item end
  if CursorHasItem() then ns.Call(ClearCursor) end
  if not Pick(stack, math.min(left, stack.count)) then return "none", item end
  ns.Call(click, slot)
  if CursorHasItem() then ns.Call(ClearCursor) end -- never leave an item at the cursor
  return "put", item
end

function ns.PutIntoTrade(order) return PutNext(order, TradeHas, TradeFree, ClickTradeButton) end
function ns.PutIntoMail(order) return PutNext(order, MailHas, MailFree, ClickSendMailItemButton) end

---------------------------------------------------------------------------
-- The bar
---------------------------------------------------------------------------
local bar, Watch
local state = { mode = nil, partner = nil, orders = {}, index = 1, gave = {} }

local function OrderTitle(o)
  local e = o.wish
  return ns.WishInfo(e).title .. (e.count > 1 and (" x" .. e.count) or "")
end

-- (04.11.2026, Era-Test) Daniel 04.11. "For ?": whom an order goes to comes from the order itself (the crafter sends the
-- wisher his goods, the wisher sends the crafter the reagents), not from the letter filled in later
local function Recipient(o)
  local e = o.wish
  if e.crafter == ns.MyName() then return e.owner end
  return e.crafter
end
ns.OrderRecipient = Recipient

-- (04.11.2026, Era-Test) what the wisher pays when he pays for the reagents (pay "p"): the reagents from the prices plus the
-- tip, with one line per reagent for the letter. nil without the agreement or without a price.
-- (04.11.2026, Era-Test, Daniel 04.11. "noch vor dem Release") a reagent the player bought himself at the auction house in the
-- last 14 days counts with what he paid per piece (ns.BoughtPrice, from the buyer's invoices in the inbox); the others with
-- the auction house prices Guildon knows (ns.Price, Prices.lua). cod.bought: "all", "some" or nil.
local function UnitPrice(item)
  local p = ns.BoughtPrice and ns.BoughtPrice(item)
  if p then return p, true end
  return ns.Price and ns.Price(item), false
end

function ns.OrderCOD(o)
  local e = o.wish
  if o.kind ~= "goods" or e.pay ~= "p" or (ns.db and ns.db.mailCOD == false) or not ns.ReagentCost then return nil end
  local cost, lines, nBought = nil, {}, 0
  if e.item then
    local p, bought = UnitPrice(e.item)
    if p then cost = p * e.count lines[1] = { e.item, e.count, p, bought } if bought then nBought = 1 end end
  else
    local all, sum = true, 0
    for _, r in ipairs(ns.RecipeInfo(e.spell).reagents or {}) do
      local p, bought = UnitPrice(r[1])
      if p then
        lines[#lines + 1] = { r[1], r[2] * e.count, p, bought }
        sum = sum + p * r[2] * e.count
        if bought then nBought = nBought + 1 end
      else
        all = false
      end
    end
    -- with a bought price the sum of the lines; otherwise as before the reagent cost from the auction house prices
    if nBought > 0 and all then cost = sum else cost = ns.ReagentCost(e.spell, e.count) nBought = 0
      for _, ln in ipairs(lines) do if ln[4] then ln[3], ln[4] = ns.Price and ns.Price(ln[1]), false end end
      for i = #lines, 1, -1 do if not lines[i][3] then table.remove(lines, i) end end
    end
  end
  cost = cost and math.floor(cost) or nil
  if not cost or cost <= 0 then return nil end
  local tip = math.floor(tonumber(e.tip) or 0)
  local bought = nBought > 0 and (nBought == #lines and "all" or "some") or nil
  return { reagents = cost, tip = tip, total = cost + tip, lines = lines, bought = bought }
end

-- money as plain text for a letter (no colour codes)
local function PlainMoney(c)
  return (ns.MoneyText(c):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- (04.11.2026, Era-Test) Daniel 04.11.: the reckoning in the letter, so that the wisher can follow the amount: one line per
-- reagent (pieces x price each = sum), the tip, the total. Letters take up to 500 characters: reagent lines that do not fit
-- give way to "...".
local BODY_MAX = 500
function ns.CODBody(o, cod)
  cod = cod or ns.OrderCOD(o)
  if not cod then return nil end
  local head = { L["Cash on delivery for your order %s:"]:format(OrderTitle(o)) }
  local tail = {}
  local label
  if cod.bought == "all" then label = o.wish.item and L["Price: %s (bought)"] or L["Reagents: %s (bought)"]
  elseif cod.bought == "some" then label = L["Reagents: %s (bought, rest auction house average)"]
  else label = o.wish.item and L["Price: %s (auction house average)"] or L["Reagents: %s (auction house average)"] end
  tail[#tail + 1] = label:format(PlainMoney(cod.reagents))
  if cod.tip > 0 then tail[#tail + 1] = L["Tip: %s"]:format(PlainMoney(cod.tip)) end
  tail[#tail + 1] = L["Total (cash on delivery): %s"]:format(PlainMoney(cod.total))
  local mid = {}
  for _, ln in ipairs(cod.lines) do
    mid[#mid + 1] = L["%d x %s at %s = %s"]:format(ln[2], ns.ItemName(ln[1]) or ("#" .. ln[1]), PlainMoney(ln[3]),
      PlainMoney(math.floor(ln[2] * ln[3]))) .. ((cod.bought == "some" and ln[4]) and (" " .. L["(bought)"]) or "")
  end
  local function Join(m) local t = {} for _, s in ipairs(head) do t[#t + 1] = s end for _, s in ipairs(m) do t[#t + 1] = s end
    for _, s in ipairs(tail) do t[#t + 1] = s end return table.concat(t, "\n") end
  local text = Join(mid)
  while #text > BODY_MAX and #mid > 0 do
    mid[#mid] = nil
    local cut = {}
    for i, s in ipairs(mid) do cut[i] = s end
    cut[#cut + 1] = "..."
    text = Join(cut)
  end
  return text:sub(1, BODY_MAX)
end

-- (04.11.2026, Era-Test) the mail bar is shared with Golddon: its button sits below our bar while the bar is there. After every
-- show, hide or move we tell Golddon (its global GolddonMailAnchor looks at GuildonCraftsMailBar and its .host); no hooks.
local function TellGolddon()
  local fn = _G.GolddonMailAnchor
  if type(fn) == "function" then pcall(fn) end
end

local function HideBar()
  if not bar then return end
  local was = bar:IsShown()
  bar:Hide()
  if was then TellGolddon() end
end

local BAR_W, PAD, GAP = 340, 10, 6

-- (02.11.2026, StyleKit 2 step 4) built from DonCore's Kit: the window's look (dark ground, gold edge, a title band), Kit buttons.
-- The note may take up to four lines (04.11.2026: the agreed cash on delivery as well).
-- (04.11.2026, Era-Test) named GuildonCraftsMailBar: Golddon looks for it and puts its button below it (TellGolddon).
local function BuildBar()
  local Kit = ns.Kit
  local S = Kit.SIZE
  bar = CreateFrame("Frame", "GuildonCraftsMailBar", UIParent)
  bar:SetSize(BAR_W, 76)
  bar:SetFrameStrata("DIALOG")
  bar:EnableMouse(true)
  Kit.Fill(bar, Kit.C.window)
  Kit.Border(bar, Kit.C.outer, 0)
  Kit.Border(bar, Kit.C.gold, 1)
  bar.band = CreateFrame("Frame", nil, bar)
  bar.band:SetPoint("TOPLEFT", bar, "TOPLEFT", 2, -2)
  bar.band:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -2, -2)
  bar.band:SetHeight(22)
  Kit.Fill(bar.band, Kit.C.panel)
  local line = Kit.Tex(bar.band, "ARTWORK", Kit.C.gold)
  line:SetPoint("BOTTOMLEFT") line:SetPoint("BOTTOMRIGHT") line:SetHeight(1)
  bar.title = Kit.Text(bar.band, "sub", Kit.C.txGold)
  bar.title:SetPoint("LEFT", bar.band, "LEFT", PAD, 0)
  bar.info = Kit.Text(bar, "sub", Kit.C.body)
  bar.info:SetPoint("TOPLEFT", bar, "TOPLEFT", PAD, -31)
  bar.info:SetWidth(BAR_W - 2 * PAD)
  bar.info:SetWordWrap(true)
  if bar.info.SetMaxLines then bar.info:SetMaxLines(4) end
  if bar.info.SetJustifyV then bar.info:SetJustifyV("TOP") end
  -- the buttons share the width evenly (Layout). (04.11.2026, Era-Test) Daniel 04.11. "beides mit einem Klick": at the
  -- mailbox one button fills in the letter and puts in the first stack; sending stays with the player.
  bar.put = Kit.Button(bar, "", { small = true, kind = "primary", onClick = function() ns.SafeCall("trade put", ns.BarAction) end })
  bar.next = Kit.Button(bar, L["next"], { small = true, onClick = function()
    state.index = state.index % math.max(1, #state.orders) + 1
    ns.PaintBar()
  end })
  bar.btnH = S.buttonSmall
  bar:Hide()
end

-- the visible buttons in one row, all the same width over the whole bar; the bar is as high as its text needs
local function Layout()
  local list = {}
  for _, b in ipairs({ bar.put, bar.next }) do if b:IsShown() then list[#list + 1] = b end end
  local n = #list
  if n > 0 then
    local w = math.floor((BAR_W - 2 * PAD - GAP * (n - 1)) / n)
    for i, b in ipairs(list) do
      b:Layout(w)
      b:ClearAllPoints()
      b:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", PAD + (i - 1) * (w + GAP), 8)
    end
  end
  ns.Kit.Fit(bar.title, BAR_W - 2 * PAD)
  local th = tonumber(bar.info:GetStringHeight()) or 12
  local lines = math.max(1, math.min(4, math.floor(th / 12 + 0.5)))
  bar.info:SetHeight(lines * 12)
  bar:SetHeight(31 + lines * 12 + 8 + (n > 0 and bar.btnH + 8 or 0))
end

-- (04.11.2026, Era-Test) Daniel 04.11. "oben rechts neben dem Brieffenster ... oben gleiche Hoehe, Kante": beside the mailbox
-- or the trade window at the top right, top edges level (it was below the window); Golddon's button goes below it.
local function Anchor()
  bar:ClearAllPoints()
  local host = state.mode == "trade" and _G.TradeFrame or _G.MailFrame
  if host and host.IsShown and host:IsShown() then
    bar:SetPoint("TOPLEFT", host, "TOPRIGHT", 6, 0)
    bar.host = host
  else
    bar:SetPoint("TOP", UIParent, "TOP", 0, -120)
    bar.host = nil
  end
end

-- (04.11.2026, Era-Test) the letter counts as filled in when Guildon filled it for this order and the "To" field still names
-- the recipient (Daniel 04.11.: "Everything is in, send the letter yourself ... das stimmt ja gar nicht" without a name)
local function LetterDone(o)
  if state.letter ~= o.wish.key then return false end
  local box = _G.SendMailNameEditBox
  if not box then return true end
  local name = ns.Str(ns.Call(box.GetText, box))
  local to = Recipient(o)
  return name ~= nil and to ~= nil and (name:lower() == ns.ShortName(to):lower() or name:lower() == to:lower())
end
ns.LetterDone = LetterDone

-- what the bar says about the agreed payment of an order
local function PayText(o)
  local e = o.wish
  if o.kind ~= "goods" or e.pay ~= "p" then return nil end
  local cod = ns.OrderCOD(o)
  if not cod then
    if ns.db and ns.db.mailCOD == false then return nil end
    return L["The wisher pays for the reagents (no auction house price known yet)."]
  end
  local M = ns.MoneyText
  if state.mode == "trade" then
    return L["Agreed: the wisher pays %s (reagents %s, tip %s)."]:format(M(cod.total), M(cod.reagents), M(cod.tip))
  end
  return L["Cash on delivery %s (reagents %s, tip %s)."]:format(M(cod.total), M(cod.reagents), M(cod.tip))
end

function ns.PaintBar()
  if not bar then return end
  local o = state.orders[state.index]
  if not o or not ns.BarWanted() then HideBar() return end
  Anchor()
  local e = o.wish
  local who = ns.ShortName(Recipient(o) or state.partner or "?")
  bar.title:SetText(ns.WORDMARK .. "  " .. L["Order: %s"]:format(OrderTitle(o)) ..
    (#state.orders > 1 and ("  (" .. state.index .. "/" .. #state.orders .. ")") or ""))
  local mail = state.mode == "mail"
  local has = mail and MailHas or TradeHas
  local item, left = Missing(o, has)
  -- a letter counts as the delivery only when all goods are attached
  if mail and o.kind == "goods" then state.complete = item == nil and o.wish.key or nil end
  local done = mail and LetterDone(o)
  local label, info
  local missing = item and L["For %s: %d x %s still missing."]:format(who, left, ns.ItemName(item) or ("#" .. item))
  if o.kind == "mats" or o.kind == "goods" then
    local put = o.kind == "mats" and L["Put in reagents"] or L["Put in goods"]
    if mail then
      if not done then
        label = item and (o.kind == "mats" and L["Fill in letter and put in reagents"] or L["Fill in letter and put in goods"])
          or L["Fill in letter"]
        info = missing or L["Everything is in. Fill in the letter, then send it yourself."]
      else
        label = item and put or nil
        info = missing or L["Everything is in. Send the letter yourself."]
      end
    else
      label = item and put or nil
      info = missing or (o.kind == "mats" and L["All reagents are in. Accept the trade yourself."] or L["Everything is in. Accept the trade yourself."])
      if o.kind == "mats" and o.enchant then info = info .. " " .. L["Put the item to enchant into the bottom slot."] end
    end
    local pay = PayText(o)
    if pay then info = info .. " " .. pay end
  else
    info = e.crafter == ns.MyName() and L["An enchantment: the other player puts the item into the bottom slot (will not be traded)."]
      or L["An enchantment: put your item into the bottom slot (will not be traded)."]
  end
  bar.info:SetText(info)
  bar.put:SetShown(label ~= nil)
  if label then bar.put:SetText(label) end
  bar.next:SetShown(#state.orders > 1)
  Layout()
  bar:Show()
  TellGolddon()
end

-- the attachments of the letter being written
local function MailItemCount()
  local n = 0
  for i = 1, MAIL_SLOTS do if ns.Str((ns.Call(GetSendMailItem, i))) then n = n + 1 end end
  return n
end

-- (04.11.2026, Era-Test) Daniel 04.11. "den richtigen Knopf gewaehlt": cash on delivery goes through the game's own fields,
-- the C.O.D. button and the amount (the game's send reads them and sets the amount itself; SetSendMailCOD alone was lost).
-- The game allows C.O.D. only with an attachment, so it is set once the first stack is in, once per letter.
function ns.ApplyCOD()
  if state.mode ~= "mail" or not state.cod or state.codDone then return false end
  if MailItemCount() == 0 then return false end
  local codBtn, moneyBtn = _G.SendMailCODButton, _G.SendMailSendMoneyButton
  if codBtn then
    if not (codBtn.GetChecked and codBtn:GetChecked()) and codBtn.Click then ns.Call(codBtn.Click, codBtn) end
    if codBtn.SetChecked then ns.Call(codBtn.SetChecked, codBtn, true) end
    if moneyBtn and moneyBtn.SetChecked then ns.Call(moneyBtn.SetChecked, moneyBtn, false) end
  end
  if _G.SendMailMoney and type(MoneyInputFrame_SetCopper) == "function" then ns.Call(MoneyInputFrame_SetCopper, _G.SendMailMoney, state.cod) end
  ns.Call(SetSendMailCOD, state.cod)
  state.codDone = true
  return true
end

-- all attachments taken out again: the game falls back to "Send money"; the amount we put in must not go out as money
function ns.CODGone()
  if state.mode ~= "mail" or not state.codDone or MailItemCount() > 0 then return end
  if _G.SendMailMoney and type(MoneyInputFrame_SetCopper) == "function" then ns.Call(MoneyInputFrame_SetCopper, _G.SendMailMoney, 0) end
  ns.Call(SetSendMailCOD, 0)
  state.codDone = false
end

function ns.BarPut()
  local o = state.orders[state.index]
  if not o then return end
  local r, item
  if state.mode == "trade" then r, item = ns.PutIntoTrade(o) else r, item = ns.PutIntoMail(o) end
  if r == "put" and o.kind == "goods" then state.gave[o.wish.key] = true end
  if r == "none" then ns.Print(L["Not in your bags: %s."]:format(ns.ItemName(item) or ("#" .. tostring(item))))
  elseif r == "full" then ns.Print(state.mode == "trade" and L["The trade window is full: trade this part first."] or L["The letter is full: send this part first."])
  elseif r == "combat" then ns.Print(L["Not in combat."]) end
  ns.After(0.2, function() ns.ApplyCOD() ns.PaintBar() end)
  return r
end

-- the bar's button: at the mailbox first the letter (when not yet filled in), then in the same click the next stack
function ns.BarAction()
  local o = state.orders[state.index]
  if not o then return end
  if state.mode == "mail" and not LetterDone(o) then
    ns.FillLetter()
    if not Missing(o, MailHas) then return "filled" end
  end
  return ns.BarPut()
end

local function Open(mode, partner)
  if not ns.Wishes then return end
  ns.InvalidateWishes()
  state.mode, state.partner, state.index, state.gave = mode, partner, 1, {}
  state.orders = ns.OrdersWith(partner)
  if not bar then BuildBar() end
  if #state.orders == 0 then HideBar() return end
  Watch(true)
  ns.PaintBar()
end

function ns.TradeBarState() return bar, state end -- (tests)

local function Close()
  HideBar()
  state.mode, state.partner, state.orders = nil, nil, {}
  Watch(false)
end

-- Where the bar belongs (Daniel 26.10.): at the trade window; at the mailbox only on the Send tab, not in the inbox.
-- A frame the client does not have counts as open, so that nothing depends on Blizzard's names.
local function IsOpen(f) if not f or not f.IsShown then return true end return f:IsShown() and true or false end

function ns.HostOpen()
  return IsOpen(state.mode == "trade" and _G.TradeFrame or _G.MailFrame)
end

function ns.BarWanted()
  if state.mode == "mail" then return ns.HostOpen() and IsOpen(_G.SendMailFrame) end
  return state.mode ~= nil and ns.HostOpen()
end

-- Our own frame looks five times a second while the window is open (no hooks on Blizzard's frames): the bar comes with the
-- Send tab and goes with the window however it was closed (Cancel, Esc, walking away), also when no event says so.
local watch
local gone = 0
function Watch(on)
  if not watch then watch = CreateFrame("Frame") end
  if not on then watch:SetScript("OnUpdate", nil) return end
  local acc = 0
  gone = 0
  watch:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 0.2 then return end
    acc = 0
    if not state.mode then return end
    if not ns.HostOpen() then
      gone = gone + 1
      if gone >= 2 then Close() end -- two looks in a row: the window may only be opening
      return
    end
    gone = 0
    if not bar then return end
    local want = ns.BarWanted() and #state.orders > 0
    if want and not bar:IsShown() then ns.PaintBar()
    elseif not want and bar:IsShown() then HideBar() end
  end)
end

-- trade: the partner is the "NPC" unit while the trade window is open
ns.On("TRADE_SHOW", function()
  local name, realm = ns.Call(UnitName, "NPC")
  name = ns.Str(name)
  if not name then return end
  local full = ns.FullName(realm and ns.Str(realm) and (name .. "-" .. realm) or name)
  Open("trade", full)
end)
ns.On("TRADE_PLAYER_ITEM_CHANGED", function() if state.mode == "trade" then ns.After(0.1, ns.PaintBar) end end)
ns.On("TRADE_CLOSED", function() if state.mode == "trade" then Close() end end)
---------------------------------------------------------------------------
-- The wisher's side (Daniel 26.10.: "Verschickte Wünsche nach dem Öffnen als erledigt, gleiches bei direktem Handel",
-- with 200 members the list would fill up): a wish counts as received when its goods come in a trade from the crafter,
-- or when the wisher opens a letter from the crafter with the goods (or with Guildon's subject after a sent order).
---------------------------------------------------------------------------
local function ItemIdOf(link)
  link = ns.Str(link)
  return link and tonumber(link:match("item:(%d+)")) or nil
end

-- my open wishes the partner works on; sentOnly: only those the crafter marked sent
local function MyWishesFrom(partner, sentOnly)
  local out, me = {}, ns.MyName()
  if not partner or not ns.Wishes then return out end
  local short = ns.ShortName(partner)
  for _, e in ipairs(ns.Wishes()) do
    if e.owner == me and e.crafter and (e.crafter == partner or ns.ShortName(e.crafter) == short)
      and (e.state == "s" or (not sentOnly and (e.state == "a" or e.state == "m"))) then
      out[#out + 1] = e
    end
  end
  return out
end

local function Received(e, how)
  if not ns.SetWishState(e.id, "d") then return false end
  if ns.CountThanks then ns.CountThanks(e.crafter) end
  local info = ns.WishInfo and ns.WishInfo(e) or {}
  ns.Print(L["Wish done (%s): %s from %s."]:format(how, info.title or "?", ns.ShortName(e.crafter)))
  return true
end

-- trade: what the partner hands over, noted while the window is open (the slots are empty once it closes)
local tradeGot, tradePartner = {}, nil
local function NoteTrade()
  tradeGot = {}
  local partner = tradePartner
  if not partner then return end
  local offered = {}
  for i = 1, 6 do
    local id = ItemIdOf(ns.Call(GetTradeTargetItemLink, i))
    if id then offered[id] = true end
  end
  -- an enchant: my item lies in the slot that is not traded
  local myItem = ItemIdOf(ns.Call(GetTradePlayerItemLink, 7))
  for _, e in ipairs(MyWishesFrom(partner)) do
    local info = ns.WishInfo(e)
    if info.item and info.item > 0 then
      if offered[info.item] then tradeGot[e.key] = e end
    elseif myItem then
      tradeGot[e.key] = e
    end
  end
end
ns.On("TRADE_SHOW", function()
  local name, realm = ns.Call(UnitName, "NPC")
  name = ns.Str(name)
  tradePartner = name and ns.FullName(realm and ns.Str(realm) and (name .. "-" .. realm) or name) or nil
  tradeGot = {}
end)
ns.On("TRADE_TARGET_ITEM_CHANGED", NoteTrade)
ns.On("TRADE_PLAYER_ITEM_CHANGED", NoteTrade)
ns.On("TRADE_ACCEPT_UPDATE", NoteTrade)

-- a finished trade: the goods I gave mark my jobs sent, the goods I got mark my wishes received
ns.On("UI_INFO_MESSAGE", function(_, _, msg)
  if msg ~= ERR_TRADE_COMPLETE and msg ~= "ERR_TRADE_COMPLETE" then return end
  if state.mode == "trade" and next(state.gave) then
    for key in pairs(state.gave) do
      local e = ns.Wish(key)
      if e and e.crafter == ns.MyName() then ns.SetJob(e.owner, e.id, "s") end
    end
    state.gave = {}
  end
  for _, e in pairs(tradeGot) do Received(e, L["by trade"]) end
  tradeGot = {}
end)

-- mail: a letter from the crafter that I have opened
function ns.CheckInbox()
  local n = ns.Num(ns.Call(GetInboxNumItems)) or 0
  if n == 0 or type(GetInboxHeaderInfo) ~= "function" then return 0 end
  local done = 0
  local maxAtt = ATTACHMENTS_MAX_RECEIVE or 16
  for i = 1, n do
    -- direct pcall: ns.Call hands back only four values, wasRead is the ninth
    local ok, _, _, sender, subject, _, _, _, hasItem, wasRead = pcall(GetInboxHeaderInfo, i)
    if not ok then sender = nil end
    sender = ns.Str(sender)
    if sender and wasRead then
      local items = {}
      if hasItem then
        for j = 1, maxAtt do
          local id = ItemIdOf(ns.Call(GetInboxItemLink, i, j))
          if id then items[id] = true end
        end
      end
      -- (31.10.2026) letters from the Guildon 0.8 days start with "Guildon: "
      local guildon = ns.Str(subject) and (ns.Str(subject):find("^Guildon Crafts: ") or ns.Str(subject):find("^Guildon: ")) and true
      for _, e in ipairs(MyWishesFrom(sender)) do
        local info = ns.WishInfo(e)
        local hit = (info.item and items[info.item]) or (guildon and e.state == "s")
        if hit and Received(e, L["by mail"]) then done = done + 1 end
      end
    end
  end
  return done
end
ns.On("MAIL_INBOX_UPDATE", function()
  if ns.Wishes then ns.CheckInbox() end
  ns.SafeCall("buys", ns.NoteBuys)
end)

---------------------------------------------------------------------------
-- (04.11.2026, Era-Test) Own auction house buys (Daniel 04.11. "noch vor dem Release"): the auction house sends the buyer a
-- letter with an invoice (GetInboxInvoiceInfo type "buyer": item name, what was paid). While the inbox is open Guildon notes
-- what was paid per piece; the cash on delivery of an order then takes these prices of the last 14 days before the
-- auction house prices. Every call goes through pcall (Era and Forever give the values in slightly different places); a
-- letter whose pieces cannot be read is left out. ns.db.buys = { { i = item ID or nil, nm = name, p = paid, n = pieces, t } }
---------------------------------------------------------------------------
local BUY_DAYS, BUY_MAX, AH_MAIL_DAYS = 14, 300, 30

local function TidyBuys()
  local cut, out = time() - BUY_DAYS * 86400, {}
  for _, b in ipairs(type(ns.db.buys) == "table" and ns.db.buys or {}) do
    if type(b) == "table" and (tonumber(b.t) or 0) >= cut and ns.Num(b.p) and ns.Num(b.n) and b.n > 0 then out[#out + 1] = b end
  end
  while #out > BUY_MAX do table.remove(out, 1) end
  ns.db.buys = out
  return out
end

-- item and pieces of the letter's first attachment: the item ID from the link; GetInboxItem gives name, itemID, texture,
-- count, ... on newer clients and name, texture, count, ... on older ones
local function Attachment(i)
  local id = ItemIdOf(ns.Call(GetInboxItemLink, i, 1))
  if type(GetInboxItem) ~= "function" then return id, nil end
  local ok, _, a, b, c = pcall(GetInboxItem, i, 1)
  if not ok then return id, nil end
  if id and a == id then return id, ns.Num(c) end
  if type(a) == "number" and type(b) == "number" and not id then return nil, nil end -- cannot tell which is the count
  return id, ns.Num(b)
end

function ns.NoteBuys()
  if not ns.db or type(GetInboxInvoiceInfo) ~= "function" then return 0 end
  local n = ns.Num(ns.Call(GetInboxNumItems)) or 0
  local list = TidyBuys()
  local now, added = time(), 0
  for i = 1, n do
    -- direct pcall: the count is the tenth value (newer clients); older ones have none, then the attachment says it
    local ok, kind, itemName, _, bid, _, _, _, _, _, count = pcall(GetInboxInvoiceInfo, i)
    itemName = ok and ns.Str(itemName) or nil
    bid = ok and ns.Num(bid) or nil
    if ok and kind == "buyer" and itemName and bid and bid > 0 then
      local id, pieces = Attachment(i)
      pieces = ns.Num(count) or pieces
      if pieces and pieces > 0 then
        local okH, _, _, _, _, _, _, daysLeft = pcall(GetInboxHeaderInfo, i)
        daysLeft = okH and tonumber(daysLeft) or nil
        local t = daysLeft and math.floor(now - math.max(0, AH_MAIL_DAYS - daysLeft) * 86400) or now
        -- the same letter on the next look: same name, amount and pieces within a day
        local dup
        for _, b in ipairs(list) do
          if b.nm == itemName and b.p == bid and b.n == pieces and math.abs((b.t or 0) - t) < 86400 then
            dup = b
            if id and not b.i then b.i = id end
          end
        end
        if not dup and t >= now - BUY_DAYS * 86400 then
          list[#list + 1] = { i = id, nm = itemName, p = bid, n = pieces, t = t }
          added = added + 1
        end
      end
    end
  end
  if added > 0 then TidyBuys() end
  return added
end

-- what the player paid per piece for an item at the auction house in the last 14 days (all buys together), nil without a buy
function ns.BoughtPrice(item)
  if not item or not ns.db or type(ns.db.buys) ~= "table" then return nil end
  local name = ns.ItemName and ns.ItemName(item)
  local cut, paid, pieces = time() - BUY_DAYS * 86400, 0, 0
  for _, b in ipairs(ns.db.buys) do
    if type(b) == "table" and (tonumber(b.t) or 0) >= cut and (b.i == item or (not b.i and name and b.nm == name))
      and ns.Num(b.p) and ns.Num(b.n) and b.n > 0 then
      paid, pieces = paid + b.p, pieces + b.n
    end
  end
  if pieces > 0 then return math.floor(paid / pieces + 0.5) end
end

---------------------------------------------------------------------------
-- Mail: orders with the player whose name is in the "To" field, or all my crafted orders
---------------------------------------------------------------------------
local function MailOrders()
  local out, me = {}, ns.MyName()
  ns.InvalidateWishes()
  for _, e in ipairs(ns.Wishes()) do
    if e.crafter == me and (e.state == "m" or e.state == "a") then
      local partner = e.owner
      for _, o in ipairs(ns.OrdersWith(partner)) do if o.wish.key == e.key then out[#out + 1] = o end end
    end
  end
  return out
end

function ns.FillLetter()
  local o = state.orders[state.index]
  if not o then return false end
  local e = o.wish
  local to = Recipient(o)
  local name = ns.Str(SendMailNameEditBox and ns.Call(SendMailNameEditBox.GetText, SendMailNameEditBox))
  if SendMailNameEditBox then ns.Call(SendMailNameEditBox.SetText, SendMailNameEditBox, ns.ShortName(to)) end
  if SendMailSubjectEditBox then
    ns.Call(SendMailSubjectEditBox.SetText, SendMailSubjectEditBox, ("Guildon Crafts: %s"):format(OrderTitle(o)):sub(1, 64))
  end
  -- cash on delivery: the wisher pays for the reagents (estimate from the prices) plus the tip.
  -- (04.11.2026, Era-Test) with the reckoning in the letter's text; the C.O.D. button and amount follow with the first stack
  state.cod, state.codDone = nil, false
  local cod = ns.OrderCOD(o)
  if cod then
    state.cod = cod.total
    local body = ns.CODBody(o, cod)
    if body and SendMailBodyEditBox then ns.Call(SendMailBodyEditBox.SetText, SendMailBodyEditBox, body) end
  end
  state.partner = to
  state.letter = e.key
  ns.ApplyCOD()
  ns.PaintBar()
  return name ~= ns.ShortName(to)
end

-- (04.11.2026, Era-Test) Daniel 04.11.: with an accepted order the mailbox opens on Send Mail, not on the inbox (the game opens
-- the inbox itself on MAIL_SHOW, so a moment later). Without an order the inbox stays.
local function SendTab()
  if state.mode ~= "mail" or #state.orders == 0 then return end
  local send = _G.SendMailFrame
  if send and send.IsShown and send:IsShown() then return end
  local tab = _G.MailFrameTab2
  if tab and tab.Click then ns.Call(tab.Click, tab) end
end
ns.MailSendTab = SendTab

ns.On("MAIL_SHOW", function()
  if not ns.Wishes then return end
  state.mode, state.index, state.gave = "mail", 1, {}
  state.letter, state.cod, state.codDone = nil, nil, false
  state.orders = MailOrders()
  -- the wisher's reagents by mail when the crafter is not around
  for _, e in ipairs(ns.Wishes()) do
    if e.owner == ns.MyName() and e.crafter and e.state == "a" and e.pay == "m" then
      for _, o in ipairs(ns.OrdersWith(e.crafter)) do if o.wish.key == e.key then state.orders[#state.orders + 1] = o end end
    end
  end
  if not bar then BuildBar() end
  if #state.orders == 0 then HideBar() return end
  Watch(true) -- the bar itself waits for the Send tab (PaintBar)
  ns.After(0.1, SendTab)
  ns.PaintBar()
end)
ns.On("MAIL_CLOSED", function() if state.mode == "mail" then Close() end end)
ns.On("MAIL_SEND_INFO_UPDATE", function()
  if state.mode ~= "mail" then return end
  ns.After(0.1, function() ns.CODGone() ns.ApplyCOD() ns.PaintBar() end)
end)
ns.On("MAIL_SEND_SUCCESS", function()
  if state.mode ~= "mail" or not state.letter then return end
  local e = ns.Wish(state.letter)
  if e and e.crafter == ns.MyName() and state.complete == state.letter then ns.SetJob(e.owner, e.id, "s") end
  state.complete = nil
  state.letter = nil
  state.cod, state.codDone = nil, false
  ns.After(0.5, function() if state.mode == "mail" then state.orders = MailOrders() state.index = 1 ns.PaintBar() end end)
end)
