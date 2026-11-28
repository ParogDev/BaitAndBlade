-- The picker (/bab panel) and the small shopping window at the auction house. Per slot (food, elixir, a poison per
-- hand, a sharpening stone) the player picks what they want and sees every tier with its bonus, level, price and
-- how many they hold; unticking "worth it" rules a tier out. Below it: what to buy, with a search button per line.
-- Everything shown comes from Core (ns.ladder, ns.state); nothing here uses an item or acts without a click.
-- luacheck: read globals CreateFrame UIParent UISpecialFrames GameTooltip C_Item IsShiftKeyDown WeakAuras tinsert
local _, ns = ...

local Panel = {}
ns.Panel = Panel

-- One meaning per colour, shared with the aura pack.
local BONE = { 0.94, 0.91, 0.82 } -- what you read
local BRASS = { 0.96, 0.78, 0.29 } -- the recommended tier, money, "buy"
local JADE = { 0.27, 0.84, 0.66 } -- nothing to do
local SLATE = { 0.56, 0.6, 0.68 } -- secondary, switched off, ruled out
local ALARM = { 1, 0.45, 0.38 } -- you cannot use this yet
local INK = { 0.05, 0.06, 0.09 } -- the window

local WHITE = "Interface\\Buttons\\WHITE8x8"
local QUESTION_ICON = 134400
local WIDTH, HEIGHT = 650, 540
local PAD = 12
local LEFT_W = 150
local SLOT_H = 44
local ROW_H = 34
local VISIBLE = 7 -- ladder rows on screen; the mouse wheel moves through the rest
local BUY_ROWS = 5 -- one per slot at most
local BUY_H = 22
local RIGHT_W = WIDTH - LEFT_W - PAD * 3

local st = { built = false, rows = 0 }
if ns.selftest then
	ns.selftest.panel = st
end

-- Runs fn through ns.guard and keeps the failure in the selftest, so a broken redraw is named, not silent.
local function safe(where, fn, ...)
	local ok, err
	if ns.guard then
		ok, err = ns.guard(where, fn, ...)
	else
		ok, err = pcall(fn, ...)
	end
	if not ok then
		st.error = where .. ": " .. tostring(err)
	end
	return ok, err
end

local function say(line)
	if ns.say then
		ns.say(line)
	end
end

local function money(copper)
	if ns.money then
		return ns.money(copper)
	end
	return string.format("%dg %02ds", copper / 10000, (copper / 100) % 100)
end

local function paint(fs, c, alpha)
	fs:SetTextColor(c[1], c[2], c[3], alpha or 1)
end

local function label(parent, font, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
	fs:SetJustifyH(justify or "LEFT")
	fs:SetWordWrap(false)
	return fs
end

local function fill(parent, layer, c, alpha)
	local t = parent:CreateTexture(nil, layer)
	t:SetColorTexture(c[1], c[2], c[3], alpha or 1)
	return t
end

local function button(parent, text, width, height)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, height or 20)
	b:SetText(text)
	return b
end

local function window(name, width, height)
	local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
	f:SetSize(width, height)
	f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	f:SetBackdropColor(INK[1], INK[2], INK[3], 0.95)
	f:SetBackdropBorderColor(BRASS[1], BRASS[2], BRASS[3], 0.45)
	f:SetFrameStrata("MEDIUM")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:Hide()
	return f
end

-- Drag to move; the place is kept in the saved variables under key.
local function remember(f, key, point, relPoint, x, y)
	local pos = ns.db and ns.db[key]
	f:ClearAllPoints()
	if type(pos) == "table" and pos.point then
		f:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
	else
		f:SetPoint(point, UIParent, relPoint, x, y)
	end
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local p, _, rp, px, py = self:GetPoint(1)
		if ns.db and p then
			ns.db[key] = { point = p, relPoint = rp, x = px, y = py }
		end
	end)
end

local function slotCfg(slot)
	local slots = ns.settings and ns.settings.slots
	return type(slots) == "table" and slots[slot] or nil
end

local function setSlot(slot, key, value)
	if ns.setSlot then
		ns.setSlot(slot, key, value)
		return
	end
	local cfg = slotCfg(slot)
	if cfg then
		cfg[key] = value
		if ns.queueRefresh then
			ns.queueRefresh()
		end
	end
end

-- The slots this character has, in Plan's order.
local function availableSlots()
	local out = {}
	local Plan = ns.Plan
	if not Plan then
		return out
	end
	local class = ns.playerClass and ns.playerClass() or nil
	for _, slot in ipairs(Plan.SLOTS) do
		if slotCfg(slot) and Plan.available(slot, class) then
			out[#out + 1] = slot
		end
	end
	return out
end

local function shoppingList()
	local list = ns.state and ns.state.shopping
	return type(list) == "table" and list or {}
end

local function itemIcon(id)
	local icon = id and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
	return icon or QUESTION_ICON
end

local function itemTooltip(owner, id)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	if id and GameTooltip.SetItemByID then
		GameTooltip:SetItemByID(id)
	end
	GameTooltip:Show()
end

local function hideTooltip()
	GameTooltip:Hide()
end

local function search(id)
	if not ns.search then
		say("Search is not available: this version of the addon has no auction house search.")
		return
	end
	local ok, why = ns.search(id)
	if not ok then
		say(why or "The search did not start.")
	end
end

-- ---------------------------------------------------------------- shopping lines (picker and auction window)

-- compact (the auction window): no "each" column, the line total only.
local function buyRow(parent, width, compact)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(width, BUY_H)
	row:EnableMouse(true)
	row.compact = compact
	row.search = button(row, "Search", 62, 18)
	row.search:SetPoint("RIGHT", 0, 0)
	row.total = label(row, "GameFontHighlightSmall", "RIGHT")
	row.total:SetPoint("RIGHT", row.search, "LEFT", -8, 0)
	row.total:SetWidth(76)
	row.each = label(row, "GameFontHighlightSmall", "RIGHT")
	row.each:SetPoint("RIGHT", row.total, "LEFT", -6, 0)
	row.each:SetWidth(96)
	row.each:SetShown(not compact)
	row.what = label(row, "GameFontHighlightSmall")
	row.what:SetPoint("LEFT", 0, 0)
	row.what:SetWidth(width - 62 - 8 - 76 - 6 - (compact and 0 or 102))
	paint(row.what, BONE)
	paint(row.total, BRASS)
	row.search:SetScript("OnClick", function()
		safe("Panel.search", search, row.id)
	end)
	row:SetScript("OnEnter", function(self)
		itemTooltip(self, self.id)
	end)
	row:SetScript("OnLeave", hideTooltip)
	return row
end

-- Fills up to #rows lines; returns the grand total line.
local function drawBuyRows(rows, list)
	local total, unpriced = 0, 0
	for i, row in ipairs(rows) do
		local b = list[i]
		if b then
			local need = b.need or 0
			row.id = b.id
			row.what:SetText(need .. " x " .. (b.name or "?"))
			if b.price then
				row.each:SetText(money(b.price) .. " each")
				row.total:SetText(money(b.price * need))
				paint(row.each, SLATE)
				paint(row.total, BRASS)
			else
				row.each:SetText("")
				row.total:SetText("no price")
				paint(row.total, SLATE, 0.8)
			end
			row:Show()
		else
			row:Hide()
		end
	end
	for _, b in ipairs(list) do
		if b.price then
			total = total + b.price * (b.need or 0)
		else
			unpriced = unpriced + 1
		end
	end
	if #list == 0 then
		return ""
	end
	local line = total > 0 and ("Total " .. money(total)) or "No prices"
	if unpriced > 0 and total > 0 then
		line = line .. ", " .. unpriced .. " without a price"
	end
	if #list > #rows then
		line = line .. " (+" .. (#list - #rows) .. " more lines)"
	end
	return line
end

-- ---------------------------------------------------------------- the picker

local ui = {} -- the picker's parts, filled by build()

local function statusOf(slot)
	local cfg = slotCfg(slot)
	local Plan = ns.Plan
	if not cfg or not cfg.on then
		return "off", SLATE
	end
	if Plan and cfg.choice == Plan.NONE then
		return "nothing chosen", SLATE
	end
	local r = ns.state and ns.state.reminders and ns.state.reminders[slot]
	if r and r.show then
		return r.text or "missing", r.kind == "buy" and BRASS or BONE
	end
	return "ok", JADE
end

local function drawSlots()
	local slots = availableSlots()
	local selected = false
	for _, slot in ipairs(slots) do
		selected = selected or slot == Panel.selected
	end
	if not selected then
		Panel.selected = slots[1]
		ui.offset = nil
	end
	local shown = 0
	for _, row in ipairs(ui.slotRows) do
		row:Hide()
	end
	for _, slot in ipairs(slots) do
		shown = shown + 1
		local row = ui.slotRows[shown]
		if not row then
			break
		end
		local cfg = slotCfg(slot)
		local spec = ns.Plan.SLOT[slot]
		local status, c = statusOf(slot)
		row.slot = slot
		row.check:SetChecked(cfg.on and true or false)
		row.title:SetText(spec and spec.title or slot)
		row.status:SetText(status)
		paint(row.status, c)
		paint(row.title, BONE, cfg.on and 1 or 0.55)
		local on = slot == Panel.selected
		row.wash:SetShown(on)
		row.bar:SetShown(on)
		row:Show()
	end
	st.slots = shown
end

local function drawLadder()
	local slot = Panel.selected
	local cfg = slot and slotCfg(slot)
	local Plan = ns.Plan
	local rows = {}
	if slot and cfg and ns.ladder then
		rows = ns.ladder(slot) or {}
	end
	local n = #rows
	st.rows = n

	local spec = slot and Plan and Plan.SLOT[slot]
	ui.heading:SetText(spec and spec.title or "")
	local choices = slot and Plan and Plan.choices(slot) or {}
	ui.dropdown:SetShown(#choices > 1)
	if ui.menuSlot ~= slot then
		ui.menuSlot = slot
		if ui.dropdown.GenerateMenu then
			ui.dropdown:GenerateMenu()
		end
	end

	local maxOffset = math.max(0, n - VISIBLE)
	if not ui.offset then
		-- a fresh slot or choice: bring the recommended tier into view, two rows from the top
		ui.offset = 0
		for i, r in ipairs(rows) do
			if r.recommended then
				ui.offset = i - 3
			end
		end
	end
	ui.offset = math.max(0, math.min(maxOffset, ui.offset))

	for i, row in ipairs(ui.ladderRows) do
		local r = rows[i + ui.offset]
		if r then
			local dim = not r.usable
			row.id = r.id
			row.check:SetChecked(not r.skipped)
			row.icon:SetTexture(itemIcon(r.id))
			row.icon:SetDesaturated(dim or r.skipped)
			row.icon:SetAlpha(dim and 0.45 or 1)
			row.name:SetText(r.name or "?")
			row.bonus:SetText(r.bonus or "")
			if dim then
				paint(row.name, SLATE, 0.75)
				paint(row.bonus, SLATE, 0.6)
				row.level:SetText("needs level " .. (r.level or "?"))
				paint(row.level, ALARM, 0.9)
			else
				paint(row.name, r.recommended and BRASS or (r.skipped and SLATE or BONE))
				paint(row.bonus, r.skipped and SLATE or BONE, r.skipped and 0.7 or 0.8)
				row.level:SetText("level " .. (r.level or "?"))
				paint(row.level, SLATE)
			end
			row.tag:SetText(r.recommended and "recommended" or (r.skipped and not dim and "ruled out" or ""))
			paint(row.tag, r.recommended and BRASS or SLATE, r.recommended and 1 or 0.7)
			row.price:SetText(r.price and money(r.price) or "no price")
			paint(row.price, r.price and BONE or SLATE, (dim or not r.price) and 0.6 or 1)
			local count = r.count or 0
			row.held:SetText(count > 0 and tostring(count) or "-")
			paint(row.held, count > 0 and JADE or SLATE, count > 0 and 1 or 0.6)
			row.wash:SetShown(r.recommended and true or false)
			row.bar:SetShown(r.recommended and true or false)
			row:Show()
		else
			row:Hide()
		end
	end

	if n == 0 then
		local none = Plan and cfg and cfg.choice == Plan.NONE
		ui.empty:SetText(none and "Nothing chosen for this slot, so no reminder." or "No tiers for this choice.")
		ui.empty:Show()
	else
		ui.empty:Hide()
	end

	-- the scroll mark on the right edge of the ladder
	if n > VISIBLE then
		local track = VISIBLE * ROW_H
		local size = math.max(18, track * VISIBLE / n)
		ui.thumb:SetHeight(size)
		ui.thumb:ClearAllPoints()
		ui.thumb:SetPoint("TOPRIGHT", ui.ladder, "TOPRIGHT", 0, -(track - size) * ui.offset / maxOffset)
		ui.thumb:Show()
		ui.track:Show()
	else
		ui.thumb:Hide()
		ui.track:Hide()
	end
end

local function drawBuying()
	local list = shoppingList()
	ui.buyTotal:SetText(drawBuyRows(ui.buyRows, list))
	ui.buyEmpty:SetShown(#list == 0)
	st.shopping = #list
	for _, s in ipairs(ui.steppers) do
		s.refresh()
	end
	if type(WeakAuras) == "table" then
		ui.auraHint:SetText("The reminders on screen are ForeverAuras auras. Install them once.")
	else
		ui.auraHint:SetText("ForeverAuras is not installed: the reminders show only in this window.")
	end
end

local function draw()
	drawSlots()
	drawLadder()
	drawBuying()
end

local function redraw()
	if ui.frame and ui.frame:IsShown() then
		safe("Panel.draw", draw)
	end
end

local function makeSlotRow(parent, index)
	local row = CreateFrame("Button", nil, parent)
	row:SetSize(LEFT_W, SLOT_H)
	row:SetPoint("TOPLEFT", 0, -(index - 1) * SLOT_H)
	row.wash = fill(row, "BACKGROUND", BRASS, 0.1)
	row.wash:SetAllPoints()
	row.bar = fill(row, "BORDER", BRASS, 1)
	row.bar:SetPoint("TOPLEFT")
	row.bar:SetPoint("BOTTOMLEFT")
	row.bar:SetWidth(2)
	local hover = fill(row, "HIGHLIGHT", BONE, 0.05)
	hover:SetAllPoints()
	row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
	row.check:SetSize(24, 24)
	row.check:SetPoint("LEFT", 6, 0)
	row.title = label(row, "GameFontNormal")
	row.title:SetPoint("TOPLEFT", 32, -8)
	row.title:SetWidth(LEFT_W - 36)
	row.status = label(row, "GameFontHighlightSmall")
	row.status:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -3)
	row.status:SetWidth(LEFT_W - 36)
	row:SetScript("OnClick", function(self)
		if Panel.selected ~= self.slot then
			Panel.selected = self.slot
			ui.offset = nil
		end
		redraw()
	end)
	row:SetScript("OnEnter", function(self)
		-- the status line is cut to the column: the tooltip has all of it
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(self.title:GetText() or "")
		GameTooltip:AddLine(self.status:GetText() or "", 1, 1, 1, true)
		GameTooltip:AddLine("The tick switches this reminder on or off.", 0.6, 0.6, 0.6, true)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", hideTooltip)
	row.check:SetScript("OnClick", function(self)
		local on = self:GetChecked() and true or false
		safe("Panel.slotOn", setSlot, row.slot, "on", on)
		redraw()
	end)
	return row
end

-- Column edges of a ladder row, from the left.
local COL_ICON = 28
local COL_TEXT = 62
local COL_HELD_W = 40
local COL_PRICE_W = 78
local COL_LEVEL_W = 80
local SCROLL_W = 10

local function makeLadderRow(parent, index)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(RIGHT_W - SCROLL_W, ROW_H)
	row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_H)
	row:EnableMouse(true)
	row.wash = fill(row, "BACKGROUND", BRASS, 0.1)
	row.wash:SetAllPoints()
	row.bar = fill(row, "BORDER", BRASS, 1)
	row.bar:SetPoint("TOPLEFT")
	row.bar:SetPoint("BOTTOMLEFT")
	row.bar:SetWidth(2)
	local rule = fill(row, "BORDER", BONE, 0.06)
	rule:SetPoint("BOTTOMLEFT")
	rule:SetPoint("BOTTOMRIGHT")
	rule:SetHeight(1)

	row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
	row.check:SetSize(22, 22)
	row.check:SetPoint("LEFT", 4, 0)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(26, 26)
	row.icon:SetPoint("LEFT", COL_ICON, 0)
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	row.held = label(row, "GameFontHighlight", "RIGHT")
	row.held:SetPoint("RIGHT", -6, 0)
	row.held:SetWidth(COL_HELD_W - 6)
	row.price = label(row, "GameFontHighlightSmall", "RIGHT")
	row.price:SetPoint("RIGHT", -COL_HELD_W, 0)
	row.price:SetWidth(COL_PRICE_W)
	row.level = label(row, "GameFontHighlightSmall", "RIGHT")
	row.level:SetPoint("TOPRIGHT", -(COL_HELD_W + COL_PRICE_W + 6), -5)
	row.level:SetWidth(COL_LEVEL_W)
	row.tag = label(row, "GameFontHighlightSmall", "RIGHT")
	row.tag:SetPoint("TOPRIGHT", row.level, "BOTTOMRIGHT", 0, -2)
	row.tag:SetWidth(COL_LEVEL_W)

	row.name = label(row, "GameFontNormal")
	local textWidth = RIGHT_W - SCROLL_W - COL_TEXT - (COL_HELD_W + COL_PRICE_W + COL_LEVEL_W + 12)
	row.name:SetPoint("TOPLEFT", COL_TEXT, -4)
	row.name:SetWidth(textWidth)
	row.bonus = label(row, "GameFontHighlightSmall")
	row.bonus:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
	row.bonus:SetWidth(textWidth)

	row:SetScript("OnEnter", function(self)
		itemTooltip(self, self.id)
	end)
	row:SetScript("OnLeave", hideTooltip)
	row.check:SetScript("OnClick", function(self)
		local skipped = not self:GetChecked()
		local slot, id = Panel.selected, row.id
		safe("Panel.skip", function()
			if ns.setSkip then
				ns.setSkip(slot, id, skipped)
			else
				local cfg = slotCfg(slot)
				if cfg then
					cfg.skip = type(cfg.skip) == "table" and cfg.skip or {}
					cfg.skip[id] = skipped
					if ns.queueRefresh then
						ns.queueRefresh()
					end
				end
			end
		end)
		redraw()
	end)
	row.check:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Worth it")
		GameTooltip:AddLine(
			"Untick a tier that costs too much for what it gives. The recommendation moves to the next one.",
			1,
			1,
			1,
			true
		)
		GameTooltip:Show()
	end)
	row.check:SetScript("OnLeave", hideTooltip)
	return row
end

-- "label [-] 5 [+]". Shift steps by five.
local function makeStepper(parent, text, get, set)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(200, 22)
	local name = label(holder, "GameFontHighlightSmall")
	name:SetPoint("LEFT", 0, 0)
	name:SetText(text)
	paint(name, SLATE)
	local minus = button(holder, "-", 22, 20)
	minus:SetPoint("LEFT", name, "RIGHT", 6, 0)
	local value = label(holder, "GameFontNormal", "CENTER")
	value:SetPoint("LEFT", minus, "RIGHT", 2, 0)
	value:SetWidth(30)
	paint(value, BONE)
	local plus = button(holder, "+", 22, 20)
	plus:SetPoint("LEFT", value, "RIGHT", 2, 0)
	local function step(direction)
		return function()
			safe("Panel.stepper", function()
				set(get() + direction * (IsShiftKeyDown() and 5 or 1))
				if ns.queueRefresh then
					ns.queueRefresh()
				end
			end)
			redraw()
		end
	end
	minus:SetScript("OnClick", step(-1))
	plus:SetScript("OnClick", step(1))
	holder.refresh = function()
		value:SetText(tostring(get()))
	end
	return holder
end

local function setting(key, fallback)
	return tonumber(ns.settings and ns.settings[key]) or fallback
end

local function build()
	local Plan = ns.Plan
	if not Plan then
		error("ns.Plan is missing: Plan.lua did not load")
	end
	if ns.selftest then
		ns.selftest.panel = st
	end
	local f = window("BaitAndBladePanel", WIDTH, HEIGHT)
	-- Left edge of the screen: the middle stays free.
	remember(f, "panelPosition", "LEFT", "LEFT", 24, 20)
	tinsert(UISpecialFrames, "BaitAndBladePanel")

	local title = label(f, "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", PAD, -PAD)
	title:SetText("BaitAndBlade")
	paint(title, BRASS)
	local sub = label(f, "GameFontHighlightSmall")
	sub:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 8, 1)
	sub:SetText("what to carry, and what it costs")
	paint(sub, SLATE)
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)
	close:SetScript("OnClick", function()
		f:Hide()
	end)

	local top = -(PAD + 28)

	-- left: one row per slot
	local left = CreateFrame("Frame", nil, f)
	left:SetPoint("TOPLEFT", PAD, top)
	left:SetSize(LEFT_W, SLOT_H * #Plan.SLOTS)
	ui.slotRows = {}
	for i = 1, #Plan.SLOTS do
		ui.slotRows[i] = makeSlotRow(left, i)
	end
	local divide = fill(f, "BORDER", BONE, 0.08)
	divide:SetPoint("TOPLEFT", left, "TOPRIGHT", PAD / 2, 0)
	divide:SetSize(1, 30 + 16 + VISIBLE * ROW_H + 30)

	-- right: the choice and its ladder
	local right = CreateFrame("Frame", nil, f)
	right:SetPoint("TOPLEFT", left, "TOPRIGHT", PAD, 0)
	right:SetSize(RIGHT_W, 30 + 16 + VISIBLE * ROW_H + 30)
	ui.heading = label(right, "GameFontNormalLarge")
	ui.heading:SetPoint("TOPLEFT", 4, -4)
	paint(ui.heading, BONE)

	local dropdown = CreateFrame("DropdownButton", nil, right, "WowStyle1DropdownTemplate")
	dropdown:SetPoint("TOPRIGHT", -SCROLL_W, -1)
	dropdown:SetWidth(190)
	dropdown:SetupMenu(function(_, root)
		local slot = Panel.selected
		if not slot then
			return
		end
		local function isSelected(choice)
			local cfg = slotCfg(slot)
			return cfg ~= nil and cfg.choice == choice
		end
		local function choose(choice)
			safe("Panel.choice", setSlot, slot, "choice", choice)
			ui.offset = nil
			redraw()
		end
		for _, choice in ipairs(Plan.choices(slot)) do
			root:CreateRadio(choice, isSelected, choose, choice)
		end
	end)
	ui.dropdown = dropdown

	local heads = CreateFrame("Frame", nil, right)
	heads:SetPoint("TOPLEFT", 0, -30)
	heads:SetSize(RIGHT_W - SCROLL_W, 16)
	local function head(text, justify)
		local fs = label(heads, "GameFontHighlightSmall", justify)
		fs:SetText(text)
		paint(fs, SLATE, 0.85)
		return fs
	end
	head("worth it"):SetPoint("LEFT", 2, 0)
	head("tier"):SetPoint("LEFT", COL_TEXT, 0)
	head("held", "RIGHT"):SetPoint("RIGHT", -6, 0)
	head("price", "RIGHT"):SetPoint("RIGHT", -COL_HELD_W, 0)

	local ladder = CreateFrame("Frame", nil, right)
	ladder:SetPoint("TOPLEFT", 0, -46)
	ladder:SetSize(RIGHT_W, VISIBLE * ROW_H)
	ladder:EnableMouseWheel(true)
	ladder:SetScript("OnMouseWheel", function(_, delta)
		ui.offset = (ui.offset or 0) - delta
		redraw()
	end)
	ui.ladder = ladder
	ui.ladderRows = {}
	for i = 1, VISIBLE do
		ui.ladderRows[i] = makeLadderRow(ladder, i)
	end
	ui.track = fill(ladder, "BACKGROUND", BONE, 0.06)
	ui.track:SetPoint("TOPRIGHT")
	ui.track:SetPoint("BOTTOMRIGHT")
	ui.track:SetWidth(4)
	ui.thumb = fill(ladder, "ARTWORK", BRASS, 0.7)
	ui.thumb:SetWidth(4)
	ui.empty = label(ladder, "GameFontHighlight")
	ui.empty:SetPoint("TOPLEFT", 6, -12)
	paint(ui.empty, SLATE)

	ui.steppers = {
		makeStepper(right, "Remind below", function()
			return setting("lowCount", Plan.LOW_COUNT)
		end, function(v)
			ns.settings.lowCount = math.max(0, math.min(v, setting("stockTo", Plan.STOCK_TO)))
		end),
		makeStepper(right, "Stock up to", function()
			return setting("stockTo", Plan.STOCK_TO)
		end, function(v)
			ns.settings.stockTo = math.max(1, setting("lowCount", Plan.LOW_COUNT), math.min(v, 200))
		end),
	}
	ui.steppers[1]:SetPoint("BOTTOMLEFT", 4, 0)
	ui.steppers[2]:SetPoint("BOTTOMLEFT", 214, 0)

	-- bottom: what to buy
	local buy = CreateFrame("Frame", nil, f)
	buy:SetPoint("TOPLEFT", PAD, top - (30 + 16 + VISIBLE * ROW_H + 30) - 10)
	buy:SetSize(WIDTH - PAD * 2, 22 + BUY_ROWS * BUY_H)
	local rule = fill(buy, "BORDER", BRASS, 0.35)
	rule:SetPoint("TOPLEFT")
	rule:SetPoint("TOPRIGHT")
	rule:SetHeight(1)
	local buyTitle = label(buy, "GameFontNormal")
	buyTitle:SetPoint("TOPLEFT", 0, -6)
	buyTitle:SetText("To buy")
	paint(buyTitle, BRASS)
	ui.buyTotal = label(buy, "GameFontHighlightSmall", "RIGHT")
	ui.buyTotal:SetPoint("TOPRIGHT", 0, -8)
	paint(ui.buyTotal, BONE)
	ui.buyRows = {}
	for i = 1, BUY_ROWS do
		local row = buyRow(buy, WIDTH - PAD * 2)
		row:SetPoint("TOPLEFT", 0, -22 - (i - 1) * BUY_H)
		ui.buyRows[i] = row
	end
	ui.buyEmpty = label(buy, "GameFontHighlightSmall")
	ui.buyEmpty:SetPoint("TOPLEFT", 0, -26)
	ui.buyEmpty:SetText("Nothing to buy: you hold enough of everything you chose.")
	paint(ui.buyEmpty, JADE)

	local install = button(f, "Install reminder auras", 170, 22)
	install:SetPoint("BOTTOMLEFT", PAD, PAD)
	install:SetScript("OnClick", function()
		if ns.AuraPack and ns.AuraPack.install then
			safe("Panel.install", ns.AuraPack.install)
		else
			say("The aura pack is missing from this copy of the addon.")
		end
	end)
	ui.auraHint = label(f, "GameFontHighlightSmall")
	ui.auraHint:SetPoint("LEFT", install, "RIGHT", 10, 0)
	ui.auraHint:SetWidth(WIDTH - PAD * 2 - 180)
	paint(ui.auraHint, SLATE)

	ui.frame = f
	st.built = true
end

-- ---------------------------------------------------------------- the shopping window at the auction house

local shop = { atAuction = false }
local SHOP_W = 400

local function buildShop()
	-- Anchored to the screen, not to AuctionHouseFrame: TradeSkillMaster puts its own window in its place.
	local f = window("BaitAndBladeShopping", SHOP_W, 34 + BUY_ROWS * BUY_H + 24)
	remember(f, "shopPosition", "RIGHT", "RIGHT", -40, 60)
	local title = label(f, "GameFontNormal")
	title:SetPoint("TOPLEFT", PAD, -9)
	title:SetText("BaitAndBlade: to buy")
	paint(title, BRASS)
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)
	close:SetScript("OnClick", function()
		shop.dismissed = true
		f:Hide()
	end)
	shop.rows = {}
	for i = 1, BUY_ROWS do
		local row = buyRow(f, SHOP_W - PAD * 2, true)
		row:SetPoint("TOPLEFT", PAD, -30 - (i - 1) * BUY_H)
		shop.rows[i] = row
	end
	shop.total = label(f, "GameFontHighlightSmall", "RIGHT")
	shop.total:SetPoint("BOTTOMRIGHT", -PAD, 8)
	paint(shop.total, BONE)
	shop.frame = f
	st.shopBuilt = true
end

-- Shown while the auction house is open and there is something to buy; closing it by hand keeps it closed
-- until the next visit.
local function drawShop()
	local list = shoppingList()
	local want = shop.atAuction and #list > 0 and not shop.dismissed
	if not want then
		if shop.frame then
			shop.frame:Hide()
		end
		return
	end
	if not shop.frame then
		buildShop()
	end
	local f = shop.frame
	local lines = math.min(#list, BUY_ROWS)
	f:SetHeight(34 + lines * BUY_H + 24)
	shop.total:SetText(drawBuyRows(shop.rows, list))
	f:Show()
end

local events = CreateFrame("Frame")
events:RegisterEvent("AUCTION_HOUSE_SHOW")
events:RegisterEvent("AUCTION_HOUSE_CLOSED")
events:SetScript("OnEvent", function(_, event)
	shop.atAuction = event == "AUCTION_HOUSE_SHOW"
	shop.dismissed = false
	st.atAuction = shop.atAuction
	safe("Panel.shop", drawShop)
end)

-- ---------------------------------------------------------------- what Core calls

-- Opens or closes the picker. Returns true when it is open afterwards.
function Panel.toggle()
	if not ui.frame then
		if not safe("Panel.build", build) then
			say("The panel could not be built: " .. tostring(st.error))
			return false
		end
	end
	local f = ui.frame
	if f:IsShown() then
		f:Hide()
		return false
	end
	f:Show()
	safe("Panel.draw", draw)
	return true
end

-- Core calls this after every change of ns.state.
function Panel.update()
	redraw()
	safe("Panel.shop", drawShop)
end

return Panel
