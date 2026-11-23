local mock = require("tests.wow_mock")

local POLE, LURE, MH, OH, IP5, IP6, CP2 = 6256, 6532, 101, 102, 8927, 8928, 3776

local function setup()
	mock.item(POLE, { name = "Fishing Pole", classID = 2, subclassID = 20 })
	mock.item(LURE, { name = "Bright Baubles", classID = 0, subclassID = 0 })
	mock.item(MH, { name = "Dazzling Longsword", classID = 2, subclassID = 7 })
	mock.item(OH, { name = "Sword of Omen", classID = 2, subclassID = 7 })
	mock.item(IP5, { name = "Instant Poison V", classID = 0, subclassID = 0 })
	mock.item(IP6, { name = "Instant Poison VI", classID = 0, subclassID = 0 })
	mock.item(CP2, { name = "Crippling Poison II", classID = 0, subclassID = 0 })
end

describe("Core", function()
	local ns
	before_each(function()
		mock.install()
		setup()
	end)

	local function macro(button)
		return button:GetAttribute("macrotext")
	end

	it("keeps the selftest contract", function()
		ns = mock.loadAddon(".")
		local st = ns.selftest.snapshot("test")
		assert.equal("0.1.0", st.version)
		assert.equal("1.60.1.70790", st.build)
		assert.is_table(BaitAndBladeDB.selftest)
	end)

	it("equips the pole, then the lure, then casts", function()
		mock.equipped = { [16] = MH, [17] = OH }
		mock.bag(POLE, LURE, IP6, CP2)
		ns = mock.loadAddon(".")
		assert.equal("/equip Fishing Pole", macro(ns.fishButton))

		mock.equipped = { [16] = POLE }
		mock.bag(MH, OH, LURE, IP6, CP2)
		ns.refresh()
		assert.equal("/use Bright Baubles\n/use 16", macro(ns.fishButton))
		assert.is_true(ns.fishButton.glow:IsShown())

		mock.enchant[0] = true
		ns.refresh()
		assert.equal("/cast Fishing", macro(ns.fishButton))
		assert.is_false(ns.fishButton.glow:IsShown())
	end)

	it("equips the weapons, then the best poisons, glowing until both hands are done", function()
		mock.equipped = { [16] = POLE }
		mock.bag(MH, OH, IP5, IP6, CP2)
		ns = mock.loadAddon(".")
		assert.equal("/equipslot 16 Dazzling Longsword\n/equipslot 17 Sword of Omen", macro(ns.poisonButton))
		assert.is_false(ns.poisonButton.glow:IsShown())

		mock.equipped = { [16] = MH, [17] = OH }
		mock.bag(POLE, IP5, IP6, CP2)
		ns.refresh()
		assert.equal("/use Instant Poison VI\n/use 16", macro(ns.poisonButton))
		assert.is_true(ns.poisonButton.glow:IsShown())

		mock.enchant[0] = true
		ns.refresh()
		assert.equal("/use Crippling Poison II\n/use 17", macro(ns.poisonButton))

		mock.enchant[1] = true
		ns.refresh()
		assert.equal("", macro(ns.poisonButton))
		assert.is_false(ns.poisonButton.glow:IsShown())
	end)

	it("uses the poison chosen in the settings", function()
		mock.equipped = { [16] = MH, [17] = OH }
		mock.bag(IP6, CP2)
		ns = mock.loadAddon(".", { settings = { mainHandPoison = "Crippling Poison" } })
		assert.equal("/use Crippling Poison II\n/use 16", macro(ns.poisonButton))
	end)

	it("never writes attributes in combat and catches up after", function()
		mock.equipped = { [16] = MH, [17] = OH }
		mock.bag(IP6, CP2)
		ns = mock.loadAddon(".")
		mock.inCombat = true
		mock.enchant[0] = true
		ns.refresh()
		assert.is_nil(ns.selftest.lastError)
		assert.equal("/use Instant Poison VI\n/use 16", macro(ns.poisonButton))
		assert.equal(2, ns.counters.deferredInCombat) -- both buttons
		mock.inCombat = false
		ns.refresh()
		assert.equal("/use Crippling Poison II\n/use 17", macro(ns.poisonButton))
	end)

	it("treats a hidden enchant as unknown, not missing", function()
		mock.equipped = { [16] = MH, [17] = OH }
		mock.bag(IP6, CP2)
		mock.enchant[0] = "secret"
		ns = mock.loadAddon(".")
		assert.equal("", macro(ns.poisonButton))
		assert.is_false(ns.poisonButton.glow:IsShown())
		assert.equal("secret", ns.selftest.enchants.mainHand)
	end)

	it("remembers the equipped weapons", function()
		mock.item(201, { name = "Other Blade", classID = 2, subclassID = 7 })
		mock.equipped = { [16] = 201, [17] = OH }
		ns = mock.loadAddon(".")
		assert.is_true(ns.rememberWeapons())
		assert.equal("Other Blade", ns.settings.mainHandWeapon)
	end)

	it("refuses to remember a fishing pole as a weapon", function()
		mock.equipped = { [16] = POLE }
		ns = mock.loadAddon(".")
		assert.is_false(ns.rememberWeapons())
		assert.equal("Dazzling Longsword", ns.settings.mainHandWeapon)
	end)
end)
