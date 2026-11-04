local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- Export for the guild website (Daniel 25.10.2026, Frankston's libra-vivendi page): one line per own character with
-- its professions, skill and learned recipes as spell IDs. Addons cannot reach the web, so the player copies the
-- text (Ctrl+C) and pastes it on the website. Format (docs/guildon-export/FORMAT.md, version 1):
--   GNX1;<game F|E>;<name>;<realm>;<faction A|H|N>;<CLASS>;<level>;<stamp>;<profs>;<checksum>
--   profs: <skill line>:<rank>:<max>:<spell IDs base 36, comma> joined by "/" (gathering professions with an empty list)
--   checksum: ns.Checksum of everything before the last ";" (8 hex digits)
-- No "|" anywhere: the game's edit boxes read it as an escape.
---------------------------------------------------------------------------
ns.EXPORT_VERSION = 1

-- own characters: class, level, faction (only the character itself can read them, kept for the export)
local function NoteMe()
  local me = ns.MyName()
  if not me then return end
  ns.db.chars = type(ns.db.chars) == "table" and ns.db.chars or {}
  local _, cls = ns.Call(UnitClass, "player")
  local fac = ns.Str(ns.Call(UnitFactionGroup, "player"))
  ns.db.chars[me] = {
    class = ns.Str(cls) and cls:match("^%u+$") or "",
    level = ns.Num(ns.Call(UnitLevel, "player")) or 0,
    faction = fac == "Alliance" and "A" or (fac == "Horde" and "H" or "N"),
  }
end
ns.On("PLAYER_LOGIN", function() ns.After(2, NoteMe) end)
ns.On("PLAYER_LEVEL_UP", function() ns.After(2, NoteMe) end)

local function Clean(s) return (tostring(s or ""):gsub("[;|/:,%c]", "")) end

-- the export line of one own character, nil without professions
function ns.ExportLine(owner)
  local entry = ns.db.prof and ns.db.prof[owner]
  if not entry then return nil end
  local ids = {}
  for skill in pairs(entry) do if ns.PROF_BY_ID[skill] then ids[#ids + 1] = skill end end
  if #ids == 0 then return nil end
  table.sort(ids)
  local stamp, profs = 0, {}
  for _, skill in ipairs(ids) do
    local e = entry[skill]
    local spells = {}
    for id in pairs(e.recipes or {}) do spells[#spells + 1] = id end
    table.sort(spells)
    for i, id in ipairs(spells) do spells[i] = ns.B36(id) end
    profs[#profs + 1] = ("%d:%d:%d:%s"):format(skill, e.rank or 0, e.max or 0, table.concat(spells, ","))
    if (e.read or 0) > stamp then stamp = e.read end
  end
  local name, realm = owner:match("^(.-)%-(.+)$")
  local c = (ns.db.chars or {})[owner] or {}
  local head = ("GNX%d;%s;%s;%s;%s;%s;%d;%d;%s"):format(ns.EXPORT_VERSION, ns.ERA and "E" or "F", Clean(name or owner),
    Clean(realm or ""), c.faction or "N", c.class or "", c.level or 0, stamp > 0 and stamp or time(), table.concat(profs, "/"))
  return head .. ";" .. ns.Checksum(head)
end

-- all own characters, the current one first
function ns.ExportText()
  local me, names = ns.MyName(), {}
  for owner in pairs(ns.db.prof or {}) do if owner ~= me then names[#names + 1] = owner end end
  table.sort(names)
  table.insert(names, 1, me)
  local lines = {}
  for _, owner in ipairs(names) do
    local l = owner and ns.ExportLine(owner)
    if l then lines[#lines + 1] = l end
  end
  return table.concat(lines, "\n"), #lines
end

-- parse one line (tests, and the reference for the website): table or nil, reason
function ns.ParseExport(line)
  local head, sum = tostring(line or ""):match("^(.*);(%x%x%x%x%x%x%x%x)$")
  if not head then return nil, "format" end
  if ns.Checksum(head) ~= sum then return nil, "checksum" end
  local v, game, name, realm, fac, cls, lv, stamp, profs = head:match("^GNX(%d+);([FE]);([^;]*);([^;]*);([AHN]);(%u*);(%d+);(%d+);(.*)$")
  if not v then return nil, "format" end
  local out = { version = tonumber(v), game = game, name = name, realm = realm, faction = fac, class = cls,
    level = tonumber(lv), stamp = tonumber(stamp), profs = {} }
  for piece in (profs .. "/"):gmatch("([^/]*)/") do
    if piece ~= "" then
      local skill, rank, max, list = piece:match("^(%d+):(%d+):(%d+):([%w,]*)$")
      if not skill then return nil, "format" end
      local p = { skill = tonumber(skill), rank = tonumber(rank), max = tonumber(max), spells = {} }
      for code in list:gmatch("%w+") do p.spells[#p.spells + 1] = ns.UnB36(code) end
      out.profs[#out.profs + 1] = p
    end
  end
  return out
end

---------------------------------------------------------------------------
-- Copy box: a dialog with a text the player selects and copies (Ctrl+C). Also used by the shopping list. (02.11.2026, StyleKit 2
-- step 4) DonCore's Kit.ShowCopy, the same box for every Don addon.
---------------------------------------------------------------------------
function ns.ShowCopyBox(title, hint, text)
  return ns.Kit.ShowCopy(title, hint, text, { selectAll = L["Select all"], close = L["Close"] })
end

function ns.CopyBox() return ns.Kit._copy end -- (tests)

function ns.ShowExport()
  local text, n = ns.ExportText()
  if n == 0 then
    ns.Print(L["Nothing to export yet: open your profession window once."])
    return false
  end
  ns.ShowCopyBox(L["Export for the guild website"],
    L["%d characters. Press Ctrl+C to copy, then paste the text on the guild website."]:format(n), text)
  return true
end

---------------------------------------------------------------------------
-- Recipe report (/gn recipes): what the game showed that Guildon's data lacks, for the Guildon authors.
-- Line 1 "GNR1;<F or E>;<version>;<client build>", then one line per recipe, sorted by spell:
-- "<spell>;<profession>;<item>;<count>;<reagent:n,reagent:n>;<n new | r reagents missing in the data>".
-- Sources: the own windows (ns.db.found, ns.db.learned) and what guild members share (kinds "prof" and "seen"). tools/guildon_report.py reads it.
---------------------------------------------------------------------------
function ns.RecipeReport()
  local idx = ns.CraftIndex()
  local prof = {}
  for _, p in pairs(idx.owners) do
    for skill, e in pairs(p.skills) do for id in pairs(e.recipes) do prof[id] = prof[id] or skill end end
  end
  for id, skill in pairs(ns.db.found) do prof[id] = prof[id] or skill end
  for id, skill in pairs(idx.seen or {}) do prof[id] = prof[id] or skill end
  local ids = {}
  for id in pairs(prof) do if ns.NeedsDetails(id) then ids[#ids + 1] = id end end
  for id in pairs(idx.details) do if not prof[id] and ns.NeedsDetails(id) then ids[#ids + 1] = id end end
  table.sort(ids)
  local build = select(2, ns.Call(GetBuildInfo)) or "?"
  local lines = { ("GNR1;%s;%s;%s"):format(ns.ERA and "E" or "F", ns.VERSION or "?", tostring(build)) }
  local n = 0
  for _, id in ipairs(ids) do
    local d = idx.details[id]
    local reag = {}
    if d then for j = 1, #(d[3] or {}), 2 do reag[#reag + 1] = d[3][j] .. ":" .. d[3][j + 1] end end
    local r = ns.RECIPES[id]
    local skill = prof[id] or (r and r[1]) or 0
    lines[#lines + 1] = ("%d;%d;%d;%d;%s;%s"):format(id, skill, d and d[1] or 0, d and d[2] or 0, table.concat(reag, ","),
      r and "r" or "n")
    n = n + 1
  end
  return table.concat(lines, "\n"), n
end

function ns.ShowRecipeReport()
  local text, n = ns.RecipeReport()
  if n == 0 then
    ns.Print(L["Guildon Crafts knows all recipes the game has shown so far. Open your profession windows to look again."])
    return false
  end
  ns.ShowCopyBox(L["Recipes Guildon Crafts does not know yet"],
    L["%d recipes. Press Ctrl+C to copy and send the text to the Guildon Crafts authors (Discord or CurseForge)."]:format(n), text)
  return true
end
