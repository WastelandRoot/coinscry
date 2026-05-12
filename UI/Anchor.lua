local _, NS = ...
NS.UI = NS.UI or {}
local Anchor = {}
NS.UI.Anchor = Anchor

-- TSM names its frames "TSM_FRAME:LargeApplicationFrame:<random>" and clears
-- the global, so we can't _G[] them. We iterate UIParent's children and match
-- on the name prefix. Note: TSM positions its vendoring frame *next to*
-- MerchantFrame (not over it), so position-based disambiguation doesn't help.
-- TSM_API.IsUIVisible("VENDORING") is the authoritative signal that the
-- vendoring frame is open.
local TSM_FRAME_PATTERN = "^TSM_FRAME:LargeApplicationFrame:"

local POLL_INTERVAL = 0.25

local currentAnchor = nil
local pollTicker = nil
local listeners = {}
local verbose = false
local tickCount = 0
local override = nil -- "merchant" | "tsm" | nil (auto)

local function ReportError(err)
	if not verbose then return end
	local h = geterrorhandler()
	if h then h(err) end
end

-- Some UIParent children (e.g. CommunitiesAddDialog on Retail/Anniversary)
-- expose a GetName method via their metatable but the underlying C call
-- errors with "bad self" when invoked. Always use pcall to probe frames
-- we don't control.
-- Swallow errors silently here; we routinely iterate UIParent children that
-- expose GetName/IsShown via __index but reject the underlying C call. Those
-- are expected and frequent — surfacing them to the error handler floods it.
-- Use ReportError() in code paths where a pcall failure is genuinely unexpected.
local function SafeGetName(frame)
	if not frame or not frame.GetName then return nil end
	local ok, name = pcall(frame.GetName, frame)
	if not ok then return nil end
	if type(name) == "string" then return name end
	return nil
end

local function SafeIsShown(frame)
	if not frame or not frame.IsShown then return false end
	local ok, shown = pcall(frame.IsShown, frame)
	if not ok then return false end
	return shown == true
end

---Returns an iterator over visible UIParent children whose name matches the
---TSM LargeApplicationFrame pattern. Use for both detection and debug dumps.
local function IterateTSMFrames()
	local children = { UIParent:GetChildren() }
	local i = 0
	return function()
		while true do
			i = i + 1
			local child = children[i]
			if not child then return nil end
			local name = SafeGetName(child)
			if name and SafeIsShown(child) and name:find(TSM_FRAME_PATTERN) then
				return child, name
			end
		end
	end
end

local function FindTSMVendoringFrame()
	if not (NS.HasTSM and NS.HasTSM()) then return nil end
	if not (TSM_API and TSM_API.IsUIVisible) then return nil end
	if not TSM_API.IsUIVisible("VENDORING") then return nil end

	-- If other TSM application UIs are also visible (Crafting, Mailing, Auction),
	-- their frames share the same name pattern. We can't disambiguate from the
	-- outside, but the user almost never has those open at a vendor, so the
	-- first match wins. If this becomes a real problem, a /tvfp anchor cycle
	-- command can let the user pick.
	for child in IterateTSMFrames() do
		return child
	end
	return nil
end

---@return Frame|nil the frame our tab + panel should attach to
local function PickAnchor()
	if not (MerchantFrame and MerchantFrame:IsShown()) then return nil end
	if override == "merchant" then return MerchantFrame end
	if override == "tsm" then return FindTSMVendoringFrame() end -- strict; nil if not found
	return FindTSMVendoringFrame() or MerchantFrame
end

---@return string detailed snapshot of detection at this moment (for /tvfp poll)
function Anchor.Probe()
	local lines = { "anchor probe:" }
	local tsmOk = NS.HasTSM and NS.HasTSM()
	lines[#lines + 1] = "  HasTSM: " .. tostring(tsmOk)
	if tsmOk and TSM_API and TSM_API.IsUIVisible then
		lines[#lines + 1] = "  TSM_API.IsUIVisible(VENDORING): " .. tostring(TSM_API.IsUIVisible("VENDORING"))
	end
	lines[#lines + 1] = "  MerchantFrame:IsShown(): " .. tostring(MerchantFrame and MerchantFrame:IsShown())
	local tsmFrame = FindTSMVendoringFrame()
	lines[#lines + 1] = "  FindTSMVendoringFrame -> " .. (tsmFrame and (SafeGetName(tsmFrame) or "?") or "nil")
	local picked = PickAnchor()
	lines[#lines + 1] = "  PickAnchor -> " .. (picked and (SafeGetName(picked) or "?") or "nil")
	lines[#lines + 1] = "  pollTicker active: " .. tostring(pollTicker ~= nil)
	lines[#lines + 1] = "  Reattach call count: " .. tickCount
	lines[#lines + 1] = "  current anchor: " .. (currentAnchor and (SafeGetName(currentAnchor) or "?") or "nil")
	return table.concat(lines, "\n")
end

---@return string a multi-line dump of TSM application frames (for /tvfp dump)
function Anchor.DumpFrames()
	local ok, result = pcall(function()
		local lines = { "TSM application frames (visible, name matches TSM_FRAME:LargeApplicationFrame:):" }
		local count = 0
		for child, name in IterateTSMFrames() do
			count = count + 1
			local w = child:GetWidth() or 0
			local h = child:GetHeight() or 0
			local l = child:GetLeft() or -1
			local t = child:GetTop() or -1
			-- %.0f rather than %d so non-integer floats from GetWidth/etc don't trip strict integer conversion
			lines[#lines + 1] = ("  %d. %s  size=%.0fx%.0f  topleft=(%.0f, %.0f)"):format(count, name, w, h, l, t)
		end
		if count == 0 then lines[#lines + 1] = "  (none)" end
		return table.concat(lines, "\n")
	end)
	if not ok then return "DumpFrames errored: " .. tostring(result) end
	return result
end

local function NotifyChanged()
	for _, cb in ipairs(listeners) do
		cb(currentAnchor)
	end
end

function Anchor.SetVerbose(v) verbose = v and true or false end
function Anchor.GetTickCount() return tickCount end

local function DescribeFrame(f)
	if not f then return "nil" end
	local name = SafeGetName(f) or "<unnamed>"
	local visible = SafeIsShown(f) and "shown" or "hidden"
	local cx, cy = nil, nil
	if f.GetCenter then
		local ok, x, y = pcall(f.GetCenter, f)
		if ok then cx, cy = x, y end
	end
	return ("%s [%s, center=(%s,%s)]"):format(name, visible, tostring(cx and math.floor(cx)), tostring(cy and math.floor(cy)))
end

local function Reattach()
	tickCount = tickCount + 1
	local desired = PickAnchor()
	if desired == currentAnchor then return end
	if verbose then
		print(("|cff66ccffTSM-VFP|r anchor: %s -> %s"):format(DescribeFrame(currentAnchor), DescribeFrame(desired)))
	end
	currentAnchor = desired
	NotifyChanged()
end

---Register a callback invoked when the active anchor changes.
---@param cb fun(anchor: Frame|nil)
function Anchor.OnChange(cb)
	table.insert(listeners, cb)
end

---@return Frame|nil
function Anchor.GetCurrent() return currentAnchor end

---Start polling for anchor changes. Idempotent.
function Anchor.StartPolling()
	if pollTicker then return end
	Reattach() -- immediate attach so we don't wait a tick on merchant open
	pollTicker = C_Timer.NewTicker(POLL_INTERVAL, Reattach)
end

---Stop polling and clear the anchor (caller is responsible for hiding UI).
function Anchor.StopPolling()
	if pollTicker then pollTicker:Cancel(); pollTicker = nil end
	if currentAnchor ~= nil then
		currentAnchor = nil
		NotifyChanged()
	end
end

---Override the auto-detected anchor. Pass nil to return to auto.
---@param o "merchant"|"tsm"|nil
function Anchor.SetOverride(o)
	override = (o == "merchant" or o == "tsm") and o or nil
	if TSMVFPCharDB then TSMVFPCharDB.anchorOverride = override end
	Reattach() -- apply immediately
end

---@return string|nil
function Anchor.GetOverride() return override end

---Load persisted override from SavedVariables. Call once after VARIABLES_LOADED.
function Anchor.LoadOverride()
	if TSMVFPCharDB and TSMVFPCharDB.anchorOverride then
		override = TSMVFPCharDB.anchorOverride
	end
end

---@return string a one-line summary for /tvfp status / debug
function Anchor.GetSummary()
	if not currentAnchor then return "no anchor" end
	local name = SafeGetName(currentAnchor) or "<unnamed>"
	local isTSM = name:find(TSM_FRAME_PATTERN) and "TSM" or "Merchant"
	return ("%s (%s)"):format(isTSM, name)
end
