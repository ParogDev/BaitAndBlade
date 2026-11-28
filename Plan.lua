-- Pure decisions about consumables, no client calls: per slot (food, elixir, a poison per hand, a sharpening stone)
-- the ladder of items for the player's choice, the one to recommend, what to remind about and what to buy.
-- Core.lua gathers the state from the client; Panel.lua and the ForeverAuras pack show the answers.
local _, ns = ...

local Logic = ns.Logic
local Data = ns.Data

local Plan = {}
ns.Plan = Plan

Plan.NONE = "None"
Plan.SLOTS = { "food", "elixir", "mainHand", "offHand", "stone" }

local POISON_CHOICES = { Plan.NONE }
for _, family in ipairs(Logic.POISON_FAMILIES) do
	POISON_CHOICES[#POISON_CHOICES + 1] = family
end

-- title: the row in the picker. verb: what the reminder says to do with the item. rogue: only rogues get the slot.
Plan.SLOT = {
	food = { title = "Food", verb = "Eat", missing = "No food buff", choices = Data.STATS },
	elixir = { title = "Elixir", verb = "Drink", missing = "No elixir", choices = Data.STATS },
	mainHand = { title = "Main hand poison", verb = "Main hand:", choices = POISON_CHOICES, rogue = true, hand = true },
	offHand = { title = "Off hand poison", verb = "Off hand:", choices = POISON_CHOICES, rogue = true, hand = true },
	stone = { title = "Sharpening stone", verb = "Sharpen with", choices = { Logic.STONE } },
}

-- The stat a class most likely wants from food and elixirs: a first guess the picker changes.
Plan.CLASS_STAT = {
	ROGUE = "Agility",
	HUNTER = "Agility",
	WARRIOR = "Strength",
	PALADIN = "Strength",
	MAGE = "Spell Power",
	WARLOCK = "Spell Power",
	PRIEST = "Healing",
	DRUID = "Intellect",
	SHAMAN = "Intellect",
}

Plan.LOW_COUNT = 5 -- below this many in the bags a slot goes on the shopping list
Plan.STOCK_TO = 20 -- and the list asks for enough to hold this many

-- The slot settings of a fresh character of this class.
function Plan.defaults(class)
	local stat = Plan.CLASS_STAT[class] or "Stamina"
	local rogue = class == "ROGUE"
	return {
		food = { on = true, choice = stat, skip = {} },
		elixir = { on = true, choice = stat, skip = {} },
		mainHand = { on = rogue, choice = "Instant Poison", skip = {} },
		offHand = { on = rogue, choice = "Crippling Poison", skip = {} },
		stone = { on = rogue, choice = Logic.STONE, skip = {} },
	}
end

-- Fills settings.slots, carrying over what 0.3 stored (a poison per hand, "stones", the agility button's switch).
-- A hand that was set to "Sharpening Stone" took no poison: it becomes None, and the stone slot covers the stone.
function Plan.migrate(settings, class)
	local fresh = Plan.defaults(class)
	local old = type(settings.slots) ~= "table"
	local slots = old and {} or settings.slots
	for _, slot in ipairs(Plan.SLOTS) do
		local cfg = type(slots[slot]) == "table" and slots[slot] or fresh[slot]
		cfg.skip = type(cfg.skip) == "table" and cfg.skip or {}
		slots[slot] = cfg
	end
	if old then
		local function hand(slot, was)
			if type(was) == "string" and was ~= "" then
				slots[slot].choice = was == Logic.STONE and Plan.NONE or was
			end
		end
		hand("mainHand", settings.mainHandPoison)
		hand("offHand", settings.offHandPoison)
		if settings.stones ~= nil then
			slots.stone.on = settings.stones and class == "ROGUE" or false
		end
		if settings.agility ~= nil then
			slots.food.on = settings.agility and true or false
			slots.elixir.on = slots.food.on
			-- 0.3 wrote agility = true for every class (it was the default): only a rogue's carries the stat over,
			-- anyone else keeps the class guess
			if settings.agility and class == "ROGUE" then
				slots.food.choice, slots.elixir.choice = "Agility", "Agility"
			end
		end
		-- the 0.3 keys are carried over: drop them so the saved file shows one source of truth
		settings.mainHandPoison, settings.offHandPoison, settings.stones, settings.agility = nil, nil, nil, nil
	end
	settings.slots = slots
	settings.lowCount = tonumber(settings.lowCount) or Plan.LOW_COUNT
	settings.stockTo = tonumber(settings.stockTo) or Plan.STOCK_TO
	return slots
end

-- Whether a class sees a slot at all.
function Plan.available(slot, class)
	return not Plan.SLOT[slot].rogue or class == "ROGUE"
end

-- A crit point is worth a point of the chosen stat; any other stat on the same item only breaks ties.
local SIDE_WEIGHT = { Crit = 1 }

local function statEntry(e, choice)
	local amount = e.stats[choice]
	if not amount then
		return nil
	end
	local score = amount
	local bonus = "+" .. amount .. " " .. choice
	for _, stat in ipairs(Data.STATS) do
		local side = stat ~= choice and e.stats[stat]
		if side then
			score = score + side * (SIDE_WEIGHT[stat] or 0.01)
			bonus = bonus .. ", +" .. side .. (stat == "Crit" and "% crit" or (" " .. stat))
		end
	end
	if e.limited then
		bonus = bonus .. " (" .. e.limited .. " only)"
	end
	return {
		id = e.id,
		ids = e.ids or { e.id },
		name = e.name,
		level = e.level,
		buff = e.buff,
		limited = e.limited,
		score = score,
		bonus = bonus,
	}
end

local cache = {}

-- Every item of a slot for one choice, strongest first: { id, ids, name, level, score, bonus, buff, limited }.
function Plan.entries(slot, choice)
	local key = slot .. "\0" .. tostring(choice)
	if cache[key] then
		return cache[key]
	end
	local out = {}
	if slot == "food" or slot == "elixir" then
		for _, e in ipairs(Data[slot]) do
			out[#out + 1] = statEntry(e, choice)
		end
	elseif slot == "stone" then
		for _, e in ipairs(Logic.SHARPENING_STONES) do
			out[#out + 1] =
				{ id = e.id, ids = { e.id }, name = e.name, level = e.level, score = e.score, bonus = e.bonus }
		end
	else
		for _, e in ipairs(Data.poisons[choice] or {}) do
			out[#out + 1] =
				{ id = e.id, ids = { e.id }, name = e.name, level = e.level, score = e.rank, bonus = "rank " .. e.rank }
		end
	end
	table.sort(out, function(a, b)
		if a.score ~= b.score then
			return a.score > b.score
		end
		return a.id < b.id
	end)
	cache[key] = out
	return out
end

-- The choices of a slot that have at least one item (a stat no food gives is not offered).
function Plan.choices(slot)
	local out = {}
	for _, choice in ipairs(Plan.SLOT[slot].choices) do
		if choice == Plan.NONE or #Plan.entries(slot, choice) > 0 then
			out[#out + 1] = choice
		end
	end
	return out
end

-- Whether the player ruled a tier out. A school-limited elixir starts ruled out (it only helps one school) until
-- the player ticks it back in: skip[id] is true, false or unset.
function Plan.skipped(cfg, entry)
	local s = cfg.skip and cfg.skip[entry.id]
	if s == nil then
		return entry.limited ~= nil
	end
	return s and true or false
end

-- The ladder the picker shows for a slot: every tier, strongest first, with
--   usable (the level allows it), skipped, price (ctx.prices[id], copper or nil), count (in the bags),
--   recommended: the strongest usable tier that is not skipped; among equals the cheapest, a priced one first.
-- Returns rows, the recommended row (or nil), the best row the bags hold (or nil), the total held.
-- ctx: { level, prices = { [id] = copper }, counts = { [id] = n } }
function Plan.ladder(slot, cfg, ctx)
	local rows, recommended, held, total = {}, nil, nil, 0
	local prices, counts = ctx.prices or {}, ctx.counts or {}
	for _, e in ipairs(Plan.entries(slot, cfg.choice)) do
		local count = 0
		for _, id in ipairs(e.ids) do
			count = count + (counts[id] or 0)
		end
		local row = {
			id = e.id,
			name = e.name,
			level = e.level,
			score = e.score,
			bonus = e.bonus,
			limited = e.limited,
			usable = e.level <= (ctx.level or 60),
			skipped = Plan.skipped(cfg, e),
			price = prices[e.id],
			count = count,
		}
		rows[#rows + 1] = row
		-- a skipped tier is ruled out for using as well as buying: a school-limited elixir in the bags is not what
		-- the reminder offers, and does not count as stock
		if row.usable and not row.skipped then
			total = total + count
			if count > 0 and not held then
				held = row
			end
			local better = not recommended
				or (
					row.score == recommended.score
					and row.price
					and (not recommended.price or row.price < recommended.price)
				)
			if better then
				recommended = row
			end
		end
	end
	if recommended then
		recommended.recommended = true
	end
	return rows, recommended, held, total
end

-- The buff spell ids that count as "this slot's buff is on" for a choice.
function Plan.buffs(slot, choice)
	local ids, seen = {}, {}
	for _, e in ipairs(Plan.entries(slot, choice)) do
		if e.buff and not seen[e.buff] then
			seen[e.buff] = true
			ids[#ids + 1] = e.buff
		end
	end
	return ids
end

local function quiet(slot)
	return { slot = slot, show = false }
end

-- One slot's reminder. missing: the buff or enchant is off (nil: the game hides it, keep the last answer).
local function remind(slot, cfg, ctx, missing)
	local spec = Plan.SLOT[slot]
	local rows, recommended, held, total = Plan.ladder(slot, cfg, ctx)
	local r = { slot = slot, show = false, count = total, rows = rows, recommended = recommended, held = held }
	-- the stock does not depend on the buff, so the shopping line stays while the game hides the buff
	if recommended and total < (ctx.lowCount or Plan.LOW_COUNT) then
		r.buy = {
			slot = slot,
			id = recommended.id,
			name = recommended.name,
			bonus = recommended.bonus,
			have = total,
			need = math.max(1, (ctx.stockTo or Plan.STOCK_TO) - total),
			price = recommended.price,
		}
	end
	if missing == nil then
		r.unknown = true
		return r
	end
	if missing then
		r.show = true
		if held then
			r.kind, r.id, r.name = "use", held.id, held.name
			r.text = spec.verb .. " " .. held.name
		elseif recommended then
			r.kind, r.id, r.name = "buy", recommended.id, recommended.name
			r.text = "Buy " .. recommended.name
		else
			r.kind = "none"
			r.text = spec.missing or (spec.title .. ": nothing for your level")
		end
	end
	return r
end

-- Everything to remind about and to buy.
-- settings: { slots = { [slot] = { on, choice, skip } } }
-- ctx: level, class, prices, counts, lowCount, stockTo, flying,
--   buffUp = function(spellIDs) -> true / false / nil (hidden),
--   hands = { mainHand = h, offHand = h }, h = { weapon = bool, poisoned, stoned } (nil: hidden by the game)
-- Returns { reminders = { [slot] = r }, shopping = { buy rows, dearest need first by slot order } }.
function Plan.evaluate(settings, ctx)
	local out = { reminders = {}, shopping = {} }
	local byID = {}
	for _, slot in ipairs(Plan.SLOTS) do
		local cfg = settings.slots[slot]
		local spec = Plan.SLOT[slot]
		local r
		if not cfg.on or cfg.choice == Plan.NONE or not Plan.available(slot, ctx.class) then
			r = quiet(slot)
		elseif slot == "stone" then
			local mh, oh = ctx.hands.mainHand, ctx.hands.offHand
			local missing = false
			if (mh.weapon and mh.stoned == nil) or (oh.weapon and oh.stoned == nil) then
				missing = nil
			elseif (mh.weapon and not mh.stoned) or (oh.weapon and not oh.stoned) then
				missing = true
			end
			r = remind(slot, cfg, ctx, missing)
		elseif spec.hand then
			local h = ctx.hands[slot]
			local missing = false
			if h.weapon then
				if h.poisoned == nil then
					missing = nil
				else
					missing = not h.poisoned
				end
			end
			r = remind(slot, cfg, ctx, missing)
		else
			local up = ctx.buffUp(Plan.buffs(slot, cfg.choice))
			local missing = nil
			if up ~= nil then
				missing = not up
			end
			r = remind(slot, cfg, ctx, missing)
		end
		if ctx.flying then
			r.show = false
		end
		out.reminders[slot] = r
		local b = r.buy
		if b then
			if byID[b.id] then
				-- both hands on one poison: one line
				byID[b.id].need = math.max(byID[b.id].need, b.need)
			else
				byID[b.id] = b
				out.shopping[#out.shopping + 1] = b
			end
		end
	end
	return out
end

return Plan
