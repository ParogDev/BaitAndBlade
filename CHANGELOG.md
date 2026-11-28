# Changelog

## 0.4.0

The addon stops using consumables for you. It reminds you, and you click the item yourself.

- Two buttons instead of three. The fishing button is unchanged. The weapons button only puts your weapons back, and it remembers the weapons you held before the pole, so "Use equipped" and `/bab weapons` are gone.
- The weapons button no longer applies poisons or sharpening stones, and the agility button that ate and drank is removed.
- Reminders for food, elixir, a poison per hand and a sharpening stone. On screen they are ForeverAuras auras. Install them with `/bab auras` or the button in the panel, then move and style them in `/fa`.
- New picker, `/bab panel`. Per slot you choose the stat (or the poison) and see every tier with its bonus, required level, TradeSkillMaster price and how many you hold. The strongest tier for your level is recommended. Untick "worth it" on a tier that is too expensive and the recommendation moves down.
- Food and elixirs are no longer agility only. Pick Agility, Strength, Attack Power, Spell Power, Healing, Mp5 or any other stat the game has food or elixirs for.
- Shopping list. A slot with fewer than 5 in your bags asks for enough to hold 20, and both numbers can be changed in the picker. The list shows each price and the total, and each line has a Search button that looks the item up at the auction house through TradeSkillMaster. A small window with the list opens with the auction house.
- ForeverAuras and TradeSkillMaster are optional. Without ForeverAuras the picker and `/bab` still show the reminders. Without TradeSkillMaster there are no prices.
- Your 0.3 settings carry over: the poison per hand, the stones switch and the agility switch.

## 0.3.1

- A weapon on Forever holds a poison and a sharpening stone at the same time, so the weapons button now puts both on each hand: poisons first, then your best stone. Before, a stone counted as the poison and a poison as the stone.
- New option "Sharpening stones too" (on by default). Switch it off for poisons only. A hand set to Sharpening Stone still gets a stone and no poison.
- A hand with the wrong poison family on it gets its own poison again. The tooltip names the one that is on.

## 0.3.0

- Sharpening stones: each hand's choice in Options can now be Sharpening Stone instead of a poison. The weapons button then puts your best stone on that hand (Elemental before Dense before Solid and so on). A weapon holds one poison or one stone at a time.
- Out of stones, the weapons button's tooltip lists the stones you can use with TSM's lowest buyout.
- On a flight path the buttons go quiet: no glow, no click, and no buy reminder. They pick up again when you land.

## 0.2.0

- Third button, agility food and elixir. Without Well Fed it eats your strongest agility food, then without an agility elixir it drinks your strongest one. It glows while it has something to use.
- With none of a missing kind in your bags, the button turns into a coin. Its tooltip lists the strongest food or elixir you can use with TSM's lowest auction house buyout, and names the cheapest of the best tier.
- Buffed both ways with at least 5 of each in your bags, the button shows only under the mouse. Below 5 it reminds you to restock.
- Options: switch the button off. Keybindings: bind it (no default key). Macro: `/click BaitAndBladeAgilityButton`.

## 0.1.2

- Key bindings: both buttons are listed under Options > Keybindings > BaitAndBlade. On the first login the addon binds SHIFT-` to the fishing button and CTRL-` to the weapons button, only where the key is free. After that your own changes stick.

## 0.1.1

- An empty off hand (two-hander set up) no longer counts as unpoisoned.
- Weapons worn in the wrong hands are swapped back instead of reported missing.
- While an equipped item's info is still loading, the buttons wait instead of guessing.

## 0.1.0

- First version. A fishing button equips your best pole, puts your best lure on it, then casts Fishing.
- A weapons button equips your main and off hand weapons, then puts the highest-rank poison of each hand's chosen type on it. It glows while either hand has no poison.
- Options panel: poison type per hand, the weapons to equip (taken from your hands), cast and glow toggles, lock.
