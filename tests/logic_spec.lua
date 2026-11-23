local ns = {}
assert(loadfile("Logic.lua"))("BaitAndBlade", ns)
local Logic = ns.Logic

local function item(id, name, extra)
	local t = { id = id, name = name, itemLevel = 10 }
	for k, v in pairs(extra or {}) do
		t[k] = v
	end
	return t
end

describe("Logic.poisonRank", function()
	it("reads roman ranks and the bare name as rank 1", function()
		assert.equal(6, Logic.poisonRank("Instant Poison VI", "Instant Poison"))
		assert.equal(1, Logic.poisonRank("Crippling Poison", "Crippling Poison"))
		assert.equal(2, Logic.poisonRank("Crippling Poison II", "Crippling Poison"))
	end)

	it("rejects other families and look-alikes", function()
		assert.is_nil(Logic.poisonRank("Deadly Poison V", "Instant Poison"))
		assert.is_nil(Logic.poisonRank("Instant Poisoner", "Instant Poison"))
		assert.is_nil(Logic.poisonRank("Instant Poison Vial", "Instant Poison"))
		assert.is_nil(Logic.poisonRank(nil, "Instant Poison"))
	end)
end)

describe("Logic.best*", function()
	it("picks the highest poison rank the player can use", function()
		local items = {
			item(1, "Instant Poison III"),
			item(2, "Instant Poison VI", { usable = false }),
			item(3, "Instant Poison V"),
			item(4, "Crippling Poison II"),
		}
		assert.equal(3, Logic.bestPoison(items, "Instant Poison").id)
		assert.equal(4, Logic.bestPoison(items, "Crippling Poison").id)
		assert.is_nil(Logic.bestPoison(items, "Wound Poison"))
	end)

	it("picks the strongest lure, by id or by name", function()
		local items = { item(6529, "Shiny Bauble"), item(99999, "Bright Baubles"), item(5, "Linen Cloth") }
		assert.equal(99999, Logic.bestLure(items).id)
	end)

	it("picks the best fishing pole and ignores other weapons", function()
		local pole = { classID = 2, subclassID = 20 }
		local items = {
			item(6256, "Fishing Pole", pole),
			item(6367, "Big Iron Fishing Pole", pole),
			item(7, "Dazzling Longsword", { classID = 2, subclassID = 7, itemLevel = 40 }),
		}
		assert.equal(6367, Logic.bestPole(items).id)
	end)
end)

describe("Logic.fishStep", function()
	local pole = item(6256, "Fishing Pole", { classID = 2, subclassID = 20 })
	local lure = item(6532, "Bright Baubles")

	it("equips the pole first", function()
		local s = Logic.fishStep({ poleEquipped = false, pole = pole, bestLure = lure })
		assert.equal("/equip Fishing Pole", s.macro)
	end)

	it("applies the lure to the main hand and glows", function()
		local s = Logic.fishStep({ poleEquipped = true, lure = false, bestLure = lure, glowFishing = true })
		assert.equal("/use Bright Baubles\n/use 16", s.macro)
		assert.is_true(s.glow)
	end)

	it("casts once pole and lure are on, only when asked", function()
		local on = Logic.fishStep({ poleEquipped = true, lure = true, castFishing = true, fishingSpell = "Fishing" })
		assert.equal("/cast Fishing", on.macro)
		local off = Logic.fishStep({ poleEquipped = true, lure = true, castFishing = false })
		assert.is_nil(off.macro)
	end)

	it("does nothing without a pole", function()
		local s = Logic.fishStep({ poleEquipped = false })
		assert.is_nil(s.macro)
		assert.matches("no fishing pole", s.reason)
	end)

	it("does not glow when the lure state is hidden", function()
		local s = Logic.fishStep({ poleEquipped = true, lure = nil, bestLure = lure, glowFishing = true })
		assert.is_falsy(s.glow)
	end)
end)

describe("Logic.poisonStep", function()
	local base
	before_each(function()
		base = {
			mhName = "Dazzling Longsword",
			ohName = "Sword of Omen",
			wantMH = "Dazzling Longsword",
			wantOH = "Sword of Omen",
			haveMH = true,
			haveOH = true,
			mhPoisoned = true,
			ohPoisoned = true,
			mhFamily = "Instant Poison",
			ohFamily = "Crippling Poison",
			mhPoison = item(8928, "Instant Poison VI"),
			ohPoison = item(3776, "Crippling Poison II"),
		}
	end)

	it("equips both weapons in one click when the pole is in hand", function()
		base.mhName, base.ohName = "Fishing Pole", nil
		local s = Logic.poisonStep(base)
		assert.equal("/equipslot 16 Dazzling Longsword\n/equipslot 17 Sword of Omen", s.macro)
		assert.is_falsy(s.glow)
	end)

	it("poisons the main hand first and glows", function()
		base.mhPoisoned, base.ohPoisoned = false, false
		local s = Logic.poisonStep(base)
		assert.equal("/use Instant Poison VI\n/use 16", s.macro)
		assert.is_true(s.glow)
	end)

	it("then the off hand", function()
		base.ohPoisoned = false
		local s = Logic.poisonStep(base)
		assert.equal("/use Crippling Poison II\n/use 17", s.macro)
		assert.is_true(s.glow)
	end)

	it("skips to the off hand when the main hand poison is out", function()
		base.mhPoisoned, base.ohPoisoned, base.mhPoison = false, false, nil
		local s = Logic.poisonStep(base)
		assert.equal("/use Crippling Poison II\n/use 17", s.macro)
	end)

	it("glows with no macro when the bags hold no poison", function()
		base.mhPoisoned, base.mhPoison = false, nil
		local s = Logic.poisonStep(base)
		assert.is_nil(s.macro)
		assert.is_true(s.glow)
		assert.matches("Instant Poison", s.reason)
	end)

	it("rests when both hands are poisoned", function()
		local s = Logic.poisonStep(base)
		assert.is_nil(s.macro)
		assert.is_falsy(s.glow)
	end)

	it("names a configured weapon that is nowhere", function()
		base.ohName, base.haveOH = nil, false
		local s = Logic.poisonStep(base)
		assert.is_nil(s.macro)
		assert.matches("Sword of Omen", s.reason)
	end)

	it("puts a sharpening stone on a hand set to stones", function()
		base.ohFamily, base.ohPoisoned = Logic.STONE, false
		base.ohPoison = item(12404, "Dense Sharpening Stone")
		local s = Logic.poisonStep(base)
		assert.equal("/use Dense Sharpening Stone\n/use 17", s.macro)
		assert.matches("sharpening stone", s.reason)
	end)

	it("asks to buy stones when a stone hand has none", function()
		base.ohFamily, base.ohPoisoned, base.ohPoison = Logic.STONE, false, nil
		local s = Logic.poisonStep(base)
		assert.is_nil(s.macro)
		assert.equal("Out of sharpening stones", s.label)
		assert.same({ "stone" }, s.buy)
		base.mhPoisoned, base.mhPoison = false, nil
		s = Logic.poisonStep(base)
		assert.equal("Out of poison", s.label)
		assert.same({ "stone" }, s.buy)
	end)

	it("does not glow when the poison state is hidden", function()
		base.mhPoisoned = nil
		local s = Logic.poisonStep(base)
		assert.is_falsy(s.glow)
		assert.is_nil(s.macro)
	end)
end)

describe("Logic agility", function()
	local stew = { id = 12212, name = "Jungle Stew", count = 3 }
	local poivre = { id = 250069, name = "Flank au Poivre", count = 1 }
	local greater = { id = 9187, name = "Elixir of Greater Agility", count = 2 }
	local mongoose = { id = 13452, name = "Elixir of the Mongoose", count = 1 }

	it("picks the strongest food and elixir, skipping ones the player can't use", function()
		assert.equal(250069, Logic.bestFood({ stew, poivre }).id)
		local tooHigh = { id = 250069, name = "Flank au Poivre", usable = false }
		assert.equal(12212, Logic.bestFood({ stew, tooHigh }).id)
		assert.equal(13452, Logic.bestElixir({ greater, mongoose }).id)
		-- a Forever copy under another id matches by name
		assert.equal(777, Logic.bestFood({ { id = 777, name = "Jungle Stew" } }).id)
		assert.equal(4, Logic.countOf({ stew, poivre, greater }, Logic.foodEntry))
	end)

	local function state(over)
		local s = { fed = false, elixirUp = false, foodCount = 0, elixirCount = 0, lowCount = 5 }
		for k, v in pairs(over) do
			s[k] = v
		end
		return s
	end

	it("eats first, then drinks, glowing", function()
		local s = Logic.agilityStep(state({ food = stew, elixir = greater }))
		assert.equal("/use Jungle Stew", s.macro)
		assert.is_true(s.glow)
		s = Logic.agilityStep(state({ fed = true, food = stew, elixir = greater }))
		assert.equal("/use Elixir of Greater Agility", s.macro)
	end)

	it("drinks while naming the missing food as a buy", function()
		local s = Logic.agilityStep(state({ elixir = greater }))
		assert.equal("/use Elixir of Greater Agility", s.macro)
		assert.same({ "food" }, s.buy)
	end)

	it("turns into a buy reminder with nothing to use", function()
		local s = Logic.agilityStep(state({ fed = true }))
		assert.is_nil(s.macro)
		assert.is_true(s.shop)
		assert.same({ "elixir" }, s.buy)
		assert.equal("Buy agility elixir", s.label)
	end)

	it("hides when buffed and stocked, reminds when low", function()
		local s = Logic.agilityStep(state({ fed = true, elixirUp = true, foodCount = 5, elixirCount = 7 }))
		assert.is_true(s.hidden)
		assert.is_nil(s.macro)
		s = Logic.agilityStep(state({ fed = true, elixirUp = true, foodCount = 2, elixirCount = 7 }))
		assert.is_falsy(s.hidden)
		assert.same({ "food" }, s.buy)
		assert.is_true(s.shop)
	end)

	it("waits when the buffs are hidden", function()
		local s = Logic.agilityStep(state({ unknown = "not now: hidden", fed = nil }))
		assert.equal("Waiting", s.label)
		assert.is_nil(s.macro)
	end)

	it("lists what to buy, strongest usable first, cheapest of the best priced tier", function()
		local prices = { [250069] = 9000, [250072] = 7000, [12212] = 100 }
		local rows, cheapest = Logic.shoppingList("food", 50, prices, 4)
		assert.equal(4, #rows)
		assert.equal(20, rows[1].agi) -- Filet o' Flank (level 55) left out at level 50
		assert.equal(250072, cheapest.id)
		rows, cheapest = Logic.shoppingList("food", 40, prices)
		assert.equal(15, rows[1].agi)
		assert.equal(12212, cheapest.id)
		local _, none = Logic.shoppingList("elixir", 60, {})
		assert.is_nil(none)
	end)
end)

describe("Logic sharpening stones", function()
	it("picks the strongest stone, by id or by Forever copy's name, Elemental over Dense", function()
		local dense = item(12404, "Dense Sharpening Stone")
		local copy = item(287980, "Elemental Sharpening Stone")
		local solid = item(7964, "Solid Sharpening Stone")
		assert.equal(dense, Logic.bestFor({ solid, dense }, Logic.STONE))
		assert.equal(copy, Logic.bestFor({ solid, dense, copy }, Logic.STONE))
		assert.is_nil(Logic.bestFor({ item(23122, "Consecrated Sharpening Stone") }, Logic.STONE))
		assert.is_nil(Logic.bestFor({ solid }, "Instant Poison"))
	end)

	it("lists stones to buy by level, with their bonus text", function()
		local rows, cheapest = Logic.shoppingList("stone", 40, { [12404] = 300, [7964] = 100 }, 4)
		assert.equal("Dense Sharpening Stone", rows[1].name)
		assert.equal("+8 damage", rows[1].bonus)
		assert.equal(12404, cheapest.id)
	end)

	it("offers stones next to the poison families", function()
		assert.equal(Logic.STONE, Logic.HAND_CHOICES[#Logic.HAND_CHOICES])
		assert.equal(#Logic.POISON_FAMILIES + 1, #Logic.HAND_CHOICES)
	end)
end)

describe("Logic.onTaxi", function()
	it("drops the macro, glow and buy reminder and hides a buy step", function()
		local s = Logic.onTaxi({ macro = "/use x", label = "Eat x", reason = "r", glow = true })
		assert.is_nil(s.macro)
		assert.is_nil(s.glow)
		assert.is_nil(s.hidden)
		assert.matches("Eat x", s.reason)
		s = Logic.onTaxi({ label = "Buy agility food", reason = "r", buy = { "food" }, shop = true })
		assert.is_nil(s.buy)
		assert.is_nil(s.shop)
		assert.is_true(s.hidden)
	end)
end)
