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
local TOP_RESERVED = 156  -- title + search + 3 dropdown rows + ilvl/reqlvl row + padding
local BOT_RESERVED = 30
local PANEL_H = TOP_RESERVED + NUM_VISIBLE_ROWS * ROW_H + BOT_RESERVED

local state = nil
local filteredOut = {}

local panelFrame
local searchBox, qualityDropdown, classDropdown, subclassDropdown, groupDropdown
local ilvlMinBox, ilvlMaxBox, reqLevelMaxBox
local scrollFrame
local rowWidgets = {}

local QUALITY_CHOICES = {
	{ label = "Any quality",   value = nil },
	{ label = "Common+",       value = 1 },
	{ label = "Uncommon+",     value = 2 },
	{ label = "Rare+",         value = 3 },
	{ label = "Epic+",         value = 4 },
	{ label = "Legendary",     value = 5 },
}

local function QualityLabelFor(value)
	for _, c in ipairs(QUALITY_CHOICES) do
		if c.value == value then return c.label end
	end
	return QUALITY_CHOICES[1].label
end

local function FormatPrice(copper)
	if not copper or copper == 0 then return "" end
	local g = math.floor(copper / 10000)
	local s = math.floor((copper % 10000) / 100)
	local c = copper % 100
	if g > 0 then return ("%dg %ds %dc"):format(g, s, c) end
	if s > 0 then return ("%ds %dc"):format(s, c) end
	return ("%dc"):format(c)
end

local function SaveState()
	if TSMVFPCharDB then
		TSMVFPCharDB.filterState = state
	end
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
	r.name:SetPoint("RIGHT", r, "RIGHT", -110, 0)
	r.name:SetJustifyH("LEFT")
	r.name:SetWordWrap(false)

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
	r:SetScript("OnClick", function(self)
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
			local cr, cg, cb = Theme.QualityColor(data.quality)
			w.name:SetTextColor(cr, cg, cb)
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

-- ============================================================================
-- Dropdown initializers
-- ============================================================================

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
				SaveState(); Refresh()
			end
			UIDropDownMenu_AddButton(info)
		end
	end)
	UIDropDownMenu_SetWidth(qualityDropdown, 130)
	UIDropDownMenu_SetText(qualityDropdown, QualityLabelFor(state.qualityMin))
end

local function InitGroupDropdown()
	local hasTSM = NS.HasTSM and NS.HasTSM() or false
	if not hasTSM then groupDropdown:Hide(); return end
	UIDropDownMenu_Initialize(groupDropdown, function()
		local info = UIDropDownMenu_CreateInfo()
		info.text = "Any group"
		info.value = nil
		info.checked = (state.groupPath == nil)
		info.func = function()
			state.groupPath = nil
			UIDropDownMenu_SetText(groupDropdown, "Any group")
			SaveState(); Refresh()
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
				SaveState(); Refresh()
			end
			UIDropDownMenu_AddButton(entry)
		end
	end)
	UIDropDownMenu_SetWidth(groupDropdown, 160)
	UIDropDownMenu_SetText(groupDropdown, state.groupPath or "Any group")
end

local function ClassLabel(classID)
	if not classID then return "All types" end
	local name = GetItemClassInfo and GetItemClassInfo(classID) or nil
	return name or ("type " .. classID)
end

local function SubclassLabel(classID, subclassID)
	if subclassID == nil then return "All subtypes" end
	local name = GetItemSubClassInfo and GetItemSubClassInfo(classID, subclassID) or nil
	return name or ("subtype " .. subclassID)
end

local function InitClassDropdown()
	UIDropDownMenu_Initialize(classDropdown, function()
		local info = UIDropDownMenu_CreateInfo()
		info.text = "All types"
		info.value = nil
		info.checked = (state.classID == nil)
		info.func = function()
			state.classID = nil
			state.subclassID = nil
			UIDropDownMenu_SetText(classDropdown, "All types")
			UIDropDownMenu_SetText(subclassDropdown, "All subtypes")
			subclassDropdown:Hide()
			SaveState(); Refresh()
		end
		UIDropDownMenu_AddButton(info)

		local classes = Filters.AvailableClasses(Scanner.GetRows())
		local sortedIDs = {}
		for cid in pairs(classes) do sortedIDs[#sortedIDs + 1] = cid end
		table.sort(sortedIDs)
		for _, cid in ipairs(sortedIDs) do
			local entry = UIDropDownMenu_CreateInfo()
			entry.text = ClassLabel(cid)
			entry.value = cid
			entry.checked = (state.classID == cid)
			entry.func = function()
				state.classID = cid
				state.subclassID = nil
				UIDropDownMenu_SetText(classDropdown, ClassLabel(cid))
				UIDropDownMenu_SetText(subclassDropdown, "All subtypes")
				subclassDropdown:Show()
				SaveState(); Refresh()
			end
			UIDropDownMenu_AddButton(entry)
		end
	end)
	UIDropDownMenu_SetWidth(classDropdown, 130)
	UIDropDownMenu_SetText(classDropdown, ClassLabel(state.classID))
end

local function InitSubclassDropdown()
	UIDropDownMenu_Initialize(subclassDropdown, function()
		local cid = state.classID
		if not cid then return end
		local info = UIDropDownMenu_CreateInfo()
		info.text = "All subtypes"
		info.value = nil
		info.checked = (state.subclassID == nil)
		info.func = function()
			state.subclassID = nil
			UIDropDownMenu_SetText(subclassDropdown, "All subtypes")
			SaveState(); Refresh()
		end
		UIDropDownMenu_AddButton(info)

		local classes = Filters.AvailableClasses(Scanner.GetRows())
		local subMap = classes[cid] or {}
		local sortedIDs = {}
		for sid in pairs(subMap) do sortedIDs[#sortedIDs + 1] = sid end
		table.sort(sortedIDs)
		for _, sid in ipairs(sortedIDs) do
			local entry = UIDropDownMenu_CreateInfo()
			entry.text = SubclassLabel(cid, sid)
			entry.value = sid
			entry.checked = (state.subclassID == sid)
			entry.func = function()
				state.subclassID = sid
				UIDropDownMenu_SetText(subclassDropdown, SubclassLabel(cid, sid))
				SaveState(); Refresh()
			end
			UIDropDownMenu_AddButton(entry)
		end
	end)
	UIDropDownMenu_SetWidth(subclassDropdown, 160)
	UIDropDownMenu_SetText(subclassDropdown, SubclassLabel(state.classID, state.subclassID))
	if state.classID == nil then subclassDropdown:Hide() else subclassDropdown:Show() end
end

-- ============================================================================
-- Numeric input helpers
-- ============================================================================

local function MakeNumberBox(parent, width)
	local b = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	b:SetSize(width, 18)
	b:SetAutoFocus(false)
	b:SetNumeric(true)
	b:SetMaxLetters(4)
	b:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	b:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	return b
end

local function ParseOptNum(text)
	text = text and text:match("^%s*(.-)%s*$") or ""
	if text == "" then return nil end
	return tonumber(text)
end

-- ============================================================================
-- Panel
-- ============================================================================

local function CreatePanel()
	state = state or (TSMVFPCharDB and TSMVFPCharDB.filterState) or Filters.NewState()
	-- Defensive: re-key any persisted state through NewState so newer fields exist.
	local defaults = Filters.NewState()
	for k, v in pairs(defaults) do
		if state[k] == nil and v ~= nil then state[k] = v end
	end

	local f = CreateFrame("Frame", "TSMVFP_Panel", UIParent, "BackdropTemplate")
	f:SetSize(PANEL_W, PANEL_H)
	f:SetFrameStrata("HIGH")
	Theme.ApplyToPanel(f)
	f:EnableMouse(true)

	-- Title + close button
	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
	title:SetText("TSM-VFP")
	title:SetTextColor(1, 0.82, 0)

	local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
	closeBtn:SetScript("OnClick", function() Panel.Hide() end)

	-- Search box (SearchBoxTemplate provides magnifier icon, "Search" placeholder, and clear button)
	searchBox = CreateFrame("EditBox", "TSMVFP_SearchBox", f, "SearchBoxTemplate")
	searchBox:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -32)
	searchBox:SetPoint("TOPRIGHT", f, "TOPRIGHT", -28, -32)
	searchBox:SetHeight(20)
	searchBox:SetAutoFocus(false)
	searchBox:SetMaxLetters(64)
	if state.nameSubstring and state.nameSubstring ~= "" then
		searchBox:SetText(state.nameSubstring)
	end
	searchBox:HookScript("OnTextChanged", function(self)
		local txt = self:GetText() or ""
		state.nameSubstring = (txt == "" and nil) or txt
		SaveState(); Refresh()
	end)

	-- Row 1: Quality + Group dropdowns
	qualityDropdown = CreateFrame("Frame", "TSMVFP_QualityDropdown", f, "UIDropDownMenuTemplate")
	qualityDropdown:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -56)
	groupDropdown = CreateFrame("Frame", "TSMVFP_GroupDropdown", f, "UIDropDownMenuTemplate")
	groupDropdown:SetPoint("TOPLEFT", qualityDropdown, "TOPRIGHT", 20, 0)

	-- Row 2: Class + Subclass dropdowns (absolute Y to avoid UIDropDown internal padding surprises)
	classDropdown = CreateFrame("Frame", "TSMVFP_ClassDropdown", f, "UIDropDownMenuTemplate")
	classDropdown:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -86)
	subclassDropdown = CreateFrame("Frame", "TSMVFP_SubclassDropdown", f, "UIDropDownMenuTemplate")
	subclassDropdown:SetPoint("TOPLEFT", classDropdown, "TOPRIGHT", 20, 0)

	-- Row 3: ilvl range + req level max
	local ilvlLabel = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	ilvlLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 26, -126)
	ilvlLabel:SetText("ilvl:")

	ilvlMinBox = MakeNumberBox(f, 36)
	ilvlMinBox:SetPoint("LEFT", ilvlLabel, "RIGHT", 6, 0)
	ilvlMinBox:SetText(state.ilvlMin and tostring(state.ilvlMin) or "")
	local dash = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	dash:SetPoint("LEFT", ilvlMinBox, "RIGHT", 4, 0)
	dash:SetText("-")
	ilvlMaxBox = MakeNumberBox(f, 36)
	ilvlMaxBox:SetPoint("LEFT", dash, "RIGHT", 4, 0)
	ilvlMaxBox:SetText(state.ilvlMax and tostring(state.ilvlMax) or "")

	ilvlMinBox:SetScript("OnTextChanged", function(self)
		state.ilvlMin = ParseOptNum(self:GetText())
		SaveState(); Refresh()
	end)
	ilvlMaxBox:SetScript("OnTextChanged", function(self)
		state.ilvlMax = ParseOptNum(self:GetText())
		SaveState(); Refresh()
	end)

	local reqLabel = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	reqLabel:SetPoint("LEFT", ilvlMaxBox, "RIGHT", 18, 0)
	reqLabel:SetText("req lvl max:")
	reqLevelMaxBox = MakeNumberBox(f, 36)
	reqLevelMaxBox:SetPoint("LEFT", reqLabel, "RIGHT", 6, 0)
	reqLevelMaxBox:SetText(state.reqLevelMax and tostring(state.reqLevelMax) or "")
	reqLevelMaxBox:SetScript("OnTextChanged", function(self)
		state.reqLevelMax = ParseOptNum(self:GetText())
		SaveState(); Refresh()
	end)

	-- Scroll frame + rows
	scrollFrame = CreateFrame("ScrollFrame", "TSMVFP_ScrollFrame", f, "FauxScrollFrameTemplate")
	scrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -TOP_RESERVED)
	scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -28, BOT_RESERVED - 6)
	scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
		FauxScrollFrame_OnVerticalScroll(self, offset, ROW_H, UpdateRows)
	end)

	rowWidgets = {}
	for i = 1, NUM_VISIBLE_ROWS do
		rowWidgets[i] = CreateRow(f, i, scrollFrame)
	end

	local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 8)
	hint:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 8)
	hint:SetJustifyH("LEFT")
	hint:SetText("click: buy 1 — shift-click: buy stack")

	InitQualityDropdown()
	InitGroupDropdown()
	InitClassDropdown()
	InitSubclassDropdown()
	f:Hide()
	return f
end

---@param anchorFrame Frame the vendor frame (MerchantFrame or TSM's); panel anchors past its right edge
function Panel.AttachTo(anchorFrame)
	if not panelFrame then panelFrame = CreatePanel() end
	panelFrame:ClearAllPoints()
	panelFrame:SetParent(anchorFrame)
	-- Anchor directly to the anchor frame's top-right, not via the tab, so the
	-- panel's top edge aligns with the anchor's top regardless of the tab Y-offset.
	-- ~32px right of the anchor leaves room for the tab to sit between them.
	panelFrame:SetPoint("TOPLEFT", anchorFrame, "TOPRIGHT", 32, 0)
end

function Panel.Show()
	if not panelFrame then return end
	panelFrame:Show()
	-- Re-init the class dropdowns each show in case the vendor changed.
	if classDropdown then InitClassDropdown() end
	if subclassDropdown then InitSubclassDropdown() end
	Refresh()
end

function Panel.Hide()
	if panelFrame then panelFrame:Hide() end
end

function Panel.Toggle()
	if not panelFrame then return end
	if panelFrame:IsShown() then Panel.Hide() else Panel.Show() end
end

function Panel.IsShown() return panelFrame and panelFrame:IsShown() end
function Panel.GetState() return state end
function Panel.GetFilteredCount() return #filteredOut end
