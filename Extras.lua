local _, ns = ...
local L = ns.L
local Style = ns.Style

---------------------------------------------------------------------------
-- Extras (GUILDON_PLAN.md "Durchgang 5", Daniel's decision 4: all of them in the first version)
--  1 cooldowns of the guild (transmute, Mooncloth, Salt Shaker): kind "cd"
--  3 recipe wanted: members mark recipes they want ("want"); a recipe item's tooltip says who could learn it
--  4 shopping list of the missing reagents (Auctionator list when it is there, else a text to copy)
--  6 notes when a member who can craft my wish comes online (the wish notes are in WishList.lua)
--  7 alts: own characters of one account linked ("alts"), whispers go to the one who is online
--  8 member tooltip: professions with skill, last seen, Guildon version, alts, orders crafted
--  9 guild emblem next to the window title (Forever: C_GuildInfo.GetGuildTabardInfo)
-- 10 thanks counter: orders received per crafter ("thx"), no ranking, no gold
-- 11 Questdon's arrow to a member on the map; item tooltips name who in the guild crafts the item
-- (2 wishes for gathered items: Wishes.lua, 5 cash on delivery: Trade.lua)
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- 1 Cooldowns
---------------------------------------------------------------------------
-- key, label, spells (one shared cooldown), item (cooldown of an item), profession
-- (Daniel 11.11.2026, Forever's client tables SpellCooldowns and SpellCategories, build 1.60.1.70888) on Forever Iron to
-- Gold and Mithril to Truesilver have an own cooldown of one hour and are no longer in the shared one; a player who
-- knew them was read by them. Forever: the spells of the shared category only, with Transmute: Legionite. Era as Classic.
ns.COOLDOWNS = {
  { key = "t", label = "Transmute", prof = 171, spells = ns.ERA
    and { 11479, 11480, 17187, 17559, 17560, 17561, 17562, 17563, 17564, 17565, 17566 }
    or { 17187, 17559, 17560, 17561, 17562, 17563, 17564, 17565, 17566, 1317279 } },
  { key = "m", label = "Mooncloth", prof = 197, spells = { 18560 } },
  { key = "s", label = "Salt Shaker", prof = 165, item = 15846 },
}

-- [spell] = seconds: recipes with a cooldown of an hour or more (Forever: the client tables, Era: CMaNGOS classic-db);
-- the tab Profitable names it, the profit of such a recipe comes once a day, not per craft
ns.RECIPE_CD = ns.ERA and { [11479] = 86400, [11480] = 172800, [17187] = 172800, [17559] = 86400, [17560] = 86400, [17561] = 86400,
    [17562] = 86400, [17563] = 86400, [17564] = 86400, [17565] = 86400, [17566] = 86400, [18560] = 345600, [22430] = 7200 }
  or { [11479] = 3600, [11480] = 3600, [17187] = 169200, [17559] = 82800, [17560] = 82800, [17561] = 82800, [17562] = 82800,
    [17563] = 82800, [17564] = 82800, [17565] = 82800, [17566] = 82800, [18560] = 342000, [22430] = 7200, [1317279] = 169200 }
-- "23 h", nil without a cooldown
function ns.RecipeCooldownText(spell)
  local s = ns.RECIPE_CD[spell]
  return s and ns.L["%d h"]:format(math.ceil(s / 3600)) or nil
end

local function Known(spell)
  local entry = (ns.db.prof or {})[ns.MyName() or ""]
  for _, e in pairs(entry or {}) do if e.recipes and e.recipes[spell] then return true end end
  return false
end

-- seconds until ready (0 = ready), nil when unknown
local function SpellLeft(spell)
  local start, duration
  if C_Spell and C_Spell.GetSpellCooldown then
    local info = ns.Call(C_Spell.GetSpellCooldown, spell)
    if type(info) == "table" then start, duration = ns.Num(info.startTime), ns.Num(info.duration) end
  elseif GetSpellCooldown then
    start, duration = ns.Call(GetSpellCooldown, spell)
    start, duration = ns.Num(start), ns.Num(duration)
  end
  if not start or not duration then return nil end
  if duration <= 2 then return 0 end -- the global cooldown
  return math.max(0, start + duration - GetTime())
end

local function ItemLeft(item)
  local fn = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
  local start, duration = ns.Call(fn, item)
  start, duration = ns.Num(start), ns.Num(duration)
  if not start or not duration then return nil end
  if duration <= 2 then return 0 end
  return math.max(0, start + duration - GetTime())
end

-- (31.10.2026, LEISTUNG_PRUEFUNG 21) time() has whole seconds and GetTime() not, so the ready time read wobbled by a
-- second and every read in combat (SPELL_UPDATE_COOLDOWN) announced the set anew: the time is rounded up to the minute,
-- and a value within a minute of the one already shared stays
local function Ready(key, at, old)
  if at <= 0 then return 0 end
  if old and old[key] and old[key] > 0 and math.abs(old[key] - at) <= 60 then return old[key] end
  return math.ceil(at / 60) * 60
end

function ns.ReadCooldowns()
  local parts, now = { "1" }, time()
  local own = ns.GetSet("cd", ns.MyName() or "")
  local old = own and ns.DecodeCooldowns(own.d)
  for _, cd in ipairs(ns.COOLDOWNS) do
    local left
    if cd.item then
      if ns.ItemCount(cd.item) > 0 then left = ItemLeft(cd.item) end
    else
      -- the longest of the known spells: one shared cooldown shows the same on each, and a spell the game took out of
      -- it does not hide the others
      for _, sp in ipairs(cd.spells) do
        local l = Known(sp) and SpellLeft(sp)
        if l and (not left or l > left) then left = l end
      end
    end
    if left then parts[#parts + 1] = cd.key .. "," .. ns.B36(Ready(cd.key, left > 0 and now + left or 0, old)) end
  end
  -- nothing to share any more (11.11.2026: a player who only knows Iron to Gold on Forever): an older set is emptied, or
  -- it would stand as "ready" for good
  if #parts == 1 then
    if own and next(old or {}) then return ns.SetOwn("cd", "1") end
    return false
  end
  return ns.SetOwn("cd", table.concat(parts, ";"))
end

function ns.DecodeCooldowns(d)
  if type(d) ~= "string" or #d > 200 or d:sub(1, 1) ~= "1" then return nil end
  local out, first = {}, true
  for piece in (d .. ";"):gmatch("([^;]*);") do
    if first then
      if piece ~= "1" then return nil end
      first = false
    else
      local key, t = piece:match("^(%l),(%w+)$")
      if not key then return nil end
      out[key] = ns.UnB36(t)
    end
  end
  return out
end

ns.RegisterKind("cd", { validate = function(d) return ns.DecodeCooldowns(d) ~= nil end })

-- list for the professions tab: { cd, owner, ready (unix, 0 = now) }
function ns.GuildCooldowns()
  local out = {}
  for _, set in ipairs(ns.SetsOf("cd")) do
    for key, t in pairs(ns.DecodeCooldowns(set.d) or {}) do
      for _, cd in ipairs(ns.COOLDOWNS) do
        if cd.key == key then out[#out + 1] = { cd = cd, owner = set.o, ready = t } end
      end
    end
  end
  table.sort(out, function(a, b)
    if a.cd.key ~= b.cd.key then return a.cd.key > b.cd.key end
    if a.ready ~= b.ready then return a.ready < b.ready end
    return a.owner < b.owner
  end)
  return out
end

local cdPending = false
local function CooldownsSoon()
  if cdPending then return end
  cdPending = true
  ns.After(5, function() cdPending = false ns.ReadCooldowns() end)
end
ns.On("PLAYER_LOGIN", function() ns.After(12, ns.ReadCooldowns) end)
ns.On("SPELL_UPDATE_COOLDOWN", CooldownsSoon)
ns.On("BAG_UPDATE_COOLDOWN", CooldownsSoon)
ns.OnInit(function() ns.NewTicker(300, ns.ReadCooldowns) end)

---------------------------------------------------------------------------
-- 3 Recipes wanted
---------------------------------------------------------------------------
local function DB()
  ns.db.wants = type(ns.db.wants) == "table" and ns.db.wants or {}
  ns.db.thanks = type(ns.db.thanks) == "table" and ns.db.thanks or {}
  return ns.db
end

local function ShareWants()
  local list = {}
  for spell in pairs(DB().wants) do list[#list + 1] = spell end
  table.sort(list)
  for i, s in ipairs(list) do list[i] = ns.B36(s) end
  ns.SetOwn("want", "1;" .. table.concat(list, ","))
end

function ns.SetWanted(spell, on)
  DB().wants[spell] = on and true or nil
  ShareWants()
  if ns.OnDataChanged then ns.OnDataChanged("want", ns.MyName()) end
end
function ns.IsWanted(spell) return DB().wants[spell] == true end

ns.RegisterKind("want", { validate = function(d) return d:match("^1;[%w,]*$") ~= nil and #d < 4000 end })

-- members who want a recipe (the player too)
function ns.WantedBy(spell)
  local out = {}
  for _, set in ipairs(ns.SetsOf("want")) do
    for code in set.d:sub(3):gmatch("%w+") do if ns.UnB36(code) == spell then out[#out + 1] = set.o break end end
  end
  if ns.IsWanted(spell) then
    local me, have = ns.MyName(), false
    for _, o in ipairs(out) do if o == me then have = true end end
    if not have then out[#out + 1] = me end
  end
  return out
end

-- members who have the profession with enough skill and do not know the recipe yet
function ns.CouldLearn(spell)
  local info = ns.RecipeInfo(spell)
  local out = {}
  if not info.prof then return out end
  for owner, p in pairs(ns.CraftIndex().owners) do
    local e = p.skills[info.prof]
    if e and not e.recipes[spell] then out[#out + 1] = { owner = owner, ok = (e.rank or 0) >= (info.skill or 0), rank = e.rank } end
  end
  table.sort(out, function(a, b) if a.ok ~= b.ok then return a.ok end return a.owner < b.owner end)
  return out
end

---------------------------------------------------------------------------
-- 10 Thanks: the wisher counts received orders per crafter
---------------------------------------------------------------------------
function ns.CountThanks(crafter)
  if not crafter or crafter == ns.MyName() then return end
  local db = DB()
  db.thanks[crafter] = (db.thanks[crafter] or 0) + 1
  local parts = { "1" }
  local names = {}
  for name in pairs(db.thanks) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do parts[#parts + 1] = name .. "," .. db.thanks[name] end
  ns.SetOwn("thx", table.concat(parts, ";"))
end

ns.RegisterKind("thx", { validate = function(d) return d:match("^1[^|]*$") ~= nil and #d < 4000 end })

function ns.ThanksOf(crafter)
  local n = 0
  for _, set in ipairs(ns.SetsOf("thx")) do
    for name, c in set.d:gmatch(";([^,;]+),(%d+)") do if name == crafter then n = n + tonumber(c) end end
  end
  return n -- the own set is among the sets
end

---------------------------------------------------------------------------
-- 7 Alts: the characters of this account (all that ran Guildon), shared by each of them
---------------------------------------------------------------------------
local function ShareAlts()
  local me = ns.MyName()
  if not me then return end
  local names, seen = {}, {}
  for owner in pairs(ns.db.chars or {}) do if not seen[owner] then seen[owner] = true names[#names + 1] = owner end end
  for owner in pairs(ns.db.prof or {}) do if not seen[owner] then seen[owner] = true names[#names + 1] = owner end end
  if #names < 2 then return end
  table.sort(names)
  ns.SetOwn("alts", "1;" .. table.concat(names, ";"))
end
ns.RegisterKind("alts", { validate = function(d) return d:match("^1;[^|,]+$") ~= nil and #d < 2000 end })
ns.On("PLAYER_LOGIN", function() ns.After(14, ShareAlts) end)

-- the characters linked with this one (not itself)
function ns.AltsOf(name)
  local out, seen = {}, { [name] = true }
  for _, set in ipairs(ns.SetsOf("alts")) do
    local has = false
    for n in set.d:sub(3):gmatch("[^;]+") do if n == name then has = true end end
    if has then for n in set.d:sub(3):gmatch("[^;]+") do if not seen[n] then seen[n] = true out[#out + 1] = n end end end
  end
  table.sort(out)
  return out
end

-- whom to whisper: the character itself when online, else an alt of the same account that is online
function ns.ReachableName(name)
  if ns.IsOnline(name) then return name end
  for _, alt in ipairs(ns.AltsOf(name)) do if ns.IsOnline(alt) and ns.IsMember(alt) then return alt, true end end
  return name
end

---------------------------------------------------------------------------
-- 8 Member tooltip lines
---------------------------------------------------------------------------
-- (31.10.2026, C3) the craft lines of a member: professions with skill, orders crafted for the guild. Guildon shows them in its
-- member tooltip (GuildonAPI.AddMemberLines); m only needs the name.
function ns.CraftLines(m)
  local lines = {}
  local name = type(m) == "table" and m.name
  if not name then return lines end
  local p = ns.CraftIndex().owners[name]
  if p then
    local parts = {}
    for _, pr in ipairs(ns.PROFS) do
      local e = p.skills[pr.id]
      if e then parts[#parts + 1] = ("%s %d/%d"):format(ns.ProfName(pr.id), e.rank or 0, e.max or 0) end
    end
    if #parts > 0 then lines[#lines + 1] = table.concat(parts, ", ") end
  end
  local thx = ns.ThanksOf(name)
  if thx > 0 then lines[#lines + 1] = L["Orders crafted for the guild: %d"]:format(thx) end
  return lines
end

function ns.MemberLines(m)
  local lines = ns.CraftLines(m)
  if not m.online and m.lastOnline then
    lines[#lines + 1] = L["Last seen: %s"]:format(m.lastOnline < 1 and L["today"] or L["%d days ago"]:format(m.lastOnline))
  end
  local alts = ns.AltsOf(m.name)
  if #alts > 0 then
    local short = {}
    for i, a in ipairs(alts) do short[i] = ns.ShortName(a) end
    lines[#lines + 1] = L["Alts: %s"]:format(table.concat(short, ", "))
  end
  return lines
end

-- Guildon loads after Guildon Crafts (it depends on it): the lines are handed over at login
function ns.HookGuildon()
  local api = rawget(_G, "GuildonAPI")
  if type(api) ~= "table" or type(api.AddMemberLines) ~= "function" then return false end
  return (pcall(api.AddMemberLines, function(m) return ns.SafeCall("guildon lines", ns.CraftLines, m) end))
end
ns.On("PLAYER_LOGIN", function() ns.HookGuildon() end)

---------------------------------------------------------------------------
-- 6 A member comes online who can craft one of my open wishes or works on one
---------------------------------------------------------------------------
function ns.OnMemberOnline(name)
  if ns.db.notifyWishes == false or not ns.Wishes then return end
  local me = ns.MyName()
  for _, e in ipairs(ns.Wishes()) do
    if e.owner == me and (e.state == "o" or e.state == "a" or e.state == "m") then
      local can = e.crafter == name
      if not can and e.state == "o" and e.spell then
        for _, o in ipairs(ns.CraftIndex().crafters[e.spell] or {}) do if o == name then can = true end end
      end
      if can and (not e.target or e.target == name) then
        ns.Print(L["%s is online and can craft your wish %s."]:format(ns.ShortName(name), ns.WishInfo(e).title))
        return
      end
    end
  end
end

---------------------------------------------------------------------------
-- 4 Shopping list
---------------------------------------------------------------------------
-- the reagents still missing for a recipe x count: { { item, pieces } }
function ns.MissingReagents(spell, count)
  local out = {}
  for _, r in ipairs(ns.RecipeInfo(spell).reagents or {}) do
    local miss = r[2] * (count or 1) - ns.ItemCount(r[1])
    if miss > 0 then out[#out + 1] = { r[1], miss } end
  end
  return out
end

function ns.ShoppingList(spell, count)
  local miss = ns.MissingReagents(spell, count)
  if #miss == 0 then ns.Print(L["You have all reagents."]) return "none" end
  local title = (ns.SpellName(spell) or L["Recipe %d"]:format(spell)) .. (count and count > 1 and (" x" .. count) or "")
  -- Auctionator's shopping list (API v1), when it is there
  local api = type(Auctionator) == "table" and type(Auctionator.API) == "table" and Auctionator.API.v1
  if api and type(api.CreateShoppingList) == "function" then
    local terms = {}
    for _, m in ipairs(miss) do
      local name = ns.ItemName(m[1])
      if name then terms[#terms + 1] = name end
    end
    if #terms == #miss and pcall(api.CreateShoppingList, "Guildon Crafts", "Guildon Crafts: " .. title, terms) then
      ns.Print(L["Auctionator shopping list made: %s."]:format("Guildon Crafts: " .. title))
      return "auctionator"
    end
  end
  local lines, total = {}, 0
  for _, m in ipairs(miss) do
    local p = ns.Price and ns.Price(m[1])
    if p then total = total + p * m[2] end
    lines[#lines + 1] = ("%d x %s%s"):format(m[2], ns.ItemName(m[1]) or L["Item %d"]:format(m[1]),
      p and ("  (" .. ns.ShortMoney(p * m[2]) .. ")") or "")
  end
  ns.ShowCopyBox(L["Shopping list: %s"]:format(title), total > 0 and L["About %s at the auction house."]:format(ns.ShortMoney(total)) or "",
    table.concat(lines, "\n"))
  return "text"
end

---------------------------------------------------------------------------
-- 11 Item tooltips: who in the guild crafts the item, who could learn a recipe item, who wants it
-- (TooltipDataProcessor, no hooks; where the client lacks it there are no lines)
---------------------------------------------------------------------------
local byResult, byRecipeItem

local function Lookups()
  if byResult then return end
  byResult, byRecipeItem = {}, {}
  for id, r in pairs(ns.RECIPES) do
    if r[5] and r[5] > 0 then byResult[r[5]] = byResult[r[5]] or {} table.insert(byResult[r[5]], id) end
    if r[4] and r[4] > 0 then byRecipeItem[r[4]] = id end
  end
end

local function Names(list, max)
  local out = {}
  for i = 1, math.min(#list, max) do
    local o = type(list[i]) == "table" and list[i].owner or list[i]
    out[#out + 1] = (ns.IsOnline(o) and "|cff4fd16a" or "|cff9ea3ad") .. ns.ShortName(o) .. "|r"
  end
  local s = table.concat(out, ", ")
  if #list > max then s = s .. " " .. L["and %d more"]:format(#list - max) end
  return s
end

-- lines for an item: { text, ... }
function ns.ItemTooltipLines(item)
  if ns.db.tooltips == false or not item then return {} end
  Lookups()
  local lines = {}
  local crafters, seen = {}, {}
  for _, spell in ipairs(byResult[item] or {}) do
    for _, o in ipairs(ns.CraftersOf(spell)) do if not seen[o] then seen[o] = true crafters[#crafters + 1] = o end end
  end
  if #crafters > 0 then lines[#lines + 1] = L["Crafted in the guild by %s"]:format(Names(crafters, 4)) end
  local spell = byRecipeItem[item]
  if spell then
    local known = ns.CraftIndex().crafters[spell] or {}
    if #known > 0 then lines[#lines + 1] = L["Known by %s"]:format(Names(known, 4)) end
    local could = {}
    for _, c in ipairs(ns.CouldLearn(spell)) do if c.ok then could[#could + 1] = c end end
    if #could > 0 then lines[#lines + 1] = L["Could learn it: %s"]:format(Names(could, 4)) end
    local want = ns.WantedBy(spell)
    if #want > 0 then lines[#lines + 1] = L["Wanted by %s"]:format(Names(want, 4)) end
  end
  return lines
end

-- (30.10.2026, Daniel: "die Meldung kommt nur, wenn es droppt", "zusätzlich zum Tooltip") a recipe someone in the guild
-- wants drops for you: a chat line names who wants it (a click on the name whispers), and the guild hears "R:<item>",
-- so the ones who want it read who found it. Only your own loot (the game's "You receive loot" lines), not quest
-- rewards, purchases or crafting.
function ns.RecipeSpellForItem(item)
  Lookups()
  return item and byRecipeItem[item] or nil
end
local function PlayerLink(full)
  return "|Hplayer:" .. full .. "|h[" .. ns.ShortName(full) .. "]|h"
end
local lootPatterns
local function LootPatterns()
  if lootPatterns then return lootPatterns end
  local list = {}
  for _, g in ipairs({ "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_SELF" }) do -- the longer one first ("...x3.")
    local f = rawget(_G, g)
    if type(f) == "string" then
      local p = "^" .. f:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0"):gsub("%%s", "(.+)"):gsub("%%d", "%%d+") .. "$"
      list[#list + 1] = p
    end
  end
  if #list > 0 then lootPatterns = list end -- kept once the game's texts are there
  return list
end
-- the item of an own loot line, or nil
function ns.OwnLootItem(text)
  if type(text) ~= "string" then return nil end
  for _, p in ipairs(LootPatterns()) do
    local link = text:match(p)
    if link then return tonumber(link:match("|Hitem:(%d+)")) end
  end
  return nil
end
function ns.OnRecipeDrop(item)
  local spell = ns.RecipeSpellForItem(item)
  if not spell then return false end
  local me, others = ns.MyName(), {}
  for _, o in ipairs(ns.WantedBy(spell)) do if o ~= me then others[#others + 1] = PlayerLink(o) end end
  if #others == 0 then return false end
  ns.Print(L["%s is wanted by %s."]:format(ns.ItemName(item) or ("#" .. item), table.concat(others, ", ")))
  ns.Send("R:" .. ns.B36(item), "GUILD")
  return true
end
ns.On("CHAT_MSG_LOOT", function(_, text)
  local item = ns.OwnLootItem(text)
  if item then ns.OnRecipeDrop(item) end
end)
-- a member found a recipe: those who want it read it
ns.MSG = ns.MSG or {}
ns.MSG.R = function(sender, rest, chat)
  if chat ~= "GUILD" then return end
  local item = rest and rest:match("^(%w+)$") and ns.UnB36(rest)
  local spell = item and ns.RecipeSpellForItem(item)
  if not (spell and ns.IsWanted(spell)) then return end
  ns.Print(L["%s found %s, the recipe you want."]:format(PlayerLink(sender), ns.ItemName(item) or ("#" .. item)))
end

local function OnTooltip(tooltip, data)
  if not tooltip or not tooltip.AddLine or type(data) ~= "table" then return end
  local id = ns.Num(data.id)
  if not id then return end
  local lines = ns.ItemTooltipLines(id)
  if #lines == 0 then return end
  tooltip:AddLine(ns.WORDMARK)
  for _, l in ipairs(lines) do tooltip:AddLine(l, 0.85, 0.85, 0.85, true) end
end

ns.OnInit(function()
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    ns.Call(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Item, ns.Guard("tooltip", OnTooltip))
  end
end)
