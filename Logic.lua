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

Logic.DEFAULTS = {
	mainHandWeapon = "Dazzling Longsword",
	offHandWeapon = "Sword of Omen",
	mainHandPoison = "Instant Poison",
	offHandPoison = "Crippling Poison",
	castFishing = true, -- the fishing button casts Fishing once the pole and the lure are on
	glowFishing = true, -- the fishing button glows when the pole is on without a lure
	locked = false,
	shown = true,
}

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

-- What the poison button does next.
-- s.mhName, s.ohName: the equipped weapons' names; s.wantMH, s.wantOH: the configured ones ("" = don't care)
-- s.haveMH, s.haveOH: the configured weapon is in the bags (or equipped)
-- s.mhPoisoned, s.ohPoisoned: true / false, nil when unknown (secret)
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
	local glow = not s.mhPoisoned or not s.ohPoisoned
	if not s.mhPoisoned and s.mhPoison then
		return {
			macro = useLine(s.mhPoison) .. "\n/use 16",
			label = "Main hand: " .. s.mhPoison.name,
			reason = "main hand has no poison",
			glow = true,
			icon = s.mhPoison,
		}
	end
	if not s.ohPoisoned and s.ohPoison then
		return {
			macro = useLine(s.ohPoison) .. "\n/use 17",
			label = "Off hand: " .. s.ohPoison.name,
			reason = "off hand has no poison",
			glow = true,
			icon = s.ohPoison,
		}
	end
	if glow then
		local want = {}
		if not s.mhPoisoned then
			want[#want + 1] = s.mhFamily or "main hand poison"
		end
		if not s.ohPoisoned and s.ohFamily ~= s.mhFamily then
			want[#want + 1] = s.ohFamily or "off hand poison"
		end
		return { label = "Out of poison", reason = "none in your bags: " .. table.concat(want, ", "), glow = true }
	end
	return { label = "Poisoned", reason = "both weapons poisoned" }
end

return Logic
