# Changes

## 1.3.2

- **One option for the window style:** the switch "Windows in the game's look" is now the choice "Window style" with "Don look" and "Blizzard look", named the same in every Don addon. Your setting stays as it was.
- **Recipe data:** refreshed (21 November).
- **Shared Don library:** updated to the current version of the Don addons.

## 1.3.1

- **Recipe card:** search and filter buttons span the whole window, list and card sit below. The card closes with its X, a second click on the row or Esc (outside combat); without a choice the list takes the full width.
- **Profession bar:** the symbols on the left show in full in the game's look.
- **Wish form:** payment as three choices one under the other instead of overlapping buttons; the form is as high as its content.
- **Recipe list:** a head "Recipe | Skill | Crafters" with tooltips; "Whisper" buttons shorten long names (full name in the tooltip); "?" instead of "0/0" for an unknown skill.
- **Data of 18 November:** 21 new reagents.

## 1.3.0
- **The game's look, out of the box:** the Crafts & Recipes window and all its pages, the wish form, the copy window and the bar at the mailbox use the game's own frame, tabs, buttons and lists, with the guild crest in the round portrait. Prefer the old look? Turn off "Windows in the game's look" in the options (tab Window); the change applies at once.
- **Options in the game's settings:** all options are now pages under Options > AddOns > Guildon: Crafts & Recipes. The gear, `/gnc options` and the minimap menu open them there. What the game's settings cannot do, like the ranks allowed to delete, opens in the Don options window from a button. Needs a game restart once; without the game's templates (Classic Era) or with the option off, everything stays in the Don window as before.
- **"Example guild" as a checkbox:** the example guild in the options now shows whether it is on or off.
- **`/gnc diag` opens a window:** the report appears in a window you can copy from; `/gnc diag chat` prints it in the chat as before.

## 1.2.7
- **More WoW Forever recipes:** 415 more recipes (2501 in all), from the newest All The Things and ForeverDB data and from recipes seen in the game, with their reagents; several reagent lists corrected.
- **Cleaner text in narrow places:** text that is shrunk to fit keeps one font and size.

## 1.2.6
- **Reagents from the WoW Forever client:** 708 recipes that showed no reagents now have them, and 123 are corrected (mostly enchanting); these recipes show reagents and cost at once.
- **Guild cooldowns follow WoW Forever:** only the transmutes that share one cooldown count for "Transmute", Transmute: Legionite is among them.
- **Profitable:** recipes with a cooldown of an hour or more show it behind the name and in the card.
- **No more rows of "No player named ... is currently playing":** when a guild member logged out while the addon was still sending them data, the chat showed one yellow line per message, most often with the map open. Nothing is sent any more to a member who went offline.

## 1.2.5
- **Recipes for WoW Forever build 70888:** 27 recipes added and 5 the game no longer has removed; cooking recipes now name their trainer or recipe item on WoW Forever.

## 1.2.4
- **More recipes on WoW Forever:** 85 recipes seen in the game added (alchemy, engineering, cooking, first aid), 197 recipes now show their reagents and 20 make the right number of items.

## 1.2.3
- **Hidden surnames on WoW Forever:** with surnames turned off in the game's options, crafters and trade partners are whispered with their right name again.

## 1.2.2
- **Surnames on WoW Forever, done right:** crafters, wishes and trade partners are shown and whispered with first name and surname. Your own professions and wishes keep their data (moved once to the new names).

## 1.2.1
- **Surnames on WoW Forever:** your own name and your trade partner's name are now recognised with a surname.

## 1.2.0
- **Narrow profession bar:** Professions and Recipes show the professions as a narrow bar of symbols (name and online / in the guild in the tooltip). The recipe card stays beside the recipe list down to a window of about 770 px instead of covering it.
- **The Don look:** the window you can drag from 720x420 to 1300x900 with the shared look of the Don addons: Overview, Professions and Recipes with the profession bar, crafters with skill bar (click to whisper), a focus card with reagents, wish list with chips and status, the wish form as a dialog, Profitable as a table. Item tooltips and quality colours in all lists.
- **Orders at the mailbox:** a bar at the top right beside the mailbox or trade window; with an open order it fills in "Send mail" with the recipient from the order, "All in" only with the right recipient, one button for letter and goods. Cash on delivery uses the game's C.O.D. button (it was lost before) and the letter shows the bill with auction prices. Items you bought at the auction house (receipts of the last 14 days) are billed at what you paid.
- **Options in the Don family window** (`/gnc options`); the Options tab is gone. Locking, hiding in combat and Shift-scaling the window are gone.
- **Minimap button:** the guild crest with a golden ring (anvil for Crafts & Recipes), menu with the logo of each part, a line to the options and "Hide minimap button". The switch counts for both parts.
- **Window size:** all Don windows share one scale, 80 % by default, set from 60 to 110 % under General > Window in the options window. Saved window sizes are reset once, places stay.
- **Number fields:** clicking into a number or money field selects the whole value.
- **Addon list:** the addon has its own logo in the game's addon list.
- **Update note:** new files, so restart the game after updating (a /reload is not enough).

## 1.1.0
- **Part of Guildon:** **Guildon: Map & Members** 0.9 needs this addon (and DonMap). The CurseForge app installs it with Guildon. If you install by hand, put the `Guildon_Crafts` folder next to `Guildon` in `Interface\AddOns`. Crafts & Recipes also works on its own.
- **First full release** after the 1.0.0 test version: professions and recipes of the guild, recipe book, wish list with orders, trade and mail help, shared prices, Profitable (off by default), cooldowns, recipes wanted, shopping lists and thanks, for WoW Forever and WoW Classic Era.
- **Much less guild traffic:** answers come in bundles, recipe lists are sent as changes only and cooldowns are rounded to the minute. A new guild member gets about 59 messages instead of 218, a newly learned recipe 1 instead of 17, and cooldowns are no longer announced again and again in combat.
- **Steady sending:** up to 8 messages at once, then one per second; messages that have to wait are sent later instead of being lost.
- **Members who left:** their data is dropped after 30 days and never passed on.
- **Please update together:** guild members on the 1.0.0 test version do not understand the new bundled messages. Members still on Guildon 0.8 are read and answered as before.

## 1.0.0
- First version, as **Guildon: Crafts & Recipes** (folder Guildon_Crafts, /gnc): the craft part of Guildon 0.8 as an addon of its own, with its own window (/gnc, /guildoncrafts) and guild channel; it shares the Guildon minimap button with the other Guildon parts.
- Professions and recipes of the guild, recipe book, wish list with orders, trade and mail help, shared prices, Profitable (off by default), cooldowns, recipes wanted, shopping lists, thanks, item tooltips, export for the guild website.
- At the first start Guildon Crafts takes over what Guildon 0.8 kept: professions, recipes, wishes and orders, prices, cooldowns, wanted recipes, thanks, the craft options and the window's place. Guildon's data stays as it is.
- Guild members still on Guildon 0.8 are read and answered under Guildon's channel, so the guild sees each other's professions during the switch.
- With Guildon 0.9 the member tooltips show the professions from Guildon Crafts.
