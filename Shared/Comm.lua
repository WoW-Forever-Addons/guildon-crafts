local _, ns = ...

---------------------------------------------------------------------------
-- Exchange core (GUILDON_PLAN.md "Wie es technisch geht"): no server, addon messages in the guild channel and by
-- whisper. Data comes in sets, key "<kind>:<owner>" (e.g. "info:Dedel-Realm"), each with stamp (time()) and checksum.
-- Only the fingerprints travel through the guild; a missing or older set is fetched by whisper from whoever announced it.
--
-- Messages (prefix ns.PREFIX, fields split by ":", the payload last):
--   H:<version>                            hello: in the guild at login, by whisper as the answer to a new peer
--   S:<kind>:<owner>:<stamp>:<sum>[;...]   "I have these sets" (in the guild when an own set changes, by whisper after H);
--                                          (31.10.2026, Runde 4) several entries per message, an empty owner = the one before
--   G:<kind>:<owner>[:<base>]              fetch request, by whisper to the one who announced it; base = checksum of the
--                                          version the asker holds (kinds with delta)
--   D:<kind>:<owner>:<stamp>:<sum>:<i>:<n>:<chunk>   one piece of a set, by whisper
--   X:<kind>:<owner>:<stamp>:<sum>:<i>:<n>:<chunk>   one piece of the changes from the asker's base to that set (delta kinds)
-- Received data are data, never code: unknown kinds are ignored, every kind checks its data (ns.RegisterKind).
-- Messages go through a queue with a pace of 4 per second; a throttled message is sent again (up to 5 tries).
-- (31.10.2026, Discord 30.10.: "addons could cause a DC") the client lets about 10 addon messages per prefix through at
-- once and then 1 a second (as in Questdon's Exchange.lua): the queue keeps to that itself (BURST, then 1 a second per
-- prefix), so a long queue (login in a big guild) is slowed down instead of throttled; a message the client still
-- throttles waits RETRY_WAIT seconds between further tries instead of being dropped after the fifth.
--
-- (31.10.2026, C4) An old prefix read along: an addon that sets ns.LEGACY_PREFIX (Guildon Crafts: "Guildon", Era "GuildonEra")
-- and ns.LEGACY_KINDS also talks to members of an older addon that still send its kinds under that prefix (Guildon 0.8).
-- Under the old prefix only these kinds count; a hello there (an old version, ns.IsLegacyVersion) is answered with the
-- own sets of these kinds and no hello of our own (the old addon would take our version for its own), announcements are
-- fetched there, requests answered there. Own changes go out under both prefixes once an old member was heard.
-- Without ns.LEGACY_PREFIX nothing of this happens (Guildon).
--
-- (31.10.2026, LEISTUNG_PRUEFUNG A3, A4) Login in a big guild: a newcomer's hello in the guild is answered by every peer
-- with its own sets, but the sets of offline owners only by RESPONDERS peers (the same ones on every client: the lowest
-- checksum of newcomer and peer among the peers heard this session); a hello by whisper (the answer to our own hello)
-- only gets our own sets. Short messages (H, P, W) go before data in their own queue. Sets and peers of members who
-- left the guild are forgotten after GONE_DAYS (ns.PruneGone) and never passed on.
--
-- (31.10.2026, LEISTUNG_PRUEFUNG Runde 4; Daniel: older versions do not count) The answer to a hello is a digest: the
-- announcements go out several per message (AnnounceAll). Kinds registered with delta = true (Crafts & Recipes: "prof",
-- "seen") keep the last changes of an own set (set.h, at most DELTA_STEPS steps and DELTA_MAX characters); who holds an
-- older version names its checksum in the request and gets only the changes (X), a newcomer gets the whole set (D).
-- A change is "keep <pre> characters at the front and <suf> at the end, put <mid> between" (Diff, Patch).
---------------------------------------------------------------------------
local PACE, MAX_TRIES, CHUNK, MAX_SET, FETCH_TIMEOUT = 0.25, 5, 200, 16000, 30
local BURST, REFILL, RETRY_WAIT, MAX_WAITS = 8, 1, 5, 12 -- (31.10.2026) per prefix: 8 at once, then 1 a second
local RESPONDERS, GONE_DAYS = 2, 30
local DELTA_STEPS, DELTA_MAX = 8, 2000 -- (Runde 4) changes kept per own delta set
local kinds = {}
local queue, fast, sending = {}, {}, false -- fast: hellos and map messages, before the data
local pending = {}   -- key -> { stamp, sum, n, parts = {}, got, from, t }
local answered = {}  -- peers answered this session
local live = {}      -- peers heard saying hello this session (they and we choose who answers a newcomer)
local legacyAnswered, legacyPeers = {}, {} -- the same under the old prefix: members of the older addon heard this session
local stats = { sent = 0, received = 0, retried = 0, dropped = 0, stored = 0, rejected = 0, paced = 0 }

function ns.RegisterKind(kind, def) kinds[kind] = def or {} end
function ns.CommStats() return stats, queue, pending, fast end -- (tests, diag)

local function Key(kind, owner) return kind .. ":" .. owner end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------
local function RawSend(msg, chat, target, prefix)
  local fn = C_ChatInfo and C_ChatInfo.SendAddonMessage or SendAddonMessage
  if type(fn) ~= "function" then return false end
  -- (05.11.2026) a whisper on the own realm goes to the name alone ("Ratloff Ashbloom" on Forever, as the game wants it)
  if chat == "WHISPER" and target and ns.Surnames and ns.Surnames() then target = ns.ShortName(target) end
  local ok, res = pcall(fn, prefix or ns.PREFIX, msg, chat, target)
  if not ok then return false end
  -- Forever (Retail) returns Enum.SendAddonMessageResult (0 = success), older clients true/false or nothing
  return res == nil or res == true or res == 0
end

-- (31.10.2026) the budget of a prefix: seconds to wait before the next message may go (0: it goes now, counted)
local budget = {} -- prefix -> { n = messages left, t = when counted }
local function Spend(prefix)
  local now = GetTime()
  local b = budget[prefix]
  if not b then b = { n = BURST, t = now } budget[prefix] = b end
  b.n, b.t = math.min(BURST, b.n + math.max(0, now - b.t) * REFILL), now
  if b.n >= 1 then b.n = b.n - 1 return 0 end
  return (1 - b.n) / REFILL
end
function ns.CommBudget(prefix) return budget[prefix or ns.PREFIX] end -- (tests)

-- (12.11.2026, Daniel: yellow lines "No player named 'Brokk Wetterhahn' is currently playing." after a member logged
-- out) whispers still waiting for him went out one by one. The game's "<name> has gone offline." and its first
-- "No player named ..." mark him; waiting whispers to him go, new ones are not queued until he is heard again.
local offline = {} -- full name -> true
local function Purge(q, name)
  for i = #q, 1, -1 do
    if q[i].chat == "WHISPER" and q[i].target == name then table.remove(q, i) stats.dropped = stats.dropped + 1 end
  end
end
function ns.CommOffline(name)
  if not name or name == ns.MyName() then return end
  offline[name] = true
  Purge(queue, name) Purge(fast, name)
  for key, p in pairs(pending) do if p.from == name then pending[key] = nil end end
end
function ns.CommIsOffline(name) return offline[name] == true end -- (tests)
local offlinePatterns = {} -- the game's text -> its pattern
local function Pattern(g)
  if type(g) ~= "string" then return nil end
  local pat = offlinePatterns[g]
  if not pat then
    pat = "^" .. g:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"):gsub("%%%%s", "(.+)") .. "$"
    offlinePatterns[g] = pat
  end
  return pat
end
ns.On("CHAT_MSG_SYSTEM", function(_, text)
  if type(text) ~= "string" then return end
  for i = 1, 2 do
    local pat = Pattern(i == 1 and ERR_FRIEND_OFFLINE_S or ERR_CHAT_PLAYER_NOT_FOUND_S)
    local who = pat and text:match(pat)
    if who then
      who = who:match("|h%[(.-)%]|h") or who
      local full = ns.FullName(who)
      if full and ns.IsMember(full) then ns.CommOffline(full) end
      return
    end
  end
end)

local function Pump()
  local q = fast[1] and fast or queue
  local item = q[1]
  if not item then sending = false return end
  local wait = Spend(item.prefix or ns.PREFIX)
  if wait > 0 then
    stats.paced = (stats.paced or 0) + 1
    ns.After(wait, Pump)
    return
  end
  table.remove(q, 1)
  -- (12.11.2026) a whisper to someone who logged out is dropped (each one would print "No player named ...")
  if item.chat == "WHISPER" and item.target and offline[item.target] then
    stats.dropped = stats.dropped + 1
    return Pump()
  end
  if RawSend(item.msg, item.chat, item.target, item.prefix) then
    stats.sent = stats.sent + 1
  else
    item.tries = item.tries + 1
    if item.tries < MAX_TRIES + MAX_WAITS then
      stats.retried = stats.retried + 1
      table.insert(q, 1, item)
      ns.After(item.tries < MAX_TRIES and PACE * 4 or RETRY_WAIT, Pump)
      return
    end
    stats.dropped = stats.dropped + 1
  end
  ns.After(PACE, Pump)
end

-- prefix: only for the old prefix (ns.LEGACY_PREFIX), else ns.PREFIX
function ns.Send(msg, chat, target, prefix)
  if type(msg) ~= "string" or #msg > 255 then return false end
  if chat == "GUILD" and not ns.InGuild() then return false end
  if chat == "WHISPER" and target and offline[target] then return false end
  -- positions: never more than one waiting (the newest counts)
  local tag = msg:sub(1, 2)
  if tag == "P:" then
    for i = #fast, 1, -1 do if fast[i].msg:sub(1, 2) == "P:" and fast[i].chat == chat then table.remove(fast, i) end end
  end
  local q = (tag == "P:" or tag == "W:" or tag == "H:") and fast or queue
  q[#q + 1] = { msg = msg, chat = chat, target = target, tries = 0, prefix = prefix }
  if not sending then sending = true ns.After(0, Pump) end
  return true
end

local function Announce(set, chat, target, prefix)
  ns.Send(("S:%s:%s:%d:%s"):format(set.k, set.o, set.t, set.s), chat, target, prefix)
end

-- (Runde 4) several sets in as few messages as possible, by owner; an owner equal to the one before is left empty
local function AnnounceAll(list, chat, target)
  table.sort(list, function(a, b) if a.o ~= b.o then return a.o < b.o end return a.k < b.k end)
  local msg, prev
  for _, set in ipairs(list) do
    local e = ("%s:%s:%d:%s"):format(set.k, set.o == prev and "" or set.o, set.t, set.s)
    if msg and #msg + 1 + #e <= 255 then
      msg = msg .. ";" .. e
    else
      if msg then ns.Send(msg, chat, target) end
      msg = ("S:%s:%s:%d:%s"):format(set.k, set.o, set.t, set.s)
    end
    prev = set.o
  end
  if msg then ns.Send(msg, chat, target) end
end

-- (Runde 4) the change from a to b: "<pre>,<suf>,<#mid>,<mid>"; Patch applies the change at pos of x to data
local function Diff(a, b)
  local la, lb, pre, suf = #a, #b, 0, 0
  local m = math.min(la, lb)
  while pre < m and a:byte(pre + 1) == b:byte(pre + 1) do pre = pre + 1 end
  while suf < m - pre and a:byte(la - suf) == b:byte(lb - suf) do suf = suf + 1 end
  local mid = b:sub(pre + 1, lb - suf)
  return ("%d,%d,%d,%s"):format(pre, suf, #mid, mid)
end

local function Patch(data, x, pos)
  local pre, suf, len, start = x:match("^(%d+),(%d+),(%d+),()", pos)
  pre, suf, len = tonumber(pre), tonumber(suf), tonumber(len)
  if not pre or pre + suf > #data or start + len - 1 > #x then return nil end
  return data:sub(1, pre) .. x:sub(start, start + len - 1) .. data:sub(#data - suf + 1), start + len
end

-- all changes of an own set from the version with checksum base on, or nil
local function Changes(set, base)
  for i, step in ipairs(set.h or {}) do
    if step.s == base then
      local out = {}
      for j = i, #set.h do out[#out + 1] = set.h[j].x end
      return table.concat(out)
    end
  end
end

local function LegacyKind(kind) return ns.LEGACY_KINDS ~= nil and ns.LEGACY_KINDS[kind] == true end

---------------------------------------------------------------------------
-- Own data
---------------------------------------------------------------------------
-- Store an own set; announced in the guild when it changed.
function ns.SetOwn(kind, data)
  local me = ns.MyName()
  if not me or not kinds[kind] or type(data) ~= "string" or #data > MAX_SET then return false end
  local key, sum = Key(kind, me), ns.Checksum(data)
  local old = ns.db.sets[key]
  if old and old.s == sum then return false end
  local set = { k = kind, o = me, t = time(), s = sum, d = data }
  if old and old.t >= set.t then set.t = old.t + 1 end
  -- (Runde 4) delta kinds keep the last changes; a change as long as half the set is not worth it
  if kinds[kind].delta and old and old.d then
    local x = Diff(old.d, data)
    if #x * 2 < #data then
      local h, size = { { s = old.s, x = x } }, #x
      for i = #(old.h or {}), 1, -1 do
        local step = old.h[i]
        if #h >= DELTA_STEPS or size + #step.x > DELTA_MAX then break end
        table.insert(h, 1, step)
        size = size + #step.x
      end
      set.h = h
    end
  end
  ns.db.sets[key] = set
  Announce(set, "GUILD")
  if ns.LEGACY_PREFIX and next(legacyPeers) and LegacyKind(kind) then Announce(set, "GUILD", nil, ns.LEGACY_PREFIX) end
  return true
end

function ns.GetSet(kind, owner) return ns.db.sets[Key(kind, owner)] end

function ns.SetsOf(kind)
  local out = {}
  for _, s in pairs(ns.db.sets) do if s.k == kind then out[#out + 1] = s end end
  for _, s in ipairs(ns.DemoSets and ns.DemoSets(kind) or {}) do out[#out + 1] = s end
  return out
end

-- Hello in the guild; force = also when already greeted (/gn sync)
local greeted = false
function ns.Hello(force)
  if not ns.InGuild() or (greeted and not force) then return end
  greeted = true
  local me = ns.MyName()
  if me then ns.db.peers[me] = { v = ns.VERSION, t = time() } end
  ns.Send("H:" .. ns.VERSION, "GUILD")
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
-- base: checksum of the version held (delta kinds); the answer may then be the changes only
local function Fetch(kind, owner, stamp, sum, from, prefix, base)
  local key = Key(kind, owner)
  local p = pending[key]
  if p and p.stamp >= stamp and GetTime() - p.t < FETCH_TIMEOUT then return end
  pending[key] = { stamp = stamp, sum = sum, parts = {}, got = 0, from = from, t = GetTime(), prefix = prefix, base = base }
  ns.Send("G:" .. key .. (base and ":" .. base or ""), "WHISPER", from, prefix)
end

-- a hello of a member of the older addon: only the own sets of the old kinds, by whisper, no hello back
local function OnLegacyHello(sender, version, chat)
  if not (ns.IsLegacyVersion and ns.IsLegacyVersion(version)) then return end
  legacyPeers[sender] = version:sub(1, 20)
  if legacyAnswered[sender] then return end
  legacyAnswered[sender] = true
  ns.After(chat == "GUILD" and (1 + math.random() * 3) or 0.5, function()
    local me = ns.MyName()
    for _, set in pairs(ns.db.sets) do
      if set.o == me and kinds[set.k] and LegacyKind(set.k) then Announce(set, "WHISPER", sender, ns.LEGACY_PREFIX) end
    end
  end)
end

-- (31.10.2026, A3) whether this client is one of the RESPONDERS that pass the offline owners' sets on to a newcomer:
-- every peer ranks the peers it heard (and itself) by the checksum of newcomer and name; a peer that knows fewer
-- answers rather more often, so the first in the guild's whole order always answers
local function Responder(newcomer)
  local me = ns.MyName()
  if not me then return false end
  local mine, better = ns.Checksum(newcomer .. me), 0
  for name in pairs(live) do
    if name ~= newcomer and name ~= me and ns.IsOnline(name) and ns.Checksum(newcomer .. name) < mine then
      better = better + 1
      if better >= RESPONDERS then return false end
    end
  end
  return true
end
ns.IsResponder = Responder -- (tests)
function ns.CommReset(name) answered[name] = nil end -- (tests)

local function OnHello(sender, version, chat)
  ns.db.peers[sender] = { v = version:sub(1, 20), t = time() }
  live[sender] = true
  if answered[sender] then return end
  answered[sender] = true
  -- answer by whisper after a short, spread delay: own version and the sets we hold (own ones; those whose owner is
  -- offline only to a newcomer in the guild and only as one of the responders)
  local guild = chat == "GUILD"
  local delay = guild and (1 + math.random() * 3) or 0.5
  ns.After(delay, function()
    if guild then ns.Send("H:" .. ns.VERSION, "WHISPER", sender) end
    local me = ns.MyName()
    local others = guild and Responder(sender)
    local list = {}
    for _, set in pairs(ns.db.sets) do
      local def = kinds[set.k]
      if def and set.o ~= sender and (set.o == me or (others and not def.direct and ns.IsMember(set.o) and not ns.IsOnline(set.o))) then
        list[#list + 1] = set
      end
    end
    AnnounceAll(list, "WHISPER", sender)
  end)
end

-- (31.10.2026, A4) sets and peers of members who left the guild: marked when the roster no longer has them, forgotten
-- GONE_DAYS later (back in the guild: the mark goes). Called after every roster, at most once a minute.
local lastPrune = -1000
function ns.PruneGone(force)
  local db = ns.db
  if not db or not ns.InGuild() or #ns.Members() == 0 then return end -- no roster yet: nothing is known
  if not force and GetTime() - lastPrune < 60 then return end
  lastPrune = GetTime()
  db.gone = db.gone or {}
  local gone, now, keep = db.gone, time(), GONE_DAYS * 86400
  local function Stays(name)
    if ns.IsMember(name) then gone[name] = nil return true end
    gone[name] = gone[name] or now
    return now - gone[name] <= keep
  end
  for key, set in pairs(db.sets) do if not Stays(set.o) then db.sets[key] = nil end end
  for name in pairs(db.peers) do if not Stays(name) then db.peers[name] = nil end end
  for name, t in pairs(gone) do if ns.IsMember(name) or now - t > keep then gone[name] = nil end end
end

local function OnAnnounce(sender, kind, owner, stamp, sum, prefix)
  if not kinds[kind] or owner == ns.MyName() or not ns.IsMember(owner) or ns.IsDemo(owner) then return end
  -- kinds that carry rights (guild master's settings, officers' deletions) only come from their owner in person
  if kinds[kind].direct and sender ~= owner then return end
  local have = ns.db.sets[Key(kind, owner)]
  if have and (have.t > stamp or (have.t == stamp and have.s == sum)) then return end
  local base = not prefix and kinds[kind].delta and have and have.d and have.s or nil
  Fetch(kind, owner, stamp, sum, sender, prefix, base)
end

local function OnRequest(sender, kind, owner, prefix, base)
  -- (C4) only kinds this addon has: Guildon 0.9 keeps the craft sets of 0.8 in its saved table, Guildon Crafts serves them
  if not kinds[kind] then return end
  local set = ns.db.sets[Key(kind, owner)]
  if not set or not set.d then return end
  -- (Runde 4) the asker holds an older version of an own delta set: only the changes since then
  local tag, data = "D", set.d
  local x = base and owner == ns.MyName() and kinds[kind].delta and Changes(set, base)
  if x and #x < #set.d then tag, data = "X", x end
  local n = math.max(1, math.ceil(#data / CHUNK))
  for i = 1, n do
    ns.Send(("%s:%s:%s:%d:%s:%d:%d:%s"):format(tag, kind, owner, set.t, set.s, i, n, data:sub((i - 1) * CHUNK + 1, i * CHUNK)),
      "WHISPER", sender, prefix)
  end
end

-- delta: the pieces are changes (X) against the version pending.base
local function OnPiece(sender, kind, owner, stamp, sum, i, n, chunk, prefix, delta)
  local key = Key(kind, owner)
  local p = pending[key]
  if not p or p.from ~= sender or p.stamp ~= stamp or p.sum ~= sum or p.prefix ~= prefix then return end
  if delta and not p.base then return end
  if n < 1 or n > math.ceil(MAX_SET / CHUNK) or i < 1 or i > n or (p.n and p.n ~= n) then return end
  if p.got > 0 and p.delta ~= delta then return end
  p.n, p.delta = n, delta
  if not p.parts[i] then p.parts[i] = chunk p.got = p.got + 1 end
  p.t = GetTime()
  if p.got < n then return end
  pending[key] = nil
  local data = table.concat(p.parts, "", 1, n)
  if delta then
    -- apply the changes to the version held; when they do not fit, the whole set is fetched
    local have, x, pos = ns.db.sets[key], data, 1
    data = have and have.s == p.base and have.d or nil
    while data and pos <= #x do data, pos = Patch(data, x, pos) end
    if not data or ns.Checksum(data) ~= sum then
      stats.rejected = stats.rejected + 1
      Fetch(kind, owner, stamp, sum, sender, prefix)
      return
    end
  end
  local def = kinds[kind]
  if ns.Checksum(data) ~= sum or (def.validate and not def.validate(data, owner)) then
    stats.rejected = stats.rejected + 1
    return
  end
  local old = ns.db.sets[key]
  if old and old.t > stamp then return end
  ns.db.sets[key] = { k = kind, o = owner, t = stamp, s = sum, d = data }
  stats.stored = stats.stored + 1
  if def.onUpdate then ns.SafeCall("set " .. kind, def.onUpdate, owner) end
  if ns.OnDataChanged then ns.OnDataChanged(kind, owner) end
end

local function N(v) return tonumber(v) end

-- short messages of other parts (map positions): ns.MSG[tag] = function(sender, rest, chat); they may also come by
-- PARTY or RAID (positions shared only with the group)
ns.MSG = ns.MSG or {}
ns.rawSenders = { n = 0 }
local CHATS = { GUILD = true, WHISPER = true, PARTY = true, RAID = true, INSTANCE_CHAT = true }

function ns.Receive(prefix, text, chat, sender)
  local legacy = ns.LEGACY_PREFIX ~= nil and prefix == ns.LEGACY_PREFIX
  if (prefix ~= ns.PREFIX and not legacy) or type(text) ~= "string" or #text > 255 then return end
  if not CHATS[chat] then return end
  local group = chat ~= "GUILD" and chat ~= "WHISPER"
  -- (05.11.2026) /gn names: the last senders as the game gives them (WoW Forever's surnames)
  local raw = ns.rawSenders
  if type(sender) == "string" and not raw[sender] and raw.n < 8 then raw.n = raw.n + 1 raw[sender] = chat raw[raw.n] = sender end
  sender = ns.FullName(sender)
  if not sender or sender == ns.MyName() or not ns.IsMember(sender) or ns.IsDemo(sender) then return end
  stats.received = stats.received + 1
  offline[sender] = nil -- heard again: whispers to him go out again
  -- (05.11.2026, Daniel: "Mit Guildon" 2, the map 2 more) any message under the own prefix shows the addon: a member
  -- online before us greeted before our login, and his whispered answer to our hello may never come (Guildon 0.11.0
  -- on Forever whispered to "<first> <surname>-<surname>"), while his map positions in the guild channel do
  if not legacy then
    local peer = ns.db.peers[sender]
    if peer then peer.t = time() else ns.db.peers[sender] = { v = "", t = time() } end
  end
  local tag, rest = text:match("^(%u):(.*)$")
  if group then
    if tag and ns.MSG[tag] and not legacy then ns.SafeCall("msg " .. tag, ns.MSG[tag], sender, rest, chat) end
    return
  end
  if legacy then
    -- the old prefix: hellos of old versions, the old kinds, and the short messages this addon reads there (ns.LEGACY_MSG)
    local lp = ns.LEGACY_PREFIX
    if tag == "H" then
      local v = rest:match("^([%w%.%-]+)$")
      if v then OnLegacyHello(sender, v, chat) end
    elseif tag == "S" then
      local kind, owner, stamp, sum = rest:match("^(%l+):([^:]+):(%d+):(%x+)$")
      if kind and LegacyKind(kind) then OnAnnounce(sender, kind, owner, N(stamp), sum, lp) end
    elseif tag == "G" and chat == "WHISPER" then
      local kind, owner = rest:match("^(%l+):([^:]+)$")
      if kind and LegacyKind(kind) then OnRequest(sender, kind, owner, lp) end
    elseif tag == "D" and chat == "WHISPER" then
      local kind, owner, stamp, sum, i, n, chunk = rest:match("^(%l+):([^:]+):(%d+):(%x+):(%d+):(%d+):(.*)$")
      if kind and LegacyKind(kind) then OnPiece(sender, kind, owner, N(stamp), sum, N(i), N(n), chunk, lp) end
    elseif tag and ns.LEGACY_MSG and ns.LEGACY_MSG[tag] and ns.MSG[tag] then
      ns.SafeCall("msg " .. tag, ns.MSG[tag], sender, rest, chat)
    end
    return
  end
  if tag == "H" then
    local v = rest:match("^([%w%.%-]+)$")
    if v then OnHello(sender, v, chat) end
  elseif tag == "S" then
    -- (Runde 4) one or more entries; an empty owner is the one of the entry before
    local prev
    for e in (rest .. ";"):gmatch("([^;]*);") do
      local kind, owner, stamp, sum = e:match("^(%l+):([^:]*):(%d+):(%x+)$")
      if owner == "" then owner = prev end
      if not kind or not owner then break end
      prev = owner
      OnAnnounce(sender, kind, owner, N(stamp), sum)
    end
  elseif tag == "G" and chat == "WHISPER" then
    local kind, owner, base = rest:match("^(%l+):([^:]+):?(%x*)$")
    if kind then OnRequest(sender, kind, owner, nil, base ~= "" and base or nil) end
  elseif (tag == "D" or tag == "X") and chat == "WHISPER" then
    local kind, owner, stamp, sum, i, n, chunk = rest:match("^(%l+):([^:]+):(%d+):(%x+):(%d+):(%d+):(.*)$")
    if kind then OnPiece(sender, kind, owner, N(stamp), sum, N(i), N(n), chunk, nil, tag == "X") end
  elseif tag and ns.MSG[tag] then
    ns.SafeCall("msg " .. tag, ns.MSG[tag], sender, rest, chat)
  end
end

ns.On("CHAT_MSG_ADDON", function(_, prefix, text, chat, sender) ns.Receive(prefix, text, chat, sender) end)

---------------------------------------------------------------------------
-- Start: register the prefix, own info set, hello a few seconds after login
---------------------------------------------------------------------------
-- "info": the character's card (Guildon version, level, class). First kind; more follow in step 2 (professions).
ns.RegisterKind("info", {
  validate = function(d) return #d <= 100 and d:match("^[%w%.%-]+;%d+;%u*$") ~= nil end,
})

function ns.InfoOf(owner)
  local set = ns.GetSet("info", owner)
  if not set then return nil end
  local v, lv, cls = set.d:match("^([^;]*);(%d+);(%u*)$")
  return { version = v, level = tonumber(lv), classFile = cls, stamp = set.t }
end

local function UpdateInfo()
  local lv = ns.Num(ns.Call(UnitLevel, "player")) or 0
  local _, cls = ns.Call(UnitClass, "player")
  ns.SetOwn("info", ("%s;%d;%s"):format(ns.VERSION, lv, ns.Str(cls) and cls:match("^%u+$") or ""))
end

ns.OnInit(function()
  local reg = C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix or RegisterAddonMessagePrefix
  ns.Call(reg, ns.PREFIX)
  if ns.LEGACY_PREFIX then ns.Call(reg, ns.LEGACY_PREFIX) end
end)

function ns.LegacyPeers() return legacyPeers end -- (tests, diag)

ns.On("PLAYER_LOGIN", function()
  ns.After(8, function()
    ns.Hello()
    UpdateInfo()
  end)
end)
ns.On("PLAYER_LEVEL_UP", function() ns.After(2, UpdateInfo) end)
ns.On("PLAYER_GUILD_UPDATE", function() ns.After(3, function() ns.Hello() UpdateInfo() end) end)

-- old fetches that never finished are forgotten
ns.OnInit(function()
  ns.NewTicker(10, function()
    local now = GetTime()
    for key, p in pairs(pending) do if now - p.t > FETCH_TIMEOUT then pending[key] = nil end end
  end)
end)

function ns.PrintDiag()
  local total, online, guildon, guildonOnline = ns.MemberCounts()
  local sets = 0
  for _ in pairs(ns.db.sets) do sets = sets + 1 end
  local npend = 0
  for _ in pairs(pending) do npend = npend + 1 end
  ns.Print(("v%s %s, prefix %s"):format(ns.VERSION, ns.ERA and "Era" or "Forever", ns.PREFIX))
  print(("  members %d, online %d, with %s %d (online %d)"):format(total, online, ns.ADDON_TITLE, guildon, guildonOnline))
  print(("  sets %d, pending %d, queue %d; sent %d, received %d, retried %d, dropped %d, stored %d, rejected %d")
    :format(sets, npend, #queue + #fast, stats.sent, stats.received, stats.retried, stats.dropped, stats.stored, stats.rejected))
  if ns.LEGACY_PREFIX then
    local n = 0
    for _ in pairs(legacyPeers) do n = n + 1 end
    print(("  also reads prefix %s: %d members with the older addon heard"):format(ns.LEGACY_PREFIX, n))
  end
  if ns.DiagExtra then ns.DiagExtra() end
  for _, e in ipairs(ns.Errors()) do print(("  error [%s] x%d: %s"):format(e.context, e.count, e.msg)) end
end
