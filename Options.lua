-- The panel under Options > AddOns > BaitAndBlade: the fishing button's behaviour, the lock, and the way into the
-- consumables panel (food, elixirs, poisons and stones to remind about, and what to buy). The weapons button needs
-- no setting: it remembers the weapons you wear.
local _, ns = ...

local Logic = ns.Logic

local Options = {}
ns.Options = Options
Options.TITLE = "BaitAndBlade"

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

	if layout and CreateSettingsButtonInitializer then
		layout:AddInitializer(
			CreateSettingsButtonInitializer(
				"Consumables and reminders",
				"Open",
				function()
					if ns.Panel and type(ns.Panel.toggle) == "function" then
						ns.Panel.toggle()
					else
						ns.say("the consumables panel is missing (Panel.lua did not load).")
					end
				end,
				"Pick the food, elixir, poisons and sharpening stone to be reminded about, and see what to buy. "
					.. "Same as /bab panel.",
				true
			)
		)
	else
		st.panelButton = "CreateSettingsButtonInitializer missing: use /bab panel"
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
	local locked = addon("locked", "Boolean", "Lock the buttons")
	Settings.CreateCheckbox(category, locked, "Unlocked, shift-drag a button to move both.")

	Settings.RegisterAddOnCategory(category)
	st.registered = true
	return category
end
