# Changelog

## 0.3.1

- The weapons button now checks which enchant a hand carries, not just that it has one. A hand set to Sharpening Stone with a poison on it gets its stone. A hand set to a poison with a stone or another poison family on it gets its poison. The tooltip says what is on the hand instead.

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
