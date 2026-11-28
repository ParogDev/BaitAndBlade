-- Addon entry: two secure buttons (fishing, weapons), their glow, the client lookups behind them, the consumable
-- state published for the ForeverAuras pack and the panel (ns.state, BAITANDBLADE_UPDATE), the selftest contract
-- (docs/verify-loop.md in the scaffolding) and /bab. A click runs one step of a macro the addon writes out of
-- combat; nothing here acts without the player's click.
local ADDON, ns = ...

BaitAndBlade = ns

local Logic = ns.Logic
local Plan = ns.Plan

ns.VERSION = "0.4.0"
ns.FISHING_SPELL_ID = 7620
ns.FISHING_ICON = 136245 -- Trade_Fishing
ns.WEAPONS_ICON = 132273 -- Ability_Poisons
ns.PRICE_SOURCE = "dbminbuyout" -- TSM: the cheapest buyout seen on the auction house
ns.PRICE_TTL = 60 -- seconds a TSM price is reused before it is read again
ns.BUTTON_SIZE = 36
ns.UPDATE_EVENT = "BAITANDBLADE_UPDATE"

local DB_VERSION = 2
local SLOT_MH, SLOT_OH = 16, 17

local counters = { refreshes = 0, attributeSets = 0, deferredInCombat = 0, uncachedItems = 0, publishes = 0 }
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

-- The player's class token ("ROGUE"), or nil when the client does not give it yet or hides it.
local function playerClass()
	local ok, _, class = pcall(UnitClass, "player")
	if ok and type(class) == "string" and not issecretvalue(class) then
		return class
	end
	return nil
end
ns.playerClass = playerClass

-- Fills the consumable slots from the 0.3 keys (idempotent). Without a class it waits for PLAYER_LOGIN unless
-- forced: a fresh character's defaults depend on it.
function ns.migrate(force)
	local class = playerClass()
	if not class and not force then
		return false
	end
	Plan.migrate(ns.settings, class)
	ns.db.dbVersion = DB_VERSION
	return true
end

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
	ns.migrate(false)
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

-- Every distinct item in the bags whose info is loaded, once per id, with count = the total of its stacks; and
-- counts: item id -> total for every item, loaded or not (the plan only needs ids).
function ns.bagItems()
	local items, seen, counts = {}, {}, {}
	local last = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
	for bag = 0, last do
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			local id = info and info.itemID
			if id and not issecretvalue(id) then
				local stack = info.stackCount
				if type(stack) ~= "number" or issecretvalue(stack) then
					stack = 1
				end
				counts[id] = (counts[id] or 0) + stack
				if seen[id] then
					seen[id].count = seen[id].count + stack
				elseif seen[id] == nil then
					local item = describe(id)
					seen[id] = item or false
					if item then
						item.count = stack
						items[#items + 1] = item
					end
				end
			end
		end
	end
	return items, counts
end

-- Whether the player has any of these buffs: true / false, nil plus the reason when the game hides auras (secret
-- values in instances and encounters) or the API is missing.
local function hasBuff(spellIDs)
	if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then
		return nil, "C_UnitAuras.GetPlayerAuraBySpellID missing"
	end
	for _, id in ipairs(spellIDs) do
		local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
		if not ok then
			return nil, "GetPlayerAuraBySpellID failed: " .. tostring(aura)
		end
		if issecretvalue(aura) then
			return nil, "not now: the game hides your buffs here"
		end
		if aura then
			return true
		end
	end
	return false
end

-- One TSM price in copper, or nil plus why (TSM not loaded, no auction data for the item).
function ns.price(itemID)
	if type(TSM_API) ~= "table" or type(TSM_API.GetCustomPriceValue) ~= "function" then
		return nil, "TSM_API.GetCustomPriceValue missing (TSM not loaded?)"
	end
	local ok, value, err = pcall(TSM_API.GetCustomPriceValue, ns.PRICE_SOURCE, "i:" .. itemID)
	if not ok then
		return nil, "GetCustomPriceValue failed: " .. tostring(value)
	end
	if type(value) ~= "number" then
		return nil, err or "no auction data"
	end
	return value
end

-- ns.price, read at most once a minute per item (the refresh runs every few seconds).
local priceCache = {}
ns.priceCache = priceCache
local function cachedPrice(itemID)
	local t = GetTime()
	local c = priceCache[itemID]
	if c and t - c.at < ns.PRICE_TTL then
		return c.value, c.why
	end
	local value, why = ns.price(itemID)
	priceCache[itemID] = { value = value, why = why, at = t }
	return value, why
end

-- Fills prices[id] for every tier of one slot's choice; the first reason a price is missing goes to selftest.
local function fillPrices(prices, slot, choice)
	for _, e in ipairs(Plan.entries(slot, choice)) do
		local value, why = cachedPrice(e.id)
		prices[e.id] = value
		if not value and why and not selftest.priceWhy then
			selftest.priceWhy = why
		end
	end
end

local function playerLevel()
	local ok, level = pcall(UnitLevel, "player")
	if ok and type(level) == "number" and not issecretvalue(level) then
		return level
	end
	return 60
end

-- Whether the player is in a rested area (an inn, a city): false when hidden or missing.
local function resting()
	if type(IsResting) ~= "function" then
		return false
	end
	local ok, r = pcall(IsResting)
	if not ok or issecretvalue(r) then
		return false
	end
	return r and true or false
end

-- The item in an equipment slot and the slot's state: "item", "empty", or "unknown" (an item is there but the
-- client hides its id or has not loaded its info yet: decide nothing until it has).
local function equipped(slot)
	local id = GetInventoryItemID("player", slot)
	if not id then
		return nil, "empty"
	end
	if issecretvalue(id) then
		return nil, "secret"
	end
	local item = describe(id)
	if not item then
		return nil, "unknown"
	end
	return item, "item"
end

local function twoHanded(itemID)
	local equipLoc = select(9, C_Item.GetItemInfo(itemID))
	if equipLoc == nil or issecretvalue(equipLoc) then
		return false
	end
	return equipLoc == "INVTYPE_2HWEAPON"
end

-- The non-permanent enchants on a weapon slot as { id =, type = } (poison, stone, lure; {} for none), nil when the
-- client hides them.
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
	local list = {}
	for _, e in pairs(enchants) do
		if type(e) == "table" then
			if issecretvalue(e.hasEnchant) or issecretvalue(e.enchantType) or issecretvalue(e.enchantID) then
				selftest.enchants[label] = "secret"
				return nil
			end
			raw[#raw + 1] = { has = e.hasEnchant, type = e.enchantType, id = e.enchantID }
			if e.hasEnchant and e.enchantType ~= permanent then
				list[#list + 1] = { id = e.enchantID or 0, type = e.enchantType }
			end
		end
	end
	selftest.enchants[label] = raw
	return list
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

-- Whether the player rides a flight path. A hidden or missing answer counts as "not flying": the buttons then work
-- as before, and selftest.taxi says why.
local function onTaxi()
	if type(UnitOnTaxi) ~= "function" then
		selftest.taxi = "UnitOnTaxi missing"
		return false
	end
	local ok, flying = pcall(UnitOnTaxi, "player")
	if not ok or issecretvalue(flying) then
		selftest.taxi = ok and "secret" or ("UnitOnTaxi failed: " .. tostring(flying))
		return false
	end
	selftest.taxi = flying and true or false
	return selftest.taxi
end
ns.onTaxi = onTaxi

-- The poison family a hand slot wants: nil when the slot is off or set to None (then whatever is on counts).
local function handChoice(slots, slot)
	local cfg = slots[slot]
	if cfg and cfg.on and cfg.choice ~= Plan.NONE then
		return cfg.choice
	end
	return nil
end

-- The state both buttons and the plan decide from, gathered in one pass.
-- Returns fish (Logic.fishStep), weapons (Logic.weaponStep) and ctx (Plan.evaluate).
function ns.gather()
	local set = ns.settings
	local slots = set.slots
	local items, counts = ns.bagItems()
	local mh, mhState = equipped(SLOT_MH)
	local oh, ohState = equipped(SLOT_OH)
	-- "not now" reasons: fishing only reads the main hand, the weapons button both hands
	local function why(state)
		if state == "secret" then
			return "not now: the game hides your equipped items here"
		elseif state == "unknown" then
			return "equipped item info not loaded yet"
		end
	end
	local fishUnknown = why(mhState)
	local unknown = fishUnknown or why(ohState)
	selftest.hands = { mainHand = mhState, offHand = ohState }

	-- weapon memory: what the player wears, read out of combat with both hands known
	if not unknown and not InCombatLockdown() then
		local function hand(it)
			return it and { name = it.name, pole = Logic.isPole(it), twoHand = twoHanded(it.id) } or nil
		end
		set.mainHandWeapon, set.offHandWeapon =
			Logic.rememberWeapons(hand(mh), hand(oh), set.mainHandWeapon, set.offHandWeapon)
	end

	local mhSlot = Enum and Enum.WeaponSlot and Enum.WeaponSlot.MainHand or 0
	local ohSlot = Enum and Enum.WeaponSlot and Enum.WeaponSlot.OffHand or 1
	selftest.enchants = {}
	local wantStone = slots.stone.on and true or false
	-- One hand for the plan: weapon (holds a weapon that is not a fishing pole), poisoned, stoned. A hand the game
	-- hides counts as a weapon with unknown enchants, so its reminders keep their last answer.
	-- mhAny: any non-permanent enchant on the main hand (the lure on a pole), nil when hidden.
	local mhAny = true
	local function planHand(it, state, weaponSlot, label, slot)
		if state == "secret" or state == "unknown" then
			return { weapon = true }
		end
		if not it or it.classID ~= Logic.WEAPON_CLASS then
			return { weapon = false }
		end
		local list = tempEnchant(weaponSlot, label)
		if slot == "mainHand" then
			mhAny = list and #list > 0 -- nil (hidden) stays nil
		end
		if Logic.isPole(it) then
			return { weapon = false }
		end
		local poisoned, _, stoned = Logic.handState(list, handChoice(slots, slot), wantStone)
		return { weapon = true, poisoned = poisoned, stoned = stoned }
	end
	local hands = {
		mainHand = planHand(mh, mhState, mhSlot, "mainHand", "mainHand"),
		offHand = planHand(oh, ohState, ohSlot, "offHand", "offHand"),
	}

	-- a remembered weapon can be in the bags or already on either hand (swapped hands: /equipslot moves it)
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
		unknown = fishUnknown,
		poleEquipped = poleEquipped,
		lure = poleEquipped and mhAny, -- nil (hidden) stays nil
		pole = Logic.bestPole(items),
		bestLure = Logic.bestLure(items),
		castFishing = set.castFishing,
		glowFishing = set.glowFishing,
		fishingSpell = fishingSpellName(),
	}
	local weapons = {
		unknown = unknown,
		mhName = mh and mh.name,
		ohName = oh and oh.name,
		wantMH = set.mainHandWeapon,
		wantOH = set.offHandWeapon,
		haveMH = have(set.mainHandWeapon),
		haveOH = have(set.offHandWeapon),
	}

	local class = playerClass()
	selftest.priceWhy = nil
	local prices = {}
	for _, slot in ipairs(Plan.SLOTS) do
		local cfg = slots[slot]
		if cfg.on and cfg.choice ~= Plan.NONE and Plan.available(slot, class) then
			fillPrices(prices, slot, cfg.choice)
		end
	end
	local buffWhy
	local ctx = {
		level = playerLevel(),
		class = class,
		counts = counts,
		prices = prices,
		lowCount = set.lowCount,
		stockTo = set.stockTo,
		hands = hands,
		buffUp = function(spellIDs)
			local up, reason = hasBuff(spellIDs)
			buffWhy = buffWhy or reason
			return up
		end,
	}
	ns.counts = counts
	return fish, weapons, ctx, function()
		return buffWhy
	end
end

-- ---------------------------------------------------------------------------------------------------------
-- Published state (ForeverAuras pack and the panel read ns.state on BAITANDBLADE_UPDATE)
-- ---------------------------------------------------------------------------------------------------------
local function money(copper)
	if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
		local ok, text = pcall(C_CurrencyInfo.GetCoinTextureString, copper)
		if ok and type(text) == "string" then
			return text
		end
	end
	return string.format("%dg %02ds %02dc", copper / 10000, (copper / 100) % 100, copper % 100)
end
ns.money = money

local function iconOf(id)
	if id and C_Item.GetItemIconByID then
		local ok, tex = pcall(C_Item.GetItemIconByID, id)
		if ok and tex and not issecretvalue(tex) then
			return tex
		end
	end
	return nil
end

-- One reminder as the auras read it.
local function public(r)
	return {
		show = r.show and true or false,
		kind = r.kind,
		text = r.text,
		name = r.name,
		id = r.id,
		icon = iconOf(r.id),
		count = r.count,
	}
end

-- Turns Plan.evaluate's answer into ns.state. A reminder the game hides (unknown) keeps the last published one
-- for its slot, shown only while not flying.
function ns.buildState(plan, flying)
	local before = ns.state and ns.state.reminders or {}
	local reminders = {}
	for _, slot in ipairs(Plan.SLOTS) do
		local r = plan.reminders[slot]
		local prev = before[slot]
		if r.unknown and prev then
			local kept = {}
			for k, v in pairs(prev) do
				kept[k] = v
			end
			kept.show = prev.show and not flying
			reminders[slot] = kept
		else
			reminders[slot] = public(r)
		end
	end
	local lines, total = {}, nil
	for _, b in ipairs(plan.shopping) do
		local price = b.price and (money(b.price) .. " each") or "no price"
		lines[#lines + 1] = b.need .. "x " .. b.name .. "  " .. price
		if b.price then
			total = (total or 0) + b.price * b.need
		end
	end
	local shop = {
		show = #plan.shopping > 0 and not flying and (resting() or ns.atAuctionHouse == true),
		text = table.concat(lines, "\n"),
		total = total,
	}
	ns.state = { reminders = reminders, shopping = plan.shopping, shop = shop }
	return ns.state
end

-- A cheap string that changes when anything the auras show changes.
local function signature(state)
	local parts = {}
	for _, slot in ipairs(Plan.SLOTS) do
		local r = state.reminders[slot] or {}
		parts[#parts + 1] = table.concat({
			slot,
			tostring(r.show),
			tostring(r.kind),
			tostring(r.text),
			tostring(r.id),
			tostring(r.count),
		}, ",")
	end
	parts[#parts + 1] = tostring(state.shop.show) .. "," .. state.shop.text .. "," .. tostring(state.shop.total)
	return table.concat(parts, ";")
end

-- Tells the auras and the panel when the state changed. Returns whether it did.
function ns.publish()
	if not ns.state then
		return false
	end
	local sig = signature(ns.state)
	if sig == ns.publishedSignature then
		return false
	end
	ns.publishedSignature = sig
	counters.publishes = counters.publishes + 1
	local wa = type(WeakAuras) == "table" and WeakAuras or nil
	selftest.auras = wa ~= nil and type(wa.ScanEvents) == "function"
	if selftest.auras then
		guard("auras", wa.ScanEvents, ns.UPDATE_EVENT)
	end
	if ns.Panel and type(ns.Panel.update) == "function" then
		guard("panel", ns.Panel.update)
	end
	return true
end

-- ---------------------------------------------------------------------------------------------------------
-- API for the panel
-- ---------------------------------------------------------------------------------------------------------

-- The ladder of one slot's current choice with prices and counts: rows, recommended, held, total (Plan.ladder).
function ns.ladder(slot)
	local cfg = ns.settings.slots[slot]
	if not cfg then
		return {}, nil, nil, 0
	end
	local prices = {}
	fillPrices(prices, slot, cfg.choice)
	local counts = ns.counts or select(2, ns.bagItems())
	return Plan.ladder(slot, cfg, { level = playerLevel(), prices = prices, counts = counts })
end

-- Changes one slot setting (key "on" or "choice"). Returns false plus why for an unknown slot or key.
function ns.setSlot(slot, key, value)
	local cfg = ns.settings.slots[slot]
	if not cfg then
		return false, "no slot " .. tostring(slot)
	end
	if key ~= "on" and key ~= "choice" then
		return false, "slot setting must be on or choice, not " .. tostring(key)
	end
	cfg[key] = value
	ns.queueRefresh()
	return true
end

-- Rules a tier in or out (skipped false un-skips a school-limited elixir that starts out skipped).
function ns.setSkip(slot, itemID, skipped)
	local cfg = ns.settings.slots[slot]
	if not cfg then
		return false, "no slot " .. tostring(slot)
	end
	cfg.skip[itemID] = skipped and true or false
	ns.queueRefresh()
	return true
end

-- Puts an item's link where the chat box would take it: TradeSkillMaster hooks this to search the auction house.
-- Returns true, or false plus why (link not loaded yet, nothing took it).
function ns.search(itemID)
	-- atAuction: a search that nothing took away from the auction house is expected, at it a broken link to TSM
	local result = { id = itemID, handled = false, at = now(), atAuction = ns.atAuctionHouse and true or false }
	selftest.search = result
	local _, link = C_Item.GetItemInfo(itemID)
	if link == nil or issecretvalue(link) or type(link) ~= "string" then
		if C_Item.RequestLoadItemDataByID then
			pcall(C_Item.RequestLoadItemDataByID, itemID)
		end
		result.why = "item link not loaded yet: try again in a moment"
		return false, result.why
	end
	-- ChatEdit_InsertLink is the name TSM hooks; Mainline keeps it only as a deprecation fallback of this one
	local insert = ChatEdit_InsertLink
	if type(insert) ~= "function" then
		insert = ChatFrameUtil and ChatFrameUtil.InsertLink
	end
	if type(insert) ~= "function" then
		result.why = "ChatEdit_InsertLink and ChatFrameUtil.InsertLink missing"
		return false, result.why
	end
	local ok, handled = pcall(insert, link)
	if not ok then
		result.why = "InsertLink failed: " .. tostring(handled)
		return false, result.why
	end
	result.handled = handled and true or false
	if not result.handled then
		result.why = "nothing took the link: open the auction house (TSM searches it) or a chat box"
		return false, result.why
	end
	return true
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
	button:SetAlpha(1)
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	GameTooltip:SetText(button.title)
	GameTooltip:AddLine(step.label, 1, 1, 1)
	GameTooltip:AddLine(step.reason, 0.7, 0.7, 0.7, true)
	if button == ns.weaponsButton then
		local s = ns.settings
		local mhName = s.mainHandWeapon ~= "" and s.mainHandWeapon or "none"
		local ohName = s.offHandWeapon ~= "" and s.offHandWeapon or "none"
		GameTooltip:AddLine("Remembered: " .. mhName .. " / " .. ohName, 0.5, 0.8, 1, true)
	end
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
		b:SetAlpha(b.step and b.step.hidden and 0 or 1)
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
	-- the 0.3 frame name: players have it bound and in macros
	ns.weaponsButton = makeButton("BaitAndBladePoisonButton", f, "Weapons", ns.WEAPONS_ICON)
	ns.weaponsButton:SetPoint("LEFT", ns.fishButton, "RIGHT", 6, 0)
	if ns.settings.shown then
		f:Show()
	else
		f:Hide()
	end
	return f
end

local function iconFor(step, button)
	if step.icon and step.icon.id then
		local tex = iconOf(step.icon.id)
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
	-- alpha, not Hide: a secure button can't be hidden in combat, and the mouse must still find it
	if not (GameTooltip:IsOwned(button) and GameTooltip:IsShown()) then
		button:SetAlpha(step.hidden and 0 or 1)
	end
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

local function stepSummary(step)
	return { label = step.label, reason = step.reason, macro = step.macro, glow = step.glow }
end

function ns.refresh()
	if not ns.frame then
		return
	end
	if type(ns.settings.slots) ~= "table" then
		ns.migrate(true)
	end
	counters.refreshes = counters.refreshes + 1
	local fish, weapons, ctx, buffWhy = ns.gather()
	local fishStep, weaponStep = Logic.fishStep(fish), Logic.weaponStep(weapons)
	ns.flying = onTaxi()
	if ns.flying then
		fishStep, weaponStep = Logic.onTaxi(fishStep), Logic.onTaxi(weaponStep)
	end
	apply(ns.fishButton, fishStep)
	apply(ns.weaponsButton, weaponStep)
	selftest.fish = stepSummary(fishStep)
	selftest.weapons = stepSummary(weaponStep)

	ctx.flying = ns.flying
	local plan = Plan.evaluate(ns.settings, ctx)
	selftest.buffs = buffWhy()
	ns.plan = plan
	ns.buildState(plan, ns.flying)
	ns.publish()
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
	local reminders, shopping = {}, {}
	if ns.state then
		for slot, r in pairs(ns.state.reminders) do
			reminders[slot] = r.show and r.text or false
		end
		for i, b in ipairs(ns.state.shopping) do
			shopping[i] = { id = b.id, need = b.need, price = b.price }
		end
	end
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
		weapons = selftest.weapons,
		reminders = reminders,
		shopping = shopping,
		search = selftest.search,
		auras = selftest.auras,
		panel = selftest.panel, -- set by Panel.lua: built, rows, error
		auraPack = selftest.auraPack, -- set by AuraPack.lua: the last import asked of ForeverAuras
		buffs = selftest.buffs,
		prices = selftest.priceWhy,
		taxi = selftest.taxi,
		enchants = selftest.enchants,
		hands = selftest.hands,
		keys = selftest.keys,
		counters = counters,
		lastError = selftest.lastError,
	}
	return ns.db.selftest
end

-- ---------------------------------------------------------------------------------------------------------
-- Key bindings (Bindings.xml lists them under Options > Keybindings > BaitAndBlade)
-- ---------------------------------------------------------------------------------------------------------
BINDING_HEADER_BAITANDBLADE = "BaitAndBlade"
for _, k in ipairs(Logic.KEYS) do
	_G["BINDING_NAME_" .. k.command] = k.label
end

-- The character's id for the once-per-character key flag (bindings can be per character). A GUID, not a name.
local function characterKey()
	local ok, guid = pcall(UnitGUID, "player")
	if ok and type(guid) == "string" and not issecretvalue(guid) then
		return guid
	end
	return nil
end

-- One default key: its plan, and for "set" whether SetBinding took it ("set" / "failed").
local function applyKey(k)
	local bound = GetBindingAction(k.key)
	if type(bound) ~= "string" or issecretvalue(bound) then
		return "unreadable"
	end
	local plan = Logic.keyPlan(bound, k.command, GetBindingKey(k.command) ~= nil)
	if plan == "set" then
		return SetBinding(k.key, k.command) and "set" or "failed"
	elseif plan == "taken" then
		local line = "%s is already bound to %s: bind the %s in Options > Keybindings."
		say(line:format(k.key, bound, k.label))
	end
	return plan
end

-- Sets the default keys once per character, out of combat (retried after combat). A key the player bound to
-- something else, or a button the player already gave another key, is left alone and named in chat. A key that
-- failed to set leaves the flag unset, so the next login tries again.
function ns.applyDefaultKeys()
	local who = characterKey()
	ns.db.keysApplied = type(ns.db.keysApplied) == "table" and ns.db.keysApplied or {}
	if not who or ns.db.keysApplied[who] then
		return
	end
	if InCombatLockdown() then
		ns.keysPending = true
		return
	end
	ns.keysPending = false
	local result, set, done = {}, {}, true
	for _, k in ipairs(Logic.KEYS) do
		local ok, outcome = pcall(applyKey, k)
		outcome = ok and outcome or ("error: " .. tostring(outcome))
		result[k.key] = outcome
		if outcome == "set" then
			set[#set + 1] = k.key .. " " .. k.label
		elseif outcome ~= "ours" and outcome ~= "kept" and outcome ~= "taken" then
			done = false
		end
	end
	if #set > 0 then
		SaveBindings(GetCurrentBindingSet())
		say("keys set: " .. table.concat(set, ", ") .. " (change them in Options > Keybindings).")
	end
	if done then
		ns.db.keysApplied[who] = true
	end
	selftest.keys = result
end

-- ---------------------------------------------------------------------------------------------------------
-- /bab
-- ---------------------------------------------------------------------------------------------------------
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
	elseif cmd == "panel" then
		if ns.Panel and type(ns.Panel.toggle) == "function" then
			ns.Panel.toggle()
		else
			say("the consumables panel is missing (Panel.lua did not load).")
		end
	elseif cmd == "auras" then
		if ns.AuraPack and type(ns.AuraPack.install) == "function" then
			ns.AuraPack.install()
		else
			say("the aura pack is missing (AuraPack.lua did not load).")
		end
	else
		ns.refresh()
		local s = ns.settings
		local mhName = s.mainHandWeapon ~= "" and s.mainHandWeapon or "none"
		local ohName = s.offHandWeapon ~= "" and s.offHandWeapon or "none"
		say("weapons remembered: " .. mhName .. " / " .. ohName .. ".")
		if selftest.fish then
			say("fishing: " .. selftest.fish.label .. " (" .. selftest.fish.reason .. ")")
			say("weapons: " .. selftest.weapons.label .. " (" .. selftest.weapons.reason .. ")")
		end
		if ns.state then
			for _, slot in ipairs(Plan.SLOTS) do
				local r = ns.state.reminders[slot]
				if r and r.show and r.text then
					say("reminder: " .. r.text)
				end
			end
			for line in ns.state.shop.text:gmatch("[^\n]+") do
				say("buy: " .. line)
			end
		end
		say("/bab show | hide | lock | unlock | reset | options | panel | auras")
		say("macros: /click BaitAndBladeFishButton, BaitAndBladePoisonButton")
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
	"UNIT_AURA",
	"PLAYER_REGEN_ENABLED",
	"GET_ITEM_INFO_RECEIVED",
	"PLAYER_LEVEL_UP",
	"SKILL_LINES_CHANGED",
	"PLAYER_CONTROL_LOST", -- taking off on a flight path
	"PLAYER_CONTROL_GAINED", -- landing
	"PLAYER_UPDATE_RESTING", -- the shopping list shows in rested areas
	"AUCTION_HOUSE_SHOW", -- and at the auction house
	"AUCTION_HOUSE_CLOSED",
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
		guard("migrate", ns.migrate, true)
		guard("createUI", ns.createUI)
		if ns.Options then
			guard("options", ns.Options.register)
		end
		guard("refresh", ns.refresh)
		guard("keys", ns.applyDefaultKeys)
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
		if ns.keysPending then
			guard("keys", ns.applyDefaultKeys)
		end
	elseif event == "UNIT_INVENTORY_CHANGED" or event == "UNIT_AURA" then
		if arg1 == "player" then
			ns.queueRefresh()
		end
	elseif event == "GET_ITEM_INFO_RECEIVED" then
		if ns.waitingForItems then
			ns.waitingForItems = false
			ns.queueRefresh()
		end
	elseif event == "AUCTION_HOUSE_SHOW" or event == "AUCTION_HOUSE_CLOSED" then
		ns.atAuctionHouse = event == "AUCTION_HOUSE_SHOW"
		ns.queueRefresh()
	else
		ns.queueRefresh()
	end
end)

-- Poisons, lures and buffs run out on a timer the client does not always announce: look again every few seconds
-- (also while the buttons are hidden: the reminders come from the same refresh).
C_Timer.NewTicker(5, function()
	if ns.frame then
		guard("refresh", ns.refresh)
	end
end)
