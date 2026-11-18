local _, ns = ...
local L = ns.L
local Kit = ns.Kit
-- (16.11.2026, Blizzard look) the page takes its blocks from the window's kit (ns.PageKit), the wish form from its own
-- pick when it is built (ns.LookKit, FUI)
local UI, FUI = Kit, Kit

---------------------------------------------------------------------------
-- Tab "Wish list" and the wish form (GUILDON_PLAN.md step 3; Don style 02.11.2026, mockup docs/layout_2026-11-02/guildon/
-- part 5). Data and rules in Wishes.lua.
-- On top the filter chips (for me, my wishes, I can craft, all), the state, the count and "New wish"; the wishes grouped
-- (fold by click), two lines each with the state as a pill; right the chosen wish in a card with what the player may do
-- (accept, crafted, sent, give back, received, cancel, delete, whisper, shopping list). Under 960 px the card goes over
-- the list. The form is DonCore's Kit.Dialog with a segmented choice for the payment.
---------------------------------------------------------------------------
local S = Kit.SIZE
local DETAIL_W = 320

ns.WISH_FILTERS = { "me", "mine", "craft", "all" }
local FILTER_TEXT = { me = "For me", mine = "My wishes", craft = "I can craft", all = "All wishes" }
-- the colour of a state (Kit.STATUS): open blue, accepted yellow, crafted and sent green, done grey, deleted red
local STATE_KIND = { o = "blue", a = "yellow", m = "green", s = "green", d = "grey", c = "grey", x = "red", e = "grey" }
ns.WISH_STATES = { "all", "o", "a", "m", "s", "d" }

local function ClassFile(owner)
  local m = ns.Member(owner)
  return m and m.classFile ~= "" and m.classFile or ((ns.InfoOf(owner) or {}).classFile or "")
end
local function Colored(owner) return "|c" .. ns.ClassHex(ClassFile(owner)) .. ns.ShortName(owner) .. "|r" end
local function ClassWho(owner)
  local file = ClassFile(owner)
  local name = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[file]) or ""
  return "|c" .. ns.ClassHex(file) .. (name ~= "" and (name .. " ") or "") .. ns.ShortName(owner) .. "|r"
end
local function RecipeTitle(spell) return ns.SpellName(spell) or L["Recipe %d"]:format(spell) end

---------------------------------------------------------------------------
-- Wish form (Kit.Dialog, mockup part 5): what is wished and who can craft it, amount, payment, tip, note, for whom
---------------------------------------------------------------------------
local form
local FORM_W = 440
local LABEL_W = 120
local ROW = S.button + S.gap
-- (18.11.2026, Daniel's picture: the three payment buttons were far too narrow, the texts ran over each other) the payment
-- is a choice of three lines under each other, a round button and the whole text each; a click on the line picks it
local PAY_ROW = 22
local PAY_H = 3 * PAY_ROW

local function PayChoice(parent, items, get, set)
  local c = CreateFrame("Frame", nil, parent)
  c.fields = {}
  function c:Paint()
    for _, f in ipairs(self.fields) do
      local on = f.value == self.value
      f.radio:SetChecked(on)
      local col = on and Kit.C.title or Kit.C.muted
      f.text:SetTextColor(col[1], col[2], col[3])
    end
  end
  function c:Update(v)
    if v == nil then v = get() end
    self.value = v
    self:Paint()
  end
  for i, it in ipairs(items) do
    local f = CreateFrame("Button", nil, c)
    f.value = it.value
    f.radio = FUI.Radio(f, {})
    if f.radio.EnableMouse then f.radio:EnableMouse(false) end
    f.radio:ClearAllPoints()
    f.radio:SetPoint("LEFT", f, "LEFT", 0, 0)
    f.text = FUI.Text(f, "row", Kit.C.body)
    f.text:SetText(it.text)
    f.text:ClearAllPoints()
    f.text:SetPoint("LEFT", f, "LEFT", 22, 0)
    f:SetScript("OnClick", function()
      c.value = it.value
      c:Paint()
      set(it.value)
    end)
    c.fields[i] = f
  end
  function c:Layout(w)
    self:SetSize(w, PAY_H)
    for i, f in ipairs(self.fields) do
      f:ClearAllPoints()
      f:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -(i - 1) * PAY_ROW)
      f:SetSize(w, PAY_ROW)
      FUI.Fit(f.text, math.max(20, w - 22))
    end
  end
  return c
end
-- the body's height: info, amount, payment, tip, note, for whom, and a line for an error only while there is one
local function FormHeight(err) return 44 + 4 * ROW + PAY_H + S.gap + (err and 18 or 0) end

local function ReagentText(info)
  local parts = {}
  for i, rg in ipairs(info.reagents or {}) do
    if i > 4 then parts[#parts + 1] = "..." break end
    parts[#parts + 1] = rg[2] .. " " .. (ns.ItemName(rg[1]) or L["Item %d"]:format(rg[1]))
  end
  return #parts > 0 and L["Reagents: %s"]:format(table.concat(parts, ", ")) or ""
end

local function Send()
  local count = form.count:GetValue() or 1
  local tip = (form.tip:GetValue() or 0) * 10000
  local w, why = ns.AddWish(form.spell, count, form.payKey, tip, form.note:GetText(), form.targetKey ~= "" and form.targetKey or nil, form.item)
  if not w then
    form.err:SetText(why == "full" and L["You have too many open wishes."] or L["Please check the amount."])
    form:SetBodySize(FORM_W - 2 * S.pad, FormHeight(true))
    FUI.Fit(form.err, form:BodyWidth())
    return
  end
  form:Hide()
  ns.Print(L["Wish made: %s. Crafters in the guild see it in their wish list."]:format(ns.WishInfo(w).title))
  ns.OpenTab("wishes")
  if ns.SelectWish then ns.SelectWish((ns.MyName() or "") .. "#" .. w.id) end
  return w
end

local function LayoutForm(d, w)
  if not d.count then return end
  local fw = math.max(60, w - LABEL_W - S.gap)
  local fx = LABEL_W + S.gap
  d.info:ClearAllPoints()
  d.info:SetPoint("TOPLEFT", d.body, "TOPLEFT", 0, 0)
  d.info:SetSize(w, 34)
  d.sub:ClearAllPoints() d.sub:SetPoint("TOPLEFT", d.info, "TOPLEFT", 0, 0) FUI.Fit(d.sub, w)
  d.reag:ClearAllPoints() d.reag:SetPoint("TOPLEFT", d.info, "TOPLEFT", 0, -18) FUI.Fit(d.reag, w)
  local y = 44
  local function Row(label, field, width)
    label:ClearAllPoints()
    label:SetPoint("TOPLEFT", d.body, "TOPLEFT", 0, -y - 7)
    FUI.Fit(label, LABEL_W)
    field:ClearAllPoints()
    field:SetPoint("TOPLEFT", d.body, "TOPLEFT", fx, -y)
    field:Layout(width)
    y = y + ROW
  end
  Row(d.labels.count, d.count, 64)
  -- the payment: its label beside the first of the three lines
  d.labels.pay:ClearAllPoints()
  d.labels.pay:SetPoint("TOPLEFT", d.body, "TOPLEFT", 0, -y - 4)
  FUI.Fit(d.labels.pay, LABEL_W)
  d.pay:ClearAllPoints()
  d.pay:SetPoint("TOPLEFT", d.body, "TOPLEFT", fx, -y)
  d.pay:Layout(fw)
  y = y + PAY_H + S.gap
  local tipY = y
  Row(d.labels.tip, d.tip, 64)
  d.estimate:ClearAllPoints()
  d.estimate:SetPoint("TOPLEFT", d.body, "TOPLEFT", fx + 64 + S.gap, -tipY - 7)
  FUI.Fit(d.estimate, math.max(20, fw - 64 - S.gap))
  Row(d.labels.note, d.note, fw)
  Row(d.labels.target, d.target, fw)
  d.err:ClearAllPoints()
  d.err:SetPoint("TOPLEFT", d.body, "TOPLEFT", 0, -y - 2)
  FUI.Fit(d.err, w)
end

local function BuildFormIn()
  form = FUI.Dialog(FUI.blizzLook and "GuildonCraftsWishFormBlizz" or "GuildonCraftsWishForm", { width = FORM_W, height = 330, onLayout = function(d, w) LayoutForm(d, w) end })
  local b = form.body
  -- the hint and the reagents: one line each, the whole text in the tooltip
  form.info = CreateFrame("Frame", nil, b)
  form.sub = FUI.Text(form.info, "sub", Kit.C.muted)
  form.reag = FUI.Text(form.info, "sub", Kit.C.quiet)
  Kit.Stateful(form.info, function() end)
  form.info._cutTexts = { form.sub, form.reag }
  form.labels = {}
  for k, text in pairs({ count = L["Amount"], pay = L["Payment"], tip = L["Tip (gold)"], note = L["Note"], target = L["For"] }) do
    local fs = FUI.Text(b, "row", Kit.C.muted)
    fs:SetText(text)
    form.labels[k] = fs
  end
  form.count = FUI.EditBox(b, { numeric = true, min = 1, max = 9999, maxLetters = 3, placeholder = "1" })
  local items = {}
  for _, key in ipairs(ns.PAY) do items[#items + 1] = { value = key, text = L[ns.PAY_TEXT[key]], tip = L[ns.PAY_TEXT[key]] } end
  form.pay = PayChoice(b, items, function() return form.payKey end, function(v) form.payKey = v end)
  form.tip = FUI.EditBox(b, { numeric = true, min = 0, max = 9999, maxLetters = 4, placeholder = "0" })
  form.estimate = FUI.Text(b, "sub", Kit.C.quiet)
  form.note = FUI.EditBox(b, { maxLetters = 60, placeholder = L["optional"], clear = true })
  form.target = FUI.Dropdown(b, {
    items = function()
      local out = { { value = "", text = L["Everyone who can craft it"] } }
      for _, o in ipairs(form.spell and ns.CraftersOf(form.spell) or {}) do
        if o ~= ns.MyName() then out[#out + 1] = { value = o, text = ns.ShortName(o) .. (ns.IsOnline(o) and "" or ("  (" .. L["offline"] .. ")")) } end
      end
      return out
    end,
    get = function() return form.targetKey or "" end,
    set = function(v) form.targetKey = v end,
  })
  form.target:SetTooltip(L["Who should craft it"], { L["Click: choose"] })
  form.count:SetNext(form.tip) form.tip:SetNext(form.note) form.note:SetNext(form.count)
  form.err = FUI.Text(b, "sub", Kit.C.red)
  form:SetButtons({
    { text = L["Cancel"], onClick = function(d) d:Hide() end },
    { text = L["Make the wish"], kind = "primary", onClick = function() Send() end },
  })
  form.Send = Send
  form:SetBodySize(FORM_W - 2 * S.pad, FormHeight())
end

-- (16.11.2026) the form in the game's look (option blizzLook): a build that fails there is done again with the Kit
local function BuildForm()
  FUI = ns.LookKit and ns.LookKit() or Kit
  if FUI == Kit then BuildFormIn() return end
  local ok, err = pcall(BuildFormIn)
  if ok then return end
  if form and form.Hide then pcall(form.Hide, form) end
  form, FUI = nil, Kit
  if ns.LookFailed then ns.LookFailed("wish form", err) end
  BuildFormIn()
end
-- the option blizzLook changed: the form is built again in the other look the next time it opens
function ns.WishFormReset()
  if not form then return end
  form:Hide()
  form = nil
end

-- item names arrive later from the server ("Item 2835" until then): fill them in when the form is open
function ns.WishFormItemInfo()
  if not form or not form:IsShown() then return end
  if form.item then
    form:SetTitle(L["Wish: %s"]:format(ns.ItemName(form.item) or L["Item %d"]:format(form.item)), ns.ItemIcon(form.item))
  elseif form.spell then
    form.reag:SetText(ReagentText(ns.RecipeInfo(form.spell)))
    form:Layout()
  end
end

-- item: a wish for a gathered item (reagent) instead of a recipe
function ns.ShowWishForm(spell, item)
  if not spell and not item then return end
  if not form then BuildForm() end
  form.spell, form.item = not item and spell or nil, item
  if item then
    form:SetTitle(L["Wish: %s"]:format(ns.ItemName(item) or L["Item %d"]:format(item)), ns.ItemIcon(item))
    local prof = ns.GatherProf(item)
    form.sub:SetText(prof and L["Members with %s see it."]:format(ns.ProfName(prof)) or L["Gatherers in the guild see it."])
    form.count:SetMaxLetters(4)
    form.reag:SetText("")
  else
    local info = ns.RecipeInfo(spell)
    form:SetTitle(L["Wish: %s"]:format(RecipeTitle(spell)), ns.RecipeIcon and ns.RecipeIcon(spell, info) or ns.SpellIcon(spell))
    local n = #ns.CraftersOf(spell)
    local mine = 0
    for _, o in ipairs(ns.CraftersOf(spell)) do if o == ns.MyName() then mine = 1 end end
    form.sub:SetText(n - mine > 0 and L["%d in the guild can craft it."]:format(n - mine) or L["Nobody in the guild knows it yet; the wish waits for someone who learns it."])
    form.count:SetMaxLetters(3)
    form.reag:SetText(ReagentText(info))
  end
  form.count:SetValue("1")
  form.tip:SetValue("")
  form.note:SetValue("")
  form.payKey = "m"
  form.targetKey = ""
  form.pay:Update()
  form.target:Update()
  form.err:SetText("")
  form:SetBodySize(FORM_W - 2 * S.pad, FormHeight())
  local est = item and ns.Price and ns.Price(item) or (not item and ns.ReagentCost and ns.ReagentCost(spell, 1))
  form.estimate:SetText(est and (item and L["AH price about %s each"] or L["reagents about %s"]):format(ns.MoneyText(est)) or "")
  form:Show()
  form:Layout()
  return form
end

function ns.WishForm() return form end -- (tests)

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------
local page

local function State()
  local db = ns.db
  db.wishFilter = FILTER_TEXT[db.wishFilter or ""] and db.wishFilter or "me"
  if db.wishState and not ns.STATE_TEXT[db.wishState] then db.wishState = nil end
  return db
end

local function Entry(e)
  local info = ns.WishInfo(e)
  local r = ns.WishRole(e)
  local whoName = r.mine and e.crafter or e.owner
  local pill = { L[ns.STATE_TEXT[e.state] or "open"], STATE_KIND[e.state] or "blue" }
  if r.lost then pill = { L["taken"], "red" } end
  local active = e.state == "o" or e.state == "a" or e.state == "m" or e.state == "s"
  -- (02.11.2026, Daniel) the item's tooltip under the mouse, its quality colour on the name (not on the symbol's edge)
  local itemID, quality = ns.RecipeItemQuality(info)
  return { key = e.key, wish = e, icon = info.icon, title = info.title .. (e.count > 1 and (" x" .. e.count) or ""),
    sub = whoName and ClassWho(whoName) or nil, pill = pill, status = pill[2], itemID = itemID,
    titleColor = not active and Kit.C.muted or (quality and Kit.QualityColor(quality)) or nil, rightWidth = 90 }
end

function ns.WishEntries()
  local db = State()
  local mine, craft, other = {}, {}, {}
  for _, e in ipairs(ns.VisibleWishes(db.wishFilter)) do
    if not db.wishState or e.state == db.wishState then
      local r = ns.WishRole(e)
      if r.mine then mine[#mine + 1] = e elseif r.forMe or r.crafter or r.myJob then craft[#craft + 1] = e else other[#other + 1] = e end
    end
  end
  local ORDER = { o = 1, a = 2, m = 3, s = 4, d = 5, c = 6, e = 7, x = 8 }
  local function Sort(a, b)
    if ORDER[a.state] ~= ORDER[b.state] then return ORDER[a.state] < ORDER[b.state] end
    return a.created > b.created
  end
  local out = {}
  local closed = type(db.wishFold) == "table" and db.wishFold or {}
  -- sections fold with a click (a big guild has many wishes)
  local function Group(list, key, title)
    if #list == 0 then return end
    table.sort(list, Sort)
    out[#out + 1] = { kind = "group", key = "h:" .. key, fold = key, text = title, count = #list, collapsed = closed[key] and true or false }
    if not closed[key] then for _, e in ipairs(list) do out[#out + 1] = Entry(e) end end
  end
  Group(craft, "craft", L["For me to craft"])
  Group(mine, "mine", L["My wishes"])
  Group(other, "other", L["Other wishes"])
  return out, #mine + #craft + #other
end

-- what the player may do with a wish: label, kind of the button (primary, danger, secondary), action
local function Actions(e)
  local r = ns.WishRole(e)
  local me = ns.MyName()
  local out = {}
  local function Add(label, fn, kind) out[#out + 1] = { label = label, fn = fn, kind = kind } end
  if r.mine then
    if e.state == "a" or e.state == "m" or e.state == "s" then
      Add(L["Received"], function() ns.SetWishState(e.id, "d") if ns.CountThanks then ns.CountThanks(e.crafter) end end, "primary")
      Add(L["Whisper %s"]:format(ns.ShortName(e.crafter)), function() ns.WhisperAbout(e.crafter, e) end)
    end
    if e.spell and e.pay == "m" and (e.state == "o" or e.state == "a") and ns.ShoppingList then
      Add(L["Shopping list"], function() ns.ShoppingList(e.spell, e.count) end)
    end
    if e.state == "o" or e.state == "a" or e.state == "m" or e.state == "s" then
      Add(L["Cancel wish"], function() ns.SetWishState(e.id, "c") end)
    else
      Add(L["Remove"], function() ns.DeleteWish(me, e.id) end)
    end
    return out
  end
  if r.lost then
    Add(L["Give back"], function() ns.SetJob(e.owner, e.id, nil) end)
  elseif r.crafter then
    if e.state == "a" then Add(L["Crafted"], function() ns.SetJob(e.owner, e.id, "m") end, "primary") end
    if e.state == "m" then Add(L["Sent"], function() ns.SetJob(e.owner, e.id, "s") end, "primary") end
    if e.state ~= "s" then Add(L["Give back"], function() ns.SetJob(e.owner, e.id, nil) end) end
  elseif e.state == "o" and r.forMe then
    Add(L["Accept"], function() ns.SetJob(e.owner, e.id, "a") end, "primary")
  end
  if e.state ~= "d" and e.state ~= "c" and e.state ~= "x" then
    Add(L["Whisper %s"]:format(ns.ShortName(e.owner)), function() ns.WhisperAbout(e.owner, e) end)
  end
  if r.officer and e.state ~= "x" then Add(L["Delete"], function() ns.DeleteWish(e.owner, e.id) end, "danger") end
  return out
end
ns.WishActions = Actions

local Refresh

-- the card: who, state, payment, tip, for whom, note, when; the reagents for the whole amount with what the player has;
-- up to four actions
local function FillDetail(d, e)
  local info = ns.WishInfo(e)
  local r = ns.WishRole(e)
  local pill = { ns.WishStateText(e), STATE_KIND[e.state] or "blue" }
  if r.lost then pill = { L["taken"], "red" } end
  local itemID, quality = ns.RecipeItemQuality(info)
  d:SetHead({ icon = info.icon, title = info.title .. (e.count > 1 and (" x" .. e.count) or ""), pill = pill,
    itemID = itemID, titleColor = quality and Kit.QualityColor(quality) or nil,
    meta = info.gather and (info.prof and L["To gather: %s"]:format(ns.ProfName(info.prof)) or L["To gather"]) or ns.ProfName(info.prof or 0) })
  local acts = {}
  for i, a in ipairs(Actions(e)) do
    if i > 4 then break end
    acts[#acts + 1] = { text = a.label, kind = a.kind, onClick = function() a.fn() Refresh() end }
  end
  d:SetActions(acts)
  d:Begin()
  local on = ns.IsOnline(e.owner)
  d:Line(L["From"], Kit.C.muted, Colored(e.owner) .. "  " .. (on and L["online"] or L["offline"]), on and Kit.C.green or Kit.C.quiet)
  if r.lost then d:Line(L["Already accepted by %s."]:format(ns.ShortName(e.crafter)), Kit.C.red) end
  d:Line(L["Payment"], Kit.C.muted, L[ns.PAY_TEXT[e.pay] or "I bring the reagents"], Kit.C.title)
  if (e.tip or 0) > 0 then d:Line(L["Tip"], Kit.C.muted, ns.MoneyText(e.tip), Kit.C.yellow) end
  d:Line(L["For"], Kit.C.muted, e.target and Colored(e.target) or L["Everyone who can craft it"], Kit.C.title)
  d:Line(L["Made"], Kit.C.muted, ns.UI.AgeText(e.created), Kit.C.title)
  if e.state == "o" then
    local left = math.max(0, e.expires - time())
    d:Line(L["runs out in %d days"]:format(math.ceil(left / 86400)), Kit.C.quiet)
  end
  if e.note ~= "" then
    d:Section(L["Note"])
    d:Para(e.note, Kit.C.body)
  end
  -- reagents for the whole amount, with what the player has
  if info.gather then
    d:Section(L["In your bags: %d of %d"]:format(ns.ItemCount(e.item), e.count))
  elseif not info.reagents or #info.reagents == 0 then
    d:Section(L["Reagents"])
    d:Para(L["Reagents unknown until a crafter opens the window."], Kit.C.muted)
  else
    d:Section(L["Reagents for %d"]:format(e.count))
    for _, rg in ipairs(info.reagents) do
      local need, have = rg[2] * e.count, ns.ItemCount(rg[1])
      local ok = have >= need
      d:Item(rg[1], ns.ItemName(rg[1]) or L["Item %d"]:format(rg[1]), ok and Kit.C.body or Kit.C.red, ("%d/%d"):format(have, need),
        ok and Kit.C.green or Kit.C.red)
    end
  end
  d:End()
end

function Refresh()
  if not page then return end
  ns.InvalidateWishes()
  local db = State()
  local data, n = ns.WishEntries()
  page.chips:SetActive(db.wishFilter)
  page.state:Update()
  page.list:SetItems(data)
  page.count:SetText(L["%d wishes"]:format(n))
  local sel = page.selected
  if sel and not ns.Wish(sel) then sel = nil page.overlay = nil end
  -- (18.11.2026) the card shows only the wish the player picked (it can be closed, the list then takes the whole width)
  page.selected = sel
  local picked
  for _, e in ipairs(data) do if e.wish and e.key == sel then picked = e break end end
  page.list:Select(picked)
  if page._w then page:Layout(page._w, page._h, page._mode) end
end
ns.RefreshWishes = Refresh

function ns.SelectWish(key)
  if not page then return end
  page.selected = key
  page.overlay = key ~= nil or nil
  Refresh()
end

ns.PAGE_BUILDERS.wishes = function(p)
  UI = ns.PageKit and ns.PageKit() or Kit
  page = p
  State()
  p.chips = UI.ChipBar(p, { onChange = function(key)
    State().wishFilter = key
    p.selected, p.overlay = nil, nil
    Refresh()
  end })
  for _, f in ipairs(ns.WISH_FILTERS) do p.chips:Add(f, L[FILTER_TEXT[f]]) end
  -- a small filter by state (Daniel 26.10., Gemini draft)
  p.state = UI.Dropdown(p, {
    items = function()
      local out = { { value = "all", text = L["All states"] } }
      for _, k in ipairs(ns.WISH_STATES) do if k ~= "all" then out[#out + 1] = { value = k, text = L[ns.STATE_TEXT[k]] } end end
      return out
    end,
    get = function() return State().wishState or "all" end,
    set = function(key) State().wishState = key ~= "all" and key or nil p.selected, p.overlay = nil, nil Refresh() end,
  })
  p.state:SetTooltip(L["State"], { L["Click: choose"] })
  p.count = UI.Text(p, "sub", Kit.C.muted, "RIGHT")
  p.new = UI.Button(p, L["New wish"], { kind = "primary", onClick = function()
    ns.Print(L["Choose a recipe, then click \"Wish\" below its details."])
    ns.OpenTab("recipes")
  end })
  p.new:SetTooltip(L["New wish"], { L["Choose a recipe, then click \"Wish\" below its details."] })
  p.list = UI.List(p, {
    onToggle = function(e)
      if not e.fold then return end
      local db = State()
      db.wishFold = type(db.wishFold) == "table" and db.wishFold or {}
      db.wishFold[e.fold] = e.collapsed or nil
      Refresh()
    end,
    onClick = function(e)
      if not e.wish then return end
      if p.selected == e.key and p.detail:IsShown() then p.CloseCard() return end
      p.selected, p.overlay = e.key, true
      p.list:Select(e)
      ns.Relayout()
    end,
  })
  p.list:SetEmpty(L["No wishes here. Wishes start in the recipes."])
  -- (18.11.2026, as in the recipes) the card closes with its X, a second click on the picked row or Esc
  p.CloseCard = function()
    p.overlay, p.selected = nil, nil
    p.list:Select(nil)
    ns.Relayout()
  end
  p.detail = UI.Detail(p, { onClose = p.CloseCard })
  if ns.CardEsc then ns.CardEsc(p.detail, p.CloseCard) end
  p.Hint = function() return L["New wishes start in the recipes. Open wishes run out after %d days."]:format(ns.db.wishDays or 14) end
  p.Layout = function(self, w, h, mode)
    self._w, self._h, self._mode = w, h, mode
    local narrow = mode ~= "full"
    -- (18.11.2026, as in the recipes) the filters take the whole width over list and card; the card of a picked wish
    -- stands beside the list from 960 px, else over it, and closes again
    local full = w - 2 * S.pad
    local e = self.selected and ns.Wish(self.selected)
    local lw = (e and not narrow) and full - DETAIL_W - S.pad or full
    local y = S.gap
    -- right: "New wish", the count, the state; the chips get what is left
    local nw = math.min(self.new.natural or 100, 140)
    self.new:Layout(nw)
    self.new:ClearAllPoints()
    self.new:SetPoint("TOPRIGHT", self, "TOPLEFT", S.pad + full, -y)
    local cw = math.min(Kit.TextWidth(self.count), 90)
    self.count:ClearAllPoints()
    self.count:SetPoint("TOPRIGHT", self, "TOPLEFT", S.pad + full - nw - S.gap, -y - 7)
    UI.Fit(self.count, 90)
    local dw = math.max(90, math.min(140, math.floor(full * 0.2)))
    local dx = S.pad + full - nw - S.gap - cw - S.gap - dw
    self.state:ClearAllPoints()
    self.state:SetPoint("TOPLEFT", self, "TOPLEFT", dx, -y)
    self.state:Layout(dw)
    self.chips:ClearAllPoints()
    self.chips:SetPoint("TOPLEFT", self, "TOPLEFT", S.pad, -y - 2)
    self.chips:Layout(math.max(40, dx - S.gap - S.pad))
    y = y + S.button + S.gap
    self.list:ClearAllPoints()
    self.list:SetPoint("TOPLEFT", self, "TOPLEFT", S.pad, -y)
    self.list:Resize(lw, math.max(40, h - y - S.gap))
    -- the card: beside the list from 960 px, else over it; it starts at the list's top (the filters stay free) and is
    -- opaque over the list
    local show = e and true or false
    self.detail:SetShown(show)
    if show then
      local cwid = narrow and math.min(DETAIL_W, full) or DETAIL_W
      self.detail:ClearAllPoints()
      self.detail:SetPoint("TOPRIGHT", self, "TOPRIGHT", -S.pad, -y)
      self.detail:Layout(cwid, h - y - S.gap)
      if ns.CardOpaque then ns.CardOpaque(self.detail, narrow) end
      if narrow then pcall(self.detail.SetFrameLevel, self.detail, (self.list:GetFrameLevel() or 1) + 20) end
      self.detail.close:Show()
      FillDetail(self.detail, e)
    end
  end
  p.Refresh = function() Refresh() end
end

---------------------------------------------------------------------------
-- A short note when a new wish for my recipes arrives (Durchgang 5, Nr. 6), once per wish
---------------------------------------------------------------------------
function ns.OnWishesArrived(owner)
  if ns.db.notifyWishes == false then return end
  ns.db.wishSeen = type(ns.db.wishSeen) == "table" and ns.db.wishSeen or {}
  ns.InvalidateWishes()
  local now = time()
  for _, e in ipairs(ns.Wishes()) do
    if e.owner == owner and e.state == "o" and not ns.db.wishSeen[e.key] and ns.WishRole(e).forMe then
      ns.db.wishSeen[e.key] = now
      ns.Print(L["New wish for you: %s from %s (/gnc wishes)."]:format(ns.WishInfo(e).title .. (e.count > 1 and (" x" .. e.count) or ""),
        ns.ShortName(owner)))
    end
  end
  for k, t in pairs(ns.db.wishSeen) do if now - t > 60 * 86400 then ns.db.wishSeen[k] = nil end end
end

-- the wisher hears when his wish was accepted or crafted
function ns.OnJobsArrived(crafter)
  if ns.db.notifyWishes == false then return end
  ns.db.jobSeen = type(ns.db.jobSeen) == "table" and ns.db.jobSeen or {}
  ns.InvalidateWishes()
  for _, e in ipairs(ns.Wishes()) do
    if e.owner == ns.MyName() and e.crafter == crafter then
      local k = e.key .. ":" .. e.state
      if not ns.db.jobSeen[k] and (e.state == "a" or e.state == "m" or e.state == "s") then
        ns.db.jobSeen[k] = time()
        ns.Print(L["Your wish %s: %s."]:format(ns.WishInfo(e).title, ns.WishStateText(e)))
      end
    end
  end
end
