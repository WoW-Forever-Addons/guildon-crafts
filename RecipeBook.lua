local _, ns = ...
local L = ns.L
local Kit = ns.Kit

---------------------------------------------------------------------------
-- Tabs "Professions" and "Recipes" (GUILDON_PLAN.md step 2, "Bedienung"; Don style 02.11.2026, mockup
-- docs/layout_2026-11-02/guildon/ parts 4, 4b and 5).
-- Professions: the professions in a sidebar (cooldowns on top), the chosen one as a hero with who in the guild has it:
-- column heads, a skill bar in the cell, online first; a click on a member opens a whisper.
-- Recipes: the professions in the same sidebar, type, search, wearable level and the filter chips (all / someone can /
-- nobody can / I can / online now) on top, recipes grouped by type (fold by click), the picked recipe in a card on the
-- right (reagents with what the player has, who wants it, who can craft it, wish / want / whisper). The sidebar is always
-- the icon rail (Daniel 02.11.2026: "das so schmal lassen und das fenster was sich öffnet nach einem klick rechts daneben
-- machen"); the card goes over the list only when the list would keep less than LIST_MIN beside it.
---------------------------------------------------------------------------
local S = Kit.SIZE
local DETAIL_W = 320
local LIST_MIN = 360

ns.BOOK_FILTERS = { "all", "someone", "nobody", "mine", "online" }
local FILTER_TEXT = { all = "All recipes", someone = "Someone can", nobody = "Nobody can", mine = "I can", online = "Online now" }
local SRC_TEXT = { t = "Trainer", i = "Recipe item", q = "Quest", s = "Learned with the profession", c = "Trainer or recipe (classic data)",
  f = "New in Forever (client data)", p = "Seen in the game (player report)" }

local function Hex(classFile) return ns.ClassHex(classFile) end
local function ClassOf(owner)
  local m = ns.Member(owner)
  if m and m.classFile ~= "" then return m.classFile end
  local info = ns.InfoOf(owner)
  return info and info.classFile or ""
end
local function Colored(owner) return "|c" .. Hex(ClassOf(owner)) .. ns.ShortName(owner) .. "|r" end

-- (02.11.2026, Daniel: "item tooltip wenn man drüber hovert", "rarity farben von wow hinterlegen", "entweder schrift, oder
-- symbol") the made item of a recipe: its id for the game's tooltip and its quality for the colour of the name (the text only)
function ns.RecipeItemQuality(info)
  local id = info and tonumber(info.item)
  if not id or id <= 0 then return nil, nil end
  local _, _, q = ns.Kit.ItemData(id)
  return id, q
end

local function ItemText(id)
  local name = ns.ItemName(id)
  return name or L["Item %d"]:format(id)
end

-- the picture the game shows for a recipe: the created item, else the spell (enchantments), else the profession
function ns.RecipeIcon(spell, info)
  info = info or ns.RecipeInfo(spell)
  return (info.item and info.item > 0 and ns.ItemIcon(info.item)) or ns.SpellIcon(spell) or ns.ProfIcon(info.prof or 0)
end

-- the link of a recipe for the chat: the crafted item, else the spell
function ns.LinkRecipe(spell)
  local info = ns.RecipeInfo(spell)
  local link
  if info.item and info.item > 0 then link = select(2, ns.ItemName(info.item)) end
  if not link then
    local fn = (C_Spell and C_Spell.GetSpellLink) or GetSpellLink
    link = ns.Str((ns.Call(fn, spell)))
  end
  local insert = (ChatFrameUtil and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink
  if link and insert then return ns.Call(insert, link) end
end

local function RecipeName(spell)
  return ns.SpellName(spell) or L["Recipe %d"]:format(spell)
end

-- Type of the crafted good (Daniel 25.10.: "nach Art des herzustellenden Gutes, Rüstung nach Platz"): from the game
-- (GetItemInfoInstant needs no cache): armour by slot, weapons by kind, everything else by item subclass; enchantments
-- without an item; the static class/subclass as fallback. Returns key, label, sort order.
local SLOT_ORDER = { "INVTYPE_HEAD", "INVTYPE_NECK", "INVTYPE_SHOULDER", "INVTYPE_CLOAK", "INVTYPE_CHEST", "INVTYPE_BODY",
  "INVTYPE_TABARD", "INVTYPE_WRIST", "INVTYPE_HAND", "INVTYPE_WAIST", "INVTYPE_LEGS", "INVTYPE_FEET", "INVTYPE_FINGER",
  "INVTYPE_TRINKET", "INVTYPE_SHIELD", "INVTYPE_HOLDABLE" }
local SLOT_RANK, SLOT_SAME = {}, { INVTYPE_ROBE = "INVTYPE_CHEST" }
for i, k in ipairs(SLOT_ORDER) do SLOT_RANK[k] = i end
local typeCache = {}

local function Instant(item)
  local fn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if not fn then return nil end
  local ok, id, typeName, subName, equipLoc, _, classID, subID = pcall(fn, item)
  if not ok or not id then return nil end
  return ns.Str(typeName), ns.Str(subName), ns.Str(equipLoc), ns.Num(classID), ns.Num(subID)
end

-- cooking by what the food gives (Daniel 25.10.: "agi food, stärke food, ap food"), from the data (build_recipes.py)
local BUFF_TEXT = { str = "Strength", agi = "Agility", sta = "Stamina", int = "Intellect", spi = "Spirit", ap = "Attack power",
  sp = "Spell power", heal = "Healing", mp5 = "Mana regeneration", hp5 = "Health regeneration" }
local BUFF_RANK = { str = 1, agi = 2, ap = 3, sta = 4, int = 5, spi = 6, sp = 7, heal = 8, mp5 = 9, hp5 = 10 }
local function FoodType(buff)
  if buff == "food" then return "food", L["Food without a buff"], 50 end
  if buff == "drink" then return "drink", L["Drinks"], 51 end
  if buff == "special" then return "special", L["Special effects"], 52 end
  local parts, first = {}, nil
  for tag in buff:gmatch("[^+]+") do
    if not BUFF_TEXT[tag] then return "other", L["Other"], 999 end
    parts[#parts + 1] = L[BUFF_TEXT[tag]]
    first = first or BUFF_RANK[tag]
  end
  return "buff:" .. buff, L["Food: %s"]:format(table.concat(parts, L[" and "])), first + #parts / 10
end

function ns.RecipeType(info)
  if info.prof == 185 and info.buff and info.buff ~= "" then return FoodType(info.buff) end
  local item = info.item or 0
  if item == 0 then
    if info.prof == 333 then return "ench", L["Enchantments"], 900 end
    return "other", L["Other"], 999
  end
  local hit = typeCache[item]
  if hit then return hit[1], hit[2], hit[3] end
  local typeName, subName, equipLoc, cls, sub = Instant(item)
  cls, sub = cls or info.cls, sub or info.sub
  local key, label, order
  equipLoc = SLOT_SAME[equipLoc or ""] or equipLoc
  if cls == 4 and equipLoc and SLOT_RANK[equipLoc] then
    key, label, order = "slot:" .. equipLoc, ns.Str(_G[equipLoc]) or equipLoc, SLOT_RANK[equipLoc]
  elseif cls == 2 then
    key, order = "weapon:" .. tostring(sub), 100
    label = subName or ns.Str((ns.Call((C_Item and C_Item.GetItemSubClassInfo) or GetItemSubClassInfo, 2, sub))) or L["Weapons"]
  elseif cls and cls >= 0 then
    key, order = "c:" .. cls .. ":" .. tostring(sub), 200 + cls
    label = subName or ns.Str((ns.Call((C_Item and C_Item.GetItemSubClassInfo) or GetItemSubClassInfo, cls, sub)))
      or typeName or ns.Str((ns.Call((C_Item and C_Item.GetItemClassInfo) or GetItemClassInfo, cls))) or L["Other"]
  else
    key, label, order = "other", L["Other"], 999
  end
  if typeName or subName then typeCache[item] = { key, label, order } end -- only answers from the game are kept
  return key, label, order
end


---------------------------------------------------------------------------
-- The profession sidebar (both tabs): a row per profession with "online / in the guild", the ones nobody has dimmed;
-- (Kit minor 4) each with its symbol; in the icon rail (under 800 px) only the symbol
---------------------------------------------------------------------------
local function Short(text)
  local s = tostring(text or "")
  -- the first two letters (UTF-8: a letter can take several bytes)
  local out, n = "", 0
  for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    if ch ~= " " then out = out .. ch n = n + 1 end
    if n >= 2 then break end
  end
  return out
end

local function ClassName(owner)
  local m = ns.Member(owner)
  if m and m.class and m.class ~= "" then return m.class end
  local file = ClassOf(owner)
  return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[file]) or ""
end

-- every profession with its crafters (online first, then skill, then name): most members first, the empty ones last
local function ProfessionData()
  local idx = ns.CraftIndex()
  local recs, byId, active, empty = {}, {}, {}, {}
  for _, p in ipairs(ns.PROFS) do
    local list = {}
    for _, e in ipairs(idx.skills[p.id] or {}) do list[#list + 1] = e end
    local online = 0
    for _, e in ipairs(list) do e.on = ns.IsOnline(e.owner) and true or false if e.on then online = online + 1 end end
    table.sort(list, function(x, y)
      if x.on ~= y.on then return x.on end
      if (x.rank or 0) ~= (y.rank or 0) then return (x.rank or 0) > (y.rank or 0) end
      return x.owner < y.owner
    end)
    local rec = { p = p, list = list, online = online }
    byId[p.id] = rec
    if #list > 0 then active[#active + 1] = rec else empty[#empty + 1] = rec end
  end
  table.sort(active, function(a, b)
    if #a.list ~= #b.list then return #a.list > #b.list end
    return a.p.order < b.p.order
  end)
  for _, r in ipairs(active) do recs[#recs + 1] = r end
  for _, r in ipairs(empty) do recs[#recs + 1] = r end
  return recs, byId
end
ns.ProfessionData = ProfessionData

-- the sidebar's items: cooldowns on top (professions tab), a head, one row per profession (craftOnly: the recipe tab)
local function SideItems(recs, cds, craftOnly, rail)
  local out = {}
  if cds and #cds > 0 then
    out[#out + 1] = { key = "cd", sel = "cd", text = L["Cooldowns"], count = #cds, short = Short(L["Cooldowns"]),
      icon = "Interface\\Icons\\INV_Misc_PocketWatch_01",
      tooltipFn = function() return L["Cooldowns"], { L["Transmute, Mooncloth and Salt Shaker of the members with Guildon Crafts."] } end }
  end
  if not rail then out[#out + 1] = { kind = "group", key = "h:profs", static = true, text = L["Professions"] } end
  for _, r in ipairs(recs) do
    if not craftOnly or r.p.craft then
      local has = #r.list > 0
      out[#out + 1] = { key = "p:" .. r.p.id, sel = r.p.id, prof = r.p.id, text = ns.ProfName(r.p.id), short = Short(ns.ProfName(r.p.id)),
        icon = ns.ProfIcon(r.p.id),
        count = ("%d / %d"):format(r.online, #r.list), quiet = not has, status = r.online > 0 and "green" or nil,
        tooltipFn = function() return ns.ProfName(r.p.id), { L["%d in the guild, %d online"]:format(#r.list, r.online) } end }
    end
  end
  return out
end

local function SelectSide(side, sel)
  for _, it in ipairs(side.list.items or {}) do
    if it.sel ~= nil and it.sel == sel then side.list:Select(it) return it end
  end
  side.list:Select(nil)
end

---------------------------------------------------------------------------
-- Professions tab
---------------------------------------------------------------------------
-- Master and detail (Daniel 26.10., Gemini draft; mockup 02.11.2026 part 5): the professions in the sidebar, on the right
-- the best crafters of the chosen one with a skill bar, online first. A big guild shows the first TOP_CRAFTERS and the
-- rest opens with a click on the last line (ns.db.profOpen).
local TOP_CRAFTERS = 10
local HERO_H = 56

local function CooldownItems()
  local out = {}
  local now = time()
  for _, c in ipairs(ns.GuildCooldowns and ns.GuildCooldowns() or {}) do
    local left = (c.ready or 0) - now
    local on = ns.IsOnline(c.owner)
    out[#out + 1] = { kind = "table", key = "cd:" .. c.cd.key .. ":" .. c.owner, owner = c.owner, class = ClassOf(c.owner),
      status = on and "green" or nil, dim = not on,
      cells = { Colored(c.owner), { text = L[c.cd.label], color = Kit.C.muted },
        left <= 0 and { text = L["ready"], color = Kit.C.green } or { text = L["in %s"]:format(left >= 86400 and
          L["%d days"]:format(math.ceil(left / 86400)) or L["%d h"]:format(math.ceil(left / 3600))), color = Kit.C.title } } }
  end
  return out
end

local function CrafterItems(rec, narrow)
  local p, list, me = rec.p, rec.list, ns.MyName()
  local out = {}
  local open = ns.db.profOpen and ns.db.profOpen[p.id]
  local cut = #list > TOP_CRAFTERS and not open
  for i, e in ipairs(list) do
    if not (cut and i > TOP_CRAFTERS) then
      local unread = p.craft and not p.gather and e.n == 0
      local hint
      if unread then
        hint = e.owner == me and L["Open your profession window once so that Guildon Crafts can read your recipes."]
          or L["Recipes not read yet."]
      end
      local full = (e.max or 0) > 0 and (e.rank or 0) >= e.max
      local cells = { Colored(e.owner) .. (unread and " *" or "") }
      if not narrow then cells[#cells + 1] = { text = ClassName(e.owner), color = Kit.C.muted } end
      cells[#cells + 1] = { bar = (e.max or 0) > 0 and (e.rank or 0) / e.max or 0, text = ("%d/%d"):format(e.rank or 0, e.max or 0),
        color = full and Kit.C.green or Kit.C.title, barColor = full and "green" or nil }
      cells[#cells + 1] = e.on and { text = L["online"], color = Kit.C.green } or { text = L["offline"], color = Kit.C.quiet }
      out[#out + 1] = { kind = "table", key = "m:" .. p.id .. ":" .. e.owner, owner = e.owner, prof = p.id, class = ClassOf(e.owner),
        status = e.on and "green" or nil, dim = not e.on, cells = cells,
        tooltipFn = function()
          local lines = { L["Skill %d of %d"]:format(e.rank or 0, e.max or 0) }
          if p.craft then lines[#lines + 1] = L["Recipes: %d"]:format(e.n) end
          lines[#lines + 1] = L["Data from %s"]:format(ns.UI.AgeText(e.t))
          if hint then lines[#lines + 1] = hint end
          return ns.ShortName(e.owner), lines, e.owner ~= me and L["Click: whisper"] or nil
        end }
    end
  end
  if #list > TOP_CRAFTERS then
    out[#out + 1] = { kind = "group", key = "more:" .. p.id, more = p.id, collapsed = not open, plainCase = true,
      text = open and L["Show only the first %d, click"]:format(TOP_CRAFTERS) or L["%d more, click to show"]:format(#list - TOP_CRAFTERS) }
  end
  return out
end

ns.PAGE_BUILDERS.professions = function(p)
  p.side = Kit.Sidebar(p, { onClick = function(e)
    if e.sel ~= nil then ns.db.profSel = e.sel p:Refresh() end
  end })
  p.side.rail = true
  p.hero = Kit.Hero(p, { height = HERO_H })
  p.recipes = Kit.Button(p, L["Recipes"], { kind = "primary", onClick = function()
    local sel = ns.db.profSel
    if type(sel) == "number" and ns.PROF_BY_ID[sel] and ns.PROF_BY_ID[sel].craft then ns.OpenRecipes(sel) end
  end })
  p.recipes:SetTooltip(L["Recipes"], nil, L["Click: open the recipes of this profession."])
  local function Head(narrow)
    local cols = { { key = "name", text = L["Name"], width = 110, grow = true } }
    if not narrow then cols[#cols + 1] = { key = "class", text = L["Class"], width = 96 } end
    cols[#cols + 1] = { key = "skill", text = L["Skill"], width = narrow and 130 or 170 }
    cols[#cols + 1] = { key = "state", text = L["State"], width = 64, justify = "RIGHT" }
    return Kit.TableHead(p, { icon = true, columns = cols })
  end
  p.headWide, p.headNarrow = Head(false), Head(true)
  p.headCd = Kit.TableHead(p, { icon = true, columns = { { key = "name", text = L["Name"], width = 110, grow = true },
    { key = "cd", text = L["Cooldown"], width = 150 }, { key = "ready", text = L["Ready"], width = 90, justify = "RIGHT" } } })
  p.list = Kit.List(p, {
    onToggle = function(e)
      if e.more then
        ns.db.profOpen = type(ns.db.profOpen) == "table" and ns.db.profOpen or {}
        ns.db.profOpen[e.more] = not e.collapsed or nil
      end
      p:Refresh()
    end,
    onClick = function(e)
      if e.owner and e.owner ~= ns.MyName() then ns.WhisperCrafter(e.owner) end
    end,
  })
  p.Hint = function() return L["Click: whisper"] .. "   " .. L["* = recipes not read yet"] end
  p.Head = function(self)
    if ns.db.profSel == "cd" then return self.headCd end
    return self._mode == "full" and self.headWide or self.headNarrow
  end
  p.Layout = function(self, w, h, mode)
    self._w, self._h, self._mode = w, h, mode
    self.side:ClearAllPoints()
    self.side:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
    self.side:Layout(h, true)
    -- another mode: the sidebar's items (no head in the rail) and the columns change, so the page fills again
    if self._lastMode ~= mode then self._lastMode = mode if self._built then self:Refresh() return end end
    local x0 = self.side:Width() + S.pad
    local lw = w - x0 - S.pad
    local y = S.gap
    local bw = self.recipes:IsShown() and math.min(self.recipes.natural or 100, 140) or 0
    self.recipes:ClearAllPoints()
    self.recipes:SetPoint("TOPRIGHT", self, "TOPLEFT", x0 + lw, -y - math.floor((HERO_H - S.button) / 2))
    if bw > 0 then self.recipes:Layout(bw) end
    self.hero:ClearAllPoints()
    self.hero:SetPoint("TOPLEFT", self, "TOPLEFT", x0, -y)
    self.hero:Layout(lw - (bw > 0 and bw + S.gap or 0))
    y = y + HERO_H + S.gap
    local head = self:Head()
    for _, hd in ipairs({ self.headWide, self.headNarrow, self.headCd }) do hd:SetShown(hd == head) end
    head:ClearAllPoints()
    head:SetPoint("TOPLEFT", self, "TOPLEFT", x0, -y)
    head:Bind(self.list)
    head:Layout(lw)
    y = y + S.chip
    self.list:ClearAllPoints()
    self.list:SetPoint("TOPLEFT", self, "TOPLEFT", x0, -y)
    self.list:Resize(lw, math.max(40, h - y - S.gap))
  end
  p.Refresh = function(self)
    self._built = true
    local recs, byId = ProfessionData()
    local cds = ns.GuildCooldowns and ns.GuildCooldowns() or {}
    local sel = ns.db.profSel
    if not (sel == "cd" and #cds > 0) and not byId[sel] then
      sel = nil
      for _, r in ipairs(recs) do if #r.list > 0 then sel = r.p.id break end end
      sel = sel or (recs[1] and recs[1].p.id)
      ns.db.profSel = sel
    end
    self.side.list:SetItems(SideItems(recs, cds, false, self.side.rail))
    SelectSide(self.side, sel)
    local narrow = self._mode ~= nil and self._mode ~= "full"
    if sel == "cd" then
      local ready = 0
      for _, c in ipairs(cds) do if (c.ready or 0) <= time() then ready = ready + 1 end end
      self.hero:SetData({ kicker = L["Your guild"], title = L["Cooldowns"], value = tostring(#cds), label = L["ready"] .. ": " .. ready })
      self.hero._tipFn = function() return L["Cooldowns"], { L["Transmute, Mooncloth and Salt Shaker of the members with Guildon Crafts."] } end
      self.recipes:Hide()
      self.list:SetItems(CooldownItems())
      self.list:SetEmpty("")
    else
      local rec = byId[sel]
      self.hero:SetData({ kicker = L["Profession"], title = rec and ns.ProfName(rec.p.id) or "", value = rec and tostring(#rec.list) or "",
        label = rec and L["online: %d"]:format(rec.online) or "", progress = rec and #rec.list > 0 and rec.online / #rec.list or nil })
      self.hero._tipFn = rec and function() return ns.ProfName(rec.p.id), { L["%d in the guild, %d online"]:format(#rec.list, rec.online) } end or nil
      self.recipes:SetShown(rec and rec.p.craft and true or false)
      self.list:SetItems(rec and CrafterItems(rec, narrow) or {})
      self.list:SetEmpty(L["Nobody in the guild yet"])
    end
    if self._w then self:Layout(self._w, self._h, self._mode) end
  end
end

---------------------------------------------------------------------------
-- Recipes
---------------------------------------------------------------------------
local book -- the page

local function BookState()
  local db = ns.db
  if not ns.PROF_BY_ID[db.bookProf or 0] or not ns.PROF_BY_ID[db.bookProf].craft then
    db.bookProf = 171
    local mine = db.prof[ns.MyName() or ""]
    if mine then
      for _, pr in ipairs(ns.PROFS) do if pr.craft and mine[pr.id] then db.bookProf = pr.id break end end
    end
  end
  db.bookFilter = FILTER_TEXT[db.bookFilter or ""] and db.bookFilter or "all"
  -- groups are closed by default (Daniel 25.10.); bookOpen holds the ones the player opened (bookFold was the old,
  -- open-by-default table and is dropped)
  db.bookOpen = type(db.bookOpen) == "table" and db.bookOpen or {}
  db.bookFold = nil
  db.bookType = type(db.bookType) == "string" and db.bookType or "all"
  return db
end

-- the level from which the crafted item can be worn or used: the game's own item data first (Forever changes some),
-- else the data file (CMaNGOS RequiredLevel, -1 = unknown); nil when nothing says
function ns.WearLevel(info)
  local item = info.item
  if not item or item == 0 then return nil end
  local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if fn then
    local ok, _, _, _, _, minLevel = pcall(fn, item)
    minLevel = ok and ns.Num(minLevel) or nil
    if minLevel then return minLevel end
  end
  local d = info.wear
  if d and d >= 0 then return d end
  return nil
end

local function Passes(db, spell, info, crafters, search, from, to)
  local f = db.bookFilter
  if f == "someone" and #crafters == 0 then return false end
  if f == "nobody" and #crafters > 0 then return false end
  if f == "mine" or f == "online" then
    local me, ok = ns.MyName(), false
    for _, o in ipairs(crafters) do
      if (f == "mine" and o == me) or (f == "online" and ns.IsOnline(o)) then ok = true break end
    end
    if not ok then return false end
  end
  -- level range: from which character level the crafted item can be used; recipes without an item or without a known level stay
  if from or to then
    local lvl = ns.WearLevel(info)
    if lvl then
      lvl = math.max(lvl, 1) -- 0 = no requirement = from level 1
      if (from and lvl < from) or (to and lvl > to) then return false end
    end
  end
  if search ~= "" then
    local hay = RecipeName(spell):lower()
    if info.item and info.item > 0 then hay = hay .. " " .. (ns.ItemName(info.item) or ""):lower() end
    if not hay:find(search, 1, true) then return false end
  end
  return true
end

-- marker (Daniel 26.10.): a tick, green when a crafter is online, grey when only offline crafters know it, and how many
local TICK = "|TInterface\\Buttons\\UI-CheckBox-Check:14:14:0:0:32:32:0:32:0:32:%d:%d:%d|t"
local function Marker(crafters)
  if #crafters == 0 then return { text = "", color = Kit.C.quiet } end
  local online = false
  for _, o in ipairs(crafters) do if ns.IsOnline(o) then online = true break end end
  local c = online and Kit.C.green or Kit.C.grey
  local tick = TICK:format(math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255))
  return { text = (#crafters > 1 and (#crafters .. " ") or "") .. tick, color = online and Kit.C.green or Kit.C.muted }
end

local function Trim(t) return (tostring(t or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")) end

-- the list items: a group per type (folded unless opened, searching or filtering), a table row per recipe (symbol, name,
-- skill, marker); returns items, all recipes of the profession, shown ones
function ns.BookEntries()
  local db = BookState()
  local search = book and book.search and Trim(book.search:GetText()) or ""
  local from = book and book.from and book.from:GetValue() or nil
  local to = book and book.to and book.to:GetValue() or nil
  local groups, order, labels, rank = {}, {}, {}, {}
  local types, typeSeen = {}, {}
  local total, shown = 0, 0
  for _, spell in ipairs(ns.RecipesOf(db.bookProf)) do
    local info = ns.RecipeInfo(spell)
    info.prof = info.prof or db.bookProf
    local tkey, tlabel, tord = ns.RecipeType(info)
    if not typeSeen[tkey] then typeSeen[tkey] = true types[#types + 1] = { key = tkey, label = tlabel, order = tord } end
    local crafters = ns.CraftersOf(spell)
    total = total + 1
    if (db.bookType == "all" or db.bookType == tkey) and Passes(db, spell, info, crafters, search, from, to) then
      shown = shown + 1
      if not groups[tkey] then groups[tkey] = {} order[#order + 1] = tkey labels[tkey] = tlabel rank[tkey] = tord end
      table.insert(groups[tkey], { spell = spell, info = info, crafters = crafters, name = RecipeName(spell) })
    end
  end
  local function ByOrder(a, b)
    local ra, rb = rank[a] or a.order, rank[b] or b.order
    if type(a) == "table" then ra, rb = a.order, b.order end
    if ra ~= rb then return ra < rb end
    if type(a) == "table" then return a.label < b.label end
    return labels[a] < labels[b]
  end
  table.sort(order, ByOrder)
  -- groups open by themselves while searching or filtering, and when only one group is left
  local auto = search ~= "" or from ~= nil or to ~= nil or db.bookFilter ~= "all" or #order == 1
  local autoClosed = book and book.autoClosed or {}
  if book and not auto then book.autoClosed = {} end
  table.sort(types, ByOrder)
  ns.bookTypes = types
  local out = {}
  for _, tkey in ipairs(order) do
    local cat = labels[tkey]
    local g = groups[tkey]
    table.sort(g, function(a, b)
      if (a.info.skill or 0) ~= (b.info.skill or 0) then return (a.info.skill or 0) < (b.info.skill or 0) end
      return a.name < b.name
    end)
    local foldKey = db.bookProf .. ":" .. cat
    local folded
    if auto then folded = autoClosed[foldKey] == true else folded = not db.bookOpen[foldKey] end
    out[#out + 1] = { kind = "group", key = "c:" .. cat, fold = foldKey, auto = auto, plainCase = true, text = cat, count = #g,
      collapsed = folded }
    if not folded then
      for _, r in ipairs(g) do
        local can = #r.crafters > 0
        local spell, info, crafters = r.spell, r.info, r.crafters
        local itemID, quality = ns.RecipeItemQuality(info)
        local lines = { ns.ProfName(info.prof or db.bookProf) .. ((info.skill or 0) > 0 and ("  " .. L["from skill %d"]:format(info.skill)) or "") }
        lines[#lines + 1] = #crafters > 0 and L["Crafters: %s"]:format(#crafters) or L["Nobody in the guild knows this recipe yet."]
        -- a recipe that makes an item: the game's item tooltip with the guild's lines below, the name in its quality colour
        out[#out + 1] = { kind = "table", key = spell, spell = spell, icon = ns.RecipeIcon(spell, info), dim = not can,
          itemID = itemID, quality = quality, tipLines = lines, tipHint = L["Shift-click: link in the chat"],
          cells = { { text = r.name, color = can and Kit.C.title or Kit.C.quiet },
            { text = (info.skill or 0) > 0 and tostring(info.skill) or "", color = Kit.C.quiet }, Marker(crafters) },
          tooltipFn = not itemID and function() return r.name, lines, L["Shift-click: link in the chat"] end or nil }
      end
    end
  end
  return out, total, shown
end

-- the card on the right: what the recipe makes, where it comes from, who wants it, the reagents with what the player has,
-- who in the guild can craft it; actions wish, want, whisper
local function CrafterFor(spell)
  local crafters, me = ns.CraftersOf(spell), ns.MyName()
  for _, o in ipairs(crafters) do if o ~= me and ns.IsOnline(o) then return o end end
  for _, o in ipairs(crafters) do if o ~= me then return o end end
end

local function FillBookDetail(d, spell)
  local info = ns.RecipeInfo(spell)
  local prof = info.prof or ns.db.bookProf
  local title = RecipeName(spell)
  local meta = ns.ProfName(prof)
  if (info.skill or 0) > 0 then meta = meta .. "  " .. L["from skill %d"]:format(info.skill) end
  local itemID, quality = ns.RecipeItemQuality(info)
  d:SetHead({ icon = ns.RecipeIcon(spell, info), title = title, meta = meta, itemID = itemID,
    titleColor = quality and Kit.QualityColor(quality) or nil })
  -- recipe wanted (Durchgang 5 Nr. 3): for recipes the player cannot craft yet
  local mineCan = false
  for _, o in ipairs(ns.CraftIndex().crafters[spell] or {}) do if o == ns.MyName() then mineCan = true end end
  local crafter = CrafterFor(spell)
  book.crafter = crafter
  local acts = { { text = L["Wish"], kind = "primary", onClick = function() if ns.ShowWishForm then ns.ShowWishForm(spell) end end,
    tooltip = { L["Wish"], { L["Ask the guild for this recipe: crafters see your wish in their wish list."] } } } }
  if not mineCan and ns.SetWanted then
    local on = ns.IsWanted(spell)
    -- (Kit minor 4) a switch: selected while the recipe is wanted
    acts[#acts + 1] = { text = L["Want"], selected = on, onClick = function()
      ns.SetWanted(spell, not ns.IsWanted(spell))
      if book and book:IsShown() then book:Refresh() end
    end, tooltip = { L["Want"], { L["Tell the guild you want to learn this recipe. Recipe items then name you in their tooltip."] } } }
  end
  if crafter then
    acts[#acts + 1] = { text = L["Whisper %s"]:format(ns.ShortName(crafter)), onClick = function() ns.WhisperCrafter(crafter, spell) end }
  end
  d:SetActions(acts)
  d:Begin()
  local made = info.item and info.item > 0 and ItemText(info.item)
  if made and (made ~= title or (info.count or 1) > 1) then
    d:Line(L["Makes: %s"]:format(made .. ((info.count or 1) > 1 and (" x" .. info.count) or "")), Kit.C.title)
  end
  if info.src then
    local src = L[SRC_TEXT[info.src] or "Other"]
    if info.recipeItem and info.recipeItem > 0 then src = src .. ": " .. ItemText(info.recipeItem) end
    d:Para(L["Source: %s"]:format(src), Kit.C.muted)
  end
  -- who wants it
  local wanted = ns.WantedBy and ns.WantedBy(spell) or {}
  if #wanted > 0 then
    local names = {}
    for i = 1, math.min(#wanted, 4) do names[i] = Colored(wanted[i]) end
    d.wantedText = L["Wanted by %s"]:format(table.concat(names, ", ")) .. (#wanted > 4 and (" " .. L["and %d more"]:format(#wanted - 4)) or "")
    d:Para(d.wantedText, Kit.C.yellow)
  else
    d.wantedText = nil
  end
  d:Section(L["Reagents"])
  if info.reagents and #info.reagents > 0 then
    for _, rg in ipairs(info.reagents) do
      local have = ns.ItemCount(rg[1])
      local ok = have >= rg[2]
      local item = rg[1]
      local _, ic = d:Item(item, ItemText(item), ok and Kit.C.body or Kit.C.red, ("%d/%d"):format(have, rg[2]), ok and Kit.C.green or Kit.C.red,
        function() if ns.ShowWishForm then ns.ShowWishForm(nil, item) end end)
      ic.extraTip = { L["Click: wish it from the guild's gatherers"] }
    end
  else
    d:Para(L["Reagents unknown until a crafter opens the window."], Kit.C.muted)
  end
  local crafters = ns.CraftersOf(spell)
  d:Section(L["Who can craft it"], #crafters > 0 and tostring(#crafters) or nil)
  local SHOW = 12
  for i = 1, math.min(#crafters, SHOW) do
    local o = crafters[i]
    local on = ns.IsOnline(o)
    -- a click whispers this crafter (with the recipe's link)
    local mine = o == ns.MyName()
    d:Line(Colored(o), nil, on and L["online"] or L["offline"], on and Kit.C.green or Kit.C.quiet, not mine and {
      onClick = function() ns.WhisperCrafter(o, spell) end,
      tooltip = { ns.ShortName(o), { on and L["online"] or L["offline"] }, L["Click: whisper"] } } or nil)
  end
  if #crafters > SHOW then d:Line(L["and %d more"]:format(#crafters - SHOW), Kit.C.quiet) end
  if #crafters == 0 then d:Line(L["Nobody in the guild knows this recipe yet."], Kit.C.quiet) end
  d:End()
end

local function RefreshBook()
  if not book then return end
  local db = BookState()
  local recs = ProfessionData()
  book.side.list:SetItems(SideItems(recs, nil, true, book.side.rail))
  SelectSide(book.side, db.bookProf)
  local data, total, shown = ns.BookEntries()
  if db.bookType ~= "all" then
    local found = false
    for _, t in ipairs(ns.bookTypes or {}) do if t.key == db.bookType then found = true end end
    if not found then db.bookType = "all" data, total, shown = ns.BookEntries() end
  end
  book.kind:Update()
  book.chips:SetActive(db.bookFilter)
  book.list:SetItems(data)
  book.count:SetText(L["%d of %d"]:format(shown, total))
  local sel = book.selected
  if sel then
    local r = ns.RECIPES[sel]
    if r and r[1] ~= db.bookProf then sel = nil end
  end
  book.selected = sel
  ns.db.bookSpell = sel
  local picked
  for _, e in ipairs(data) do if e.spell and e.spell == sel then picked = e break end end
  book.list:Select(picked)
  if book._w then book:Layout(book._w, book._h, book._mode) end
end
ns.RefreshBook = RefreshBook

function ns.RecipeBookShow(prof, spell)
  local db = BookState()
  if prof and ns.PROF_BY_ID[prof] and ns.PROF_BY_ID[prof].craft then db.bookProf = prof end
  if book then book.selected, book.overlay = spell, spell ~= nil or nil end
  db.bookSpell = spell
end

-- a new profession starts with empty search and level fields (Daniel 25.10.)
local function ClearFields()
  for _, f in ipairs({ book.search, book.from, book.to }) do
    f:SetText("")
    if f.hint then f.hint:Show() end
    if f.clear then f.clear:Hide() end
    if f.ClearFocus then f:ClearFocus() end
  end
end

ns.PAGE_BUILDERS.recipes = function(p)
  book = p
  BookState()
  p.side = Kit.Sidebar(p, { onClick = function(e)
    if not e.prof or e.prof == ns.db.bookProf then return end
    ns.db.bookProf = e.prof
    ns.db.bookType = "all"
    p.selected = nil
    ClearFields()
    RefreshBook()
  end })
  p.side.rail = true
  p.kind = Kit.Dropdown(p, {
    items = function()
      local out = { { value = "all", text = L["All types"] } }
      for _, t in ipairs(ns.bookTypes or {}) do out[#out + 1] = { value = t.key, text = t.label } end
      return out
    end,
    get = function() return BookState().bookType end,
    set = function(key) BookState().bookType = key p.selected = nil RefreshBook() end,
  })
  p.kind:SetTooltip(L["Type"], { L["Click: choose"] })
  p.search = Kit.SearchBox(p, { placeholder = L["Recipe, item"], onChange = function() RefreshBook() end })
  -- from and to: the level from which the crafted item can be worn or used (Daniel 26.10.), not the skill
  p.from = Kit.EditBox(p, { numeric = true, min = 1, max = 99, maxLetters = 2, placeholder = L["from"], onChange = function() RefreshBook() end })
  p.to = Kit.EditBox(p, { numeric = true, min = 1, max = 99, maxLetters = 2, placeholder = L["to"], onChange = function() RefreshBook() end })
  for _, f in ipairs({ p.from, p.to }) do
    f:SetTooltip(L["Wearable from level"], { L["Shows recipes whose item can be worn or used from this character level up to that level."] })
  end
  p.from:SetNext(p.to) p.to:SetNext(p.from)
  p.chips = Kit.ChipBar(p, { onChange = function(key)
    BookState().bookFilter = key
    RefreshBook()
  end })
  for _, f in ipairs(ns.BOOK_FILTERS) do p.chips:Add(f, L[FILTER_TEXT[f]]) end
  p.count = Kit.Text(p, "sub", Kit.C.muted, "RIGHT")
  p.list = Kit.List(p, {
    onToggle = function(e)
      if not e.fold then return end
      local db = BookState()
      if e.auto then
        p.autoClosed = p.autoClosed or {}
        p.autoClosed[e.fold] = e.collapsed or nil
      else
        db.bookOpen[e.fold] = not e.collapsed or nil
      end
      RefreshBook()
    end,
    onClick = function(e)
      if not e.spell then return end
      -- shift-click puts the link into the open chat line, like in the game's profession window
      if IsShiftKeyDown and IsShiftKeyDown() and ns.LinkRecipe(e.spell) then return end
      p.selected, p.overlay = e.spell, true
      ns.db.bookSpell = e.spell
      p.list:Select(e)
      ns.Relayout()
    end,
  })
  p.list.columns = { { key = "name", width = 120, grow = true }, { key = "skill", width = 30, justify = "RIGHT" }, { key = "mark", width = 44, justify = "RIGHT" } }
  p.list.tableIcon = true
  p.list:SetEmpty(L["No recipe fits the filter."])
  p.detail = Kit.Detail(p, { onClose = function()
    p.overlay = nil
    if p._narrow then p.selected = nil ns.db.bookSpell = nil p.list:Select(nil) end
    ns.Relayout()
  end })
  p.selected = ns.db.bookSpell
  p.Hint = function() return L["Shift-click: link in the chat"] .. "   " .. L["Click a reagent's symbol: wish it from the guild's gatherers"] end
  p.Layout = function(self, w, h, mode)
    self._w, self._h, self._mode = w, h, mode
    self.side:ClearAllPoints()
    self.side:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
    self.side:Layout(h, true)
    if self._lastMode ~= mode then self._lastMode = mode if self._built then RefreshBook() return end end
    local x0 = self.side:Width() + S.pad
    -- the card beside the list while the list keeps LIST_MIN, else over it
    local narrow = w - x0 - S.pad - DETAIL_W - S.pad < LIST_MIN
    self._narrow = narrow
    local side = narrow and 0 or DETAIL_W + S.pad
    local lw = w - x0 - S.pad - side
    -- first line: type, search, level from and to, the count on the right
    local y = S.gap
    local cw = math.min(Kit.TextWidth(self.count), 90)
    local room = lw - cw - S.gap
    local kw = math.max(80, math.min(150, math.floor(room * 0.28)))
    local fw = 40
    local sw = math.max(60, math.min(220, room - kw - 2 * fw - 3 * S.gap))
    local x = x0
    self.kind:ClearAllPoints() self.kind:SetPoint("TOPLEFT", self, "TOPLEFT", x, -y) self.kind:Layout(kw)
    x = x + kw + S.gap
    self.search:ClearAllPoints() self.search:SetPoint("TOPLEFT", self, "TOPLEFT", x, -y) self.search:Layout(sw)
    x = x + sw + S.gap
    self.from:ClearAllPoints() self.from:SetPoint("TOPLEFT", self, "TOPLEFT", x, -y) self.from:Layout(fw)
    x = x + fw + 4
    self.to:ClearAllPoints() self.to:SetPoint("TOPLEFT", self, "TOPLEFT", x, -y) self.to:Layout(fw)
    self.count:ClearAllPoints()
    self.count:SetPoint("TOPRIGHT", self, "TOPLEFT", x0 + lw, -y - 7)
    Kit.Fit(self.count, 90)
    -- second line: the filter chips
    y = y + S.button + S.gap
    self.chips:ClearAllPoints()
    self.chips:SetPoint("TOPLEFT", self, "TOPLEFT", x0, -y)
    self.chips:Layout(lw)
    y = y + S.chip + S.gap
    self.list:ClearAllPoints()
    self.list:SetPoint("TOPLEFT", self, "TOPLEFT", x0, -y)
    self.list:Resize(lw, math.max(40, h - y - S.gap))
    -- the card: a column of its own from 960 px, else over the list when a recipe is picked
    local sel = self.selected
    if narrow and not self.overlay then sel = nil end
    local show = sel ~= nil or not narrow
    self.detail:SetShown(show)
    if show then
      local dw = narrow and math.min(DETAIL_W, w - x0 - S.pad) or DETAIL_W
      self.detail:ClearAllPoints()
      self.detail:SetPoint("TOPRIGHT", self, "TOPRIGHT", -S.pad, -S.gap)
      self.detail:Layout(dw, h - 2 * S.gap)
      if narrow then pcall(self.detail.SetFrameLevel, self.detail, (self.list:GetFrameLevel() or 1) + 20) end
      if sel then
        if narrow then self.detail.close:Show() else self.detail.close:Hide() end
        FillBookDetail(self.detail, sel)
      else
        self.detail.close:Hide()
        self.detail:SetHead({ title = L["Recipes"], meta = ns.ProfName(BookState().bookProf) })
        self.detail:SetActions({})
        self.detail:Begin()
        self.detail:Para(L["Choose a recipe on the left."], Kit.C.muted)
        self.detail:Para(L["Wishes start here: choose a recipe, then \"Wish\". Crafters in the guild see it in their wish list."], Kit.C.quiet)
        self.detail:End()
      end
    end
  end
  p.Refresh = function(self)
    self._built = true
    RefreshBook()
  end
end

-- item names arrive later from the server: repaint the open book once
local itemQueued = false
function ns.OnItemInfo()
  if ns.WishFormItemInfo then ns.WishFormItemInfo() end
  if itemQueued or not book or not book:IsVisible() then return end
  itemQueued = true
  ns.After(0.5, function() itemQueued = false RefreshBook() end)
end
