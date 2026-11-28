# BaitAndBlade

A WoW: Forever addon for people who fish between fights. It has two buttons, and it reminds you about food, elixirs, poisons and sharpening stones. It tells you what to buy and what it costs. It never eats, drinks or poisons for you.

## The two buttons

**Fishing button.** Each click does the next thing that is missing.

1. No fishing pole in hand: equips the best pole in your bags.
2. Pole on, no lure: puts the best lure in your bags on it (Aquadynamic Fish Attractor before Bright Baubles before Nightcrawlers before Shiny Bauble). The button glows.
3. Pole and lure on: casts Fishing (can be turned off).

**Weapons button.** One click puts your weapons back in your hands, main hand and off hand. The addon remembers the weapons you held before you took the pole out, so there is nothing to set up. Change weapons and it remembers the new ones.

The buttons no longer apply poisons or stones, and the third button that ate and drank is gone. Those are reminders now, and you use the item yourself.

On a flight path the buttons and the reminders go quiet until you land. In combat the buttons keep the step they had when combat started, because the game locks secure buttons in combat.

## Reminders

There are five slots: food, elixir, main hand poison, off hand poison and sharpening stone. The two poison slots are for rogues. When a slot's buff or weapon coating is missing, the addon reminds you with the item to use, for example "Eat Filet o' Flank". With none in your bags the reminder says what to buy.

The reminders on screen are ForeverAuras auras (ForeverAuras is the WeakAuras fork for Forever). There is one icon per slot with the reminder under it, and a text list of what to buy. Install them once with `/bab auras` or the "Install reminder auras" button in the panel. ForeverAuras opens its import window and you press Import. After that you move, resize or restyle them in `/fa` like any other aura.

## The picker

`/bab panel` opens it. Options > AddOns > BaitAndBlade has a button for it too.

On the left is one line per slot with a tick to switch it on or off and what it is asking for right now. Click a slot and the right side shows its ladder:

- A dropdown for what you want from the slot. For food and elixirs that is a stat: Agility, Attack Power, Spell Power, Mp5 and so on. For a hand it is a poison, or None.
- Every tier that gives it, strongest first, with its bonus, the level it needs, TradeSkillMaster's price and how many you hold.
- The strongest tier you can use is marked "recommended". Tiers above your level are grey and say the level they need.
- Each tier has a "worth it" tick. Untick one that costs too much for what it gives, and the recommendation moves to the next tier. An elixir that only helps one spell school starts unticked.

Under the ladder are two numbers. "Remind below" is the stock at which a slot goes on the shopping list (5 by default). "Stock up to" is how many the list asks you to hold (20 by default).

## Shopping list

The bottom of the picker lists what to buy: how many, which item, the price each, the line total and a grand total. Each line has a Search button. At the auction house it searches for the item through TradeSkillMaster.

When you open the auction house with something on the list, a small window with the same lines and Search buttons appears. Drag it where you want it. It closes with the auction house.

The aura shows the list too, in rested areas and at the auction house.

## Optional addons

- **ForeverAuras** draws the reminders on screen. Without it the picker still shows every reminder and the whole shopping list, and `/bab` prints them in chat.
- **TradeSkillMaster** supplies prices (its lowest auction buyout) and runs the searches. Without it there are no prices. The picker then recommends by strength alone.

## Setup

- Options > AddOns > BaitAndBlade: cast and glow toggles for the fishing button, lock, and the button that opens the picker.
- Shift-drag a button to move both.
- Keys: SHIFT-` clicks the fishing button and CTRL-` the weapons button, set on the first login where the key is free. Change them under Options > Keybindings > BaitAndBlade. Macros work too: `/click BaitAndBladeFishButton` and `/click BaitAndBladePoisonButton`.

## Commands

`/bab` prints what each button will do next, the reminders and the shopping list.

`/bab panel | auras | show | hide | lock | unlock | reset | options`

## Licence

MIT. See `LICENSE`.
