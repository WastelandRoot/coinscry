local _, NS = ...
NS.UI = NS.UI or {}
local Anchor = {}
NS.UI.Anchor = Anchor

-- TSM names its frames "TSM_FRAME:LargeApplicationFrame:<random>" and clears
-- the global, so we can't _G[] them. We iterate UIParent's children, match
-- on the name prefix, and disambiguate by position (the vendoring frame
-- covers MerchantFrame; Crafting/Mailing/etc. don't).
local TSM_FRAME_PATTERN = "^TSM_FRAME:LargeApplicationFrame:"

local POLL_INTERVAL = 0.25

local currentAnchor = nil
local pollTicker = nil
local listeners = {}

local function FrameCenterInside(inner, outer)
	if not (inner and outer) then return false end
	local cx, cy = inner:GetCenter()
	local l, r, t, b = outer:GetLeft(), outer:GetRight(), outer:GetTop(), outer:GetBottom()
	if not (cx and l and r and t and b) then return false end
	return cx >= l and cx <= r and cy >= b and cy <= t
end

local function FindTSMVendoringFrame()
	if not (NS.HasTSM and NS.HasTSM()) then return nil end
	if not (TSM_API and TSM_API.IsUIVisible) then return nil end
	if not TSM_API.IsUIVisible("VENDORING") then return nil end
	if not (MerchantFrame and MerchantFrame:IsShown()) then return nil end

	for _, child in ipairs({ UIParent:GetChildren() }) do
		local name = child.GetName and child:GetName() or nil
		if name and child.IsShown and child:IsShown() and name:find(TSM_FRAME_PATTERN) then
			if FrameCenterInside(child, MerchantFrame) then
				return child
			end
		end
	end
	return nil
end

---@return Frame|nil the frame our tab + panel should attach to
local function PickAnchor()
	if not (MerchantFrame and MerchantFrame:IsShown()) then return nil end
	return FindTSMVendoringFrame() or MerchantFrame
end

local function NotifyChanged()
	for _, cb in ipairs(listeners) do
		cb(currentAnchor)
	end
end

local function Reattach()
	local desired = PickAnchor()
	if desired == currentAnchor then return end
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

---@return string a one-line summary for /tvfp status / debug
function Anchor.GetSummary()
	if not currentAnchor then return "no anchor" end
	local name = currentAnchor.GetName and currentAnchor:GetName() or "<unnamed>"
	local isTSM = name and name:find(TSM_FRAME_PATTERN) and "TSM" or "Merchant"
	return ("%s (%s)"):format(isTSM, name or "?")
end
