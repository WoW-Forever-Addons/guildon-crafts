local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- (31.10.2026, C4, DONCORE_PLAN.md "Craftdon aus Guildon lösen", "Übergang") Guildon Crafts takes over what Guildon 0.8 kept in
-- GuildonDB: professions, recipes seen, wishes and orders, prices, cooldowns, "wanted", thanks, the book and list choices,
-- the craft options. Guildon depends on Guildon Crafts and loads after it, so GuildonDB is only there at
-- PLAYER_LOGIN. Once done (GuildonCraftsDB.tookGuildon), never again. Only what Guildon Crafts does not have yet is taken: a key that
-- is missing or an empty table, a set Guildon Crafts lacks or holds older. GuildonDB itself stays as it is (Guildon clears these
-- keys in a later version), so nothing is lost if someone switches Guildon Crafts off again.
--
-- And the old prefix: members still on Guildon 0.8 send the craft kinds under "Guildon" ("GuildonEra"); Guildon Crafts reads
-- them there and answers their hellos with its own sets (GuildShared/Comm.lua, ns.LEGACY_PREFIX).
---------------------------------------------------------------------------
ns.LEGACY_PREFIX = ns.ERA and "GuildonEra" or "Guildon"
ns.LEGACY_KINDS = { prof = true, seen = true, wish = true, job = true, mod = true, cfg = true, price = true, cd = true,
  want = true, thx = true }
ns.LEGACY_MSG = { R = true } -- "a member found a recipe" (Extras.lua)

-- Guildon below 0.9 still had the professions
function ns.IsLegacyVersion(v)
  local major, minor = tostring(v or ""):match("^(%d+)%.(%d+)")
  major, minor = tonumber(major), tonumber(minor)
  return major ~= nil and (major == 0 and minor < 9)
end

-- the keys of GuildonDB that belong to the crafts
ns.TAKE_KEYS = { "prof", "learned", "found", "chars", "wishes", "jobs", "mods", "wishSeen", "jobSeen", "wishDays", "wishFilter",
  "wishFold", "wishState", "notifyWishes", "prices", "priceShared", "wants", "thanks", "tooltips", "mailCOD", "showProfit",
  "profitDesc", "profitMine", "profitMineDefault", "profitProf", "profitSort", "profitStock", "profOpen", "profSel",
  "bookFilter", "bookFold", "bookOpen", "bookProf", "bookSpell", "bookType" }
-- keys Guildon Crafts fills with a default before PLAYER_LOGIN (Wishes.lua DB() at OnInit): still the default counts as not set
ns.TAKE_DEFAULTS = { wishDays = 14 }
-- (02.11.2026, StyleKit 2 step 4) the old window's place and look are no longer taken: the Don window keeps its own (db.window)

local function Copy(v, depth)
  if type(v) ~= "table" then return v end
  if (depth or 0) > 20 then return nil end
  local out = {}
  for k, x in pairs(v) do out[Copy(k, (depth or 0) + 1)] = Copy(x, (depth or 0) + 1) end
  return out
end

local function Empty(v) return v == nil or (type(v) == "table" and next(v) == nil) end

-- db: GuildonCraftsDB, gdb: GuildonDB; returns the number of keys and sets taken, nil when there was nothing to take from
function ns.TakeOverGuildon(db, gdb)
  if type(db) ~= "table" or db.tookGuildon or type(gdb) ~= "table" then return nil end
  local keys, sets = 0, 0
  for _, k in ipairs(ns.TAKE_KEYS) do
    local unset = Empty(db[k]) or (ns.TAKE_DEFAULTS[k] ~= nil and db[k] == ns.TAKE_DEFAULTS[k])
    if unset and not Empty(gdb[k]) and db[k] ~= gdb[k] then db[k] = Copy(gdb[k]) keys = keys + 1 end
  end
  db.sets = type(db.sets) == "table" and db.sets or {}
  if type(gdb.sets) == "table" then
    for key, s in pairs(gdb.sets) do
      if type(s) == "table" and ns.LEGACY_KINDS[s.k] and type(s.o) == "string" and type(s.d) == "string"
        and key == s.k .. ":" .. s.o and (not db.sets[key] or (tonumber(db.sets[key].t) or 0) < (tonumber(s.t) or 0)) then
        db.sets[key] = Copy(s)
        sets = sets + 1
      end
    end
  end
  db.tookGuildon = time()
  return keys, sets
end

ns.On("PLAYER_LOGIN", function()
  local keys, sets = ns.TakeOverGuildon(ns.db, rawget(_G, "GuildonDB"))
  if not keys then return end
  if ns.InvalidateCrafters then ns.InvalidateCrafters() end
  if ns.InvalidateWishes then ns.InvalidateWishes() end
  if ns.InvalidatePrices then ns.InvalidatePrices() end
  if keys + sets > 0 then ns.Print(L["Took over the professions, wishes and prices from Guildon (%d settings, %d data sets)."]:format(keys, sets)) end
end)
