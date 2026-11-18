local addonName, ns = ...
local L = ns.L
ns.Style = LibStub("DonCore-1.0"):Get("Style", 4):ForAddon() -- DonCore's Style (Libs/DonCore/Style.lua) for texts: Hex, Number, Wordmark, tooltips; the windows are built from DonCore's Kit (02.11.2026)
LibStub("DonCore-1.0"):Get("Settings", 1):Attach(addonName, ns) -- (16.11.2026) the pages in the game's settings with the option blizzLook (Libs\DonCore\Settings.lua minor 4, Options.lua)

---------------------------------------------------------------------------
-- Guildon Crafts: the guild's crafts (DONCORE_PLAN.md "Craftdon aus Guildon lösen", 31.10.2026): professions, recipe book, wish list
-- with orders, trade and mail help, shared prices. Taken out of Guildon 0.8; Guildon keeps the guild map and the members.
-- (02.11.2026, StyleKit 2 step 4) the window and its pages are built from DonCore's Kit, every option is in DonCore's options window.
-- Own frames only: no hooksecurefunc, no HookScript, no Blizzard frame scripts.
-- Classic.lua (only in Guildon_Crafts_Vanilla.toc, loaded before this file) sets ns.ERA.
-- Error guard, events, saved table and helpers are in Shared/Base.lua (GuildShared/), loaded right after this file.
---------------------------------------------------------------------------
ns.defaults = {
  window = {},         -- (02.11.2026, Don style) place and size of the window (DonCore Kit.Window's store)
  tab = "overview",    -- last open tab
  sets = {},           -- shared data sets, key "<kind>:<owner>" (Comm.lua)
  peers = {},          -- Guildon Crafts users seen: full name -> { v = version, t = time() }
}
ns.SCHEMA = 1
ns.WORDMARK = "|cff3fa9f5Guil|rdon Crafts"
-- own prefix per game version, so Forever and Era data never mix
ns.PREFIX = ns.ERA and "GuildonCraftsEra" or "GuildonCrafts"

ns.DBNAME = "GuildonCraftsDB"
ns.ERROR_HINT = "an error occurred, /gnc diag for details"
ns.ADDON_TITLE = "Guildon Crafts"

-- (16.11.2026, Daniel: "Sollte Standart sein", the Blizzard look as the default for all Don addons) the one place that picks
-- the blocks of the windows: DonCore's Kit, or with the option blizzLook (on by default) the same blocks from the game's own
-- templates (DonCore Blizz). Returns kit, isBlizzard, reason (why the Kit builds although the option is on). A client
-- without the templates (Era, test mocks) keeps the Don look without a word. The window (Shared/Window.lua) picks it when
-- it is built and hands it to the pages (ns.PageKit); the wish form, the copy box and the mail bar pick it when built.
function ns.LookKit()
  local Core = LibStub("DonCore-1.0")
  local Kit = Core:Get("Kit", 4)
  if not (ns.db and ns.db.blizzLook ~= false) then return Kit, false, "option off" end
  local Bz = Core:Get("Blizz", 5)
  if not Bz then return Kit, false, "no DonCore Blizz" end
  local kit, miss = Bz.Kit()
  if kit then return kit, true end
  return Kit, false, "missing: " .. tostring(miss)
end
-- a window that failed in the game's look and was built with the Kit: noted for /gnc diag, one chat line per session
-- (the window, GuildShared/Window.lua, calls it too when the addon has it: one line for all; its reason is in ns.WindowLook)
local lookErrors, said = {}, false
function ns.LookFailed(what, err)
  lookErrors[#lookErrors + 1] = tostring(what) .. ": " .. tostring(err)
  if said or not ns.Print then return end
  said = true
  ns.Print(L["The window could not be built in the game's look, it opens in the Don look. %s says why."]:format("/gnc diag"))
end
-- "blizzard" or "kit (reason)" for the windows built from now on, and the failed builds (diag, tests)
function ns.LookNote()
  local _, blizz, why = ns.LookKit()
  return blizz and "blizzard" or ("kit (" .. tostring(why) .. ")"), lookErrors
end
-- the Blizz module itself (Bz.Box for the mail bar), nil without it
function ns.Blizz() return LibStub("DonCore-1.0"):Get("Blizz", 5) end

-- (GuildShared/Base.lua calls this once the saved table is there, before the init callbacks)
function ns.MigrateDB(db)
  -- (02.11.2026, StyleKit 2 step 4) the window is DonCore's Kit.Window now: the old panel's place, size, lock, scale,
  -- opacity and combat fade are gone (the Don window keeps place and size in db.window); the Options tab is gone
  db.panel, db.panelWidth, db.panelHeight, db.panelLocked, db.panelScale, db.panelAlpha, db.combatFade, db.darkLook = nil, nil, nil, nil, nil, nil, nil, nil
  if db.tab == "options" then db.tab = "overview" end
end
-- (31.10.2026) one of the Guildon parts: its entry at the shared minimap button (Shared/Launcher.lua), with the open wishes
ns.MODULE = { id = "crafts", title = "Guildon: Crafts & Recipes", icon = "Interface\\Icons\\Trade_BlackSmithing", order = 2 }
function ns.LauncherTip()
  local n = ns.OpenWishesForMe and ns.OpenWishesForMe() or 0
  return n > 0 and { L["Open wishes you can craft: %d"]:format(n) } or nil
end

-- Guildon Crafts's line in /gnc diag after the exchange numbers (GuildShared/Comm.lua ns.PrintDiag)
function ns.DiagExtra(out)
  out = out or print
  -- (16.11.2026) the look of the windows and why
  local note, errs = ns.LookNote()
  out(("  look: window %s, others %s%s"):format(ns.WindowLook and tostring(ns.WindowLook()) or "?", note,
    #errs > 0 and (", failed: " .. table.concat(errs, "; ")) or ""))
  if ns.OptionsLook then out("  options: " .. ns.OptionsLook()) end -- (16.11.2026) "game settings" or "don window"
  if ns.RecipeReport then out(("  recipes the data lacks or knows without reagents: %d (/gnc recipes)"):format(select(2, ns.RecipeReport()))) end
end

-- (16.11.2026, Daniel: "bei allen addons soll der diag befehl ein fenster zum kopieren aufmachen") /gnc diag shows the
-- lines ns.PrintDiag (GuildShared/Comm.lua) prints in the copy box (ns.ShowCopyBox: the game's look with blizzLook, else
-- the Kit); "/gnc diag chat" prints them as before, and a box that cannot be shown prints them too.
-- the diag lines as plain text, colours and links taken out: ns.PrintDiag hands them to add (the global print stays
-- untouched, changing it would taint it)
function ns.DiagLines()
  local lines = {}
  local function add(s)
    lines[#lines + 1] = (tostring(s):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1"))
  end
  if not ns.PrintDiag then return lines end
  local ok, err = pcall(ns.PrintDiag, add)
  if not ok then add("  diag error: " .. tostring(err)) end
  return lines
end
function ns.ShowDiag()
  local ok, lines = pcall(ns.DiagLines)
  if ok and #lines > 0 then
    local shown, d = pcall(ns.ShowCopyBox, ns.ADDON_TITLE .. " diag", L["Ctrl+A selects all, Ctrl+C copies."], table.concat(lines, "\n"))
    if shown and d then return d end
  end
  if ns.PrintDiag then ns.PrintDiag() end
end

function GuildonCrafts_OnAddonCompartmentClick()
  if ns.ToggleWindow then ns.ToggleWindow() end
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
SLASH_GUILDONCRAFTS1 = "/gnc"
SLASH_GUILDONCRAFTS2 = "/guildoncrafts"
ns.COMMANDS = {
  { "/gnc", "show or hide the window" },
  { "/gnc wishes", "the wish list" },
  { "/gnc options", "all settings (also the cog in the window)" },
  { "/gnc sync", "ask the guild for new data now" },
  { "/gnc diag", "state of the exchange and errors" },
  { "/gnc demo", "example guild to try the windows (again: off)" },
  { "/gnc export", "your professions as text for the guild website" },
  { "/gnc recipes", "recipes the game showed that Guildon Crafts does not know yet, to send to the authors" },
  { "/gnc help", "this list" },
}

function ns.PrintHelp()
  ns.Print(L["Commands:"])
  for _, c in ipairs(ns.COMMANDS) do print("  |cffebebeb" .. c[1] .. "|r  |cff9ea3ad" .. L[c[2]] .. "|r") end
end

function ns.Slash(msg)
  msg = tostring(msg or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
  if msg == "" or msg == "show" or msg == "toggle" then
    if ns.ToggleWindow then ns.ToggleWindow() end
  elseif msg == "wishes" or msg == "wish" or msg == "wünsche" then
    if ns.OpenTab then ns.OpenTab("wishes") end
  elseif msg == "options" or msg == "optionen" or msg == "config" then
    if not (ns.OpenOptions and ns.OpenOptions()) then ns.Print(L["The options window is missing (DonCore)."]) end
  elseif msg == "sync" then
    if ns.Hello then ns.Hello(true) end
    ns.Print(L["Asked the guild for new data."])
  elseif msg == "demo" or msg == "demo on" or msg == "demo off" or msg == "beispiel" then
    if ns.SetDemo then ns.SetDemo(msg == "demo off" and false or (msg == "demo on" and true or not ns.demo)) end
  elseif msg == "export" then
    if ns.ShowExport then ns.ShowExport() end
  elseif msg == "recipes" or msg == "rezepte" then
    if ns.ShowRecipeReport then ns.ShowRecipeReport() end
  elseif msg == "diag" then
    ns.ShowDiag()
  elseif msg == "diag chat" then
    if ns.PrintDiag then ns.PrintDiag() end
  elseif msg == "help" or msg == "?" or msg == "hilfe" then
    ns.PrintHelp()
  else
    ns.Print(L["Unknown command: %s"]:format(msg))
    ns.PrintHelp()
  end
end

SlashCmdList["GUILDONCRAFTS"] = function(msg) ns.SafeCall("slash", ns.Slash, msg) end
