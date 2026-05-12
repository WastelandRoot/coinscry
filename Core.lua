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

local Scanner, Tab, Panel, Anchor

local function ApplyAnchor(anchor)
	if not anchor then
		if Tab then Tab.Hide() end
		if Panel then Panel.Hide() end
		return
	end
	if Tab then Tab.AttachTo(anchor) end
	if Panel then Panel.AttachTo(anchor) end
end

local function OnMerchantShow()
	Scanner = Scanner or NS.Scanner
	Tab = Tab or NS.UI.Tab
	Panel = Panel or NS.UI.Panel
	Anchor = Anchor or NS.UI.Anchor

	Scanner.Rescan()
	local resetOnOpen = (NS.UI.Settings and NS.UI.Settings.ShouldResetOnOpen and NS.UI.Settings.ShouldResetOnOpen())
		or (NS.UI.Settings == nil) -- if Settings module isn't loaded yet, default to reset
	if resetOnOpen and Panel.ResetFilters then Panel.ResetFilters() end
	Anchor.StartPolling() -- triggers immediate attach via the registered listener
end

local function OnMerchantUpdate()
	if NS.Scanner then NS.Scanner.Rescan() end
	if NS.UI.Panel then NS.UI.Panel.Refresh() end
end

local function OnMerchantClosed()
	if NS.UI.Anchor then NS.UI.Anchor.StopPolling() end
end

local function GetVersion()
	if C_AddOns and C_AddOns.GetAddOnMetadata then
		return C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "?"
	elseif _G.GetAddOnMetadata then
		return _G.GetAddOnMetadata(ADDON_NAME, "Version") or "?"
	end
	return "?"
end

local function OnPlayerLogin()
	local ok, err = CheckTSM()
	local ver = GetVersion()
	if ok then
		Log("v%s loaded — TSM integration active", ver)
	else
		Log("v%s loaded — %s; group filter disabled, all other filters available", ver, err)
	end
	if NS.UI.Tab then
		NS.UI.Tab.SetClickHandler(function() NS.UI.Panel.Toggle() end)
	end
	if NS.UI.Anchor then
		NS.UI.Anchor.LoadOverride()
		NS.UI.Anchor.OnChange(ApplyAnchor)
	end
	if NS.ItemCache then
		NS.ItemCache.OnResolved(function()
			if NS.UI.Panel then NS.UI.Panel.Refresh() end
		end)
	end
	if NS.UI.Settings and NS.UI.Settings.ApplyOnLoad then
		NS.UI.Settings.ApplyOnLoad()
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
	elseif msg == "config" or msg == "settings" or msg == "options" then
		if NS.UI and NS.UI.Settings then NS.UI.Settings.Toggle() end
	elseif msg == "status" then
		local ok, err = CheckTSM()
		Log("status — TSM=%s%s", tostring(ok), ok and "" or (" ("..err..")"))
		if MerchantFrame and MerchantFrame:IsShown() then
			Log("  MerchantFrame shown, %d items", GetMerchantNumItems() or 0)
			if ok then
				Log("  TSM vendoring visible: %s", tostring(TSM_API.IsUIVisible("VENDORING")))
			end
			if NS.UI and NS.UI.Anchor then
				Log("  anchor: %s", NS.UI.Anchor.GetSummary())
				local ov = NS.UI.Anchor.GetOverride and NS.UI.Anchor.GetOverride()
				Log("  anchor mode: %s", ov and ("pinned to "..ov) or "auto")
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
	elseif msg == "debug" then
		if not (MerchantFrame and MerchantFrame:IsShown()) then
			Log("no merchant open")
			return
		end
		local Panel = NS.UI and NS.UI.Panel
		local s = Panel and Panel.GetState and Panel.GetState() or nil
		Log("debug — panel state: qualityMin=%s, groupPath=%s, nameSubstring=%s",
			tostring(s and s.qualityMin), tostring(s and s.groupPath), tostring(s and s.nameSubstring))
		if not s then Log("  panel never opened yet"); return end
		local rows = NS.Scanner.GetRows()
		Log("  scanner has %d rows; testing each row against state:", #rows)
		local matched = 0
		for i, row in ipairs(rows) do
			local quietQuality = (s.qualityMin == nil) or (row.quality and row.quality >= s.qualityMin)
			local quietGroup = (s.groupPath == nil) or (row.groupPath == s.groupPath)
			local pass = quietQuality and quietGroup
			if pass then matched = matched + 1 end
			-- only print interesting ones (matches + group-mismatches if a group filter is active)
			if pass or (s.groupPath ~= nil) then
				print(("    %d. %s — row.groupPath=%s (type=%s), state.groupPath=%s (type=%s), match=%s")
					:format(i, row.name or "?",
						tostring(row.groupPath), type(row.groupPath),
						tostring(s.groupPath), type(s.groupPath),
						tostring(pass)))
			end
			if i >= 20 then break end
		end
		Log("  matched=%d, filteredOut length=%d", matched, Panel.GetFilteredCount and Panel.GetFilteredCount() or -1)
	elseif msg == "dump" then
		if NS.UI and NS.UI.Anchor then
			print(NS.UI.Anchor.DumpFrames())
		end
	elseif msg == "poll" then
		if NS.UI and NS.UI.Anchor then
			print(NS.UI.Anchor.Probe())
		end
	elseif msg == "trace" or msg == "trace on" then
		if NS.UI and NS.UI.Anchor then
			NS.UI.Anchor.SetVerbose(true)
			Log("anchor tracing ON")
		end
	elseif msg == "trace off" then
		if NS.UI and NS.UI.Anchor then
			NS.UI.Anchor.SetVerbose(false)
			Log("anchor tracing OFF")
		end
	elseif msg == "theme" then
		local elvui = NS.UI and NS.UI.Themes and NS.UI.Themes.ElvUI or nil
		Log("theme — Default always on; ElvUI active=%s", tostring(elvui and elvui.IsActive and elvui.IsActive() or false))
		Log("  _G.ElvUI type=%s; _G.ElvUI[1] type=%s; _G.ElvUI[1].Skins=%s",
			type(_G.ElvUI),
			type(_G.ElvUI) == "table" and type(_G.ElvUI[1]) or "n/a",
			(type(_G.ElvUI) == "table" and type(_G.ElvUI[1]) == "table") and tostring(_G.ElvUI[1].Skins ~= nil) or "n/a")
	elseif msg == "reset" then
		if NS.UI and NS.UI.Panel and NS.UI.Panel.ResetFilters then
			NS.UI.Panel.ResetFilters()
			Log("filters reset")
		end
	elseif msg:find("^anchor%s+") then
		local sub = msg:match("^anchor%s+(%S+)")
		if sub == "merchant" or sub == "tsm" then
			if NS.UI and NS.UI.Anchor then
				NS.UI.Anchor.SetOverride(sub)
				Log("anchor pinned to %s (persists across reloads; /tvfp anchor auto to clear)", sub)
			end
		elseif sub == "auto" then
			if NS.UI and NS.UI.Anchor then
				NS.UI.Anchor.SetOverride(nil)
				Log("anchor auto-detect re-enabled")
			end
		else
			Log("usage: /tvfp anchor [merchant|tsm|auto]")
		end
	elseif msg == "scan" then
		if not (MerchantFrame and MerchantFrame:IsShown()) then
			Log("no merchant open")
			return
		end
		if NS.Scanner then NS.Scanner.Rescan() end
		local rows = NS.Scanner and NS.Scanner.GetRows() or {}
		Log("scan — %d rows:", #rows)
		local tsm = CheckTSM()
		for i, row in ipairs(rows) do
			local groupRepr
			if not tsm then
				groupRepr = "(no TSM)"
			elseif row.groupPath then
				groupRepr = "group=|cff00ff00" .. row.groupPath .. "|r"
			elseif row.itemString then
				groupRepr = "group=nil (itemString=" .. row.itemString .. ")"
			else
				groupRepr = "group=nil (itemString=nil; link=" .. tostring(row.link) .. ")"
			end
			print(("  %d. %s — %s"):format(i, row.name or "?", groupRepr))
			if i >= 20 then
				print(("  ... +%d more"):format(#rows - 20))
				break
			end
		end
	else
		Log("usage: /tvfp [toggle|config|status|reset|anchor <merchant|tsm|auto>|trace [on|off]|groups|scan|dump|poll|debug|theme]")
	end
end
