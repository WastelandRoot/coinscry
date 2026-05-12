local _, NS = ...
NS.UI = NS.UI or {}
NS.UI.Themes = NS.UI.Themes or {}
local Theme = {}
NS.UI.Themes.Default = Theme

Theme.name = "default"
Theme.rowHeight = 22

Theme.colors = {
	bg          = { r = 0.05, g = 0.05, b = 0.05, a = 0.92 },
	border      = { r = 0.50, g = 0.50, b = 0.50, a = 1.00 },
	bgPanel     = { r = 0.08, g = 0.08, b = 0.10, a = 1.00 },
	rowAlt      = { r = 1.00, g = 1.00, b = 1.00, a = 0.04 },
	rowHover    = { r = 1.00, g = 1.00, b = 1.00, a = 0.10 },
	text        = { r = 1.00, g = 1.00, b = 1.00 },
	textHeader  = { r = 1.00, g = 0.82, b = 0.00 },
	textDim     = { r = 0.65, g = 0.65, b = 0.65 },
}

local BACKDROP_FRAME = {
	bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	edgeSize = 16,
	insets   = { left = 4, right = 4, top = 4, bottom = 4 },
}

local function ApplyBackdrop(frame, backdrop, bgColor, borderColor)
	if not frame.SetBackdrop then
		Mixin(frame, BackdropTemplateMixin)
		frame:HookScript("OnSizeChanged", frame.OnBackdropSizeChanged)
	end
	frame:SetBackdrop(backdrop)
	frame:SetBackdropColor(bgColor.r, bgColor.g, bgColor.b, bgColor.a or 1)
	frame:SetBackdropBorderColor(borderColor.r, borderColor.g, borderColor.b, borderColor.a or 1)
end

function Theme.ApplyToPanel(frame)
	ApplyBackdrop(frame, BACKDROP_FRAME, Theme.colors.bgPanel, Theme.colors.border)
end

local BACKDROP_TAB = {
	bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	edgeSize = 12,
	insets   = { left = 3, right = 3, top = 3, bottom = 3 },
}

function Theme.ApplyToTab(button)
	-- CreateFrame("Button", ..., "BackdropTemplate") gives us SetBackdrop.
	button:SetBackdrop(BACKDROP_TAB)
	button:SetBackdropColor(Theme.colors.bgPanel.r, Theme.colors.bgPanel.g, Theme.colors.bgPanel.b, 1)
	button:SetBackdropBorderColor(Theme.colors.border.r, Theme.colors.border.g, Theme.colors.border.b, 1)
	button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	if button:GetHighlightTexture() then button:GetHighlightTexture():SetBlendMode("ADD") end
end

function Theme.ApplyToButton(button)
	button:SetNormalFontObject("GameFontNormalSmall")
	button:SetHighlightFontObject("GameFontHighlightSmall")
	button:SetDisabledFontObject("GameFontDisableSmall")
	if button.SetNormalTexture and not button:GetNormalTexture() then
		button:SetNormalTexture("Interface\\Buttons\\UI-Panel-Button-Up")
		button:SetPushedTexture("Interface\\Buttons\\UI-Panel-Button-Down")
		button:SetHighlightTexture("Interface\\Buttons\\UI-Panel-Button-Highlight", "ADD")
	end
end

-- Default-theme no-op stubs so the shared theme interface is symmetric.
-- ElvUI overrides these.
function Theme.ApplyToCloseButton(_) end
function Theme.ApplyToEditBox(_) end
function Theme.ApplyToDropDown(_) end
function Theme.ApplyToScrollBar(_) end

function Theme.QualityColor(quality)
	local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality or 1]
	if c then return c.r, c.g, c.b end
	return 1, 1, 1
end
