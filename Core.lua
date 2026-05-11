local ADDON_NAME = ...
local TSMVFP = CreateFrame("Frame", ADDON_NAME .. "_Frame")
_G.TSMVFP = TSMVFP

TSMVFPDB = TSMVFPDB or {}
TSMVFPCharDB = TSMVFPCharDB or {}

local PREFIX = "|cff66ccffTSM-VFP|r: "
local function Log(fmt, ...)
	print(PREFIX .. fmt:format(...))
end

local function CheckTSM()
	if not TSM_API then
		return false, "TSM not loaded"
	end
	if type(TSM_API.IsUIVisible) ~= "function" then
		return false, "TSM_API.IsUIVisible missing"
	end
	if type(TSM_API.GetGroupPathByItem) ~= "function" then
		return false, "TSM_API.GetGroupPathByItem missing"
	end
	return true
end
TSMVFP.HasTSM = CheckTSM

local function OnMerchantShow()
	local n = GetMerchantNumItems() or 0
	local tsmOk = CheckTSM()
	local tsmVisible = tsmOk and TSM_API.IsUIVisible("VENDORING") or false
	Log("MERCHANT_SHOW — %d items, TSM=%s, TSM vendoring visible=%s",
		n, tostring(tsmOk), tostring(tsmVisible))
end

local function OnMerchantUpdate()
	local n = GetMerchantNumItems() or 0
	Log("MERCHANT_UPDATE — %d items", n)
end

local function OnMerchantClosed()
	Log("MERCHANT_CLOSED")
end

local function OnPlayerLogin()
	local ok, err = CheckTSM()
	if ok then
		Log("loaded — TSM integration active")
	else
		Log("loaded — %s; group filter disabled, all other filters available", err)
	end
end

TSMVFP:RegisterEvent("PLAYER_LOGIN")
TSMVFP:RegisterEvent("MERCHANT_SHOW")
TSMVFP:RegisterEvent("MERCHANT_UPDATE")
TSMVFP:RegisterEvent("MERCHANT_CLOSED")

TSMVFP:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		OnPlayerLogin()
	elseif event == "MERCHANT_SHOW" then
		OnMerchantShow()
	elseif event == "MERCHANT_UPDATE" then
		OnMerchantUpdate()
	elseif event == "MERCHANT_CLOSED" then
		OnMerchantClosed()
	end
end)

SLASH_TSMVFP1 = "/tvfp"
SlashCmdList["TSMVFP"] = function(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	if msg == "" or msg == "status" then
		local ok, err = CheckTSM()
		Log("status — TSM=%s%s", tostring(ok), ok and "" or (" ("..err..")"))
		if MerchantFrame and MerchantFrame:IsShown() then
			Log("  MerchantFrame shown, %d items", GetMerchantNumItems() or 0)
			if ok then
				Log("  TSM vendoring visible: %s", tostring(TSM_API.IsUIVisible("VENDORING")))
			end
		else
			Log("  no merchant open")
		end
	elseif msg == "groups" then
		local ok = CheckTSM()
		if not ok then
			Log("TSM not loaded — group filter unavailable")
			return
		end
		local groups = {}
		TSM_API.GetGroupPaths(groups)
		Log("groups (%d):", #groups)
		for i = 1, math.min(#groups, 10) do
			print("    " .. groups[i])
		end
		if #groups > 10 then
			print("    ... +" .. (#groups - 10) .. " more")
		end
	else
		Log("usage: /tvfp [status|groups]")
	end
end
