-- Minimal WoW client globals so the addon loads under busted: scriptable bags, equipped items, weapon enchants and
-- combat. Frames are dumb tables that accept any method; the real check is the in-game reload.
local M = {}

local function newFrame(_, name)
	local f = { _events = {}, _attrs = {}, _scripts = {}, _shown = true, _name = name }
	function f:RegisterEvent(e)
		self._events[e] = true
	end
	function f:SetScript(k, fn)
		self._scripts[k] = fn
	end
	function f:SetAttribute(k, v)
		if M.inCombat then
			error("SetAttribute in combat")
		end
		self._attrs[k] = v
	end
	function f:GetAttribute(k)
		return self._attrs[k]
	end
	function f:Show()
		self._shown = true
	end
	function f:Hide()
		self._shown = false
	end
	function f:IsShown()
		return self._shown
	end
	function f:SetAlpha(a)
		self._alpha = a
	end
	function f:GetAlpha()
		return self._alpha or 1
	end
	function f:CreateTexture()
		return newFrame()
	end
	function f:CreateAnimationGroup()
		return newFrame()
	end
	function f:CreateAnimation()
		return newFrame()
	end
	function f:GetPoint()
		return "CENTER", nil, "CENTER", 0, 0
	end
	setmetatable(f, {
		__index = function()
			return function() end
		end,
	})
	if name then
		_G[name] = f
	end
	M.frames[#M.frames + 1] = f
	return f
end

function M.install()
	M.frames = {}
	M.chat = {}
	M.timers = {}
	M.inCombat = false
	M.items = {} -- id -> { name, itemLevel, classID, subclassID, usable }
	M.bags = {} -- [bag][slot] = id
	M.equipped = {} -- [slot] = id
	M.enchant = { [0] = false, [1] = false } -- weapon slot -> true / false / "secret"
	M.secret = {}

	_G.CreateFrame = newFrame
	_G.UIParent = newFrame()
	_G.GameTooltip = newFrame()
	_G.DEFAULT_CHAT_FRAME = {
		AddMessage = function(_, line)
			M.chat[#M.chat + 1] = line
		end,
	}
	_G.SlashCmdList = {}
	_G.WOW_PROJECT_ID = 18
	_G.NUM_TOTAL_EQUIPPED_BAG_SLOTS = 4
	_G.Enum = {
		WeaponSlot = { MainHand = 0, OffHand = 1, Ranged = 2 },
		ItemEnchantType = { None = 0, Permanent = 1, Temporary = 2, Imbue = 3 },
	}
	_G.GetBuildInfo = function()
		return "1.60.1", "70790", "Nov 4 2026", 16001
	end
	_G.C_AddOns = {
		GetAddOnMetadata = function()
			return "@project-version@"
		end,
	}
	_G.date = function(fmt)
		return os.date(fmt)
	end
	_G.strtrim = function(s)
		return (s:gsub("^%s+", ""):gsub("%s+$", ""))
	end
	_G.issecretvalue = function(v)
		return v ~= nil and M.secret[v] == true
	end
	_G.InCombatLockdown = function()
		return M.inCombat
	end
	_G.IsShiftKeyDown = function()
		return false
	end
	_G.C_Timer = {
		After = function(sec, fn)
			M.timers[#M.timers + 1] = { sec = sec, fn = fn }
		end,
		NewTicker = function() end,
	}
	_G.C_Spell = {
		GetSpellName = function()
			return "Fishing"
		end,
	}
	_G.GetInventoryItemID = function(_, slot)
		return M.equipped[slot]
	end
	_G.C_Item = {
		GetItemInfo = function(id)
			local it = M.items[id]
			if not it then
				return nil
			end
			return it.name, "|Hitem:" .. id .. "|h", 1, it.itemLevel or 10
		end,
		GetItemInfoInstant = function(id)
			local it = M.items[id]
			return id, "", "", "", 0, it and it.classID or 0, it and it.subclassID or 0
		end,
		IsUsableItem = function(id)
			local it = M.items[id]
			return it and it.usable ~= false
		end,
		GetItemIconByID = function(id)
			return 1000 + id
		end,
		GetWeaponEnchantInfo = function(slot)
			local e = M.enchant[slot]
			if e == "secret" then
				local v = {}
				M.secret[v] = true
				return { { hasEnchant = v, enchantType = 2 } }
			end
			if e then
				return { { hasEnchant = true, enchantType = 2, timeLeft = 1800000, charges = 0, enchantID = 1 } }
			end
			return { { hasEnchant = false, enchantType = 0, timeLeft = 0, charges = 0, enchantID = 0 } }
		end,
	}
	_G.C_Container = {
		GetContainerNumSlots = function(bag)
			return M.bags[bag] and 16 or 0
		end,
		GetContainerItemInfo = function(bag, slot)
			local id = M.bags[bag] and M.bags[bag][slot]
			if not id then
				return nil
			end
			return { itemID = id, stackCount = M.stacks[id] or 1 }
		end,
	}
	M.stacks = {} -- id -> stack size of each bag slot holding it
	M.auras = {} -- spell id -> true, or "secret"
	M.prices = {} -- item id -> copper
	M.level = 60
	_G.C_UnitAuras = {
		GetPlayerAuraBySpellID = function(id)
			local a = M.auras[id]
			if a == "secret" then
				local v = {}
				M.secret[v] = true
				return v
			end
			return a and { spellId = id } or nil
		end,
	}
	_G.UnitLevel = function()
		return M.level
	end
	_G.TSM_API = {
		GetCustomPriceValue = function(_, itemString)
			local id = tonumber(itemString:match("^i:(%d+)$"))
			return M.prices[id]
		end,
	}
	_G.Settings = nil
	M.bindings = {} -- key -> command
	M.saved = 0
	M.setBindingFails = false
	_G.GetBindingAction = function(key)
		return M.bindings[key] or ""
	end
	_G.GetBindingKey = function(command)
		for k, c in pairs(M.bindings) do
			if c == command then
				return k
			end
		end
	end
	_G.SetBinding = function(key, command)
		if M.inCombat then
			error("SetBinding in combat")
		end
		if M.setBindingFails then
			return false
		end
		M.bindings[key] = command
		return true
	end
	_G.UnitGUID = function()
		return "Player-1-ABC"
	end
	_G.SaveBindings = function()
		M.saved = M.saved + 1
	end
	_G.GetCurrentBindingSet = function()
		return 2
	end
end

function M.item(id, fields)
	M.items[id] = fields
	return id
end

-- Puts the ids in bag 0, slots 1..n.
function M.bag(...)
	M.bags[0] = { ... }
end

function M.loadAddon(dir, saved)
	local ns = {}
	for _, f in ipairs({ "Logic.lua", "Options.lua", "Core.lua" }) do
		local chunk, err = loadfile(dir .. "/" .. f)
		assert(chunk, err)
		chunk("BaitAndBlade", ns)
	end
	_G.BaitAndBladeDB = saved
	M.fire("ADDON_LOADED", "BaitAndBlade")
	M.fire("PLAYER_LOGIN")
	M.ns = ns
	return ns
end

function M.fire(event, ...)
	for _, f in ipairs(M.frames) do
		if f._scripts.OnEvent and f._events[event] then
			f._scripts.OnEvent(f, event, ...)
		end
	end
end

return M
