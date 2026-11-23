-- luacheck for a WoW: Forever addon. Run from this folder (tools\lua.ps1 does): the generated globals list
-- lives in the scaffolding root; standalone (CI in this repo) falls back to a short list.
std = "lua51"
max_line_length = 140
codes = true
ignore = {
	"212/self", -- unused self
	"212/_.*", -- unused args named _x
	"211/_.*", -- unused locals named _x
}

local client = {
	"CreateFrame", "C_AddOns", "C_Item", "C_Container", "C_Spell", "C_Timer", "GetBuildInfo", "GetInventoryItemID",
	"InCombatLockdown", "IsShiftKeyDown", "WOW_PROJECT_ID", "issecretvalue", "date", "strtrim", "Enum",
}
-- FrameXML globals the generated list may not carry.
local framexml = {
	"DEFAULT_CHAT_FRAME", "NUM_TOTAL_EQUIPPED_BAG_SLOTS", "NUM_BAG_SLOTS", "UIParent", "GameTooltip", "Settings",
	"CreateSettingsButtonInitializer",
}

local ok, wow = pcall(dofile, "../../tools/luacheck-wow-globals.lua")
read_globals = {}
if ok and type(wow) == "table" then
	for _, g in ipairs(wow.read_globals) do
		if g ~= "SlashCmdList" then
			read_globals[#read_globals + 1] = g
		end
	end
else
	-- CI in this repo runs standalone: every global the addon touches must be here.
	for _, g in ipairs(client) do
		read_globals[#read_globals + 1] = g
	end
end
for _, g in ipairs(framexml) do
	read_globals[#read_globals + 1] = g
end

globals = { "BaitAndBlade", "BaitAndBladeDB", "SLASH_BAITANDBLADE1", "SLASH_BAITANDBLADE2", "SlashCmdList" }

local testGlobals = { "BaitAndBlade", "BaitAndBladeDB", "_G", "SlashCmdList" }
for _, g in ipairs(client) do
	testGlobals[#testGlobals + 1] = g
end
for _, g in ipairs(framexml) do
	testGlobals[#testGlobals + 1] = g
end
files["tests/"] = { std = "+busted", globals = testGlobals }
exclude_files = { ".luacheckrc", ".release/" }
