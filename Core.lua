-- Addon entry: two secure buttons (fishing, weapons and poisons), their glow, the client lookups behind them, the
-- selftest contract (docs/verify-loop.md in the scaffolding) and /bab. A click runs one step of a macro the addon
-- writes out of combat; nothing here acts without the player's click.
local ADDON, ns = ...

BaitAndBlade = ns

local Logic = ns.Logic

ns.VERSION = "0.1.1"
ns.FISHING_SPELL_ID = 7620
ns.FISHING_ICON = 136245 -- Trade_Fishing
ns.POISON_ICON = 132273 -- Ability_Poisons
ns.BUTTON_SIZE = 36

local DB_VERSION = 1
local SLOT_MH, SLOT_OH = 16, 17

local counters = { refreshes = 0, attributeSets = 0, deferredInCombat = 0, uncachedItems = 0 }
local selftest = { counters = counters }
ns.counters = counters
ns.selftest = selftest

local function now()
	return date("%Y-%m-%d %H:%M:%S")
end

local function say(line)
	DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffBaitAndBlade|r: " .. line)
end
ns.say = say

local function guard(where, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		selftest.lastError = { where = where, error = tostring(err), at = now() }
	end
	return ok, err
end
ns.guard = guard

function ns.initDB(saved)
	local db = type(saved) == "table" and saved or {}
	db.dbVersion = db.dbVersion or DB_VERSION
	db.settings = type(db.settings) == "table" and db.settings or {}
	for k, v in pairs(Logic.DEFAULTS) do
		if db.settings[k] == nil then
			db.settings[k] = v
		end
	end
	db.selftest = db.selftest or {}
	ns.db = db
	ns.settings = db.settings
	BaitAndBladeDB = db
	return db
end

local function version()
	local ok, v = pcall(C_AddOns.GetAddOnMetadata, ADDON, "Version")
	if not ok or type(v) ~= "string" or v:find("@", 1, true) then
		return ns.VERSION
	end
	return v
end
ns.version = version

-- ---------------------------------------------------------------------------------------------------------
-- Client lookups
-- ---------------------------------------------------------------------------------------------------------

-- One item as Logic wants it, or nil when the client has not loaded its info yet ("not now": a later
-- GET_ITEM_INFO_RECEIVED refreshes).
local function describe(itemID)
	local name, _, _, itemLevel = C_Item.GetItemInfo(itemID)
	if not name then
		counters.uncachedItems = counters.uncachedItems + 1
		ns.waitingForItems = true
		return nil
	end
	local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
	local usable = true
	if C_Item.IsUsableItem then
		local ok, u = pcall(C_Item.IsUsableItem, itemID)
		-- weapons and poles are not "usable" items: only the false of a consumable means "can't use it yet"
		if ok and u == false and classID ~= Logic.WEAPON_CLASS then
			usable = false
		end
	end
	return {
		id = itemID,
		name = name,
		itemLevel = itemLevel,
		classID = classID,
		subclassID = subclassID,
		usable = usable,
	}
end
ns.describe = describe

-- Every distinct item in the bags, once per id.
function ns.bagItems()
	local items, seen = {}, {}
	local last = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
	for bag = 0, last do
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			local id = info and info.itemID
			if id and not issecretvalue(id) and not seen[id] then
				seen[id] = true
				local item = describe(id)
				if item then
					items[#items + 1] = item
				end
			end
		end
	end
	return items
end

-- The item in an equipment slot and the slot's state: "item", "empty", or "unknown" (an item is there but the
-- client hides its id or has not loaded its info yet: decide nothing until it has).
local function equipped(slot)
	local id = GetInventoryItemID("player", slot)
	if not id then
		return nil, "empty"
	end
	if issecretvalue(id) then
		return nil, "unknown"
	end
	local item = describe(id)
	if not item then
		return nil, "unknown"
	end
	return item, "item"
end

-- Whether a weapon slot carries a temporary enchant (poison, lure): true / false, nil when the client hides it.
-- The raw answer goes into selftest.enchants so a wrong reading can be told from a wrong rule.
local function tempEnchant(weaponSlot, label)
	if not (C_Item.GetWeaponEnchantInfo and Enum and Enum.WeaponSlot) then
		selftest.enchants = { error = "C_Item.GetWeaponEnchantInfo or Enum.WeaponSlot missing" }
		return nil
	end
	local ok, enchants = pcall(C_Item.GetWeaponEnchantInfo, weaponSlot)
	selftest.enchants = selftest.enchants or {}
	if not ok then
		selftest.enchants[label] = "GetWeaponEnchantInfo failed: " .. tostring(enchants)
		return nil
	end
	if type(enchants) ~= "table" then
		selftest.enchants[label] = "GetWeaponEnchantInfo gave " .. type(enchants)
		return nil
	end
	local permanent = Enum.ItemEnchantType and Enum.ItemEnchantType.Permanent or 1
	local raw = {}
	local found = false
	for _, e in pairs(enchants) do
		if type(e) == "table" then
			if issecretvalue(e.hasEnchant) or issecretvalue(e.enchantType) then
				selftest.enchants[label] = "secret"
				return nil
			end
			raw[#raw + 1] = { has = e.hasEnchant, type = e.enchantType, id = e.enchantID }
			if e.hasEnchant and e.enchantType ~= permanent then
				found = true
			end
		end
	end
	selftest.enchants[label] = raw
	return found
end

local function fishingSpellName()
	if C_Spell and C_Spell.GetSpellName then
		local ok, name = pcall(C_Spell.GetSpellName, ns.FISHING_SPELL_ID)
		if ok and type(name) == "string" and not issecretvalue(name) then
			return name
		end
	end
	return "Fishing"
end

-- The state both buttons decide from, gathered in one pass.
function ns.gather()
	local set = ns.settings
	local items = ns.bagItems()
	local mh, mhState = equipped(SLOT_MH)
	local oh, ohState = equipped(SLOT_OH)
	local unknown = mhState == "unknown" or ohState == "unknown"
	local mhSlot = Enum and Enum.WeaponSlot and Enum.WeaponSlot.MainHand or 0
	local ohSlot = Enum and Enum.WeaponSlot and Enum.WeaponSlot.OffHand or 1
	selftest.enchants = {}
	-- A hand with no weapon in it has nothing to poison: it counts as done (an equip step comes first when a
	-- weapon is wanted there). Not `x and f() or false`: f() returning nil (hidden) must stay nil.
	local mhEnchant, ohEnchant = true, true
	if mh and mh.classID == Logic.WEAPON_CLASS then
		mhEnchant = tempEnchant(mhSlot, "mainHand")
	end
	if oh and oh.classID == Logic.WEAPON_CLASS then
		ohEnchant = tempEnchant(ohSlot, "offHand")
	end
	-- a wanted weapon can be in the bags or already on either hand (swapped hands: /equipslot moves it)
	local function have(name)
		if (mh and mh.name == name) or (oh and oh.name == name) then
			return true
		end
		for _, it in ipairs(items) do
			if it.name == name then
				return true
			end
		end
		return false
	end
	local poleEquipped = mh ~= nil and Logic.isPole(mh)
	local fish = {
		unknown = unknown,
		poleEquipped = poleEquipped,
		lure = poleEquipped and mhEnchant, -- nil (hidden) stays nil
		pole = Logic.bestPole(items),
		bestLure = Logic.bestLure(items),
		castFishing = set.castFishing,
		glowFishing = set.glowFishing,
		fishingSpell = fishingSpellName(),
	}
	local poison = {
		unknown = unknown,
		mhName = mh and mh.name,
		ohName = oh and oh.name,
		wantMH = set.mainHandWeapon,
		wantOH = set.offHandWeapon,
		haveMH = have(set.mainHandWeapon),
		haveOH = have(set.offHandWeapon),
		mhPoisoned = mhEnchant,
		ohPoisoned = ohEnchant,
		mhFamily = set.mainHandPoison,
		ohFamily = set.offHandPoison,
		mhPoison = Logic.bestPoison(items, set.mainHandPoison),
		ohPoison = Logic.bestPoison(items, set.offHandPoison),
	}
	return fish, poison
end

-- ---------------------------------------------------------------------------------------------------------
-- Buttons
-- ---------------------------------------------------------------------------------------------------------
local function makeGlow(button)
	local glow = button:CreateTexture(nil, "OVERLAY")
	glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	glow:SetBlendMode("ADD")
	glow:SetVertexColor(1, 0.85, 0.2)
	glow:SetPoint("CENTER")
	glow:SetSize(ns.BUTTON_SIZE * 1.9, ns.BUTTON_SIZE * 1.9)
	glow:Hide()
	local anim = glow:CreateAnimationGroup()
	anim:SetLooping("BOUNCE")
	local alpha = anim:CreateAnimation("Alpha")
	alpha:SetFromAlpha(0.35)
	alpha:SetToAlpha(1)
	alpha:SetDuration(0.6)
	button.glow, button.glowAnim = glow, anim
end

local function setGlow(button, on)
	if on then
		if not button.glow:IsShown() then
			button.glow:Show()
			button.glowAnim:Play()
		end
	elseif button.glow:IsShown() then
		button.glowAnim:Stop()
		button.glow:Hide()
	end
end
ns.setGlow = setGlow

local function showTooltip(button)
	local step = button.step
	if not step then
		return
	end
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	GameTooltip:SetText(button.title)
	GameTooltip:AddLine(step.label, 1, 1, 1)
	GameTooltip:AddLine(step.reason, 0.7, 0.7, 0.7, true)
	if not step.macro then
		GameTooltip:AddLine("Click does nothing right now.", 1, 0.4, 0.4)
	end
	if not ns.settings.locked then
		GameTooltip:AddLine("Shift-drag to move.", 0.5, 0.5, 0.5)
	end
	GameTooltip:Show()
end

local function makeButton(name, parent, title, defaultIcon)
	local b = CreateFrame("Button", name, parent, "SecureActionButtonTemplate")
	b:SetSize(ns.BUTTON_SIZE, ns.BUTTON_SIZE)
	-- AnyDown and AnyUp: the secure handler runs once, on down or up as ActionButtonUseKeyDown says, for a mouse
	-- click and for /click in a macro alike
	b:RegisterForClicks("AnyUp", "AnyDown")
	b:SetAttribute("type", "macro")
	b.title = title
	b.defaultIcon = defaultIcon
	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	icon:SetTexture(defaultIcon)
	b.icon = icon
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
	hl:SetBlendMode("ADD")
	makeGlow(b)
	b:SetScript("OnEnter", showTooltip)
	b:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	-- the macro is rewritten right before the click reads it, from the bags as they are now (out of combat only:
	-- in combat the attributes are locked and the last macro written runs)
	b:SetScript("PreClick", function()
		if not InCombatLockdown() then
			guard("refresh", ns.refresh)
		end
	end)
	b:SetScript("PostClick", function()
		C_Timer.After(0.5, function()
			guard("refresh", ns.refresh)
		end)
	end)
	b:RegisterForDrag("LeftButton")
	b:SetScript("OnDragStart", function()
		if not ns.settings.locked and IsShiftKeyDown() and not InCombatLockdown() then
			parent:StartMoving()
			parent.moving = true
		end
	end)
	b:SetScript("OnDragStop", function()
		if not parent.moving then
			return
		end
		parent.moving = false
		parent:StopMovingOrSizing()
		local point, _, relPoint, x, y = parent:GetPoint()
		ns.db.position = { point = point, relPoint = relPoint, x = x, y = y }
	end)
	return b
end

function ns.createUI()
	if ns.frame then
		return ns.frame
	end
	local f = CreateFrame("Frame", "BaitAndBladeFrame", UIParent)
	f:SetSize(ns.BUTTON_SIZE * 2 + 6, ns.BUTTON_SIZE)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	local pos = ns.db.position
	if type(pos) == "table" and pos.point then
		f:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
	else
		f:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
	end
	ns.frame = f
	ns.fishButton = makeButton("BaitAndBladeFishButton", f, "Fishing", ns.FISHING_ICON)
	ns.fishButton:SetPoint("LEFT", f, "LEFT", 0, 0)
	ns.poisonButton = makeButton("BaitAndBladePoisonButton", f, "Weapons and poisons", ns.POISON_ICON)
	ns.poisonButton:SetPoint("LEFT", ns.fishButton, "RIGHT", 6, 0)
	if ns.settings.shown then
		f:Show()
	else
		f:Hide()
	end
	return f
end

local function iconFor(step, button)
	if step.icon and step.icon.id then
		local tex = C_Item.GetItemIconByID and C_Item.GetItemIconByID(step.icon.id)
		if tex then
			return tex
		end
	end
	return button.defaultIcon
end

local function apply(button, step)
	button.step = step
	button.icon:SetTexture(iconFor(step, button))
	button.icon:SetDesaturated(step.macro == nil)
	setGlow(button, step.glow)
	if InCombatLockdown() then
		ns.attributesStale = true
		counters.deferredInCombat = counters.deferredInCombat + 1
		return
	end
	local text = step.macro or ""
	if button:GetAttribute("macrotext") ~= text then
		button:SetAttribute("macrotext", text)
		counters.attributeSets = counters.attributeSets + 1
	end
end

function ns.refresh()
	if not ns.frame then
		return
	end
	counters.refreshes = counters.refreshes + 1
	local fish, poison = ns.gather()
	local fishStep, poisonStep = Logic.fishStep(fish), Logic.poisonStep(poison)
	apply(ns.fishButton, fishStep)
	apply(ns.poisonButton, poisonStep)
	selftest.fish = { label = fishStep.label, reason = fishStep.reason, macro = fishStep.macro, glow = fishStep.glow }
	selftest.poison =
		{ label = poisonStep.label, reason = poisonStep.reason, macro = poisonStep.macro, glow = poisonStep.glow }
end

-- One refresh per frame burst: bag and equipment events arrive in clusters.
function ns.queueRefresh()
	if ns.refreshQueued then
		return
	end
	ns.refreshQueued = true
	C_Timer.After(0.2, function()
		ns.refreshQueued = false
		guard("refresh", ns.refresh)
	end)
end

-- ---------------------------------------------------------------------------------------------------------
-- selftest
-- ---------------------------------------------------------------------------------------------------------
function selftest.snapshot(phase)
	local okB, buildVersion, buildNumber, _, interface = pcall(GetBuildInfo)
	ns.db.selftest = {
		phase = phase,
		version = version(),
		build = okB and (tostring(buildVersion) .. "." .. tostring(buildNumber)) or "GetBuildInfo failed",
		interface = okB and interface or nil,
		project = WOW_PROJECT_ID,
		loadedAt = selftest.loadedAt,
		savedAt = now(),
		settings = ns.settings,
		options = selftest.options,
		fish = selftest.fish,
		poison = selftest.poison,
		enchants = selftest.enchants,
		counters = counters,
		lastError = selftest.lastError,
	}
	return ns.db.selftest
end

-- ---------------------------------------------------------------------------------------------------------
-- /bab
-- ---------------------------------------------------------------------------------------------------------
-- Stores the weapons in the main and off hand as the ones the poison button equips.
function ns.rememberWeapons()
	local mh, mhState = equipped(SLOT_MH)
	local oh, ohState = equipped(SLOT_OH)
	if mhState == "unknown" or ohState == "unknown" then
		say("your weapons' item info is not loaded yet: try again in a moment.")
		return false
	end
	if not mh or Logic.isPole(mh) then
		say("equip your normal weapons first (main hand is " .. (mh and mh.name or "empty") .. ").")
		return false
	end
	ns.settings.mainHandWeapon = mh.name
	ns.settings.offHandWeapon = oh and oh.name or ""
	say("weapons set: " .. mh.name .. " / " .. (oh and oh.name or "no off hand") .. ".")
	ns.queueRefresh()
	return true
end

function ns.setShown(shown)
	ns.settings.shown = shown
	if InCombatLockdown() then
		say("in combat: the buttons " .. (shown and "show" or "hide") .. " after combat.")
		ns.visibilityStale = true
		return
	end
	if shown then
		ns.frame:Show()
	else
		ns.frame:Hide()
	end
end

function ns.slash(msg)
	local cmd = strtrim(msg or ""):lower()
	if cmd == "show" or cmd == "hide" then
		ns.setShown(cmd == "show")
	elseif cmd == "lock" or cmd == "unlock" then
		ns.settings.locked = cmd == "lock"
		say(ns.settings.locked and "buttons locked." or "buttons unlocked: shift-drag to move.")
	elseif cmd == "weapons" then
		ns.rememberWeapons()
	elseif cmd == "reset" then
		if InCombatLockdown() then
			say("in combat: try /bab reset after combat.")
			return
		end
		ns.db.position = nil
		ns.frame:ClearAllPoints()
		ns.frame:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
	elseif cmd == "options" or cmd == "config" then
		if ns.Options and ns.Options.category then
			Settings.OpenToCategory(ns.Options.category:GetID())
		else
			say("no options panel: " .. tostring(selftest.options and selftest.options.error))
		end
	else
		ns.refresh()
		local s = ns.settings
		local line = "weapons %s / %s, poisons %s / %s."
		say(line:format(s.mainHandWeapon, s.offHandWeapon, s.mainHandPoison, s.offHandPoison))
		if selftest.fish then
			say("fishing: " .. selftest.fish.label .. " (" .. selftest.fish.reason .. ")")
			say("poisons: " .. selftest.poison.label .. " (" .. selftest.poison.reason .. ")")
		end
		say("/bab show | hide | lock | unlock | weapons (remember equipped) | reset | options")
		say("macros: /click BaitAndBladeFishButton  and  /click BaitAndBladePoisonButton")
	end
end

SLASH_BAITANDBLADE1 = "/bab"
SLASH_BAITANDBLADE2 = "/baitandblade"
SlashCmdList.BAITANDBLADE = function(msg)
	guard("slash", ns.slash, msg)
	if selftest.lastError and selftest.lastError.where == "slash" then
		say("error: " .. selftest.lastError.error)
		selftest.lastError = nil
	end
end

-- ---------------------------------------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------------------------------------
local events = CreateFrame("Frame")
ns.events = events
for _, e in ipairs({
	"ADDON_LOADED",
	"PLAYER_LOGIN",
	"PLAYER_LOGOUT",
	"BAG_UPDATE_DELAYED",
	"PLAYER_EQUIPMENT_CHANGED",
	"WEAPON_ENCHANT_CHANGED",
	"UNIT_INVENTORY_CHANGED",
	"PLAYER_REGEN_ENABLED",
	"GET_ITEM_INFO_RECEIVED",
	"PLAYER_LEVEL_UP",
	"SKILL_LINES_CHANGED",
}) do
	events:RegisterEvent(e)
end
events:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 == ADDON then
			ns.initDB(BaitAndBladeDB)
		end
	elseif event == "PLAYER_LOGIN" then
		selftest.loadedAt = now()
		guard("createUI", ns.createUI)
		if ns.Options then
			guard("options", ns.Options.register)
		end
		guard("refresh", ns.refresh)
		guard("snapshot", selftest.snapshot, "login")
	elseif event == "PLAYER_LOGOUT" then
		guard("snapshot", selftest.snapshot, "logout")
	elseif event == "PLAYER_REGEN_ENABLED" then
		if ns.visibilityStale then
			ns.visibilityStale = false
			ns.setShown(ns.settings.shown)
		end
		ns.attributesStale = false
		ns.queueRefresh()
	elseif event == "UNIT_INVENTORY_CHANGED" then
		if arg1 == "player" then
			ns.queueRefresh()
		end
	elseif event == "GET_ITEM_INFO_RECEIVED" then
		if ns.waitingForItems then
			ns.waitingForItems = false
			ns.queueRefresh()
		end
	else
		ns.queueRefresh()
	end
end)

-- Poisons and lures run out on a timer the client does not always announce: look again every few seconds.
C_Timer.NewTicker(5, function()
	if ns.frame and ns.frame:IsShown() then
		guard("refresh", ns.refresh)
	end
end)
