local ADDON_NAME, NS = ...

local TSMVFP = CreateFrame("Frame", ADDON_NAME .. "_Frame")
_G.TSMVFP = TSMVFP
NS.Addon = TSMVFP

TSMVFPDB = TSMVFPDB or {}
TSMVFPCharDB = TSMVFPCharDB or {}

local PREFIX = "|cff66ccffTSM-VFP|r: "
local function Log(fmt, ...)
	print(PREFIX .. fmt:format(...))
end
NS.Log = Log

local function CheckTSM()
	if not TSM_API then return false, "TSM not loaded" end
	if type(TSM_API.IsUIVisible) ~= "function" then return false, "TSM_API.IsUIVisible missing" end
	if type(TSM_API.GetGroupPathByItem) ~= "function" then return false, "TSM_API.GetGroupPathByItem missing" end
	return true
end
TSMVFP.HasTSM = CheckTSM
NS.HasTSM = CheckTSM

local Scanner, Tab, Panel

local function OnMerchantShow()
	Scanner = Scanner or NS.Scanner
	Tab = Tab or NS.UI.Tab
	Panel = Panel or NS.UI.Panel

	Scanner.Rescan()

	-- M1 anchors to MerchantFrame only; M2 will pick TSM frame when visible.
	local anchor = MerchantFrame
	if anchor then
		Tab.AttachTo(anchor)
		Panel.AttachTo(Tab.Get())
	end
end

local function OnMerchantUpdate()
	if NS.Scanner then NS.Scanner.Rescan() end
	if NS.UI.Panel then NS.UI.Panel.Refresh() end
end

local function OnMerchantClosed()
	if NS.UI.Tab then NS.UI.Tab.Hide() end
	if NS.UI.Panel then NS.UI.Panel.Hide() end
end

local function OnPlayerLogin()
	local ok, err = CheckTSM()
	if ok then
		Log("loaded — TSM integration active")
	else
		Log("loaded — %s; group filter disabled, all other filters available", err)
	end
	if NS.UI.Tab then
		NS.UI.Tab.SetClickHandler(function() NS.UI.Panel.Toggle() end)
	end
	if NS.ItemCache then
		NS.ItemCache.OnResolved(function()
			if NS.UI.Panel then NS.UI.Panel.Refresh() end
		end)
	end
end

TSMVFP:RegisterEvent("PLAYER_LOGIN")
TSMVFP:RegisterEvent("MERCHANT_SHOW")
TSMVFP:RegisterEvent("MERCHANT_UPDATE")
TSMVFP:RegisterEvent("MERCHANT_CLOSED")

TSMVFP:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then OnPlayerLogin()
	elseif event == "MERCHANT_SHOW" then OnMerchantShow()
	elseif event == "MERCHANT_UPDATE" then OnMerchantUpdate()
	elseif event == "MERCHANT_CLOSED" then OnMerchantClosed()
	end
end)

SLASH_TSMVFP1 = "/tvfp"
SlashCmdList["TSMVFP"] = function(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	if msg == "" or msg == "toggle" then
		if NS.UI and NS.UI.Panel then NS.UI.Panel.Toggle() end
	elseif msg == "status" then
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
		for i = 1, math.min(#groups, 10) do print("    " .. groups[i]) end
		if #groups > 10 then print("    ... +" .. (#groups - 10) .. " more") end
	else
		Log("usage: /tvfp [toggle|status|groups]")
	end
end
