# BaitAndBlade

A WoW: Forever addon for rogues who fish. It puts three buttons on screen. Each click does the next thing that is missing.

**Fishing button**

1. No fishing pole in hand: equips the best pole in your bags.
2. Pole on, no lure: puts the best lure in your bags on it (Aquadynamic Fish Attractor before Bright Baubles before Nightcrawlers before Shiny Bauble). The button glows.
3. Pole and lure on: casts Fishing (can be turned off).

**Weapons button**

1. Your weapons are not in your hands: equips them (main hand and off hand in one click).
2. Main hand has no poison: puts the highest rank of your main hand poison on it.
3. Off hand has no poison: the same for the off hand.

The button glows while your weapons are on and either hand has no poison. Defaults: Instant Poison on the main hand, Crippling Poison on the off hand. Only ranks you can use count.

A weapon on Forever holds a poison and a sharpening stone at the same time, so after the poisons the button puts your best stone on each hand: Elemental, Dense, Solid, Heavy, Coarse, Rough. Options: "Sharpening stones too" switches the stones off; a hand set to "Sharpening Stone" gets a stone and no poison. With no stones left, the tooltip lists the ones you can use and TSM's price for each.

On a flight path all three buttons go quiet (no glow, no click, no buy reminder) until you land.

**Agility button**

1. No Well Fed buff: eats your strongest agility food (on Forever the wolf, lion, crocolisk dishes, Jungle Stew and the new steaks give Agility). Sit 10 seconds for the buff.
2. No agility elixir on: drinks your strongest one (Mongoose before Greater Agility before Ferocity and so on).
3. Nothing to use for a missing buff: the button shows a coin. Hover it for the strongest food or elixir you can use and TradeSkillMaster's lowest buyout for each, plus the cheapest of the best tier.
4. Both buffs on and at least 5 of each in your bags: the button shows only under the mouse. Below 5 it reminds you to restock.

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
