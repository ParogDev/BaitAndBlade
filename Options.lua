-- The panel under Options > AddOns > BaitAndBlade: which poison goes on which hand, the fishing button's behaviour,
-- and the weapons the poison button equips (taken from what is in your hands, since the Settings API has no text box).
local _, ns = ...

local Logic = ns.Logic

local Options = {}
ns.Options = Options
Options.TITLE = "BaitAndBlade"

local function poisonChoices()
	local c = Settings.CreateControlTextContainer()
	for _, choice in ipairs(Logic.HAND_CHOICES) do
		c:Add(choice, choice)
	end
	return c:GetData()
end

function Options.register()
	if Options.category then
		return Options.category
	end
	local st = { settings = 0 }
	ns.selftest.options = st
	if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting) then
		st.error = "Settings API missing: no options panel"
		return nil
	end
	local set = ns.settings
	local category, layout = Settings.RegisterVerticalLayoutCategory(Options.TITLE)
	Options.category = category

	local function addon(key, kind, name)
		st.settings = st.settings + 1
		local s = Settings.RegisterAddOnSetting(
			category,
			"BAB_" .. key,
			key,
			set,
			Settings.VarType[kind],
			name,
			Logic.DEFAULTS[key]
		)
		s:SetValueChangedCallback(function()
			ns.queueRefresh()
		end)
		return s
	end

	Settings.CreateDropdown(
		category,
		addon("mainHandPoison", "String", "Main hand poison or stone"),
		poisonChoices,
		"What the button puts on the main hand: the highest rank of the poison in your bags that you can use, or "
			.. "your best sharpening stone. A weapon holds one of them at a time."
	)
	Settings.CreateDropdown(
		category,
		addon("offHandPoison", "String", "Off hand poison or stone"),
		poisonChoices,
		"What the button puts on the off hand: the highest rank of the poison in your bags that you can use, or "
			.. "your best sharpening stone. A weapon holds one of them at a time."
	)

	if layout and CreateSettingsButtonInitializer then
		local function weaponsLine()
			return "Weapons: " .. (set.mainHandWeapon or "?") .. " / " .. (set.offHandWeapon or "?")
		end
		layout:AddInitializer(
			CreateSettingsButtonInitializer(
				weaponsLine(),
				"Use equipped",
				function()
					ns.rememberWeapons()
				end,
				"Stores the weapons now in your main and off hand as the ones the poison button equips. "
					.. "Same as /bab weapons. The new names show here after a /reload.",
				true
			)
		)
	end

	Settings.CreateCheckbox(
		category,
		addon("castFishing", "Boolean", "Cast Fishing when ready"),
		"Once the pole and a lure are on, the fishing button casts Fishing."
	)
	Settings.CreateCheckbox(
		category,
		addon("glowFishing", "Boolean", "Glow when the lure is missing"),
		"The fishing button glows while the pole is on without a lure and one is in your bags."
	)
	Settings.CreateCheckbox(
		category,
		addon("agility", "Boolean", "Agility food and elixir button"),
		"A third button eats your strongest agility food, then drinks your strongest agility elixir. With none in "
			.. "your bags it shows what to buy and its TSM price; buffed and stocked, it shows only under the mouse."
	)
	local locked = addon("locked", "Boolean", "Lock the buttons")
	Settings.CreateCheckbox(category, locked, "Unlocked, shift-drag a button to move both.")

	Settings.RegisterAddOnCategory(category)
	st.registered = true
	return category
end
