local _, NS = ...
NS.UI = NS.UI or {}
local Tab = {}
NS.UI.Tab = Tab

local Theme = NS.UI.Themes.Default

local TAB_W, TAB_H = 28, 64
local Y_OFFSET = -32

local tabButton
local clickHandler

local function CreateTab()
	local b = CreateFrame("Button", "TSMVFP_Tab", UIParent)
	b:SetSize(TAB_W, TAB_H)
	b:SetFrameStrata("HIGH")
	Theme.ApplyToTab(b)

	b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	b.label:SetPoint("CENTER", b, "CENTER", 0, 0)
	b.label:SetText("F")
	b.label:SetTextColor(1, 0.82, 0)

	b:SetScript("OnClick", function() if clickHandler then clickHandler() end end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("TSM-VFP — vendor filters")
		GameTooltip:AddLine("Click to toggle filter panel", 1, 1, 1)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)

	b:Hide()
	return b
end

---@param anchorFrame Frame the parent vendor frame
function Tab.AttachTo(anchorFrame)
	if not tabButton then tabButton = CreateTab() end
	tabButton:ClearAllPoints()
	tabButton:SetParent(anchorFrame)
	tabButton:SetPoint("TOPRIGHT", anchorFrame, "TOPLEFT", 2, Y_OFFSET)
	tabButton:Show()
end

function Tab.Hide()
	if tabButton then tabButton:Hide() end
end

function Tab.SetClickHandler(fn)
	clickHandler = fn
end

function Tab.Get()
	return tabButton
end
