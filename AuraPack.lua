-- The reminder auras for ForeverAuras, as an import string. /bab auras and the panel button hand it to ForeverAuras,
-- which opens its own import window: the player confirms there, nothing is installed without that click.
-- STRING is generated: do not edit it by hand. Its source is auras/baitandblade/baitandblade.lua in the author's
-- workspace, built with `python tools/foreverauras/fa.py encode`. To change an aura, change it in ForeverAuras,
-- export the group and replace the string. The auras only read BaitAndBlade.state and listen for the
-- BAITANDBLADE_UPDATE event that Core fires.
-- luacheck: no max line length
-- luacheck: read globals WeakAuras
local _, ns = ...

local AuraPack = {}
ns.AuraPack = AuraPack

-- stylua: ignore
AuraPack.STRING = "!WA:2!LJ1sZTrXw44iyJwqLOqLBrCa6iUX3KqkvYpiVaxuASLtmxzj7Xk2j8YU1m9OPDg1DtpZyhrLIfEvwDF4lWkUxUL)fag2Lv4FbNYfByB(jKFbC6zKFOGnuQcvSRkB6PpNPv3NhFFNJMUV5Y1kNBo3hE68C3nTO8OscxRaQlBOyU7gnACtTmwvSyXbFcxeX0cAWCmDixkE06Awt8z92k2MUTf0wCNMMfBHJRS(TQzp5hwRA9svSPb8MIgJvUA9Y2RfYc8MwI7fKDDhMzlnBq(k2wHsDKLqky2HkQdRTomI2Sjt3NMk4TOrm)vJdzv4T4r(Bqfo(sDNn6jPstOPTyMDRXSJzxUCv99R55fYI6t3oDI7ROY5ifrAzqaZDmFEGRMjwsLBV(9nitiLUQxTBDLd43NRv)LU1ofLli(uHR60D)c88s1FQU1pBe6FQ(FkL(sLIlAsc4HrRgP5gVo8mdO7mDoRiJt5ehgjBTr6JfsuHrOO4qBhFMZ9SzlJHZgjJHhhYR63lw4eHzOlCrIMffRfepAqiJWeURfl6S5zTcKuxmxifUCZQdZUbx4j1yehLgyOyDWXTCzHoQV1M1IlCrBJ4PLTir(mYE9ec11vkUbXdJFxMWsIyxMqjkjpukikMojMyuf6t1kMW40HMqcQt4swXNgrIKKgXTlqQYyUHDV)flmsHIePMeGObDbmrPr3vtgSWvkwyWc5w(NVtUWgdIRAWHZ5S0dpbIPHxdoocJn50IgyCdffZ5rqFWl9i4LT4OFBVc3nYFMg(mEt)Ozw3OBwzS2HD2Jz95szRPZuSWWR6iLbUYve(BT9SzxHRy(QxDB56S7hnopK2arxlcV5NoaqwgohKhEl4VcNhga(BQlzvAY6LQoUvLsJxEHBp94LQx(YKPRu6ULTxiHHmz1BUW81SRmoMc)MDtHzjKaPdnG0GmAxrLDEHgFrJK4yJcgGbBVZlO3j3TVAlysA4w1bOCbDYY0fc9LRCXK5r6yMj2NGHYIyO1trIvrsN6FCyzOBBNryO3yD5ZVhtBsmrQw7W20mWjJPn4WJmsXIgZdUyweAmx3qd4DXe(3DKiH3z69WvsgDusEKpM)aabOROojfn5Lz1tlOmL0LLzdxE4sjUYYSHOI2WLYUEyCd7KogH340W52cfBqDUNPLHW1do3AgfsnABpo9XclZd5ivAXn6iZCBYuNC2plgzWKjIdciZ7ZJyB)6q(NZYSvhbzsb)mB2r0rgi1FqF91NHkF9hEs4CA84mGM1mdlygYFErQGh2IqDMj4AkzwQiKmgwAKjczUKPyU84wBTZQMfpY(3v007rx721Rmz1YRNOn9CN(LWdDKKXbnJxBOmBM86T9WntBGTGY0pBtChWIbw1QxV2upozD7000Q0TRxBR0vF30MAV3Xs3RLqip3RnKvDQezAmYaWA4oZBQUzpb)(m3NKAQMPjA)PuBFfminVMQwD(otuNi9y9PyzTX2o2LrLBpQVt6X3TYo20zpg82Nza48xbiV8Qlt1Ctjrld0YEzAqmlJ2b7e0KfEPbwvPLyulQ96ypgSBMgrPqZfha4QtGPOcdxy3aj0mnuEfZ4vVMzCORNjTm)zskZN2MglZdd1PcpmmmYmW7mdCf0OUAsLC4A(W19HBS)LOt4H)VNF8W0(K9wPxyu1)6WZc3)AUW7R(YdFBQxk2UXrKKCVvUfSYaJbJJvuHYMcPWeyXt4MWTweMe(a4VNbQKbMQRADqvOgwDdMgMbS7hMfQd3E)kkbZTimpCh4UWhcF07Dm4JHSWNaFkSWpblcuOrsraWjd4UxcoWapOzgW)siPfwkL8c373JS2Fcz18VNVf6MpRK1))ZV8yRoMCptxx7W0gpqc7xFuWQ6fk7pEKjv)IhP9SjKwSbVjQ8m3H9BF(LjLPMCpZz)3hIM4bsz)QJagvVWy)HJk55x8iSVEcHn5kNk(S)xI)Vp)sKjxjuptx)NhAg4bsw)ph6MuVqv)(Jgz4xOiQNYquFJuIANRbExIQLbqzUkfvaTD90ROq3578TQuEI6pU7pY3QekU62FnpqTmxkbmZQ7CvfAzCuaxWG62h4ntSXt)v)B1937V1t)L(Vzvep5Tp4Ph0l4PWFx8eIlu7bUKcRc)dki8l)PF(PlnHMpkzBJWiIVJ7rm3j)fmIxK8fiWnmsJPZ8gZk9NG6YBU1CbU8DCgSybXCL876E5FGJNN374C1rO1tUm8hO)yrEsHcjBZVf3)2z)va"

-- Hands the pack to ForeverAuras' import window. Returns true when the window was asked for, false with the reason
-- in chat when ForeverAuras is missing or refuses the string.
function AuraPack.install()
	local st = { at = date and date("%Y-%m-%d %H:%M:%S") or nil }
	if ns.selftest then
		ns.selftest.auraPack = st
	end
	local function say(line)
		if ns.say then
			ns.say(line)
		end
	end
	if type(WeakAuras) ~= "table" or type(WeakAuras.Import) ~= "function" then
		st.error = "ForeverAuras not loaded (no WeakAuras.Import)"
		say("ForeverAuras is not installed: the reminders need it")
		return false
	end
	-- Import(string) shows the import window and returns nothing; a string it cannot read comes back as nil, reason.
	local ok, a, b = pcall(WeakAuras.Import, AuraPack.STRING)
	if not ok then
		st.error = "WeakAuras.Import failed: " .. tostring(a)
		say("ForeverAuras could not open the import: " .. tostring(a))
		return false
	end
	if type(b) == "string" then
		st.error = "WeakAuras.Import refused the string: " .. b
		say("ForeverAuras refused the reminder auras: " .. b)
		return false
	end
	st.asked = true
	say("ForeverAuras opened its import window: press Import there to add the reminder auras.")
	return true
end

return AuraPack
