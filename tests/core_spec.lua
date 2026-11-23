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
		assert.equal("0.1.2", st.version)
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

	it("treats an empty off hand as nothing to poison (two-hander set up)", function()
		mock.item(301, { name = "Big Axe", classID = 2, subclassID = 1 })
		mock.equipped = { [16] = 301 }
		mock.enchant[0] = true
		mock.bag(IP6, CP2)
		ns = mock.loadAddon(".", { settings = { mainHandWeapon = "Big Axe", offHandWeapon = "" } })
		assert.equal("", macro(ns.poisonButton))
		assert.is_false(ns.poisonButton.glow:IsShown())
	end)

	it("swaps hands instead of calling the weapons missing", function()
		mock.equipped = { [16] = OH, [17] = MH }
		mock.bag(IP6, CP2)
		ns = mock.loadAddon(".")
		assert.equal("/equipslot 16 Dazzling Longsword\n/equipslot 17 Sword of Omen", macro(ns.poisonButton))
	end)

	it("decides nothing while an equipped item's info is not loaded", function()
		mock.equipped = { [16] = 999, [17] = OH } -- 999: no item info yet
		mock.bag(POLE, LURE, IP6, CP2)
		ns = mock.loadAddon(".")
		assert.equal("", macro(ns.poisonButton))
		assert.equal("", macro(ns.fishButton))
		assert.equal("Waiting", ns.selftest.poison.label)
		assert.is_false(ns.poisonButton.glow:IsShown())
	end)

	it("still fishes when only the off hand's info is not loaded", function()
		mock.equipped = { [16] = MH, [17] = 999 }
		mock.bag(POLE, LURE)
		ns = mock.loadAddon(".")
		assert.equal("/equip Fishing Pole", macro(ns.fishButton))
		assert.equal("", macro(ns.poisonButton))
	end)

	it("says the game hides a secret equipped item instead of 'loading'", function()
		mock.equipped = { [16] = MH, [17] = OH }
		mock.secret[MH] = true
		ns = mock.loadAddon(".")
		assert.matches("hides", ns.selftest.fish.reason)
		assert.equal("secret", ns.selftest.hands.mainHand)
	end)

	it("sets the default keys once, on free keys only", function()
		mock.bindings["CTRL-`"] = "TOGGLEBAG1"
		ns = mock.loadAddon(".")
		assert.equal("CLICK BaitAndBladeFishButton:LeftButton", mock.bindings["SHIFT-`"])
		assert.equal("TOGGLEBAG1", mock.bindings["CTRL-`"])
		assert.equal("set", ns.selftest.keys["SHIFT-`"])
		assert.equal("taken", ns.selftest.keys["CTRL-`"])
		assert.equal(1, mock.saved)
		assert.is_true(BaitAndBladeDB.keysApplied["Player-1-ABC"])
		assert.matches("SHIFT%-` Fishing button", mock.chat[#mock.chat])
		assert.not_matches("CTRL", mock.chat[#mock.chat])
	end)

	it("leaves keys alone once applied for this character, so a player's change sticks", function()
		ns = mock.loadAddon(".", { keysApplied = { ["Player-1-ABC"] = true } })
		assert.is_nil(mock.bindings["SHIFT-`"])
		assert.equal(0, mock.saved)
	end)

	it("sets the keys for a second character", function()
		ns = mock.loadAddon(".", { keysApplied = { ["Player-1-OTHER"] = true } })
		assert.equal("CLICK BaitAndBladeFishButton:LeftButton", mock.bindings["SHIFT-`"])
	end)

	it("tries again next login when a key fails to set", function()
		mock.setBindingFails = true
		ns = mock.loadAddon(".")
		assert.equal("failed", ns.selftest.keys["SHIFT-`"])
		assert.is_nil(BaitAndBladeDB.keysApplied["Player-1-ABC"])
	end)

	it("waits for the end of combat to set the keys", function()
		mock.inCombat = true
		ns = mock.loadAddon(".")
		assert.is_nil(mock.bindings["SHIFT-`"])
		mock.inCombat = false
		mock.fire("PLAYER_REGEN_ENABLED")
		assert.equal("CLICK BaitAndBladeFishButton:LeftButton", mock.bindings["SHIFT-`"])
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
