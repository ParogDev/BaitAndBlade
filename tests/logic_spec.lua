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

	it("does not glow when the poison state is hidden", function()
		base.mhPoisoned = nil
		local s = Logic.poisonStep(base)
		assert.is_falsy(s.glow)
		assert.is_nil(s.macro)
	end)
end)
