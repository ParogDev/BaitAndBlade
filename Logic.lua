-- Pure decisions, no client calls: which pole, lure and poison in the bags is best, and what the next click of each
-- button should do. Core.lua gathers the state from the client and turns the answer into a secure macro.
local _, ns = ...

local Logic = {}
ns.Logic = Logic

Logic.POISON_FAMILIES = {
	"Instant Poison",
	"Crippling Poison",
	"Deadly Poison",
	"Mind-numbing Poison",
	"Wound Poison",
}

-- On Forever a weapon holds a poison and a sharpening stone at the same time. A hand set to this name takes no
-- poison, only its stone; the settings store it as the hand's choice, next to the poison families.
Logic.STONE = "Sharpening Stone"
Logic.HAND_CHOICES = {}
for i, family in ipairs(Logic.POISON_FAMILIES) do
	Logic.HAND_CHOICES[i] = family
end
Logic.HAND_CHOICES[#Logic.HAND_CHOICES + 1] = Logic.STONE

-- Sharpening stones by item id, from the Forever client's item table (build 1.60.1.70888); 287978 and 287980 are
-- Forever copies and match by name. score: the damage bonus, and 10 for the Elemental stone's +2% crit so it wins.
-- Consecrated (undead only) and Blackfathom (Season of Discovery) are left out.
Logic.SHARPENING_STONES = {
	{ id = 18262, name = "Elemental Sharpening Stone", bonus = "+2% crit", score = 10, level = 50 },
	{ id = 12404, name = "Dense Sharpening Stone", bonus = "+8 damage", score = 8, level = 35 },
	{ id = 7964, name = "Solid Sharpening Stone", bonus = "+6 damage", score = 6, level = 25 },
	{ id = 2871, name = "Heavy Sharpening Stone", bonus = "+4 damage", score = 4, level = 15 },
	{ id = 2863, name = "Coarse Sharpening Stone", bonus = "+3 damage", score = 3, level = 5 },
	{ id = 2862, name = "Rough Sharpening Stone", bonus = "+2 damage", score = 2, level = 1 },
}

Logic.DEFAULTS = {
	mainHandWeapon = "Dazzling Longsword",
	offHandWeapon = "Sword of Omen",
	mainHandPoison = "Instant Poison",
	offHandPoison = "Crippling Poison",
	stones = true, -- the best sharpening stone on both weapons, next to their poisons
	castFishing = true, -- the fishing button casts Fishing once the pole and the lure are on
	glowFishing = true, -- the fishing button glows when the pole is on without a lure
	agility = true, -- the third button: agility food, then agility elixir
	lowCount = 5, -- below this many of either in the bags, the agility button shows a buy reminder
	locked = false,
	shown = true,
}

-- Agility food by item id, from the Forever client's item table (build 1.60.1.70888): on Forever the old Stamina
-- and Spirit well-fed dishes give Agility, by tier. agi is the Well Fed bonus, level the required level.
Logic.AGILITY_FOOD = {
	{ id = 238638, name = "Filet o' Flank", agi = 25, level = 55 },
	{ id = 250069, name = "Flank au Poivre", agi = 20, level = 45 },
	{ id = 250072, name = "Swiftstrike Steak", agi = 20, level = 45 },
	{ id = 12212, name = "Jungle Stew", agi = 15, level = 35 },
	{ id = 18045, name = "Tender Wolf Steak", agi = 15, level = 35 },
	{ id = 287973, name = "Tender Wolf Steak", agi = 15, level = 1 },
	{ id = 3728, name = "Tasty Lion Steak", agi = 10, level = 25 },
	{ id = 13851, name = "Hot Wolf Ribs", agi = 10, level = 25 },
	{ id = 20074, name = "Heavy Crocolisk Stew", agi = 10, level = 25 },
	{ id = 1017, name = "Seasoned Wolf Kabob", agi = 5, level = 15 },
	{ id = 3727, name = "Hot Lion Chops", agi = 5, level = 15 },
	{ id = 3664, name = "Crocolisk Gumbo", agi = 5, level = 15 },
	{ id = 12209, name = "Lean Wolf Steak", agi = 5, level = 15 },
	{ id = 2684, name = "Coyote Steak", agi = 3, level = 5 },
	{ id = 3662, name = "Crocolisk Steak", agi = 3, level = 5 },
	{ id = 2680, name = "Spiced Wolf Meat", agi = 1, level = 1 },
}

-- Agility elixirs (Forever has no item called "agility potion": the battle elixirs are the agility drinks). score is
-- the Agility, plus 2 for the Mongoose's crit, so it wins its tie with Greater Agility.
Logic.AGILITY_ELIXIRS = {
	{ id = 13452, name = "Elixir of the Mongoose", agi = 25, score = 27, level = 46 },
	{ id = 9187, name = "Elixir of Greater Agility", agi = 25, score = 25, level = 38 },
	{ id = 250328, name = "Elixir of Cunning", agi = 25, score = 25, level = 55 },
	{ id = 250350, name = "Elixir of Ferocity", agi = 18, score = 18, level = 55 },
	{ id = 8949, name = "Elixir of Agility", agi = 15, score = 15, level = 27 },
	{ id = 3390, name = "Elixir of Lesser Agility", agi = 8, score = 8, level = 18 },
	{ id = 2457, name = "Elixir of Minor Agility", agi = 4, score = 4, level = 2 },
}

-- The buffs they give, by spell id: either Well Fed (the tiered one, and Filet o' Flank's own), and each elixir's.
Logic.FOOD_BUFFS = { 1248420, 1225779 }
Logic.ELIXIR_BUFFS = { 17538, 11334, 1250918, 1250985, 11328, 3160, 2374 }

local function index(list)
	local byID, byName = {}, {}
	for _, e in ipairs(list) do
		byID[e.id] = e
		byName[e.name] = byName[e.name] or e
	end
	return byID, byName
end
local FOOD_BY_ID, FOOD_BY_NAME = index(Logic.AGILITY_FOOD)
local ELIXIR_BY_ID, ELIXIR_BY_NAME = index(Logic.AGILITY_ELIXIRS)
local STONE_BY_ID, STONE_BY_NAME = index(Logic.SHARPENING_STONES)

-- Which hand choice a temporary weapon enchant belongs to, by SpellItemEnchantment id, from the Forever client's
-- table (build 1.60.1.71037): each poison family's ranks, and the sharpening stones ("Sharpened +2" to "+8" and the
-- Elemental stone's "Critical +2%"). A hand set to one poison family is not done while another one is on it.
Logic.ENCHANT_KIND = {}
for kind, ids in pairs({
	["Instant Poison"] = { 323, 324, 325, 623, 624, 625 },
	["Deadly Poison"] = { 7, 8, 626, 627, 2630 },
	["Crippling Poison"] = { 22, 603 },
	["Mind-numbing Poison"] = { 35, 23, 643 },
	["Wound Poison"] = { 703, 704, 705, 706 },
	[Logic.STONE] = { 40, 13, 14, 483, 1643, 2506 },
}) do
	for _, id in ipairs(ids) do
		Logic.ENCHANT_KIND[id] = kind
	end
end
-- the choices the table can judge; any other setting (empty, a family it lacks) takes whatever is on
Logic.ENCHANT_KIND_CHOICE = {}
for _, kind in pairs(Logic.ENCHANT_KIND) do
	Logic.ENCHANT_KIND_CHOICE[kind] = true
end

-- Enum.ItemEnchantType: on Forever a weapon holds a stone (Temporary) and a poison (Imbue) at once, one of each.
Logic.ENCHANT_TEMPORARY = 2
Logic.ENCHANT_IMBUE = 3

-- What a hand carries against what it is set to. enchants: { { id =, type = } } for its non-permanent enchants,
-- nil when the game hides them. choice: the hand's poison family, or Logic.STONE for "stone only, no poison".
-- wantStone: a stone goes on this hand too. Returns poisoned, on, stoned:
--   poisoned: the chosen family is on (true when the hand takes no poison); on: the other family on it instead
--   stoned: a sharpening stone is on (true when the hand takes none)
-- An enchant the table does not know (a new rank, an oil) fills its slot: better quiet than a wrong nag.
function Logic.handState(enchants, choice, wantStone)
	if enchants == nil then
		return nil, nil, nil
	end
	local stoneOnly = choice == Logic.STONE
	local poisoned = stoneOnly or Logic.ENCHANT_KIND_CHOICE[choice] == nil
	local stoned = not (wantStone or stoneOnly)
	local on
	for _, e in ipairs(enchants) do
		local kind = Logic.ENCHANT_KIND[e.id]
		if kind == Logic.STONE or (kind == nil and e.type == Logic.ENCHANT_TEMPORARY) then
			stoned = true
		elseif kind == nil or kind == choice then
			poisoned = true
		else
			on = on or kind
		end
	end
	if poisoned then
		on = nil
	end
	return poisoned, on, stoned
end

function Logic.stoneEntry(item)
	return STONE_BY_ID[item.id] or STONE_BY_NAME[item.name]
end

-- The table entry for a bag item (by id, then by name for a Forever copy under another id), or nil.
function Logic.foodEntry(item)
	return FOOD_BY_ID[item.id] or FOOD_BY_NAME[item.name]
end

function Logic.elixirEntry(item)
	return ELIXIR_BY_ID[item.id] or ELIXIR_BY_NAME[item.name]
end

-- Default keys, set once (only on a key that is free or already ours) and then left to Options > Keybindings.
Logic.KEYS = {
	{ key = "SHIFT-`", command = "CLICK BaitAndBladeFishButton:LeftButton", label = "Fishing button" },
	{ key = "CTRL-`", command = "CLICK BaitAndBladePoisonButton:LeftButton", label = "Weapons and poisons button" },
}

-- What to do with one default key: "set", "ours" (already bound to it) or "taken" (the player bound it to
-- something else: never overwritten) or "kept" (the command already has another key: the player chose it).
-- bound is GetBindingAction(key); commandHasKey whether GetBindingKey(command) gives any key.
function Logic.keyPlan(bound, command, commandHasKey)
	if bound == command then
		return "ours"
	end
	if commandHasKey then
		return "kept"
	end
	if bound == nil or bound == "" then
		return "set"
	end
	return "taken"
end

-- Fishing lures by item id, then by name (a Forever item id that differs still matches by name): skill bonus.
Logic.LURES_BY_ID = {
	[6529] = 25, -- Shiny Bauble
	[6530] = 50, -- Nightcrawlers
	[6811] = 50, -- Aquadynamic Fish Lens
	[6532] = 75, -- Bright Baubles
	[7307] = 75, -- Flesh Eating Worm
	[6533] = 100, -- Aquadynamic Fish Attractor
}
Logic.LURES_BY_NAME = {
	["Shiny Bauble"] = 25,
	["Nightcrawlers"] = 50,
	["Aquadynamic Fish Lens"] = 50,
	["Bright Baubles"] = 75,
	["Flesh Eating Worm"] = 75,
	["Aquadynamic Fish Attractor"] = 100,
}

-- Fishing poles by item id: skill bonus. Any other weapon of the Fishing Pole subclass counts as +0.
Logic.POLES_BY_ID = {
	[6256] = 0, -- Fishing Pole
	[12225] = 3, -- Blump Family Fishing Pole
	[6365] = 5, -- Strong Fishing Pole
	[6366] = 15, -- Darkwood Fishing Pole
	[6367] = 20, -- Big Iron Fishing Pole
	[19022] = 25, -- Nat Pagle's Extreme Angler FC-5000
	[19970] = 35, -- Arcanite Fishing Pole
}
Logic.WEAPON_CLASS = 2
Logic.FISHING_POLE_SUBCLASS = 20

local ROMAN = { I = 1, II = 2, III = 3, IV = 4, V = 5, VI = 6, VII = 7, VIII = 8, IX = 9, X = 10 }

-- The rank of a poison in its family: "Instant Poison VI" -> 6, "Crippling Poison" -> 1, anything else -> nil.
function Logic.poisonRank(name, family)
	if type(name) ~= "string" or type(family) ~= "string" then
		return nil
	end
	if name == family then
		return 1
	end
	if name:sub(1, #family + 1) ~= family .. " " then
		return nil
	end
	return ROMAN[name:sub(#family + 2)]
end

function Logic.lureBonus(item)
	return Logic.LURES_BY_ID[item.id] or Logic.LURES_BY_NAME[item.name]
end

function Logic.isPole(item)
	return item.classID == Logic.WEAPON_CLASS and item.subclassID == Logic.FISHING_POLE_SUBCLASS
end

function Logic.poleBonus(item)
	if not Logic.isPole(item) then
		return nil
	end
	return Logic.POLES_BY_ID[item.id] or 0
end

-- The item with the highest score; items the client calls unusable (level or skill too low) are skipped.
-- Ties go to the higher item level, then the lower id, so the pick is stable.
function Logic.best(items, score)
	local bestItem, bestScore
	for _, item in ipairs(items) do
		local s = item.usable ~= false and score(item) or nil
		if s then
			local better = not bestItem
				or s > bestScore
				or (s == bestScore and (item.itemLevel or 0) > (bestItem.itemLevel or 0))
				or (s == bestScore and (item.itemLevel or 0) == (bestItem.itemLevel or 0) and item.id < bestItem.id)
			if better then
				bestItem, bestScore = item, s
			end
		end
	end
	return bestItem
end

function Logic.bestPoison(items, family)
	return Logic.best(items, function(item)
		return Logic.poisonRank(item.name, family)
	end)
end

function Logic.bestStone(items)
	return Logic.best(items, function(item)
		local e = Logic.stoneEntry(item)
		return e and e.score
	end)
end

-- The best poison in the bags for a hand's choice (nil for a stone-only hand: its stone comes from bestStone).
function Logic.bestFor(items, choice)
	if choice == Logic.STONE then
		return nil
	end
	return Logic.bestPoison(items, choice)
end

function Logic.bestLure(items)
	return Logic.best(items, Logic.lureBonus)
end

function Logic.bestPole(items)
	return Logic.best(items, Logic.poleBonus)
end

function Logic.bestFood(items)
	return Logic.best(items, function(item)
		local e = Logic.foodEntry(item)
		return e and e.agi
	end)
end

function Logic.bestElixir(items)
	return Logic.best(items, function(item)
		local e = Logic.elixirEntry(item)
		return e and e.score
	end)
end

-- How many of a kind the bags hold, usable ones only (item.count is the stack total; 1 when unknown).
function Logic.countOf(items, entry)
	local n = 0
	for _, item in ipairs(items) do
		if item.usable ~= false and entry(item) then
			n = n + (item.count or 1)
		end
	end
	return n
end

-- What each kind of buy reminder lists, and its tooltip header.
Logic.SHOP_KINDS = {
	food = { list = Logic.AGILITY_FOOD, header = "Buy agility food:" },
	elixir = { list = Logic.AGILITY_ELIXIRS, header = "Buy an agility elixir:" },
	stone = { list = Logic.SHARPENING_STONES, header = "Buy sharpening stones:" },
}

-- What to buy for one kind ("food", "elixir" or "stone") at a player level: the entries the player can use,
-- strongest first. prices[id] is the TSM price in copper (nil: no data). cheapest is the cheapest priced entry of
-- the strongest tier that has a price, so the pick is "the best you can get on the auction house right now".
-- Each row's bonus is the text the tooltip shows ("+15 Agi", "+8 damage").
function Logic.shoppingList(kind, level, prices, limit)
	local list = Logic.SHOP_KINDS[kind].list
	local rows = {}
	for _, e in ipairs(list) do
		if (e.level or 1) <= (level or 60) then
			rows[#rows + 1] = {
				id = e.id,
				name = e.name,
				agi = e.agi,
				bonus = e.bonus or ("+" .. e.agi .. " Agi"),
				score = e.score or e.agi,
				price = prices[e.id],
			}
		end
	end
	table.sort(rows, function(a, b)
		if a.score ~= b.score then
			return a.score > b.score
		end
		return a.id < b.id
	end)
	local cheapest
	for _, r in ipairs(rows) do
		if r.price then
			if cheapest and r.score < cheapest.score then
				break
			end
			if not cheapest or r.price < cheapest.price then
				cheapest = r
			end
		end
	end
	local shown = {}
	for i = 1, math.min(#rows, limit or #rows) do
		shown[i] = rows[i]
	end
	return shown, cheapest
end

-- The macro line that uses an item: by name (what /use expects), by id when the name is not loaded.
local function useLine(item)
	return "/use " .. (item.name or ("item:" .. item.id))
end

-- What the fishing button does next.
-- s.poleEquipped: the main hand holds a fishing pole
-- s.lure: true / false, nil when unknown (the client hid the enchant: a secret value)
-- s.pole, s.bestLure: the best pole and lure in the bags (nil when none)
-- s.castFishing, s.glowFishing: settings; s.fishingSpell: the localized spell name
-- Returns { macro = text or nil, label, reason, glow, icon = item or nil }.
function Logic.fishStep(s)
	if s.unknown then
		-- s.unknown is the reason (item info loading, or hidden by the game)
		local reason = type(s.unknown) == "string" and s.unknown or "equipped item info not loaded yet"
		return { label = "Waiting", reason = reason }
	end
	local cast = s.castFishing and ("/cast " .. (s.fishingSpell or "Fishing")) or nil
	if not s.poleEquipped then
		if s.pole then
			return { macro = "/equip " .. s.pole.name, label = "Equip " .. s.pole.name, reason = "pole", icon = s.pole }
		end
		return { label = "No fishing pole", reason = "no fishing pole in your bags" }
	end
	if s.lure == nil then
		return { macro = cast, label = "Fish", reason = "lure unknown (the game hides it here)" }
	end
	if s.lure then
		return { macro = cast, label = "Fish", reason = "pole and lure on" }
	end
	if s.bestLure then
		return {
			macro = useLine(s.bestLure) .. "\n/use 16",
			label = "Apply " .. s.bestLure.name,
			reason = "no lure on the pole",
			glow = s.glowFishing and true or false,
			icon = s.bestLure,
		}
	end
	return { macro = cast, label = "Fish", reason = "no lure on the pole and none in your bags" }
end

local function wanted(name)
	return type(name) == "string" and name ~= ""
end

-- What the poison button does next.
-- s.mhName, s.ohName: the equipped weapons' names; s.wantMH, s.wantOH: the configured ones ("" = don't care)
-- s.haveMH, s.haveOH: the configured weapon is in the bags (or equipped)
-- s.mhPoisoned, s.ohPoisoned: the hand carries its chosen poison: true / false, nil when unknown (secret)
-- s.mhOn, s.ohOn: when not, the other poison family on it, or nil
-- s.mhStoned, s.ohStoned: the hand carries the stone it wants (true when it wants none); s.stone: the best in the bags
-- s.mhPoison, s.ohPoison: the best poison of each hand's family in the bags; s.mhFamily, s.ohFamily: their names
function Logic.poisonStep(s)
	if s.unknown then
		-- s.unknown is the reason (item info loading, or hidden by the game)
		local reason = type(s.unknown) == "string" and s.unknown or "equipped item info not loaded yet"
		return { label = "Waiting", reason = reason }
	end
	local lines, missing = {}, {}
	if wanted(s.wantMH) and s.mhName ~= s.wantMH then
		if s.haveMH then
			lines[#lines + 1] = "/equipslot 16 " .. s.wantMH
		else
			missing[#missing + 1] = s.wantMH
		end
	end
	if wanted(s.wantOH) and s.ohName ~= s.wantOH then
		if s.haveOH then
			lines[#lines + 1] = "/equipslot 17 " .. s.wantOH
		else
			missing[#missing + 1] = s.wantOH
		end
	end
	if #lines > 0 then
		return {
			macro = table.concat(lines, "\n"),
			label = "Equip weapons",
			reason = #missing > 0 and ("not in your bags: " .. table.concat(missing, ", ")) or "weapons",
		}
	end
	if #missing > 0 then
		return { label = "Weapons missing", reason = "not in your bags: " .. table.concat(missing, ", ") }
	end
	if s.mhPoisoned == nil or s.ohPoisoned == nil then
		return { label = "Poisons", reason = "poison state unknown (the game hides it here)" }
	end
	if s.mhStoned == nil or s.ohStoned == nil then
		return { label = "Stones", reason = "stone state unknown (the game hides it here)" }
	end
	-- A weapon holds one poison and one sharpening stone at once. Poisons first, main hand first; a hand with another
	-- poison family on it gets the same click (the new poison replaces the old).
	local function poisonReason(hand, on)
		return on and (hand .. " has " .. on .. ", set to another poison") or (hand .. " has no poison")
	end
	local function need(done, item, slot, hand, reason)
		return { done = done, item = item, slot = slot, hand = hand, reason = reason }
	end
	local needs = {
		need(s.mhPoisoned, s.mhPoison, 16, "Main hand", poisonReason("main hand", s.mhOn)),
		need(s.ohPoisoned, s.ohPoison, 17, "Off hand", poisonReason("off hand", s.ohOn)),
		need(s.mhStoned, s.stone, 16, "Main hand", "main hand has no sharpening stone"),
		need(s.ohStoned, s.stone, 17, "Off hand", "off hand has no sharpening stone"),
	}
	for _, n in ipairs(needs) do
		if not n.done and n.item then
			return {
				macro = useLine(n.item) .. "\n/use " .. n.slot,
				label = n.hand .. ": " .. n.item.name,
				reason = n.reason,
				glow = true,
				icon = n.item,
			}
		end
	end
	local want = {}
	if not s.mhPoisoned then
		want[#want + 1] = s.mhFamily or "main hand poison"
	end
	if not s.ohPoisoned and s.ohFamily ~= s.mhFamily then
		want[#want + 1] = s.ohFamily or "off hand poison"
	end
	local outOfStones = not s.mhStoned or not s.ohStoned
	if outOfStones then
		want[#want + 1] = "sharpening stones"
	end
	if #want > 0 then
		local step =
			{ label = "Out of poison", reason = "none in your bags: " .. table.concat(want, ", "), glow = true }
		-- stones have a shopping list (TSM prices on mouseover)
		if outOfStones then
			step.buy = { "stone" }
			if #want == 1 then
				step.label = "Out of sharpening stones"
			end
		end
		return step
	end
	return { label = "Poisoned", reason = "both weapons have their poison and stone on" }
end

local KIND_NAME = { food = "agility food", elixir = "agility elixir" }

-- What the agility button does next: food first, then the elixir.
-- s.fed, s.elixirUp: the buff is on (true / false), nil when unknown (s.unknown says why)
-- s.food, s.elixir: the strongest of each in the bags (nil when none); s.foodCount, s.elixirCount: totals
-- s.lowCount: below this many, remind to buy
-- Returns { macro, label, reason, glow, icon, buy = { "food" / "elixir" ... } or nil, hidden }.
-- hidden: both buffs on and enough of both: the button shows only under the mouse.
function Logic.agilityStep(s)
	if s.unknown then
		return { label = "Waiting", reason = s.unknown }
	end
	local low = s.lowCount or 5
	local buy = {}
	if not s.fed and not s.food then
		buy[#buy + 1] = "food"
	end
	if not s.elixirUp and not s.elixir then
		buy[#buy + 1] = "elixir"
	end
	local function needs()
		local names = {}
		for _, k in ipairs(buy) do
			names[#names + 1] = KIND_NAME[k]
		end
		return table.concat(names, " and ")
	end
	local step
	if not s.fed and s.food then
		step = {
			macro = useLine(s.food),
			label = "Eat " .. s.food.name,
			reason = "no Well Fed buff (sit 10 seconds to get it)",
			glow = true,
			icon = s.food,
		}
	elseif not s.elixirUp and s.elixir then
		step = {
			macro = useLine(s.elixir),
			label = "Drink " .. s.elixir.name,
			reason = "no agility elixir on",
			glow = true,
			icon = s.elixir,
		}
	end
	if step then
		if #buy > 0 then
			step.buy = buy
			step.reason = step.reason .. "; none in your bags: " .. needs()
		end
		return step
	end
	if #buy > 0 then
		return { label = "Buy " .. needs(), reason = "buff missing and none in your bags", buy = buy, shop = true }
	end
	-- both buffs on: remind when either runs low
	if (s.foodCount or 0) < low then
		buy[#buy + 1] = "food"
	end
	if (s.elixirCount or 0) < low then
		buy[#buy + 1] = "elixir"
	end
	if #buy > 0 then
		local line = "buffed; running low: %d food, %d elixirs left"
		return {
			label = "Low on " .. needs(),
			reason = line:format(s.foodCount or 0, s.elixirCount or 0),
			buy = buy,
			shop = true,
		}
	end
	local line = "Well Fed and elixir on; %d food, %d elixirs in your bags"
	return { label = "Buffed", reason = line:format(s.foodCount or 0, s.elixirCount or 0), hidden = true }
end

-- On a flight path nothing can be used and nothing bought: the step loses its macro, glow and buy reminder, and
-- names what waits for the landing. A buy reminder goes out of sight altogether (shown under the mouse only), as
-- does a step that was already hidden.
function Logic.onTaxi(step)
	return {
		label = "On a flight path",
		reason = "after you land: " .. tostring(step.label),
		icon = step.icon,
		hidden = step.hidden or step.shop or step.buy ~= nil or nil,
		taxi = true,
	}
end

return Logic
