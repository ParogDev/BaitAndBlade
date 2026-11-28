-- Pure decisions, no client calls: which pole and lure in the bags is best, what the next click of each button
-- should do, what a weapon's enchants mean and which weapons to remember. Core.lua gathers the state from the
-- client and turns the answer into a secure macro; Plan.lua decides about consumables.
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

-- On Forever a weapon holds a poison and a sharpening stone at the same time. The stone slot's one choice, and the
-- enchant kind of every stone.
Logic.STONE = "Sharpening Stone"

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

-- Plan.migrate owns the consumable settings (slots, lowCount, stockTo) and reads the 0.3 keys it replaces.
Logic.DEFAULTS = {
	mainHandWeapon = "", -- the weapons the weapons button puts back, remembered from what the player wears
	offHandWeapon = "",
	castFishing = true, -- the fishing button casts Fishing once the pole and the lure are on
	glowFishing = true, -- the fishing button glows when the pole is on without a lure
	locked = false,
	shown = true,
}

-- Which choice a temporary weapon enchant belongs to, by SpellItemEnchantment id, from the Forever client's
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
-- the choices the table can judge; any other setting (nil, a family it lacks) takes whatever is on
Logic.ENCHANT_KIND_CHOICE = {}
for _, kind in pairs(Logic.ENCHANT_KIND) do
	Logic.ENCHANT_KIND_CHOICE[kind] = true
end

-- Enum.ItemEnchantType: on Forever a weapon holds a stone (Temporary) and a poison (Imbue) at once, one of each.
Logic.ENCHANT_TEMPORARY = 2
Logic.ENCHANT_IMBUE = 3

-- What a hand carries against what it is set to. enchants: { { id =, type = } } for its non-permanent enchants,
-- nil when the game hides them. choice: the hand's poison family, nil for "no poison wanted" (whatever is on
-- counts), or Logic.STONE for "stone only, no poison". wantStone: a stone goes on this hand too.
-- Returns poisoned, on, stoned:
--   poisoned: the chosen family is on (true when the hand takes no poison); on: the other family on it instead
--   stoned: a sharpening stone is on (true when the hand takes none)
-- An enchant the table does not know (a new rank, an oil) fills its slot: better quiet than a wrong nag.
function Logic.handState(enchants, choice, wantStone)
	if enchants == nil then
		return nil, nil, nil
	end
	local stoneOnly = choice == Logic.STONE
	local poisoned = stoneOnly or choice == nil or Logic.ENCHANT_KIND_CHOICE[choice] == nil
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

-- Default keys, set once (only on a key that is free or already ours) and then left to Options > Keybindings.
-- The weapons button keeps its 0.3 frame name: players have it bound.
Logic.KEYS = {
	{ key = "SHIFT-`", command = "CLICK BaitAndBladeFishButton:LeftButton", label = "Fishing button" },
	{ key = "CTRL-`", command = "CLICK BaitAndBladePoisonButton:LeftButton", label = "Weapons button" },
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

function Logic.bestLure(items)
	return Logic.best(items, Logic.lureBonus)
end

function Logic.bestPole(items)
	return Logic.best(items, Logic.poleBonus)
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

-- What the weapons button does next: put the remembered weapons back, nothing else (poisons, stones, food and
-- elixirs are reminders the ForeverAuras pack shows).
-- s.mhName, s.ohName: the equipped weapons' names; s.wantMH, s.wantOH: the remembered ones ("" = none)
-- s.haveMH, s.haveOH: the remembered weapon is in the bags (or equipped)
-- Returns { macro = text or nil, label, reason, glow }.
function Logic.weaponStep(s)
	if s.unknown then
		-- s.unknown is the reason (item info loading, or hidden by the game)
		local reason = type(s.unknown) == "string" and s.unknown or "equipped item info not loaded yet"
		return { label = "Waiting", reason = reason }
	end
	if not wanted(s.wantMH) and not wanted(s.wantOH) then
		return {
			label = "No weapons remembered",
			reason = "wear your weapons once (not the fishing pole) and this button remembers them",
		}
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
			glow = true,
		}
	end
	if #missing > 0 then
		return { label = "Weapons missing", reason = "not in your bags: " .. table.concat(missing, ", ") }
	end
	return { label = "Weapons on", reason = "your remembered weapons are in your hands" }
end

-- The weapons to remember after an equipment change. mh, oh: { name, pole, twoHand } for what each hand holds, nil
-- for an empty hand. wantMH, wantOH: the names remembered so far. Returns the two names to store.
--   main hand empty or a fishing pole: keep both (fishing, or mid-swap)
--   both hands hold something: remember both
--   off hand empty, two-hander in the main hand: that weapon and no off hand
--   off hand empty, one-hander in the main hand: the new main hand, and keep the off hand (the pole came off the
--   main hand first, the off hand follows)
function Logic.rememberWeapons(mh, oh, wantMH, wantOH)
	wantMH, wantOH = wantMH or "", wantOH or ""
	if not mh or mh.pole then
		return wantMH, wantOH
	end
	if oh then
		return mh.name, oh.name
	end
	if mh.twoHand then
		return mh.name, ""
	end
	return mh.name, wantOH
end

-- On a flight path nothing can be used: the step loses its macro and glow and names what waits for the landing.
function Logic.onTaxi(step)
	return {
		label = "On a flight path",
		reason = "after you land: " .. tostring(step.label),
		icon = step.icon,
		hidden = step.hidden or nil,
		taxi = true,
	}
end

return Logic
