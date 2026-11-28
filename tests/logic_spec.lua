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

describe("Logic.best*", function()
	it("picks the strongest lure, by id or by name", function()
		local items = { item(6529, "Shiny Bauble"), item(99999, "Bright Baubles"), item(5, "Linen Cloth") }
		assert.equal(99999, Logic.bestLure(items).id)
	end)

	it("skips a lure the player can't use", function()
		local items = { item(6529, "Shiny Bauble"), item(6533, "Aquadynamic Fish Attractor", { usable = false }) }
		assert.equal(6529, Logic.bestLure(items).id)
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

describe("Logic.weaponStep", function()
	local base
	before_each(function()
		base = {
			mhName = "Dazzling Longsword",
			ohName = "Sword of Omen",
			wantMH = "Dazzling Longsword",
			wantOH = "Sword of Omen",
			haveMH = true,
			haveOH = true,
		}
	end)

	it("equips both weapons in one click when the pole is in hand, glowing", function()
		base.mhName, base.ohName = "Fishing Pole", nil
		local s = Logic.weaponStep(base)
		assert.equal("/equipslot 16 Dazzling Longsword\n/equipslot 17 Sword of Omen", s.macro)
		assert.equal("Equip weapons", s.label)
		assert.is_true(s.glow)
	end)

	it("rests with no macro and no glow when the weapons are on", function()
		local s = Logic.weaponStep(base)
		assert.equal("Weapons on", s.label)
		assert.is_nil(s.macro)
		assert.is_falsy(s.glow)
	end)

	it("says so when no weapon is remembered", function()
		base.wantMH, base.wantOH = "", ""
		local s = Logic.weaponStep(base)
		assert.equal("No weapons remembered", s.label)
		assert.is_nil(s.macro)
		assert.is_string(s.reason)
	end)

	it("names a remembered weapon that is nowhere, and equips the other", function()
		base.mhName, base.ohName, base.haveOH = "Fishing Pole", nil, false
		local s = Logic.weaponStep(base)
		assert.equal("/equipslot 16 Dazzling Longsword", s.macro)
		assert.matches("Sword of Omen", s.reason)
		base.mhName = "Dazzling Longsword"
		s = Logic.weaponStep(base)
		assert.equal("Weapons missing", s.label)
		assert.is_nil(s.macro)
	end)

	it("puts back a two-hander with no off hand remembered", function()
		base.mhName, base.ohName, base.wantMH, base.wantOH = "Fishing Pole", nil, "Big Axe", ""
		local s = Logic.weaponStep(base)
		assert.equal("/equipslot 16 Big Axe", s.macro)
	end)

	it("waits while the equipped items are unknown", function()
		base.unknown = "not now: the game hides your equipped items here"
		local s = Logic.weaponStep(base)
		assert.equal("Waiting", s.label)
		assert.is_nil(s.macro)
		assert.matches("hides", s.reason)
	end)
end)

describe("Logic.rememberWeapons", function()
	local sword = { name = "Dazzling Longsword" }
	local omen = { name = "Sword of Omen" }
	local axe = { name = "Big Axe", twoHand = true }
	local pole = { name = "Fishing Pole", pole = true, twoHand = true }

	it("keeps both names while the main hand is empty or a pole", function()
		assert.same({ "A", "B" }, { Logic.rememberWeapons(nil, nil, "A", "B") })
		assert.same({ "A", "B" }, { Logic.rememberWeapons(pole, nil, "A", "B") })
		assert.same({ "", "" }, { Logic.rememberWeapons(pole, nil, nil, nil) })
	end)

	it("remembers both hands when both hold something", function()
		assert.same({ "Dazzling Longsword", "Sword of Omen" }, { Logic.rememberWeapons(sword, omen, "A", "B") })
	end)

	it("forgets the off hand for a two-hander", function()
		assert.same({ "Big Axe", "" }, { Logic.rememberWeapons(axe, nil, "A", "B") })
	end)

	it("keeps the off hand when a one-hander comes back first", function()
		assert.same({ "Dazzling Longsword", "Sword of Omen" }, {
			Logic.rememberWeapons(sword, nil, "Dazzling Longsword", "Sword of Omen"),
		})
		assert.same({ "New Blade", "Sword of Omen" }, {
			Logic.rememberWeapons({ name = "New Blade" }, nil, "Dazzling Longsword", "Sword of Omen"),
		})
	end)
end)

describe("Logic.handState", function()
	local P, S = Logic.ENCHANT_IMBUE, Logic.ENCHANT_TEMPORARY

	it("reads a poison and a stone on one weapon (the reading from the game)", function()
		local both = { { id = 1643, type = S }, { id = 325, type = P } }
		assert.same({ true, nil, true }, { Logic.handState(both, "Instant Poison", true) })
		-- the stone alone does not count as the poison, nor the poison as the stone
		assert.same({ false, nil, true }, { Logic.handState({ both[1] }, "Instant Poison", true) })
		assert.same({ true, nil, false }, { Logic.handState({ both[2] }, "Instant Poison", true) })
	end)

	it("names another poison family on the hand", function()
		assert.same({ false, "Crippling Poison", true }, {
			Logic.handState({ { id = 22, type = P } }, "Instant Poison", false),
		})
	end)

	it("stone-only and no-poison hands want no poison, and stones off want no stone", function()
		assert.same({ true, nil, false }, { Logic.handState({ { id = 22, type = P } }, Logic.STONE, false) })
		assert.same({ true, nil, false }, { Logic.handState({}, nil, true) })
		assert.same({ false, nil, true }, { Logic.handState({}, "Instant Poison", false) })
		assert.same({ true, nil, true }, { Logic.handState({ { id = 2506, type = S } }, Logic.STONE, true) })
		assert.is_nil(Logic.handState(nil, "Instant Poison", true))
	end)

	it("an enchant the table does not know fills its slot", function()
		local odd = { { id = 99999, type = S }, { id = 99998, type = P } }
		assert.same({ true, nil, true }, { Logic.handState(odd, "Wound Poison", true) })
	end)
end)

describe("Logic.keyPlan", function()
	it("sets a free key, keeps the player's choices", function()
		assert.equal("set", Logic.keyPlan("", "CMD", false))
		assert.equal("ours", Logic.keyPlan("CMD", "CMD", true))
		assert.equal("kept", Logic.keyPlan("", "CMD", true))
		assert.equal("taken", Logic.keyPlan("OTHER", "CMD", false))
	end)

	it("labels the weapons button by what it does now, on the frame name players bound", function()
		assert.equal("CLICK BaitAndBladePoisonButton:LeftButton", Logic.KEYS[2].command)
		assert.equal("Weapons button", Logic.KEYS[2].label)
	end)
end)

describe("Logic.onTaxi", function()
	it("drops the macro and glow and names the step for after landing", function()
		local s = Logic.onTaxi({ macro = "/use x", label = "Equip weapons", reason = "r", glow = true })
		assert.is_nil(s.macro)
		assert.is_nil(s.glow)
		assert.is_nil(s.hidden)
		assert.is_true(s.taxi)
		assert.matches("Equip weapons", s.reason)
	end)
end)
