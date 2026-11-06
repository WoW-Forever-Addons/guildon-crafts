local _, ns = ...

---------------------------------------------------------------------------
-- The guild: name, own rank, members with online state. Names are kept as "Name-Realm" (ns.FullName).
-- The roster comes from the game after a request (C_GuildInfo.GuildRoster, on Era also GuildRoster) and
-- GUILD_ROSTER_UPDATE; requests at most every 15 s, while the window is open every 60 s.
---------------------------------------------------------------------------
local members, byName = {}, {}
local lastRequest, rebuildPending = -100, false
local myName

-- (05.11.2026, Daniel's /gn names on WoW Forever) Forever has surnames (C_PlayerInfo.ShouldDisplaySurname() true):
-- UnitName and UnitFullName give the surname where other clients give the realm ("Mae", "Wipeborn"), the roster and the
-- senders of addon messages give "Elfi Crowsong" and "Ratloff Ashbloom" (first name, space, surname, no realm), and a
-- whisper needs that whole name ("/w Ratloff Ashbloom" works). The realm is GetNormalizedRealmName()
-- ("CAMWOWEU4Realm7PvE"). So a member is "<first> <surname>-<realm>" there, shown and whispered as "<first> <surname>".
-- (05.11.2026, Siyo) with the surnames hidden in the game's options ShouldDisplaySurname() is false, yet UnitFullName still
-- gives the surname in the realm's place and the roster and the senders still say "Siyo Fren": the surname became the
-- realm ("Rectan Buckhammer-Fren") and whispers failed ("no player named ..."). So a client that knows the function counts
-- as one with surnames also when the second value of UnitFullName is not the own realm; its realm never comes from there.
local function SurnameClient()
  return C_PlayerInfo ~= nil and type(C_PlayerInfo.ShouldDisplaySurname) == "function"
end
local function RealmKey(s) s = ns.Str(s) return s and (s:gsub("[%s%-]", "")) or nil end
local function Surnames()
  if not SurnameClient() then return false end
  if ns.Call(C_PlayerInfo.ShouldDisplaySurname) == true then return true end
  local _, second = ns.Call(UnitFullName, "player")
  second = RealmKey(second)
  local realm = RealmKey(ns.Call(GetNormalizedRealmName)) or RealmKey(ns.Call(GetRealmName))
  if not second or not realm then return false end
  return second ~= realm and second ~= RealmKey(ns.Call(GetRealmName))
end
ns.Surnames = Surnames

local function Realm()
  local r
  if not SurnameClient() then
    local _, rr = ns.Call(UnitFullName, "player")
    r = ns.Str(rr)
  end
  if not r then r = ns.Str(ns.Call(GetNormalizedRealmName)) end
  if not r then r = ns.Str(ns.Call(GetRealmName)) end
  return r and r:gsub("[%s%-]", "") or "?"
end

function ns.FullName(name)
  name = ns.Str(name)
  if not name then return nil end
  name = name:gsub("^%s+", ""):gsub("%s+$", "")
  if name:find("-", 1, true) then return name end
  return name .. "-" .. Realm()
end

-- the full name of a unit ("player", "NPC" in a trade, "target"): on Forever with the surname
function ns.UnitFull(unit)
  local n, r = ns.Call(UnitName, unit)
  n, r = ns.Str(n), ns.Str(r)
  if not n then return nil end
  if Surnames() then return ns.FullName(r and (n .. " " .. r) or n) end
  return ns.FullName(r and (n .. "-" .. r) or n)
end

-- kept only once the realm is known: a name with "-?" from an early call never matched the own messages again
function ns.MyName()
  if not myName then
    local full = ns.UnitFull("player")
    if not full then return nil end
    if full:sub(-2) == "-?" then return full end
    myName = full
  end
  return myName
end
function ns.ForgetMyName() myName = nil end -- (tests)

function ns.ShortName(full)
  full = tostring(full or "")
  local n, r = full:match("^(.-)%-(.+)$")
  if n and r == Realm() then return n end
  return full
end

function ns.InGuild() return ns.Call(IsInGuild) and true or false end

-- guild name, own rank name, own rank index (0 = guild master)
function ns.GuildInfo()
  if not ns.InGuild() then
    if ns.demo then return ns.L["Example guild"], ns.L["Member"], 2 end
    return nil
  end
  local g, rank, idx = ns.Call(GetGuildInfo, "player")
  return ns.Str(g), ns.Str(rank), ns.Num(idx)
end

function ns.RequestRoster(force)
  if not ns.InGuild() then return end
  local now = GetTime()
  if not force and now - lastRequest < 15 then return end
  lastRequest = now
  if C_GuildInfo and type(C_GuildInfo.GuildRoster) == "function" then
    ns.Call(C_GuildInfo.GuildRoster)
  elseif type(GuildRoster) == "function" then
    ns.Call(GuildRoster)
  end
end

local wasOnline = {}
local function Rebuild()
  members, byName = {}, {}
  local total = ns.InGuild() and ns.Num(ns.Call(GetNumGuildMembers)) or 0
  for i = 1, math.min(total, 1000) do
    local ok, name, rank, rankIndex, level, class, zone, _, _, online, _, classFile = pcall(GetGuildRosterInfo, i)
    local full = ok and ns.FullName(name)
    if full and not byName[full] then
      local m = {
        name = full, short = ns.ShortName(full), rank = ns.Str(rank) or "", rankIndex = ns.Num(rankIndex) or 99,
        level = ns.Num(level) or 0, class = ns.Str(class) or "", classFile = ns.Str(classFile) or "",
        zone = ns.Str(zone) or "", online = online == true or online == 1,
      }
      if not m.online and GetGuildRosterLastOnline then
        local okL, years, months, days = pcall(GetGuildRosterLastOnline, i)
        if okL and ns.Num(days) then m.lastOnline = (ns.Num(years) or 0) * 365 + (ns.Num(months) or 0) * 30 + days end
      end
      members[#members + 1] = m
      byName[full] = m
    end
  end
  -- example members of /gn demo (Demo.lua): only on this screen, never sent to or accepted from anyone
  for _, m in ipairs(ns.DemoMembers and ns.DemoMembers() or {}) do
    if not byName[m.name] then members[#members + 1] = m byName[m.name] = m end
  end
  table.sort(members, function(a, b)
    if a.online ~= b.online then return a.online end
    return a.short < b.short
  end)
  -- who just came online (not at the first roster of the session)
  local first = next(wasOnline) == nil
  local now = {}
  for _, m in ipairs(members) do
    now[m.name] = m.online
    if m.online and wasOnline[m.name] == false and not first and ns.OnMemberOnline and m.name ~= ns.MyName() then
      ns.SafeCall("member online", ns.OnMemberOnline, m.name)
    end
    -- (04.11.2026) and who just went offline (Guildon's map takes him off at once)
    if not m.online and wasOnline[m.name] == true and ns.OnMemberOffline and m.name ~= ns.MyName() then
      ns.SafeCall("member offline", ns.OnMemberOffline, m.name)
    end
  end
  wasOnline = now
end

function ns.Members() return members end
function ns.Member(full) return full and byName[full] or nil end
function ns.IsMember(full) return full ~= nil and (byName[full] ~= nil or full == ns.MyName()) end
function ns.IsOnline(full) local m = byName[full or ""] return m and m.online or full == ns.MyName() end

function ns.MemberCounts()
  local online, guildon, guildonOnline = 0, 0, 0
  for _, m in ipairs(members) do
    if m.online then online = online + 1 end
    if ns.db.peers[m.name] or m.demo then
      guildon = guildon + 1
      if m.online then guildonOnline = guildonOnline + 1 end
    end
  end
  return #members, online, guildon, guildonOnline
end

-- Blizzard's class colours as the modern client has them, fixed (Daniel 25.10.: "eindeutige Blizzard-Klassenfarben"):
-- Classic Era's RAID_CLASS_COLORS gives the shaman the paladin's pink, so the two would look the same on the map.
ns.CLASS_RGB = {
  WARRIOR = { 0.78, 0.61, 0.43 }, PALADIN = { 0.96, 0.55, 0.73 }, HUNTER = { 0.67, 0.83, 0.45 }, ROGUE = { 1.00, 0.96, 0.41 },
  PRIEST = { 1.00, 1.00, 1.00 }, DEATHKNIGHT = { 0.77, 0.12, 0.23 }, SHAMAN = { 0.00, 0.44, 0.87 }, MAGE = { 0.25, 0.78, 0.92 },
  WARLOCK = { 0.53, 0.53, 0.93 }, MONK = { 0.00, 1.00, 0.60 }, DRUID = { 1.00, 0.49, 0.04 }, DEMONHUNTER = { 0.64, 0.19, 0.79 },
  EVOKER = { 0.20, 0.58, 0.50 },
}
function ns.ClassRGB(classFile)
  local c = ns.CLASS_RGB[classFile or ""]
  if c then return c[1], c[2], c[3] end
end

-- class colour of a member as a hex string (fallback: the kit's primary text)
function ns.ClassHex(classFile)
  local r, g, b = ns.ClassRGB(classFile)
  if r then return ("ff%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5)) end
  return ns.Style.Hex("textPrimary")
end

-- (31.10.2026, LEISTUNG_PRUEFUNG 21) a big guild fires GUILD_ROSTER_UPDATE often: rebuilt at most every ROSTER_SLOW
-- seconds while the window is closed, every half second while it is open and before the first roster
local ROSTER_SLOW = 3
local function RosterChanged()
  if rebuildPending then return end
  rebuildPending = true
  local open = ns.WindowOpen and ns.WindowOpen()
  ns.After((open or #members == 0) and 0.5 or ROSTER_SLOW, function()
    rebuildPending = false
    Rebuild()
    if ns.PruneGone then ns.SafeCall("prune", ns.PruneGone) end
    if ns.OnRosterChanged then ns.OnRosterChanged() end
  end)
end

ns.On("GUILD_ROSTER_UPDATE", RosterChanged)
ns.On("PLAYER_GUILD_UPDATE", function() ns.RequestRoster(true) RosterChanged() end)
-- (05.11.2026) once on WoW Forever: the own characters were kept as "Mae-Wipeborn" (first name, the surname taken for
-- the realm); now "Mae Wipeborn-<realm>". Every key and text of the saved data that names one of them is renamed
-- (characters, sets, professions, wishes "<owner>#<id>", alts "1;A;B"); an entry under the new name wins. Other
-- members' data under old names is dropped later as non-members and comes again from the guild.
local function Swap(v, map)
  if type(v) ~= "string" then return v end
  for old, new in pairs(map) do
    local from = 1
    while true do
      local a, b = v:find(old, from, true)
      if not a then break end
      local before, after = v:sub(a - 1, a - 1), v:sub(b + 1, b + 1)
      if (a == 1 or not before:find("[%w%-]")) and not after:find("[%w%-]") then
        v = v:sub(1, a - 1) .. new .. v:sub(b + 1)
        from = a + #new
      else
        from = b + 1
      end
    end
  end
  return v
end
local function Rename(t, map, depth)
  if depth > 12 then return end
  local moves = {}
  for k, v in pairs(t) do
    if type(v) == "table" then Rename(v, map, depth + 1)
    elseif type(v) == "string" then local nv = Swap(v, map) if nv ~= v then t[k] = nv end end
    local nk = Swap(k, map)
    if nk ~= k then moves[#moves + 1] = k end
  end
  for _, k in ipairs(moves) do
    local nk = Swap(k, map)
    if t[nk] == nil then t[nk] = t[k] end
    t[k] = nil
  end
end
function ns.MigrateSurnames()
  local db = ns.db
  if type(db) ~= "table" or db.surnames == 1 or not Surnames() then return false end
  local realm = Realm()
  if realm == "?" then return false end
  local map, any = {}, false
  for key in pairs(type(db.chars) == "table" and db.chars or {}) do
    local first, sur = tostring(key):match("^([^%s%-]+)%-([^%s%-]+)$")
    if first and sur ~= realm then map[key] = first .. " " .. sur .. "-" .. realm any = true end
  end
  if any then Rename(db, map, 0) end
  db.surnames = 1
  return true
end

ns.On("PLAYER_LOGIN", function()
  ns.SafeCall("surnames", ns.MigrateSurnames)
  ns.RequestRoster(true) RosterChanged()
end)
ns.On("PLAYER_ENTERING_WORLD", function() ns.RequestRoster() end)

function ns.RebuildRoster() Rebuild() end -- (tests)
