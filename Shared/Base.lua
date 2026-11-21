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
function ns.SafeCall(context, fn, ...)
  return Done(context, pcall(fn, ...))
end

function ns.Guard(context, fn)
  return function(...) return ns.SafeCall(context, fn, ...) end
end

function ns.After(delay, fn)
  if C_Timer and C_Timer.After then C_Timer.After(delay, ns.Guard("timer", fn)) end
end

function ns.NewTicker(delay, fn)
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
  return true
end

function ns.OnInit(fn) table.insert(initCallbacks, fn) end

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
