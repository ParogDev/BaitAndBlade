local mock = require("tests.wow_mock")

local POLE, LURE, MH, OH, IP6, CP2, AXE = 6256, 6532, 101, 102, 8928, 3776, 301
local FILET, MONGOOSE, ELEMENTAL = 238638, 13452, 18262

local function setup()
	mock.item(POLE, { name = "Fishing Pole", classID = 2, subclassID = 20, equipLoc = "INVTYPE_2HWEAPON" })
	mock.item(LURE, { name = "Bright Baubles", classID = 0, subclassID = 0 })
	mock.item(MH, { name = "Dazzling Longsword", classID = 2, subclassID = 7 })
	mock.item(OH, { name = "Sword of Omen", classID = 2, subclassID = 7 })
	mock.item(AXE, { name = "Big Axe", classID = 2, subclassID = 1, equipLoc = "INVTYPE_2HWEAPON" })
	mock.item(IP6, { name = "Instant Poison VI", classID = 0, subclassID = 0 })
	mock.item(CP2, { name = "Crippling Poison II", classID = 0, subclassID = 0 })
end

-- Saved settings of a character that remembers the two swords.
local function swords()
	return { settings = { mainHandWeapon = "Dazzling Longsword", offHandWeapon = "Sword of Omen" } }
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
		assert.equal("0.4.0", st.version)
		assert.equal("1.60.1.70790", st.build)
		assert.is_table(st.weapons)
		assert.is_table(st.reminders)
		assert.is_table(st.shopping)
		assert.is_true(st.auras)
		assert.equal(2, BaitAndBladeDB.dbVersion)
		assert.is_table(BaitAndBladeDB.selftest)
		assert.is_nil(ns.selftest.lastError)
	end)

	it("equips the pole, then the lure, then casts", function()
		mock.equipped = { [16] = MH, [17] = OH }
		mock.bag(POLE, LURE)
		ns = mock.loadAddon(".")
		assert.equal("/equip Fishing Pole", macro(ns.fishButton))

		mock.equipped = { [16] = POLE }
		mock.bag(MH, OH, LURE)
		ns.refresh()
		assert.equal("/use Bright Baubles\n/use 16", macro(ns.fishButton))
		assert.is_true(ns.fishButton.glow:IsShown())

		mock.enchant[0] = true
		ns.refresh()
		assert.equal("/cast Fishing", macro(ns.fishButton))
		assert.is_false(ns.fishButton.glow:IsShown())
	end)

	describe("weapons button", function()
		it("remembers what the player wears and puts it back after fishing", function()
			mock.equipped = { [16] = MH, [17] = OH }
			mock.bag(POLE)
			ns = mock.loadAddon(".")
			assert.equal("Dazzling Longsword", ns.settings.mainHandWeapon)
			assert.equal("Sword of Omen", ns.settings.offHandWeapon)
			assert.equal("Weapons on", ns.weaponsButton.step.label)
			assert.equal("", macro(ns.weaponsButton))

			mock.equipped = { [16] = POLE }
			mock.bag(MH, OH)
			ns.refresh()
			assert.equal("Sword of Omen", ns.settings.offHandWeapon)
			assert.equal("/equipslot 16 Dazzling Longsword\n/equipslot 17 Sword of Omen", macro(ns.weaponsButton))
			assert.is_true(ns.weaponsButton.glow:IsShown())

			-- the main hand comes back first: the off hand is not forgotten
			mock.equipped = { [16] = MH }
			mock.bag(POLE, OH)
			ns.refresh()
			assert.equal("Sword of Omen", ns.settings.offHandWeapon)
			assert.equal("/equipslot 17 Sword of Omen", macro(ns.weaponsButton))
		end)

		it("remembers a two-hander with no off hand", function()
			mock.equipped = { [16] = AXE }
			ns = mock.loadAddon(".", swords())
			assert.equal("Big Axe", ns.settings.mainHandWeapon)
			assert.equal("", ns.settings.offHandWeapon)
			assert.equal("Weapons on", ns.weaponsButton.step.label)
		end)

		it("keeps the 0.3 weapon names while the pole is in hand", function()
			mock.equipped = { [16] = POLE }
			mock.bag(MH, OH)
			ns = mock.loadAddon(".", swords())
			assert.equal("Dazzling Longsword", ns.settings.mainHandWeapon)
			assert.equal("/equipslot 16 Dazzling Longsword\n/equipslot 17 Sword of Omen", macro(ns.weaponsButton))
		end)

		it("says so when no weapon was ever worn", function()
			mock.equipped = { [16] = POLE }
			ns = mock.loadAddon(".")
			assert.equal("No weapons remembered", ns.weaponsButton.step.label)
			assert.equal("", macro(ns.weaponsButton))
		end)

		it("never writes attributes or weapon memory in combat, and catches up after", function()
			mock.equipped = { [16] = POLE }
			mock.bag(MH, OH)
			ns = mock.loadAddon(".", swords())
			mock.inCombat = true
			mock.item(201, { name = "Other Blade", classID = 2, subclassID = 7 })
			mock.equipped = { [16] = 201, [17] = OH }
			ns.refresh()
			assert.is_nil(ns.selftest.lastError)
			assert.equal("Dazzling Longsword", ns.settings.mainHandWeapon)
			assert.equal("/equipslot 16 Dazzling Longsword\n/equipslot 17 Sword of Omen", macro(ns.weaponsButton))
			assert.equal(2, ns.counters.deferredInCombat) -- both buttons
			mock.inCombat = false
			ns.refresh()
			assert.equal("Other Blade", ns.settings.mainHandWeapon)
			assert.equal("", macro(ns.weaponsButton))
		end)

		it("decides nothing while an equipped item's info is not loaded", function()
			mock.equipped = { [16] = 999, [17] = OH } -- 999: no item info yet
			mock.bag(POLE, LURE)
			ns = mock.loadAddon(".", swords())
			assert.equal("", macro(ns.weaponsButton))
			assert.equal("", macro(ns.fishButton))
			assert.equal("Waiting", ns.selftest.weapons.label)
			assert.equal("Dazzling Longsword", ns.settings.mainHandWeapon)
		end)

		it("still fishes when only the off hand's info is not loaded", function()
			mock.equipped = { [16] = MH, [17] = 999 }
			mock.bag(POLE, LURE)
			ns = mock.loadAddon(".")
			assert.equal("/equip Fishing Pole", macro(ns.fishButton))
			assert.equal("", macro(ns.weaponsButton))
		end)

		it("says the game hides a secret equipped item instead of 'loading'", function()
			mock.equipped = { [16] = MH, [17] = OH }
			mock.secret[MH] = true
			ns = mock.loadAddon(".")
			assert.matches("hides", ns.selftest.fish.reason)
			assert.equal("secret", ns.selftest.hands.mainHand)
		end)
	end)

	it("goes quiet on a flight path: no macro, no glow, no reminder, no shopping list", function()
		mock.equipped = { [16] = POLE }
		mock.bag(MH, OH)
		mock.taxi = true
		mock.resting = true
		ns = mock.loadAddon(".", swords())
		assert.equal("", macro(ns.weaponsButton))
		assert.is_false(ns.weaponsButton.glow:IsShown())
		assert.equal("On a flight path", ns.weaponsButton.step.label)
		assert.is_true(ns.selftest.taxi)
		for _, r in pairs(ns.state.reminders) do
			assert.is_false(r.show)
		end
		assert.is_false(ns.state.shop.show)

		mock.taxi = false
		ns.refresh()
		assert.equal("/equipslot 16 Dazzling Longsword\n/equipslot 17 Sword of Omen", macro(ns.weaponsButton))
		assert.is_true(ns.state.reminders.food.show)
		assert.is_true(ns.state.shop.show)
	end)

	it("treats a hidden taxi state as on the ground", function()
		mock.equipped = { [16] = POLE }
		mock.bag(MH, OH)
		mock.taxi = "secret"
		ns = mock.loadAddon(".", swords())
		assert.equal("/equipslot 16 Dazzling Longsword\n/equipslot 17 Sword of Omen", macro(ns.weaponsButton))
		assert.equal("secret", ns.selftest.taxi)
	end)

	describe("settings", function()
		it("migrates 0.3 settings at load and keeps the weapon names", function()
			mock.equipped = { [16] = POLE }
			local saved = swords()
			saved.dbVersion = 1
			saved.settings.mainHandPoison = "Deadly Poison"
			saved.settings.offHandPoison = "Sharpening Stone"
			saved.settings.stones = false
			ns = mock.loadAddon(".", saved)
			local slots = ns.settings.slots
			assert.equal("Deadly Poison", slots.mainHand.choice)
			assert.equal("None", slots.offHand.choice)
			assert.is_false(slots.stone.on)
			assert.equal("Dazzling Longsword", ns.settings.mainHandWeapon)
			assert.equal(2, BaitAndBladeDB.dbVersion)
			assert.is_nil(ns.settings.mainHandPoison)
		end)

		it("waits for the class before giving a fresh character its defaults", function()
			ns = mock.loadAddon(".")
			mock.class = nil
			local db = ns.initDB({ settings = {} })
			assert.is_nil(db.settings.slots)
			mock.class = "ROGUE"
			assert.is_true(ns.migrate(false))
			assert.is_true(db.settings.slots.mainHand.on)
			assert.equal("ROGUE", ns.playerClass())
			mock.class = "secret"
			assert.is_nil(ns.playerClass())
		end)

		it("changes slots and skips for the panel and queues a refresh", function()
			ns = mock.loadAddon(".")
			local timers = #mock.timers
			assert.is_true(ns.setSlot("food", "choice", "Strength"))
			assert.equal("Strength", ns.settings.slots.food.choice)
			assert.is_true(ns.setSkip("elixir", 9264, false))
			assert.is_false(ns.settings.slots.elixir.skip[9264])
			assert.is_true(#mock.timers > timers)
			assert.is_false(ns.setSlot("nope", "on", true))
			assert.is_false(ns.setSlot("food", "skip", {}))
		end)
	end)

	describe("published state", function()
		before_each(function()
			mock.item(FILET, { name = "Filet o' Flank", classID = 0, subclassID = 5 })
			mock.equipped = { [16] = MH, [17] = OH }
			mock.stacks = { [IP6] = 10, [MONGOOSE] = 10, [ELEMENTAL] = 10 }
			mock.bag(IP6, MONGOOSE, ELEMENTAL)
			mock.enchant[0] = { { id = 1643, type = 2 } } -- a stone, no poison
			mock.enchant[1] = true -- stone and poison
			mock.auras[17538] = true -- Mongoose on
			mock.prices[CP2] = 12000
		end)

		it("publishes reminders and a shopping list in the shape the auras read", function()
			mock.resting = true
			ns = mock.loadAddon(".")
			local mh = ns.state.reminders.mainHand
			assert.same({
				show = true,
				kind = "use",
				text = "Main hand: Instant Poison VI",
				name = "Instant Poison VI",
				id = IP6,
				icon = 1000 + IP6,
				count = 10,
			}, mh)
			assert.is_false(ns.state.reminders.offHand.show)
			assert.is_false(ns.state.reminders.elixir.show)
			assert.is_false(ns.state.reminders.stone.show)
			local food = ns.state.reminders.food
			assert.is_true(food.show)
			assert.equal("buy", food.kind)
			assert.equal("Buy Filet o' Flank", food.text)

			local lines = {}
			for line in ns.state.shop.text:gmatch("[^\n]+") do
				lines[#lines + 1] = line
			end
			assert.same({ "20x Filet o' Flank  no price", "20x Crippling Poison II  1g 20s 00c each" }, lines)
			assert.equal(240000, ns.state.shop.total)
			assert.is_true(ns.state.shop.show)
			assert.equal(2, #ns.state.shopping)

			local st = ns.selftest.snapshot("test")
			assert.equal("Main hand: Instant Poison VI", st.reminders.mainHand)
			assert.is_false(st.reminders.offHand)
			assert.same({ id = CP2, need = 20, price = 12000 }, st.shopping[2])
		end)

		it("shows the shopping list only when resting or at the auction house", function()
			ns = mock.loadAddon(".")
			assert.is_false(ns.state.shop.show)
			mock.fire("AUCTION_HOUSE_SHOW")
			ns.refresh()
			assert.is_true(ns.state.shop.show)
			mock.fire("AUCTION_HOUSE_CLOSED")
			ns.refresh()
			assert.is_false(ns.state.shop.show)
		end)

		it("keeps the last reminder while the game hides the enchant or the buff", function()
			ns = mock.loadAddon(".")
			local before = ns.state.reminders.mainHand
			assert.is_true(before.show)
			local scans = #mock.scans
			mock.enchant[0] = "secret"
			mock.auras[17538] = "secret"
			ns.refresh()
			assert.same(before, ns.state.reminders.mainHand)
			assert.is_false(ns.state.reminders.elixir.show)
			assert.equal(scans, #mock.scans)
		end)

		it("tells the auras and the panel only when the state changed", function()
			local updates = 0
			ns = mock.loadAddon(".")
			assert.same({ "BAITANDBLADE_UPDATE" }, mock.scans)
			ns.Panel = {
				update = function()
					updates = updates + 1
				end,
			}
			ns.refresh()
			ns.refresh()
			assert.equal(1, #mock.scans)
			assert.equal(0, updates)
			mock.enchant[0] = true
			ns.refresh()
			assert.equal(2, #mock.scans)
			assert.equal(1, updates)
			assert.is_false(ns.state.reminders.mainHand.show)
		end)

		it("works without ForeverAuras", function()
			_G.WeakAuras = nil
			ns = mock.loadAddon(".")
			assert.is_false(ns.selftest.auras)
			assert.is_nil(ns.selftest.lastError)
		end)

		it("reads a TSM price at most once a minute", function()
			local calls = 0
			local get = TSM_API.GetCustomPriceValue
			TSM_API.GetCustomPriceValue = function(...)
				calls = calls + 1
				return get(...)
			end
			ns = mock.loadAddon(".")
			local first = calls
			assert.truthy(first > 0)
			mock.prices[CP2] = 50000
			ns.refresh()
			assert.equal(first, calls)
			assert.equal(12000, ns.state.shopping[2].price)
			mock.time = mock.time + 61
			ns.refresh()
			assert.equal(50000, ns.state.shopping[2].price)
		end)

		it("gives the panel a ladder with counts and prices", function()
			ns = mock.loadAddon(".")
			local rows, rec, held, total = ns.ladder("offHand")
			assert.equal(CP2, rows[1].id)
			assert.equal(12000, rows[1].price)
			assert.equal(CP2, rec.id)
			assert.is_nil(held)
			assert.equal(0, total)
			local _, _, mhHeld, mhTotal = ns.ladder("mainHand")
			assert.equal(IP6, mhHeld.id)
			assert.equal(10, mhTotal)
		end)
	end)

	describe("auction house search", function()
		it("hands the item link to ChatEdit_InsertLink", function()
			ns = mock.loadAddon(".")
			assert.is_true(ns.search(CP2))
			assert.matches("item:3776", mock.inserted[1])
			assert.is_true(ns.selftest.search.handled)
			assert.equal(CP2, ns.selftest.search.id)
		end)

		it("says when the link is not loaded yet and asks the client for it", function()
			ns = mock.loadAddon(".")
			local ok, why = ns.search(4242)
			assert.is_false(ok)
			assert.matches("not loaded", why)
			assert.same({ 4242 }, mock.requested)
			assert.equal(0, #mock.inserted)
		end)

		it("says when nothing took the link", function()
			mock.insertTaken = false
			ns = mock.loadAddon(".")
			local ok, why = ns.search(CP2)
			assert.is_false(ok)
			assert.matches("nothing took", why)
			assert.is_false(ns.selftest.search.handled)
		end)

		it("falls back to ChatFrameUtil.InsertLink without the deprecated name", function()
			local got
			_G.ChatEdit_InsertLink = nil
			_G.ChatFrameUtil = {
				InsertLink = function(link)
					got = link
					return true
				end,
			}
			ns = mock.loadAddon(".")
			assert.is_true(ns.search(IP6))
			assert.matches("item:8928", got)
		end)
	end)

	describe("keys", function()
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
	end)

	describe("/bab", function()
		it("prints the reminders and the shopping list, and says what is missing", function()
			mock.equipped = { [16] = MH, [17] = OH }
			ns = mock.loadAddon(".")
			ns.slash("")
			local all = table.concat(mock.chat, "\n")
			assert.matches("reminder: Buy Filet o' Flank", all)
			assert.matches("buy: 20x Filet o' Flank", all)
			ns.slash("panel")
			assert.matches("panel is missing", mock.chat[#mock.chat])
			local opened = false
			ns.Panel = {
				toggle = function()
					opened = true
				end,
			}
			ns.slash("panel")
			assert.is_true(opened)
			ns.slash("auras")
			assert.matches("aura pack is missing", mock.chat[#mock.chat])
		end)
	end)
end)
