# BaitAndBlade

A WoW: Forever addon for rogues who fish. It puts two buttons on screen. Each click does the next thing that is missing.

**Fishing button**

1. No fishing pole in hand: equips the best pole in your bags.
2. Pole on, no lure: puts the best lure in your bags on it (Aquadynamic Fish Attractor before Bright Baubles before Nightcrawlers before Shiny Bauble). The button glows.
3. Pole and lure on: casts Fishing (can be turned off).

**Weapons button**

1. Your weapons are not in your hands: equips them (main hand and off hand in one click).
2. Main hand has no poison: puts the highest rank of your main hand poison on it.
3. Off hand has no poison: the same for the off hand.

The button glows while your weapons are on and either hand has no poison. Defaults: Instant Poison on the main hand, Crippling Poison on the off hand. Only ranks you can use count.

## Setup

- Options > AddOns > BaitAndBlade: poison per hand, cast and glow toggles, lock.
- Hold your normal weapons and press **Use equipped** there (or type `/bab weapons`) to set the weapons the button equips.
- Shift-drag a button to move both.
- Keys: SHIFT-` clicks the fishing button and CTRL-` the weapons button, set on the first login where the key is free. Change them under Options > Keybindings > BaitAndBlade. Macros work too: `/click BaitAndBladeFishButton` and `/click BaitAndBladePoisonButton`.

In combat the buttons keep the step they had when combat started: the game locks secure buttons in combat.

## Commands

`/bab` shows what each button will do next. `/bab show | hide | lock | unlock | weapons | reset | options`.

## Licence

MIT. See `LICENSE`.
