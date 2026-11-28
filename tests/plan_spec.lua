local ns = {}
for _, f in ipairs({ "Logic.lua", "Data.lua", "Plan.lua" }) do
	assert(loadfile(f))("BaitAndBlade", ns)
end
local Plan, Logic, Data = ns.Plan, ns.Logic, ns.Data

local FILET, STEW, WOLF, WOLF_COPY, LION = 238638, 12212, 18045, 287973, 3728
local MONGOOSE, CUNNING, GREATER_AGI, MINOR_AGI = 13452, 250328, 9187, 2457
local SHADOW, HOLY, NATURE, GREATER_ARCANE = 9264, 21546, 250343, 13454
local IP6, CP2, ELEMENTAL, DENSE = 8928, 3776, 18262, 12404

local function ids(rows)
	local out = {}
	for i, r in ipairs(rows) do
		out[i] = r.id
	end
	return out
end

describe("Plan.migrate", function()
	it("carries the 0.3 rogue settings over and drops the old keys", function()
		local s = {
			mainHandPoison = "Deadly Poison",
			offHandPoison = "Sharpening Stone",
			stones = false,
			agility = true,
			lowCount = 3,
		}
		local slots = Plan.migrate(s, "ROGUE")
		assert.equal(s.slots, slots)
		assert.equal("Deadly Poison", slots.mainHand.choice)
		assert.is_true(slots.mainHand.on)
		-- a hand set to the stone took no poison: None, and the stone slot covers the stone
		assert.equal(Plan.NONE, slots.offHand.choice)
		assert.is_false(slots.stone.on)
		assert.is_true(slots.food.on)
		assert.equal("Agility", slots.food.choice)
		assert.equal("Agility", slots.elixir.choice)
		assert.equal(3, s.lowCount)
		assert.equal(Plan.STOCK_TO, s.stockTo)
		assert.is_nil(s.mainHandPoison)
		assert.is_nil(s.offHandPoison)
		assert.is_nil(s.stones)
		assert.is_nil(s.agility)
		for _, slot in ipairs(Plan.SLOTS) do
			assert.is_table(slots[slot].skip)
		end
	end)

	it("is idempotent: a second run keeps what the player changed since", function()
		local s = { mainHandPoison = "Wound Poison" }
		Plan.migrate(s, "ROGUE")
		s.slots.mainHand.choice = "Instant Poison"
		s.slots.food.skip[STEW] = true
		s.mainHandPoison = "Wound Poison" -- even a stale old key does not win again
		Plan.migrate(s, "ROGUE")
		assert.equal("Instant Poison", s.slots.mainHand.choice)
		assert.is_true(s.slots.food.skip[STEW])
	end)

	it("an agility switch turned off turns food and elixir off", function()
		local s = { agility = false }
		Plan.migrate(s, "ROGUE")
		assert.is_false(s.slots.food.on)
		assert.is_false(s.slots.elixir.on)
	end)

	it("a non-rogue keeps its class stat and gets no poison or stone slot", function()
		local s =
			{ mainHandPoison = "Instant Poison", offHandPoison = "Crippling Poison", stones = true, agility = true }
		local slots = Plan.migrate(s, "WARRIOR")
		assert.equal("Strength", slots.food.choice)
		assert.equal("Strength", slots.elixir.choice)
		assert.is_true(slots.food.on)
		assert.is_false(slots.mainHand.on)
		assert.is_false(slots.stone.on)
		assert.is_false(Plan.available("mainHand", "WARRIOR"))
		assert.is_true(Plan.available("stone", "WARRIOR"))
	end)

	it("a fresh character gets its class guess, and an unknown class Stamina", function()
		assert.equal("Spell Power", Plan.migrate({}, "MAGE").food.choice)
		local none = Plan.migrate({}, nil)
		assert.equal("Stamina", none.food.choice)
		assert.is_false(none.mainHand.on)
	end)
end)

describe("Plan.entries and Plan.choices", function()
	it("orders a stat's food and elixirs strongest first, side stats only breaking ties", function()
		local food = Plan.entries("food", "Agility")
		assert.equal(FILET, food[1].id)
		assert.equal("+25 Agility, +10 Stamina", food[1].bonus)
		local elixirs = Plan.entries("elixir", "Agility")
		-- Mongoose's crit counts a full point each, Cunning's intellect only breaks the tie with Greater Agility
		assert.same({ MONGOOSE, CUNNING, GREATER_AGI }, { elixirs[1].id, elixirs[2].id, elixirs[3].id })
		assert.same({ WOLF, WOLF_COPY }, Plan.entries("food", "Agility")[5].ids)
	end)

	it("lists poisons by rank and stones by score", function()
		assert.equal(IP6, Plan.entries("mainHand", "Instant Poison")[1].id)
		assert.equal(CP2, Plan.entries("offHand", "Crippling Poison")[1].id)
		assert.same({}, Plan.entries("mainHand", Plan.NONE))
		assert.equal(ELEMENTAL, Plan.entries("stone", Logic.STONE)[1].id)
		assert.equal(DENSE, Plan.entries("stone", Logic.STONE)[2].id)
	end)

	it("offers only choices that have items, None first for a hand", function()
		local hand = Plan.choices("mainHand")
		assert.equal(Plan.NONE, hand[1])
		assert.equal(#Logic.POISON_FAMILIES + 1, #hand)
		local food = Plan.choices("food")
		local offered = {}
		for _, c in ipairs(food) do
			offered[c] = true
		end
		for _, stat in ipairs(Data.STATS) do
			assert.equal(#Plan.entries("food", stat) > 0, offered[stat] == true)
		end
		assert.same({ Logic.STONE }, Plan.choices("stone"))
	end)

	it("gathers the buff ids of a choice once each", function()
		local buffs = Plan.buffs("food", "Agility")
		assert.truthy(#buffs >= 2)
		local seen = {}
		for _, id in ipairs(buffs) do
			assert.is_nil(seen[id])
			seen[id] = true
		end
		assert.is_true(seen[1248420])
		assert.is_true(seen[1225779])
	end)
end)

describe("Plan.ladder", function()
	local function cfg(choice, skip)
		return { on = true, choice = choice, skip = skip or {} }
	end

	it("gates by level and recommends the strongest usable tier", function()
		local rows, rec = Plan.ladder("food", cfg("Agility"), { level = 40 })
		assert.equal(#Plan.entries("food", "Agility"), #rows)
		assert.is_false(rows[1].usable) -- Filet o' Flank, level 55
		assert.equal(STEW, rec.id) -- ties with Tender Wolf Steak; lower id without prices
		assert.is_true(rec.recommended)
	end)

	it("breaks a tie by price: the cheaper, and a priced one over an unpriced one", function()
		local _, rec = Plan.ladder("food", cfg("Agility"), { level = 40, prices = { [STEW] = 900, [WOLF] = 500 } })
		assert.equal(WOLF, rec.id)
		_, rec = Plan.ladder("food", cfg("Agility"), { level = 40, prices = { [WOLF] = 5000 } })
		assert.equal(WOLF, rec.id)
		_, rec = Plan.ladder("food", cfg("Agility"), { level = 40, prices = { [STEW] = 900, [WOLF] = 1500 } })
		assert.equal(STEW, rec.id)
	end)

	it("skips a tier the player ruled out, for buying and for using", function()
		local rows, rec, held, total =
			Plan.ladder("food", cfg("Agility", { [STEW] = true }), { level = 40, counts = { [STEW] = 4 } })
		assert.equal(WOLF, rec.id)
		assert.is_nil(held)
		assert.equal(0, total)
		for _, r in ipairs(rows) do
			if r.id == STEW then
				assert.is_true(r.skipped)
				assert.equal(4, r.count)
			end
		end
	end)

	it("skips school-limited elixirs by default; skip[id] = false brings one back", function()
		local _, rec = Plan.ladder("elixir", cfg("Spell Power"), { level = 60 })
		assert.equal(GREATER_ARCANE, rec.id)
		local rows
		rows, rec = Plan.ladder("elixir", cfg("Spell Power", { [SHADOW] = false }), { level = 60 })
		assert.equal(SHADOW, rec.id)
		for _, r in ipairs(rows) do
			if r.id == HOLY or r.id == NATURE then
				assert.is_true(r.skipped)
				assert.matches("only%)$", r.bonus)
			end
		end
	end)

	it("counts held items across copy ids, usable tiers only, and names the best held", function()
		local counts = { [WOLF_COPY] = 3, [LION] = 2, [FILET] = 4 }
		local rows, rec, held, total = Plan.ladder("food", cfg("Agility"), { level = 40, counts = counts })
		assert.equal(WOLF, held.id)
		assert.equal(3, held.count)
		assert.equal(5, total) -- Filet o' Flank is too high to count
		assert.equal(STEW, rec.id)
		assert.equal(4, rows[1].count)
	end)

	it("returns no recommendation when nothing is usable", function()
		local rows, rec, held, total = Plan.ladder("elixir", cfg("Agility"), { level = 1 })
		assert.truthy(#rows > 0)
		assert.is_nil(rec)
		assert.is_nil(held)
		assert.equal(0, total)
		assert.equal(MINOR_AGI, rows[#rows].id)
	end)
end)

describe("Plan.evaluate", function()
	local settings
	local function hand(weapon, poisoned, stoned)
		return { weapon = weapon, poisoned = poisoned, stoned = stoned }
	end
	local function ctx(over)
		local c = {
			level = 60,
			class = "ROGUE",
			prices = {},
			counts = {},
			lowCount = 5,
			stockTo = 20,
			flying = false,
			buffUp = function()
				return true
			end,
			hands = { mainHand = hand(true, true, true), offHand = hand(true, true, true) },
		}
		for k, v in pairs(over or {}) do
			c[k] = v
		end
		return c
	end
	local stocked = { [FILET] = 10, [MONGOOSE] = 10, [IP6] = 10, [CP2] = 10, [ELEMENTAL] = 10 }

	before_each(function()
		settings = {}
		Plan.migrate(settings, "ROGUE")
	end)

	it("stays quiet when everything is on and stocked", function()
		local out = Plan.evaluate(settings, ctx({ counts = stocked }))
		for _, slot in ipairs(Plan.SLOTS) do
			assert.is_false(out.reminders[slot].show)
		end
		assert.same({}, out.shopping)
	end)

	it("says to use what the bags hold, to buy what they don't, and names nothing for the level", function()
		local missing = function()
			return false
		end
		local out = Plan.evaluate(settings, ctx({ buffUp = missing, counts = { [STEW] = 10 } }))
		local food = out.reminders.food
		assert.is_true(food.show)
		assert.equal("use", food.kind)
		assert.equal("Eat Jungle Stew", food.text)
		assert.equal(STEW, food.id)
		local elixir = out.reminders.elixir
		assert.equal("buy", elixir.kind)
		assert.equal("Buy Elixir of the Mongoose", elixir.text)

		out = Plan.evaluate(settings, ctx({ level = 1, buffUp = missing }))
		assert.equal("none", out.reminders.elixir.kind)
		assert.equal("No elixir", out.reminders.elixir.text)
	end)

	it("lists what runs low with the price, even while the buff is on", function()
		local out = Plan.evaluate(settings, ctx({ counts = { [FILET] = 2 }, prices = { [FILET] = 12345 } }))
		assert.is_false(out.reminders.food.show)
		local row = out.shopping[1]
		assert.equal("food", row.slot)
		assert.equal(FILET, row.id)
		assert.equal(2, row.have)
		assert.equal(18, row.need)
		assert.equal(12345, row.price)
	end)

	it("marks a hidden buff unknown, not missing, and keeps its shopping line", function()
		local hidden = function()
			return nil
		end
		local out = Plan.evaluate(settings, ctx({ buffUp = hidden }))
		assert.is_true(out.reminders.food.unknown)
		assert.is_false(out.reminders.food.show)
		assert.equal(FILET, out.reminders.food.buy.id)
	end)

	it("reminds a weapon hand of its poison, not a pole or an empty hand", function()
		local hands = { mainHand = hand(true, false, true), offHand = hand(true, true, true) }
		local out = Plan.evaluate(settings, ctx({ hands = hands, counts = stocked }))
		assert.is_true(out.reminders.mainHand.show)
		assert.equal("Main hand: Instant Poison VI", out.reminders.mainHand.text)

		hands = { mainHand = hand(false), offHand = hand(false) }
		out = Plan.evaluate(settings, ctx({ hands = hands, counts = stocked }))
		assert.is_false(out.reminders.mainHand.show)
		assert.is_false(out.reminders.offHand.show)
		assert.is_false(out.reminders.stone.show)
		assert.is_nil(out.reminders.mainHand.unknown)
	end)

	it("hidden enchants are unknown", function()
		local hands = { mainHand = hand(true, nil, nil), offHand = hand(true, true, true) }
		local out = Plan.evaluate(settings, ctx({ hands = hands, counts = stocked }))
		assert.is_true(out.reminders.mainHand.unknown)
		assert.is_true(out.reminders.stone.unknown)
	end)

	it("reminds of the stone when either weapon hand lacks one", function()
		local hands = { mainHand = hand(true, true, true), offHand = hand(true, true, false) }
		local out = Plan.evaluate(settings, ctx({ hands = hands, counts = stocked }))
		assert.is_true(out.reminders.stone.show)
		assert.equal("Sharpen with Elemental Sharpening Stone", out.reminders.stone.text)
		hands = { mainHand = hand(true, true, false), offHand = hand(false) }
		out = Plan.evaluate(settings, ctx({ hands = hands, counts = stocked }))
		assert.is_true(out.reminders.stone.show)
	end)

	it("shows no reminder on a flight path", function()
		local hands = { mainHand = hand(true, false, false), offHand = hand(true, false, false) }
		local missing = function()
			return false
		end
		local out = Plan.evaluate(settings, ctx({ hands = hands, buffUp = missing, flying = true }))
		for _, slot in ipairs(Plan.SLOTS) do
			assert.is_false(out.reminders[slot].show)
		end
	end)

	it("lists one line when both hands use one poison", function()
		settings.slots.offHand.choice = "Instant Poison"
		local out = Plan.evaluate(settings, ctx({ counts = { [FILET] = 10, [MONGOOSE] = 10, [ELEMENTAL] = 10 } }))
		assert.same({ IP6 }, ids(out.shopping))
		assert.equal(20, out.shopping[1].need)
	end)

	it("leaves a non-rogue's hand slots quiet even when switched on", function()
		local warrior = {}
		Plan.migrate(warrior, "WARRIOR")
		warrior.slots.mainHand.on = true
		local hands = { mainHand = hand(true, false, true), offHand = hand(false) }
		local out = Plan.evaluate(warrior, ctx({ class = "WARRIOR", hands = hands }))
		assert.is_false(out.reminders.mainHand.show)
		assert.is_nil(out.reminders.mainHand.buy)
	end)

	it("a slot switched off or set to None says nothing and buys nothing", function()
		settings.slots.food.on = false
		settings.slots.mainHand.choice = Plan.NONE
		local hands = { mainHand = hand(true, false, true), offHand = hand(true, true, true) }
		local out = Plan.evaluate(settings, ctx({ hands = hands }))
		assert.is_false(out.reminders.food.show)
		assert.is_nil(out.reminders.food.buy)
		assert.is_false(out.reminders.mainHand.show)
	end)
end)
