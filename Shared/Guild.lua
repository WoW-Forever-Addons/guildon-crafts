local addonName, ns = ...

---------------------------------------------------------------------------
-- The guild: name, own rank, members with online state. Names are kept as "Name-Realm" (ns.FullName).
-- The roster comes from the game after a request (C_GuildInfo.GuildRoster, on Era also GuildRoster) and
-- GUILD_ROSTER_UPDATE; requests at most every 15 s, while the window is open every 60 s.
-- (21.11.2026, Ruckler: Guildon, Crafts and Groups each rebuilt the roster in the same frame) one roster for all loaded
-- Guildon parts: the first copy of this file makes the global GuildSharedRoster (like GuildonLauncher), the others sign
-- in. One request, one timer and one rebuild for all; each part then runs its own PruneGone, OnRosterChanged and
-- OnMemberOnline/Offline. The example members of /gn demo stay with the part that shows them. A copy with another
-- ROSTER_PROTO keeps a roster of its own.
---------------------------------------------------------------------------
local ROSTER_PROTO = 1
local R = rawget(_G, "GuildSharedRoster")
if type(R) ~= "table" or R.proto ~= ROSTER_PROTO then
  R = { proto = ROSTER_PROTO, members = {}, byName = {}, spare = {}, gen = 0, sorted = true, copies = {},
    lastRequest = -100, pending = false, wasOnline = {}, spareOnline = {}, lastAt = {} }
  if rawget(_G, "GuildSharedRoster") == nil then GuildSharedRoster = R end
end
-- (22.11.2026, Ruckler) fields an older copy of this file did not make (it may have made the shared roster)
R.full, R.fullN, R.memberGen = R.full or {}, R.fullN or 0, R.memberGen or 0
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

-- (21.11.2026, Ruckler) Realm() runs for every name (roster, every addon message): the realm the client gave is kept
-- for the session (it never changes before a reload); while the client gives none it is asked again at most once a
-- second, and the count over the saved names below runs once until the saved data or the realm changes
local realmKnown, realmAskedAt = nil, -100
local guessDb, guessChars, guessSets, guess, guessAt
local function Now() return type(GetTime) == "function" and GetTime() or 0 end
local function Realm()
  local db = type(ns.db) == "table" and ns.db or nil
  local r = realmKnown
  if not r then
    local now = Now()
    if now - realmAskedAt >= 1 or now < realmAskedAt then
      realmAskedAt = now
      if not SurnameClient() then
        local _, rr = ns.Call(UnitFullName, "player")
        r = ns.Str(rr)
      end
      if not r then r = ns.Str(ns.Call(GetNormalizedRealmName)) end
      if not r then r = ns.Str(ns.Call(GetRealmName)) end
      r = r and r:gsub("[%s%-]", "")
      if r == "" then r = nil end
      realmKnown = r
    end
  end
  if r then
    if db and db.realmName ~= r then db.realmName = r end
    return r
  end
  -- (Daniel 21.11.2026, laptop: "Mairi Wipeborn" twice in a tooltip) the client can give an empty realm name for a while;
  -- then the last realm seen, else the realm most saved names carry, never "?" while one is known
  if db and type(db.realmName) == "string" and db.realmName ~= "" then return db.realmName end
  local chars = db and type(db.chars) == "table" and db.chars or nil
  local sets = db and type(db.sets) == "table" and db.sets or nil
  -- "?" is counted again after 10 s: names with a realm may have come in since
  if guess and guessDb == db and guessChars == chars and guessSets == sets and (guess ~= "?" or Now() - guessAt < 10) then
    return guess
  end
  local count, best, bn = {}, nil, 0
  local function Add(name)
    local x = type(name) == "string" and name:match("%-([^%-]+)$")
    if x and x ~= "?" then count[x] = (count[x] or 0) + 1 if count[x] > bn then best, bn = x, count[x] end end
  end
  for k in pairs(chars or {}) do Add(k) end
  for _, set in pairs(sets or {}) do if type(set) == "table" then Add(set.o) end end
  guessDb, guessChars, guessSets, guess, guessAt = db, chars, sets, best or "?", Now()
  return guess
end
-- (tests, and ns.ForgetMyName) the realm is asked again at the next name
local function ForgetRealm() realmKnown, realmAskedAt, guess = nil, -100, nil end

function ns.FullName(name)
  name = ns.Str(name)
  if not name then return nil end
  name = name:gsub("^%s+", ""):gsub("%s+$", "")
  if name:find("-", 1, true) then return name end
  local realm = Realm()
  -- (21.11.2026, Ruckler) a name with "-?" may get saved: ns.FixUnknownRealm runs at the next login
  if realm == "?" and type(ns.db) == "table" then ns.db.realmDirty = true end
  return name .. "-" .. realm
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
function ns.ForgetMyName() myName = nil ForgetRealm() end -- (tests)

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
  -- (21.11.2026, Ruckler) shared by all parts: a forced request of another part in the same second counts too
  if now - R.lastRequest < (force and 1 or 15) and now >= R.lastRequest then return end
  R.lastRequest = now
  if C_GuildInfo and type(C_GuildInfo.GuildRoster) == "function" then
    ns.Call(C_GuildInfo.GuildRoster)
  elseif type(GuildRoster) == "function" then
    ns.Call(GuildRoster)
  end
end

-- (21.11.2026, Ruckler) the shared rebuild: the member tables are kept and filled anew, the list is sorted only when
-- someone asks for it (ns.Members), the realm is known once for all names, the last-online days are asked again only
-- for members who were online before or every 5 minutes (they count whole days)
-- (22.11.2026, Ruckler, DonMonitor report: timer Guild.lua:325 avg 27 ms every 4-6 s) the full name of a roster name is
-- kept while the realm stays the same and the short name of a member already known is not made again (two gsub, a find
-- and a match per member and rebuild before); the counts the game gives (members, online) are kept with the time, so
-- RosterChanged can tell cheaply whether anything changed; R.memberGen counts the rebuilds that changed who is a member
local LAST_ONLINE_AGAIN = 300
local function ByShort(a, b) return R.byName[a].short < R.byName[b].short end
local function Counts()
  if not ns.InGuild() then return 0, 0 end
  local total, online = ns.Call(GetNumGuildMembers)
  return ns.Num(total) or 0, ns.Num(online)
end
-- (24.11.2026, Ruckler, DonMonitor on the laptop: timer Guild.lua:380 avg 14.6 ms, max 22.5 ms about every 30 s) the
-- rebuild runs in slices: members are read until SLICE_MS have passed (SLICE_N members where the client has no
-- debugprofilestop), the next ones in the next frame. The new list and lookup are made aside and swapped in at the end,
-- so the parts read the last whole roster until then. A GUILD_ROSTER_UPDATE while slices run (the game's list may have
-- changed under the indexes) starts the list again; after AGAIN_MAX such starts the rest runs in one go. Then each part
-- is told in a frame of its own (who came online or went offline, then its prune and its page).
local SLICE_MS, SLICE_N, AGAIN_MAX = 4, 150, 3
local function Begin(b)
  local list = R.spareList
  if type(list) ~= "table" or list == R.members then list = {} end
  local by = R.spareBy
  if type(by) ~= "table" or by == R.byName or by == R.spare then by = {} end
  for k in pairs(by) do by[k] = nil end
  b.list, b.by, b.prev, b.n, b.i = list, by, R.byName, 0, 1
  b.t = GetTime()
  b.total, b.onlineCount = Counts()
  b.last = math.min(b.total, 1000)
  local realm, cache = Realm(), R.full
  b.realm, b.sameRealm = realm, R.fullRealm == realm
  if not b.sameRealm or R.fullN > 3000 then
    for k in pairs(cache) do cache[k] = nil end
    R.fullRealm, R.fullN = realm, 0
  end
  b.before, b.joined = #R.members, false
end
-- one member of the game's list (index i) into the new list
local function Read(b, i)
  local ok, name, rank, rankIndex, level, class, zone, _, _, online, _, classFile = pcall(GetGuildRosterInfo, i)
  local cache = R.full
  local full = ok and type(name) == "string" and cache[name]
  if ok and not full then
    full = ns.FullName(name)
    if full and b.realm ~= "?" and type(name) == "string" then cache[name] = full R.fullN = R.fullN + 1 end
  end
  local by = b.by
  if not full or by[full] then return end
  local m = b.prev[full]
  local wasOff = m ~= nil and not m.online
  if not m then m, b.joined = {}, true end
  if not (b.sameRealm and m.short and m.name == full) then m.short = ns.ShortName(full) end
  m.name, m.rank, m.rankIndex = full, ns.Str(rank) or "", ns.Num(rankIndex) or 99
  m.level, m.class, m.classFile = ns.Num(level) or 0, ns.Str(class) or "", ns.Str(classFile) or ""
  m.zone, m.online = ns.Str(zone) or "", online == true or online == 1
  local lastAt, t = R.lastAt, b.t
  if m.online or not GetGuildRosterLastOnline then
    m.lastOnline = nil
    lastAt[full] = nil
  elseif not (wasOff and m.lastOnline and lastAt[full] and t - lastAt[full] < LAST_ONLINE_AGAIN and t >= lastAt[full]) then
    m.lastOnline = nil
    local okL, years, months, days = pcall(GetGuildRosterLastOnline, i)
    if okL and ns.Num(days) then m.lastOnline = (ns.Num(years) or 0) * 365 + (ns.Num(months) or 0) * 30 + days end
    lastAt[full] = t
  end
  local n = b.n + 1
  b.n = n
  b.list[n] = m
  by[full] = m
end
-- members until the time is up (whole: all that are left); true when the list is read
local function Slice(b, whole)
  local clock = not whole and type(debugprofilestop) == "function" and debugprofilestop or nil
  local t0 = clock and clock()
  local i, last, k = b.i, b.last, 0
  while i <= last do
    Read(b, i)
    i, k = i + 1, k + 1
    if not whole and k % 10 == 0 and i <= last then
      if clock then
        if clock() - t0 >= SLICE_MS then break end
      elseif k >= SLICE_N then
        break
      end
    end
  end
  b.i = i
  return i > last
end
-- the list is read: swapped in; who came online or went offline (the lists up, down)
local function Finish(b)
  local list, by, prev, n = b.list, b.by, b.prev, b.n
  for i = #list, n + 1, -1 do list[i] = nil end
  for full in pairs(prev) do if not by[full] then R.lastAt[full] = nil end end
  R.spareList, R.members = R.members, list
  R.spareBy, R.byName = prev, by
  R.gen, R.sorted = R.gen + 1, false
  if b.joined or n ~= b.before then R.memberGen = R.memberGen + 1 end
  R.seenTotal, R.seenOnline, R.builtAt, R.skipped = b.total, b.onlineCount, b.t, false
  -- who just came online (not at the first roster of the session) and who just went offline
  local was, now = R.wasOnline, R.spareOnline
  for k in pairs(now) do now[k] = nil end
  local first = next(was) == nil
  local up, down
  for i = 1, n do
    local m = list[i]
    now[m.name] = m.online
    if m.online and was[m.name] == false and not first then up = up or {} up[#up + 1] = m.name end
    if not m.online and was[m.name] == true then down = down or {} down[#down + 1] = m.name end
  end
  R.wasOnline, R.spareOnline = now, was
  -- in the order of the sorted list, as before
  if up and #up > 1 then table.sort(up, ByShort) end
  if down and #down > 1 then table.sort(down, ByShort) end
  return up, down
end
-- the parts are told one per frame: moved of each, then (after a rebuild of RosterChanged) changed of each
local function Tell(steps, k)
  local s = steps[k]
  if not s then return end
  -- the next one first: an error in this part does not keep the others from being told
  if steps[k + 1] then ns.After(0, function() Tell(steps, k + 1) end) end
  s()
end
-- a rebuild: notify = the parts' changed() follow (RosterChanged); whole = all now, the parts' moved() too (tests,
-- /gn demo). The running rebuild is R.build (shared by the parts); R.again: an update came while it ran.
local function Rebuild(notify, whole)
  local b = R.build
  if b and whole then
    -- a rebuild in slices runs: done now from the start (the list may have changed), its parts told as it would have
    b.whole, R.again = true, true
    b.step()
    return
  end
  if b then
    -- (RosterChanged waits for a running one, so this should not happen) the running one starts again and tells the parts
    R.again, b.notify = true, b.notify or notify
    return
  end
  b = { notify = notify, whole = whole, again = 0 }
  R.build, R.again = b, false
  Begin(b)
  local function Step()
    if R.build ~= b then return end
    b.at = GetTime()
    if R.again then
      R.again = false
      b.again = b.again + 1
      Begin(b)
    end
    if not Slice(b, b.whole or b.again >= AGAIN_MAX) then ns.After(0, Step) return end
    R.build = nil
    if b.notify then R.pending = false end
    local up, down = Finish(b)
    local steps = {}
    for _, c in ipairs(R.copies) do
      if b.whole then c.moved(up, down) else steps[#steps + 1] = function() c.moved(up, down) end end
    end
    if b.notify then for _, c in ipairs(R.copies) do steps[#steps + 1] = c.changed end end
    Tell(steps, 1)
  end
  b.step = Step
  Step()
end

-- this part's view: the shared roster, with the example members of /gn demo (Demo.lua) added when they are on; those
-- are only on this screen, never sent to or accepted from anyone
local NONE = {}
local view, viewBy, viewGen, viewDemo, viewSorted
local function View()
  local demo = ns.DemoMembers and ns.DemoMembers() or NONE
  if #demo == 0 then return R.members, nil end
  if viewGen ~= R.gen or viewDemo ~= demo or not view then
    view, viewBy = {}, {}
    for i, m in ipairs(R.members) do view[i] = m end
    for _, m in ipairs(demo) do
      if not R.byName[m.name] and not viewBy[m.name] then view[#view + 1] = m viewBy[m.name] = m end
    end
    viewGen, viewDemo, viewSorted = R.gen, demo, false
  end
  return view, viewBy
end
local function Online(a, b)
  if a.online ~= b.online then return a.online end
  return a.short < b.short
end

-- online first, then by name
function ns.Members()
  local list = View()
  if list == R.members then
    if not R.sorted then table.sort(list, Online) R.sorted = true end
  elseif not viewSorted then
    table.sort(list, Online) viewSorted = true
  end
  return list
end
local function Lookup(full)
  local m = R.byName[full]
  if m then return m end
  local _, by = View()
  return by and by[full] or nil
end
function ns.Member(full) return full and Lookup(full) or nil end
function ns.IsMember(full) return full ~= nil and (Lookup(full) ~= nil or full == ns.MyName()) end
function ns.IsOnline(full) local m = Lookup(full or "") return m and m.online or full == ns.MyName() end

-- (22.11.2026, Ruckler) is there a roster at all, without sorting the list (ns.PruneGone after every rebuild)
function ns.HasRoster() return #View() > 0 end

function ns.MemberCounts()
  local members = View()
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
-- (22.11.2026, Ruckler, DonMonitor report: timer Guild.lua:325 avg 27 ms every 4-6 s, all windows closed) with the
-- windows closed an update is looked at cheaply first: while the game's counts of members and of members online are
-- the ones of the last rebuild, nothing runs (no timer) until ROSTER_IDLE seconds have passed (zones, levels, one
-- member going as another comes); ROSTER_BLIND where the client gives no count of members online. Changed counts
-- rebuild after ROSTER_SLOW seconds as before, yet at most every ROSTER_GAP seconds. What was skipped is caught up
-- when a window opens (ns.RosterWanted) and when a guild message comes from a name the roster does not have
-- (ns.RosterMiss, GuildShared/Comm.lua). With a window open and before the first roster nothing changed.
local ROSTER_SLOW = 3
local ROSTER_GAP, ROSTER_IDLE, ROSTER_BLIND, MISS_AGAIN, PRUNE_AGAIN = 10, 60, 15, 30, 600
local prunedGen, prunedAt = nil, -1000

-- (21.11.2026, Ruckler) this part signs in to the shared roster: asked whether its window is open, told who came online
-- or went offline after every rebuild, and told when the roster changed (its prune and its open page)
R.copies[#R.copies + 1] = {
  id = addonName,
  open = function() return ns.WindowOpen and ns.WindowOpen() and true or false end,
  empty = function() return #View() == 0 end,
  moved = function(up, down)
    local me = (up or down) and ns.MyName()
    for _, name in ipairs(up or NONE) do
      if ns.OnMemberOnline and name ~= me then ns.SafeCall("member online", ns.OnMemberOnline, name) end
    end
    -- (04.11.2026) and who just went offline (Guildon's map takes him off at once)
    for _, name in ipairs(down or NONE) do
      if ns.OnMemberOffline and name ~= me then ns.SafeCall("member offline", ns.OnMemberOffline, name) end
    end
  end,
  -- (22.11.2026, Ruckler) the prune only when who is a member changed, else every 10 minutes (it has its own minute too)
  changed = function()
    if not ns.db then return end
    local t = GetTime()
    if ns.PruneGone and (prunedGen ~= R.memberGen or t - prunedAt >= PRUNE_AGAIN or t < prunedAt) then
      prunedGen, prunedAt = R.memberGen, t
      ns.SafeCall("prune", ns.PruneGone)
    end
    if ns.OnRosterChanged then ns.SafeCall("roster", ns.OnRosterChanged) end
  end,
}

-- force: not looked at cheaply first (login, the own guild changed, a window opened, an unknown sender)
-- (24.11.2026) R.why counts what started the rebuilds (/dump GuildSharedRoster.why): counts (the game's counts of members
-- or members online changed), idle (a minute without a change), force (login, guild, window, unknown sender), open (a
-- window open or no roster yet), again (an update while the slices ran)
local function Why(k) local w = R.why if type(w) ~= "table" then w = {} R.why = w end w[k] = (w[k] or 0) + 1 end
local function RosterChanged(force)
  local t = GetTime()
  local b = R.build
  -- a rebuild runs: the game's list may have changed under it, it starts again (an error left it behind: dropped)
  if b and b.at and t - b.at < 5 and t >= b.at then R.again = true Why("again") return end
  if b then R.build = nil R.pending = false end
  if R.pending and R.pendingAt and t - R.pendingAt < 30 and t >= R.pendingAt then return end
  local fast = false
  for _, c in ipairs(R.copies) do
    if c.open() or c.empty() then fast = true break end
  end
  local delay = fast and 0.5 or ROSTER_SLOW
  local why = fast and "open" or (force == true and "force") or nil
  if not fast and force ~= true then
    local age = R.builtAt and t - R.builtAt or -1
    if age >= 0 then
      local total, online = Counts()
      local same = total == R.seenTotal and online == R.seenOnline
      if same and age < (online and ROSTER_IDLE or ROSTER_BLIND) then
        R.skipped = true
        return
      end
      why = same and "idle" or "counts"
      if ROSTER_GAP - age > delay then delay = ROSTER_GAP - age end
    end
  end
  R.pending, R.pendingAt = true, t
  ns.After(delay, function()
    Why(why or "first")
    Rebuild(true)
  end)
end

-- a window opens: updates skipped while all were closed are caught up at once (half a second, as with every update
-- while it is open)
function ns.RosterWanted()
  if R.skipped then RosterChanged(true) end
end
-- a message in the guild channel from a name the roster does not have (he just joined): asked for and rebuilt soon,
-- at most every MISS_AGAIN seconds
-- (24.11.2026) and each name at most every MISS_NAME seconds: a sender the roster still does not have after the rebuild
-- (a name written another way, a member past the first 1000) asked for a rebuild every 30 s before; the last names are
-- kept in R.missNames (/dump GuildSharedRoster.missNames)
local MISS_NAME = 600
function ns.RosterMiss(name)
  local t = GetTime()
  if R.missAt and t - R.missAt < MISS_AGAIN and t >= R.missAt then return end
  if type(name) == "string" then
    local seen = R.missBy
    if type(seen) ~= "table" or (R.missByN or 0) > 200 then seen = {} R.missBy, R.missByN = seen, 0 end
    local at = seen[name]
    if at and t - at < MISS_NAME and t >= at then return end
    if not at then R.missByN = (R.missByN or 0) + 1 end
    seen[name] = t
    local last = R.missNames
    if type(last) ~= "table" then last = {} R.missNames = last end
    table.insert(last, 1, name)
    last[6] = nil
  end
  R.missAt = t
  ns.RequestRoster()
  RosterChanged(true)
end

ns.On("GUILD_ROSTER_UPDATE", function() RosterChanged() end)
ns.On("PLAYER_GUILD_UPDATE", function() ns.RequestRoster(true) RosterChanged(true) end)
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

-- (Daniel 21.11.2026) names saved or received while the realm was unknown ("Mairi Wipeborn-?") move to the realm once it
-- is known, so one character is never listed twice; an entry under the right name wins
-- (21.11.2026, Ruckler) at login only when needed: once over the whole saved data (db.realmFix), then only after a name
-- with "-?" was made (ns.FullName) or received (GuildShared/Comm.lua) (db.realmDirty)
function ns.FixUnknownRealm()
  local db = ns.db
  if type(db) ~= "table" then return false end
  local realm = Realm()
  if realm == "?" then return false end
  local map, any = {}, false
  local function Add(name)
    if type(name) == "string" and name:sub(-2) == "-?" and #name > 2 then map[name] = name:sub(1, -3) .. "-" .. realm any = true end
  end
  for _, t in pairs(db) do
    if type(t) == "table" then
      for k, v in pairs(t) do Add(k) if type(v) == "table" then Add(v.o) end end
    end
  end
  if any then Rename(db, map, 0) ns.ForgetMyName() end
  db.realmFix, db.realmDirty = 1, nil
  return any
end

ns.On("PLAYER_LOGIN", function()
  ns.SafeCall("surnames", ns.MigrateSurnames)
  if ns.db.realmFix ~= 1 or ns.db.realmDirty then ns.SafeCall("realm", ns.FixUnknownRealm) end
  ns.RequestRoster(true) RosterChanged(true)
end)
-- (21.11.2026, Ruckler) one request for all parts (ns.RequestRoster keeps the time in the shared roster)
ns.On("PLAYER_ENTERING_WORLD", function() ns.RequestRoster() end)

function ns.RebuildRoster() Rebuild(false, true) end -- (tests, /gn demo): all at once
