local _, NS = ...
NS.UI = NS.UI or {}
local Tab = {}
NS.UI.Tab = Tab

local TAB_SIZE = 40
local Y_OFFSET = -34
local LOGO_PATH = "Interface\\AddOns\\coinscry\\Media\\Logo64"

local tabButton
local clickHandler

local function CreateTab()
	local b = CreateFrame("Button", "Coinscry_Tab", UIParent, "BackdropTemplate")
	b:SetSize(TAB_SIZE, TAB_SIZE)
	b:SetFrameStrata("DIALOG") -- above TSM's vendor frame (HIGH)
	NS.UI.ApplyTheme("ApplyToTab", b)

	-- Logo icon as a child texture on top of the themed backdrop. Inset a few
	-- pixels so the backdrop's border still shows around the edges.
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetTexture(LOGO_PATH)
	b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", 3, -3)
	b.icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3, 3)

	b:SetScript("OnClick", function() if clickHandler then clickHandler() end end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Coinscry — vendor filters")
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
	tabButton:SetPoint("TOPLEFT", anchorFrame, "TOPRIGHT", -2, Y_OFFSET)
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
