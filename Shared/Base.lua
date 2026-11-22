local addonName, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- GuildShared (DONCORE_PLAN.md "Craftdon aus Guildon lösen", 31.10.2026): the base Guildon and Guildon Crafts share. The source is
-- the workshop folder GuildShared/, tools/sync_core.sh copies it into <Addon>/Shared/; every copy works in its own ns.
-- The addon's Core.lua (loaded before this file) sets ns.DBNAME (its SavedVariables), ns.defaults, ns.SCHEMA, ns.WORDMARK,
-- ns.ERROR_HINT (the locale key of the "an error occurred" line) and may set ns.MigrateDB(db).
-- Own frames only: no hooksecurefunc, no HookScript, no Blizzard frame scripts.
---------------------------------------------------------------------------

do
  local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  local ok, v = pcall(get or function() end, addonName, "Version")
  ns.VERSION = (ok and type(v) == "string" and v ~= "") and v or "0"
end

---------------------------------------------------------------------------
-- Error guard: handlers, timers and UI callbacks run protected.
---------------------------------------------------------------------------
local MAX_ERRORS, MAX_MSG = 10, 160
local errors, warned = {}, false

local function Shorten(msg)
  msg = tostring(msg or "?"):gsub("\\", "/")
  msg = msg:gsub("[^%s:]*/([%w_]+%.[lx][um][al])", "%1")
  if #msg > MAX_MSG then msg = msg:sub(1, MAX_MSG) .. "..." end
  return msg
end

local function Record(context, err)
  if type(err) ~= "string" then err = "(unreadable error)" end
  local ok, msg = pcall(Shorten, err)
  if not ok then msg = "(unreadable error)" end
  for _, e in ipairs(errors) do
    if e.msg == msg and e.context == context then e.count = e.count + 1 return end
  end
  if #errors < MAX_ERRORS then errors[#errors + 1] = { context = context, msg = msg, count = 1 } end
  if not warned then
    warned = true
    print(ns.WORDMARK .. ": " .. L[ns.ERROR_HINT])
  end
end

function ns.Errors() return errors end

-- (21.11.2026, Ruckler) pcall with the arguments directly: no table and no closures per call (every event, every
-- listener); the error is recorded only when there is one (the same message the handler of xpcall got)
local function Done(context, ok, a, b, c)
  if ok then return a, b, c end
  pcall(Record, context, a)
end
-- (21.11.2026, Ruckler, Daniel: "monitor ... dass ich das im spiel testen kann") every protected call that takes
-- SLOW_MS or more goes into the global ring DonSlowLog (60 entries, not saved): addon, context, the function's file and
-- line, ms. DonMonitor's report lists it. Below the threshold it costs two debugprofilestop calls, no garbage.
local SLOW_MS, SLOW_MAX = 8, 200 -- (22.11.2026) 8 ms as DonMonitor's hitch threshold; the report sums them up
local dps = type(debugprofilestop) == "function" and debugprofilestop or nil
-- (22.11.2026) where a listener, ticker or timer was made: "File.lua:123" of the first line outside this file
local fnWhere = setmetatable({}, { __mode = "k" })
local function Where(level)
  if type(debugstack) ~= "function" then return nil end
  local ok, stack = pcall(debugstack, level, 6, 0)
  if not ok or type(stack) ~= "string" then return nil end
  local first
  for file, line in stack:gsub("\\", "/"):gmatch('([%w_]+%.lua)["%]]*:(%d+)') do
    local at = file .. ":" .. line
    if file ~= "Base.lua" then return at end
    first = first or at
  end
  return first
end
local function NoteWhere(fn, level)
  if type(fn) == "function" and not fnWhere[fn] then fnWhere[fn] = Where(level + 1) end
end
local function NoteSlow(context, fn, ms)
  local log = rawget(_G, "DonSlowLog")
  if type(log) ~= "table" then log = { n = 0 } DonSlowLog = log end
  -- (22.11.2026) the game has no debug.getinfo (the lookup threw, pcall swallowed it, nothing was ever noted): the
  -- place comes from fnWhere (noted with debugstack when the listener, ticker or timer was made)
  local where = fnWhere[fn] or "?"
  local okT, clock = pcall(date, "%H:%M:%S")
  log.n = (log.n or 0) + 1
  log[(log.n - 1) % SLOW_MAX + 1] = { n = log.n, t = okT and clock or "?", a = addonName, c = tostring(context), f = where,
    ms = math.floor(ms * 10 + 0.5) / 10 }
end
local function SlowDone(context, fn, t0, ...)
  local ms = dps() - t0
  if ms >= SLOW_MS then pcall(NoteSlow, context, fn, ms) end
  return ...
end
function ns.SafeCall(context, fn, ...)
  if not dps then return Done(context, pcall(fn, ...)) end
  return SlowDone(context, fn, dps(), Done(context, pcall(fn, ...)))
end

function ns.Guard(context, fn)
  return function(...) return ns.SafeCall(context, fn, ...) end
end

function ns.After(delay, fn)
  -- (22.11.2026) the place of a timer only while DonMonitor runs (timers are made often, a debugstack each)
  if rawget(_G, "DonMonitorDB") then NoteWhere(fn, 2) end
  if C_Timer and C_Timer.After then C_Timer.After(delay, ns.Guard("timer", fn)) end
end

function ns.NewTicker(delay, fn)
  NoteWhere(fn, 2)
  if C_Timer and C_Timer.NewTicker then return C_Timer.NewTicker(delay, ns.Guard("ticker", fn)) end
end

---------------------------------------------------------------------------
-- Events on our own frame. Several modules may listen to one event.
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
local listeners, initCallbacks = {}, {}

function ns.On(event, fn)
  if not listeners[event] then
    listeners[event] = {}
    local ok = pcall(frame.RegisterEvent, frame, event) -- unknown events throw
    if not ok then listeners[event] = nil return false end
  end
  table.insert(listeners[event], fn)
  NoteWhere(fn, 2)
  return true
end

function ns.OnInit(fn) NoteWhere(fn, 2) table.insert(initCallbacks, fn) end

frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    local name = ...
    if name ~= addonName then return end
    local db = type(_G[ns.DBNAME]) == "table" and _G[ns.DBNAME] or {}
    _G[ns.DBNAME] = db
    for k, v in pairs(ns.defaults) do
      if type(db[k]) ~= type(v) then db[k] = type(v) == "table" and {} or v end
    end
    db.schema = ns.SCHEMA
    if ns.MigrateDB then ns.MigrateDB(db) end
    ns.db = db
    for _, fn in ipairs(initCallbacks) do ns.SafeCall("init", fn) end
    return
  end
  if not ns.db then return end
  -- (21.11.2026, Ruckler) addon messages of other addons never reach the listeners: only GuildShared/Comm.lua reads
  -- CHAT_MSG_ADDON, and it takes only ns.PREFIX and ns.LEGACY_PREFIX
  if event == "CHAT_MSG_ADDON" and ns.PREFIX then
    local prefix = ...
    if prefix ~= ns.PREFIX and (ns.LEGACY_PREFIX == nil or prefix ~= ns.LEGACY_PREFIX) then return end
  end
  local list = listeners[event]
  if list then
    for i = 1, #list do ns.SafeCall(event, list[i], event, ...) end
  end
end)

---------------------------------------------------------------------------
-- Window settings for Style.Panel
---------------------------------------------------------------------------
local SHARED = { locked = "panelLocked", scale = "panelScale", alpha = "panelAlpha", combatFade = "combatFade" }
function ns.PanelGet(tableName)
  return function(key)
    local flat = SHARED[key]
    if flat then return ns.db[flat] end
    return ns.db[tableName][key]
  end
end
function ns.PanelSet(tableName)
  return function(key, value)
    local flat = SHARED[key]
    if flat then ns.db[flat] = value else ns.db[tableName][key] = value end
  end
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
function ns.Print(msg) print(ns.WORDMARK .. ": " .. tostring(msg)) end

-- Secret values (Midnight rules) never reach comparisons or table keys in our code.
function ns.Usable(v)
  if type(v) == "nil" then return false end
  if canaccessvalue then
    local ok, r = pcall(canaccessvalue, v)
    if ok then return r and true or false end
    return false
  end
  if issecretvalue then
    local ok, r = pcall(issecretvalue, v)
    if ok then return not r end
    return false
  end
  return true
end

function ns.Num(v)
  if type(v) == "number" and ns.Usable(v) then return v end
  return nil
end

function ns.Str(v)
  if type(v) == "string" and ns.Usable(v) and v ~= "" then return v end
  return nil
end

function ns.Call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d = pcall(fn, ...)
  if ok then return a, b, c, d end
  return nil
end

-- 32 bit checksum of a string as 8 hex digits (same result on every client; Lua numbers are doubles)
function ns.Checksum(s)
  local h = 2166136261
  for i = 1, #s do h = (h * 31 + s:byte(i)) % 4294967296 end
  return ("%08x"):format(h)
end
