local ADDON_NAME, NS = ...
NS.UI = NS.UI or {}
local Settings = {}
NS.UI.Settings = Settings

-- Global settings (TSMVFPDB) with defaults applied on first read.
local DEFAULTS = {
	resetOnOpen = true,
	verbose     = false,
}

local function GetSetting(key)
	TSMVFPDB = TSMVFPDB or {}
	if TSMVFPDB[key] == nil then TSMVFPDB[key] = DEFAULTS[key] end
	return TSMVFPDB[key]
end

local function SetSetting(key, value)
	TSMVFPDB = TSMVFPDB or {}
	TSMVFPDB[key] = value
end

Settings.Get = GetSetting
Settings.Set = SetSetting

local frame
local widgets = {}

local ANCHOR_CHOICES = {
	{ label = "Auto-detect",   value = nil },
	{ label = "Merchant frame", value = "merchant" },
	{ label = "TSM vendor frame", value = "tsm" },
}

local function AnchorLabelFor(value)
	for _, c in ipairs(ANCHOR_CHOICES) do
		if c.value == value then return c.label end
	end
	return ANCHOR_CHOICES[1].label
end

local function MakeCheckbox(parent, label, x, y, getter, setter)
	local c = CreateFrame("CheckButton", nil, parent, "ChatConfigCheckButtonTemplate")
	c:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	local text = _G[c:GetName() and (c:GetName() .. "Text")] or c.Text
	if text then
		text:SetText(label)
		text:SetPoint("LEFT", c, "RIGHT", 2, 1)
	else
		c.label = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		c.label:SetPoint("LEFT", c, "RIGHT", 4, 0)
		c.label:SetText(label)
	end
	c:SetChecked(getter() and true or false)
	c:SetScript("OnClick", function(self)
		setter(self:GetChecked() and true or false)
	end)
	return c
end

local function MakeDropdown(parent, name, labelText, x, y, width, choices, getter, setter)
	local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	label:SetText(labelText)

	local d = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")
	d:SetPoint("TOPLEFT", label, "BOTTOMLEFT", -14, -4)
	UIDropDownMenu_SetWidth(d, width or 160)
	NS.UI.ApplyTheme("ApplyToDropDown", d, width or 160)

	local function LabelFor(v)
		for _, c in ipairs(choices) do
			if c.value == v then return c.label end
		end
		return choices[1].label
	end

	UIDropDownMenu_Initialize(d, function()
		for _, c in ipairs(choices) do
			local info = UIDropDownMenu_CreateInfo()
			info.text = c.label
			info.value = c.value
			info.checked = (getter() == c.value)
			info.func = function()
				setter(c.value)
				UIDropDownMenu_SetText(d, c.label)
			end
			UIDropDownMenu_AddButton(info)
		end
	end)
	UIDropDownMenu_SetText(d, LabelFor(getter()))
	return d
end

local function CreateFrame_()
	local f = CreateFrame("Frame", "TSMVFP_SettingsFrame", UIParent, "BackdropTemplate")
	f:SetSize(420, 360)
	f:SetFrameStrata("DIALOG")
	f:SetPoint("CENTER")
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	NS.UI.ApplyTheme("ApplyToPanel", f)

	-- Title
	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -12)
	title:SetText("TSM-VFP — Settings")
	title:SetTextColor(1, 0.82, 0)

	local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
	closeBtn:SetScript("OnClick", function() f:Hide() end)
	NS.UI.ApplyTheme("ApplyToCloseButton", closeBtn)

	-- About section
	local aboutHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	aboutHeader:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -44)
	aboutHeader:SetText("About")
	aboutHeader:SetTextColor(1, 0.82, 0)

	local version = "?"
	if C_AddOns and C_AddOns.GetAddOnMetadata then
		version = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "?"
	elseif _G.GetAddOnMetadata then
		version = _G.GetAddOnMetadata(ADDON_NAME, "Version") or "?"
	end
	local versionText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	versionText:SetPoint("TOPLEFT", aboutHeader, "BOTTOMLEFT", 4, -4)
	versionText:SetText(("Version %s — vendor filters for TBC Anniversary"):format(version))

	-- Behavior section
	local behaviorHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	behaviorHeader:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -94)
	behaviorHeader:SetText("Behavior")
	behaviorHeader:SetTextColor(1, 0.82, 0)

	widgets.resetOnOpen = MakeCheckbox(
		f, "Reset filters when opening a vendor", 16, -114,
		function() return GetSetting("resetOnOpen") end,
		function(v) SetSetting("resetOnOpen", v) end
	)

	-- Anchor section
	local anchorHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	anchorHeader:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -156)
	anchorHeader:SetText("Anchor")
	anchorHeader:SetTextColor(1, 0.82, 0)

	widgets.anchorMode = MakeDropdown(
		f, "TSMVFP_SettingsAnchorMode", "Which vendor frame to attach to:",
		16, -176, 200, ANCHOR_CHOICES,
		function()
			return (NS.UI.Anchor and NS.UI.Anchor.GetOverride and NS.UI.Anchor.GetOverride()) or nil
		end,
		function(v)
			if NS.UI.Anchor and NS.UI.Anchor.SetOverride then
				NS.UI.Anchor.SetOverride(v)
			end
		end
	)

	-- Diagnostics section
	local diagHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	diagHeader:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -252)
	diagHeader:SetText("Diagnostics")
	diagHeader:SetTextColor(1, 0.82, 0)

	widgets.verbose = MakeCheckbox(
		f, "Anchor tracing (logs to chat when anchor switches)", 16, -272,
		function() return GetSetting("verbose") end,
		function(v)
			SetSetting("verbose", v)
			if NS.UI.Anchor and NS.UI.Anchor.SetVerbose then NS.UI.Anchor.SetVerbose(v) end
		end
	)

	local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 12)
	hint:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 12)
	hint:SetJustifyH("LEFT")
	hint:SetText("Settings apply immediately. /tvfp config to reopen.")

	f:Hide()
	return f
end

function Settings.Show()
	if not frame then frame = CreateFrame_() end
	-- Re-sync widget state in case CLI commands changed it since last show.
	if widgets.resetOnOpen then widgets.resetOnOpen:SetChecked(GetSetting("resetOnOpen")) end
	if widgets.verbose then widgets.verbose:SetChecked(GetSetting("verbose")) end
	if widgets.anchorMode then
		UIDropDownMenu_SetText(widgets.anchorMode, AnchorLabelFor(
			NS.UI.Anchor and NS.UI.Anchor.GetOverride and NS.UI.Anchor.GetOverride() or nil
		))
	end
	frame:Show()
end

function Settings.Hide()
	if frame then frame:Hide() end
end

function Settings.Toggle()
	if not frame then Settings.Show(); return end
	if frame:IsShown() then Settings.Hide() else Settings.Show() end
end

---Apply settings to runtime state. Call once after PLAYER_LOGIN so saved
---verbose/anchor preferences re-establish on reload.
function Settings.ApplyOnLoad()
	if NS.UI.Anchor and NS.UI.Anchor.SetVerbose then
		NS.UI.Anchor.SetVerbose(GetSetting("verbose"))
	end
end

---@return boolean whether filters should reset on each MERCHANT_SHOW
function Settings.ShouldResetOnOpen()
	return GetSetting("resetOnOpen") and true or false
end
