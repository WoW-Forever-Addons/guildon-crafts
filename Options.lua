local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- Guildon Crafts's options in DonCore's shared options window (StyleKit 2 step 4, 02.11.2026; mockup part 6): the settings of
-- the old Options tab. The cog in the window's header, /gnc options and the Blizzard AddOns page open it.
-- Tabs: Notifications (chat notes, how long wishes stay), Tooltips and trade, Window (the tab Profitable, minimap button,
-- place), Ranks (who may delete other members' wishes: the guild master chooses, everyone sees his choice), Tools.
-- (16.11.2026) With the option blizzLook (on by default) and the game's templates at login the same options are pages in
-- the game's settings (Options > AddOns > Guildon: Crafts & Recipes, DonCore Settings 4 fullPages) and every cog and
-- /gnc options ends there (DonCore Options spec.redirect); the ranks (a check list) stay in DonCore's window (a button there).
---------------------------------------------------------------------------
local Opt = LibStub("DonCore-1.0"):Get("Options", 2)

ns.OPTION_DEFAULTS = {
  notifyWishes = true, wishDays = 14, tooltips = true, mailCOD = true, showProfit = false, minimapButton = true,
  blizzLook = true, -- (16.11.2026, Daniel: "Sollte Standart sein") the windows in the game's look (Core.lua ns.LookKit)
}

local function IsMaster() return ns.IsGuildMaster and ns.IsGuildMaster(ns.MyName()) or false end

local ITEMS = {
  { header = "Notifications" },
  { key = "notifyWishes", name = "Tell me about new wishes and my crafters",
    tip = "A chat message when someone wishes for something you can make, or a crafter for your wish comes online." },
  { key = "wishDays", name = "Open wishes run out after", kind = "dropdown", tip = "Old wishes disappear from the list after this time.",
    options = function() return { { 7, L["%d days"]:format(7) }, { 14, L["%d days"]:format(14) }, { 30, L["%d days"]:format(30) } } end },
  { header = "Tooltips and trade" },
  { key = "tooltips", name = "Guild lines in item tooltips (who crafts it, who wants a recipe)", tip = "Adds the guild to the game's item tooltips." },
  { key = "mailCOD", name = "Cash on delivery when the wisher pays for the reagents",
    tip = "The mail to the wisher asks for the price of the reagents on delivery." },
  { header = "Window" },
  { key = "showProfit", name = "Tab Profitable", tip = "Recipes by profit per craft from auction prices. Off by default." },
  -- (16.11.2026, Daniel: the Blizzard look as the default for all Don addons) the windows from the game's own templates
  -- (20.11.2026, Daniel: the same option in every Don addon) the choice "Window style" with "Don look" / "Blizzard look" from
  -- DonCore (Libs\DonCore\Settings.lua minor 6, ns.LookOption after Settings:Attach in Core.lua), still on db.blizzLook
  -- (true/false). No onChange: Changed() below handles blizzLook for DonCore's window and the game's settings.
  ns.LookOption({ addon = "Guildon Crafts", category = "Guildon: Crafts & Recipes" }),
  { key = "minimapButton", name = "Minimap button", tip = "Shows the Guildon button at the minimap. All Guildon parts share it." },
  { kind = "button", optKey = "button:resetWindow", name = "Reset window position", button = "Reset",
    tip = "Puts the Guildon Crafts window back in the middle of the screen at its first size.", onClick = function() if ns.ResetWindow then ns.ResetWindow() end end },
  -- officer ranks (GUILDON_PLAN.md decision 3): the guild master chooses, everyone else sees the choice
  { header = "Ranks" },
  { key = "officerRanks", name = "Ranks that may delete other members' wishes", kind = "checklist",
    tip = "Only the guild master can change this; everyone sees his choice. Until he has chosen: ranks 1 and 2 of the list.",
    options = function()
      local names, n = ns.RankNames()
      local out = {}
      for i = 0, (n or 0) - 1 do out[#out + 1] = { i, names[i] or "?" } end
      return out
    end,
    isChecked = function(i) return ns.OfficerRanks()[i] and true or false end,
    setChecked = function(i, on)
      if not IsMaster() then return end
      local cur = {}
      for r in pairs(ns.OfficerRanks()) do cur[r] = true end
      cur[i] = on and true or nil
      cur[0] = true -- the guild master always may
      ns.SetOfficerRanks(cur)
    end,
    blockedBy = function() if not IsMaster() then return { reason = L["Only the guild master can change this."] } end end },
}

-- the tabs of DonCore's window; the game's settings get the same lists as pages
local NOTIFY_MAIN = { "notifyWishes", "wishDays" }
local TIPS_MAIN = { "tooltips", "mailCOD" }
local WINDOW_MAIN = { "showProfit", "blizzLook", "minimapButton", "button:resetWindow" }

-- one change, from DonCore's window or the game's settings
local function Changed(key)
  if key == "minimapButton" then if ns.RefreshMinimapButton then ns.RefreshMinimapButton() end
  elseif key == "showProfit" then if ns.RefreshTabs then ns.RefreshTabs() end
  elseif key == "wishDays" then if ns.InvalidateWishes then ns.InvalidateWishes() end
  elseif key == "blizzLook" then ns.LookChanged() end
  if ns.Refresh then ns.Refresh() end
  if ns.RefreshSettingsUI then ns.SafeCall("settings", ns.RefreshSettingsUI) end -- the game's settings show the new value
end

local function Status()
  local total, online, guildon = ns.MemberCounts()
  local open = ns.OpenWishesForMe and ns.OpenWishesForMe() or 0
  return { ("Guildon Crafts %s"):format(tostring(ns.VERSION or "")),
    ns.InGuild() and L["%d members"]:format(total) .. ", " .. L["online: %d"]:format(online) .. ", " .. L["With Guildon Crafts"] .. ": " .. guildon
      or L["You are not in a guild."],
    L["Open wishes you can craft: %d"]:format(open) }
end

local function Tools()
  return {
    { "Example guild", "On / off", function() if ns.SetDemo then ns.SetDemo(not ns.demo) end end,
      "Made-up members to try the windows, only on your screen.", state = function() return ns.demo and true or false end },
    { "Sync", "Ask now", function() if ns.Hello then ns.Hello(true) end ns.Print(L["Asked the guild for new data."]) end,
      "Asks the guild for new data now." },
    { "Export", "Show", function() if ns.ShowExport then ns.ShowExport() end end,
      "Your characters' professions and recipes as one text to copy." },
  }
end

local direct = false -- (16.11.2026) DonCore's window on purpose (the ranks), not the game's settings
local function Register()
  if not (Opt and Opt.Register) then return end
  local db = ns.db
  -- (04.11.2026, Era-Test) the minimap switch is DonCore's MinimapButton option (minor 3) through the shared button
  -- (Shared/Launcher.lua): our name and tip, switching the one button for every Guildon part
  if ns.MinimapOption then
    for i, it in ipairs(ITEMS) do
      if it.key == "minimapButton" and not it.donCommon then ITEMS[i] = ns.MinimapOption({ name = it.name, tip = it.tip }) end
    end
  end
  for k, v in pairs(ns.OPTION_DEFAULTS) do if db[k] == nil then db[k] = v end end
  Opt.Register(ns.OPTIONS_ID, {
    name = "Guildon: Crafts & Recipes", order = 31, addon = "Guildon_Crafts",
    tabs = {
      { key = "notify", title = "Notifications", icon = "Interface\\Icons\\INV_Letter_15",
        text = "Chat notes about wishes, and how long open wishes stay on the list.",
        main = NOTIFY_MAIN },
      { key = "tips", title = "Tooltips and trade", icon = "Interface\\Icons\\INV_Misc_Note_01",
        text = "The guild in the game's item tooltips, and the mail to a wisher.",
        main = TIPS_MAIN },
      { key = "window", title = "Window", icon = "Interface\\Icons\\Trade_BlackSmithing",
        text = "The tab Profitable, the look of the windows, the minimap button of all Guildon parts and the place of the window.",
        main = WINDOW_MAIN },
      { key = "ranks", title = "Ranks", icon = "Interface\\Icons\\INV_Misc_GroupNeedMore",
        text = "Which guild ranks may delete other members' wishes. The guild master chooses, everyone sees his choice.",
        main = { "officerRanks" } },
      { key = "tools", title = "Tools", text = "Status", status = true, tools = { "Example guild", "Sync", "Export" } },
    },
    pages = function() return { { items = ITEMS } } end,
    tools = Tools,
    db = function() return ns.db end,
    default = function(key) return ns.OPTION_DEFAULTS[key] end,
    changed = Changed,
    status = Status,
    help = function()
      local lines = {}
      for _, c in ipairs(ns.COMMANDS or {}) do lines[#lines + 1] = c[1] .. "  " .. L[c[2]] end
      return table.concat(lines, "\n")
    end,
    T = function(s) return L[s] end,
    labels = function(s) return L[s] end,
    -- (16.11.2026, DonCore Options 6) with the option blizzLook every cog and /gnc options ends in the game's settings
    redirect = function() if direct then return false end return ns.OpenGameOptions and ns.OpenGameOptions() or false end,
  })
end

-- (16.11.2026) the option blizzLook changed: every window is built again in the other look (an open one at once)
function ns.LookChanged()
  if ns.WindowReset then ns.SafeCall("window look", ns.WindowReset) end
  if ns.WishFormReset then ns.SafeCall("wish form look", ns.WishFormReset) end
  if ns.CopyReset then ns.SafeCall("copy look", ns.CopyReset) end
  if ns.MailBarReset then ns.SafeCall("mail bar look", ns.MailBarReset) end
end

---------------------------------------------------------------------------
-- (16.11.2026) The game's settings: the same items as pages, built at login when the option blizzLook is on and the client
-- has the game's templates (else nothing there, as before). A change of the option works for the options after a /reload.
---------------------------------------------------------------------------
local category, fullPages = nil, false

local function ItemOf(key)
  for _, it in ipairs(ITEMS) do if it.key == key or it.optKey == key then return it end end
end
local function PageItems(keys)
  local out = {}
  for _, k in ipairs(keys) do out[#out + 1] = ItemOf(k) end
  return out
end

local function GamePages()
  return {
    { title = "Notifications", tip = "Chat notes about wishes, and how long open wishes stay on the list.", items = PageItems(NOTIFY_MAIN) },
    { title = "Tooltips and trade", tip = "The guild in the game's item tooltips, and the mail to a wisher.", items = PageItems(TIPS_MAIN) },
    { title = "Window", tip = "The tab Profitable, the look of the windows, the minimap button of all Guildon parts and the place of the window.",
      items = PageItems(WINDOW_MAIN) },
    -- the ranks are a check list the game's settings do not have: DonCore's window shows and changes them
    { title = "Ranks", tip = "Which guild ranks may delete other members' wishes. The guild master chooses, everyone sees his choice.", items = {
      { kind = "button", name = "Ranks that may delete other members' wishes", button = "Show",
        tip = "The ranks are chosen in DonCore's options window. Only the guild master can change them; everyone sees his choice.",
        onClick = function() if ns.OpenDonWindow then ns.OpenDonWindow("ranks") end end },
    } },
  }
end
ns.GameOptionPages = GamePages -- (tests)

local function BuildGameOptions()
  category, fullPages = nil, false
  if not (ns.BuildSettings and ns.db and ns.db.blizzLook ~= false and ns.LookKit and select(2, ns.LookKit())) then return end
  category = ns.BuildSettings({ name = "Guildon: Crafts & Recipes", ownWindow = true, fullPages = true,
    status = Status, tools = Tools(), pages = GamePages(),
    db = function() return ns.db end, default = function(key) return ns.OPTION_DEFAULTS[key] end, changed = Changed,
    T = function(s) return L[s] end })
  fullPages = category ~= nil
end
ns.BuildGameOptions = BuildGameOptions -- (tests)

-- true when the game's settings were opened at Guildon Crafts (option blizzLook, pages built at login, not in combat)
function ns.OpenGameOptions()
  if not (ns.db and ns.db.blizzLook ~= false and fullPages and category and Settings and Settings.OpenToCategory) then return false end
  if InCombatLockdown and InCombatLockdown() then ns.Print(L["Not in combat."]) return true end
  Settings.OpenToCategory(category:GetID())
  return true
end
function ns.OptionsLook() return fullPages and "game settings" or "don window" end

-- DonCore's window at Guildon Crafts although the options are the game's (the ranks)
function ns.OpenDonWindow(tab)
  if not (Opt and Opt.Open) then return nil end
  direct = true
  local win = ns.SafeCall("options window", Opt.OpenFromBlizzard or Opt.Open, ns.OPTIONS_ID, tab)
  direct = false
  return win
end

function ns.OpenOptions(tab)
  if Opt and Opt.Open then Opt.Open(ns.OPTIONS_ID, tab) return true end
end

ns.OnInit(function()
  ns.SafeCall("options", Register)
  ns.SafeCall("game options", BuildGameOptions)
end)
