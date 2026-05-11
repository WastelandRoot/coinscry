local _, NS = ...
NS.UI = NS.UI or {}
local Panel = {}
NS.UI.Panel = Panel

local Theme = NS.UI.Themes.Default
local Filters = NS.Filters
local Scanner = NS.Scanner

local PANEL_W = 440
local ROW_H = Theme.rowHeight
local NUM_VISIBLE_ROWS = 14
local TOP_RESERVED = 100  -- title + quality dropdown + group dropdown + padding
local BOT_RESERVED = 30   -- hint line + padding
local PANEL_H = TOP_RESERVED + NUM_VISIBLE_ROWS * ROW_H + BOT_RESERVED

local state = nil
local filteredOut = {}

local panelFrame, qualityDropdown, groupDropdown, scrollFrame
local rowWidgets = {}

local QUALITY_CHOICES = {
	{ label = "Any quality",   value = nil },
	{ label = "Common+",       value = 1 },
	{ label = "Uncommon+",     value = 2 },
	{ label = "Rare+",         value = 3 },
	{ label = "Epic+",         value = 4 },
	{ label = "Legendary",     value = 5 },
}

local function FormatPrice(copper)
	if not copper or copper == 0 then return "" end
	local g = math.floor(copper / 10000)
	local s = math.floor((copper % 10000) / 100)
	local c = copper % 100
	if g > 0 then return ("%dg %ds %dc"):format(g, s, c) end
	if s > 0 then return ("%ds %dc"):format(s, c) end
	return ("%dc"):format(c)
end

local function BuyRow(row, qty)
	if not row or not row.index then return end
	qty = qty or 1
	BuyMerchantItem(row.index, qty)
	local label = (row.link or row.name or "?")
	print(("|cff66ccffTSM-VFP|r: bought %dx %s"):format(qty, label))
end

local function CreateRow(parent, i, anchorTo)
	local r = CreateFrame("Button", nil, parent)
	r:SetSize(PANEL_W - 40, ROW_H)
	if i == 1 then
		r:SetPoint("TOPLEFT", anchorTo, "TOPLEFT", 0, 0)
	else
		r:SetPoint("TOPLEFT", rowWidgets[i - 1], "BOTTOMLEFT", 0, 0)
	end

	r.bg = r:CreateTexture(nil, "BACKGROUND")
	r.bg:SetAllPoints()
	r.bg:SetColorTexture(1, 1, 1, 0)

	r.icon = r:CreateTexture(nil, "ARTWORK")
	r.icon:SetSize(ROW_H - 4, ROW_H - 4)
	r.icon:SetPoint("LEFT", r, "LEFT", 2, 0)

	r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
	r.name:SetPoint("RIGHT", r, "RIGHT", -110, 0) -- reserve ~110px for price column
	r.name:SetJustifyH("LEFT")
	r.name:SetWordWrap(false) -- auto-truncates with ellipsis when too long

	r.price = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	r.price:SetPoint("RIGHT", r, "RIGHT", -4, 0)
	r.price:SetJustifyH("RIGHT")
	r.price:SetTextColor(1, 0.82, 0)

	r:SetScript("OnEnter", function(self)
		self.bg:SetColorTexture(1, 1, 1, 0.10)
		if self.dataRow and self.dataRow.link then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetHyperlink(self.dataRow.link)
			GameTooltip:Show()
		end
	end)
	r:SetScript("OnLeave", function(self)
		self.bg:SetColorTexture(1, 1, 1, (self.alt and 0.04 or 0))
		GameTooltip:Hide()
	end)
	r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	r:SetScript("OnClick", function(self, btn)
		if not self.dataRow then return end
		if IsShiftKeyDown() then
			BuyRow(self.dataRow, self.dataRow.stackCount or 1)
		else
			BuyRow(self.dataRow, 1)
		end
	end)
	return r
end

local function UpdateRows()
	if not panelFrame or not panelFrame:IsShown() then return end
	local offset = FauxScrollFrame_GetOffset(scrollFrame) or 0
	for i = 1, NUM_VISIBLE_ROWS do
		local w = rowWidgets[i]
		local dataIdx = offset + i
		local data = filteredOut[dataIdx]
		if data then
			w.dataRow = data
			w.alt = (dataIdx % 2 == 0)
			w.bg:SetColorTexture(1, 1, 1, w.alt and 0.04 or 0)
			w.icon:SetTexture(data.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
			local r, g, b = Theme.QualityColor(data.quality)
			w.name:SetTextColor(r, g, b)
			w.name:SetText(data.name or "...")
			local priceText = FormatPrice(data.price)
			if data.hasExtendedCost then
				priceText = (priceText == "" and "+ items" or (priceText .. " + items"))
			end
			w.price:SetText(priceText)
			w:Show()
		else
			w.dataRow = nil
			w:Hide()
		end
	end
	FauxScrollFrame_Update(scrollFrame, #filteredOut, NUM_VISIBLE_ROWS, ROW_H)
end

local function Refresh()
	if not state then return end
	Filters.Apply(Scanner.GetRows(), state, filteredOut)
	UpdateRows()
end
Panel.Refresh = Refresh

local function InitQualityDropdown()
	UIDropDownMenu_Initialize(qualityDropdown, function()
		for _, choice in ipairs(QUALITY_CHOICES) do
			local info = UIDropDownMenu_CreateInfo()
			info.text = choice.label
			info.value = choice.value
			info.checked = (state.qualityMin == choice.value)
			info.func = function()
				state.qualityMin = choice.value
				UIDropDownMenu_SetText(qualityDropdown, choice.label)
				Refresh()
			end
			UIDropDownMenu_AddButton(info)
		end
	end)
	UIDropDownMenu_SetWidth(qualityDropdown, 130)
	UIDropDownMenu_SetText(qualityDropdown, QUALITY_CHOICES[1].label)
end

local function InitGroupDropdown()
	local hasTSM = NS.HasTSM and NS.HasTSM() or false
	if not hasTSM then
		groupDropdown:Hide()
		return
	end
	UIDropDownMenu_Initialize(groupDropdown, function()
		local info = UIDropDownMenu_CreateInfo()
		info.text = "Any group"
		info.value = nil
		info.checked = (state.groupPath == nil)
		info.func = function()
			state.groupPath = nil
			UIDropDownMenu_SetText(groupDropdown, "Any group")
			Refresh()
		end
		UIDropDownMenu_AddButton(info)

		local groups = {}
		if TSM_API and TSM_API.GetGroupPaths then
			pcall(TSM_API.GetGroupPaths, groups)
			table.sort(groups)
		end
		for _, path in ipairs(groups) do
			local entry = UIDropDownMenu_CreateInfo()
			entry.text = path
			entry.value = path
			entry.checked = (state.groupPath == path)
			entry.func = function()
				state.groupPath = path
				UIDropDownMenu_SetText(groupDropdown, path)
				Refresh()
			end
			UIDropDownMenu_AddButton(entry)
		end
	end)
	UIDropDownMenu_SetWidth(groupDropdown, 200)
	UIDropDownMenu_SetText(groupDropdown, "Any group")
end

local function CreatePanel()
	state = state or Filters.NewState()

	local f = CreateFrame("Frame", "TSMVFP_Panel", UIParent, "BackdropTemplate")
	f:SetSize(PANEL_W, PANEL_H)
	f:SetFrameStrata("HIGH")
	Theme.ApplyToPanel(f)
	f:EnableMouse(true)

	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
	title:SetText("TSM-VFP")
	title:SetTextColor(1, 0.82, 0)

	qualityDropdown = CreateFrame("Frame", "TSMVFP_QualityDropdown", f, "UIDropDownMenuTemplate")
	qualityDropdown:SetPoint("TOPLEFT", title, "BOTTOMLEFT", -16, -8)

	groupDropdown = CreateFrame("Frame", "TSMVFP_GroupDropdown", f, "UIDropDownMenuTemplate")
	groupDropdown:SetPoint("TOPLEFT", qualityDropdown, "BOTTOMLEFT", 0, -2)

	scrollFrame = CreateFrame("ScrollFrame", "TSMVFP_ScrollFrame", f, "FauxScrollFrameTemplate")
	scrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -TOP_RESERVED)
	scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -28, BOT_RESERVED - 6)
	scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
		FauxScrollFrame_OnVerticalScroll(self, offset, ROW_H, UpdateRows)
	end)

	-- Rows live on the panel itself (NOT inside the ScrollFrame); FauxScrollFrame
	-- is a scrollbar-only widget and does not render descendants. We position rows
	-- over the same viewport area as the ScrollFrame and update them on scroll.
	rowWidgets = {}
	for i = 1, NUM_VISIBLE_ROWS do
		rowWidgets[i] = CreateRow(f, i, scrollFrame)
	end

	local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, -8)
	hint:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, -8)
	hint:SetJustifyH("LEFT")
	hint:SetText("click: buy 1 — shift-click: buy stack")

	InitQualityDropdown()
	InitGroupDropdown()
	f:Hide()
	return f
end

---@param anchorTab Frame the side tab; panel slides out to its right
function Panel.AttachTo(anchorTab)
	if not panelFrame then panelFrame = CreatePanel() end
	panelFrame:ClearAllPoints()
	panelFrame:SetParent(anchorTab)
	panelFrame:SetPoint("TOPLEFT", anchorTab, "TOPRIGHT", 4, 0)
end

function Panel.Show()
	if not panelFrame then return end
	panelFrame:Show()
	Refresh()
end

function Panel.Hide()
	if panelFrame then panelFrame:Hide() end
end

function Panel.Toggle()
	if not panelFrame then return end
	if panelFrame:IsShown() then Panel.Hide() else Panel.Show() end
end

function Panel.IsShown()
	return panelFrame and panelFrame:IsShown()
end

function Panel.GetState() return state end
function Panel.GetFilteredCount() return #filteredOut end
