local _, NS = ...
NS.UI = NS.UI or {}
local Panel = {}
NS.UI.Panel = Panel

local Theme = NS.UI.Themes.Default
local Filters = NS.Filters
local Scanner = NS.Scanner

local PANEL_W = 440
local ROW_H = Theme.rowHeight
local DEFAULT_VISIBLE_ROWS = 14
local MAX_ROWS = 25 -- widget pool; user can resize panel up to this many rows tall
local HEADER_H = 18 -- column header strip above the scroll area
local TOP_RESERVED = 216 + HEADER_H
local BOT_RESERVED = 30
local PANEL_H = TOP_RESERVED + DEFAULT_VISIBLE_ROWS * ROW_H + BOT_RESERVED
local MIN_PANEL_W = 420
local MIN_PANEL_H = TOP_RESERVED + 3 * ROW_H + BOT_RESERVED -- enough for header + 3 rows + bottom hint

-- Column geometry. Icon + qty + ilvl + cost are fixed-width;
-- Name fills the remaining horizontal space.
local COL_ICON_W = 20
local COL_QTY_W  = 36 -- "x1" / "xN" buy-qty preview prefix (fits up to "x999")
local COL_ILVL_W = 40
local COL_COST_W = 100
local COL_RIGHT_PAD = 4 -- inside-the-row pad on the right
local COL_GAP = 6       -- gap between columns

local state = nil
local filteredOut = {}

local panelFrame
local searchBox, qualityDropdown, classDropdown, subclassDropdown, groupDropdown, demonDropdown
local ilvlMinBox, ilvlMaxBox, reqLevelMaxBox
local affordableCheck, canUseCheck, knownCheck
local headerRow, hdrName, hdrIlvl, hdrCost
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

-- TSM-style money colors: numbers white, denomination letters tinted.
local PRICE_NUM = "|cffffffff"
local PRICE_G   = "|cffffd70a"
local PRICE_S   = "|cffc0c0c0"
local PRICE_C   = "|cffcc8a3f"
local PRICE_END = "|r"

local function FormatPrice(copper)
	if not copper or copper == 0 then return "" end
	local g = math.floor(copper / 10000)
	local s = math.floor((copper % 10000) / 100)
	local c = copper % 100
	local out = {}
	if g > 0 then
		out[#out + 1] = PRICE_NUM .. g .. PRICE_END .. PRICE_G .. "g" .. PRICE_END
	end
	if g > 0 or s > 0 then
		out[#out + 1] = PRICE_NUM .. s .. PRICE_END .. PRICE_S .. "s" .. PRICE_END
	end
	out[#out + 1] = PRICE_NUM .. c .. PRICE_END .. PRICE_C .. "c" .. PRICE_END
	return table.concat(out, " ")
end

local function BuyRow(row, qty)
	if not row or not row.index then return end
	qty = qty or 1
	BuyMerchantItem(row.index, qty)
	local label = (row.link or row.name or "?")
	print(("|cff66ccffCoinscry|r: bought %dx %s"):format(qty, label))
end

-- Static popup for right-click quantity-buy. Defined once at module load;
-- the OnAccept closure captures BuyRow above.
-- TBC Anniversary's StaticPopup uses retail-era member names: self.EditBox
-- (capital E) rather than the classic-era self.editBox. Helper that grabs
-- whichever is present so the dialog works across forks.
local function PopupEditBox(self)
	return self.EditBox or self.editBox
end

StaticPopupDialogs["Coinscry_BUY_QTY"] = {
	text = "Buy how many?\n%s",
	button1 = ACCEPT,
	button2 = CANCEL,
	hasEditBox = 1,
	maxLetters = 5,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
	enterClicksFirstButton = 1, -- modern WoW handles Enter -> button1 automatically
	OnShow = function(self)
		local row = self.data
		local default = (row and row.stackCount) or 1
		if row and row.numAvailable and row.numAvailable > 0 then
			default = math.min(default, row.numAvailable)
		end
		local eb = PopupEditBox(self)
		if not eb then return end
		eb:SetText(tostring(default))
		eb:SetNumeric(true)
		eb:HighlightText()
		eb:SetFocus()
	end,
	OnAccept = function(self)
		local row = self.data
		if not row then return end
		local eb = PopupEditBox(self)
		local qty = tonumber((eb and eb:GetText()) or "")
		if not qty or qty < 1 then return end
		if row.numAvailable and row.numAvailable > 0 then
			qty = math.min(qty, row.numAvailable)
		end
		BuyRow(row, qty)
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
}

local function CreateRow(parent, i, anchorTo)
	local r = CreateFrame("Button", nil, parent)
	r:SetHeight(ROW_H)
	-- Anchor LEFT + RIGHT to the scroll area so rows stretch horizontally when
	-- the panel is resized wider. Vertical position is by stacking against the
	-- previous row, or against the scroll-area top for row 1.
	if i == 1 then
		r:SetPoint("TOPLEFT", anchorTo, "TOPLEFT", 0, 0)
		r:SetPoint("TOPRIGHT", anchorTo, "TOPRIGHT", 0, 0)
	else
		r:SetPoint("TOPLEFT", rowWidgets[i - 1], "BOTTOMLEFT", 0, 0)
		r:SetPoint("TOPRIGHT", rowWidgets[i - 1], "BOTTOMRIGHT", 0, 0)
	end

	r.bg = r:CreateTexture(nil, "BACKGROUND")
	r.bg:SetAllPoints()
	r.bg:SetColorTexture(1, 1, 1, 0)

	-- Icon (leftmost column, no header)
	r.icon = r:CreateTexture(nil, "ARTWORK")
	r.icon:SetSize(ROW_H - 4, ROW_H - 4)
	r.icon:SetPoint("LEFT", r, "LEFT", 2, 0)

	-- Buy-qty preview: 'x1' default, 'xN' (stackCount) when Shift is held.
	-- Reserves a fixed-width slot so the Name column doesn't jitter on modifier change.
	r.qty = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	r.qty:SetPoint("LEFT", r.icon, "RIGHT", COL_GAP, 0)
	r.qty:SetWidth(COL_QTY_W)
	r.qty:SetJustifyH("LEFT")

	-- Cost (rightmost) — anchored to row right with internal padding.
	-- Inline color codes handle per-denomination tinting; base color is white
	-- so the digits show through cleanly.
	r.price = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	r.price:SetPoint("RIGHT", r, "RIGHT", -COL_RIGHT_PAD, 0)
	r.price:SetWidth(COL_COST_W)
	r.price:SetJustifyH("RIGHT")

	-- iLvl (second-from-right) — left of price.
	r.ilvl = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	r.ilvl:SetPoint("RIGHT", r.price, "LEFT", -COL_GAP, 0)
	r.ilvl:SetWidth(COL_ILVL_W)
	r.ilvl:SetJustifyH("RIGHT")

	-- Name fills the rest, between qty and ilvl.
	r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	r.name:SetPoint("LEFT", r.qty, "RIGHT", 2, 0)
	r.name:SetPoint("RIGHT", r.ilvl, "LEFT", -COL_GAP, 0)
	r.name:SetJustifyH("LEFT")
	r.name:SetWordWrap(false)

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
		if btn == "RightButton" then
			local label = (self.dataRow.link or self.dataRow.name or "?")
			local dialog = StaticPopup_Show("Coinscry_BUY_QTY", label)
			if dialog then dialog.data = self.dataRow end
			return
		end
		if IsShiftKeyDown() then
			BuyRow(self.dataRow, self.dataRow.stackCount or 1)
		else
			BuyRow(self.dataRow, 1)
		end
	end)
	return r
end

---Number of rows that fit in the current scroll-frame height. Recomputed each
---update so resize Just Works without explicit subscription.
local function VisibleRowCount()
	if not scrollFrame then return DEFAULT_VISIBLE_ROWS end
	local h = scrollFrame:GetHeight() or (DEFAULT_VISIBLE_ROWS * ROW_H)
	return math.max(1, math.min(MAX_ROWS, math.floor(h / ROW_H)))
end

local function UpdateRows()
	if not panelFrame or not panelFrame:IsShown() then return end
	local offset = FauxScrollFrame_GetOffset(scrollFrame) or 0
	local visible = VisibleRowCount()
	local shiftHeld = IsShiftKeyDown and IsShiftKeyDown() or false
	for i = 1, MAX_ROWS do
		local w = rowWidgets[i]
		if i > visible then
			w.dataRow = nil
			w:Hide()
		else
			local dataIdx = offset + i
			local data = filteredOut[dataIdx]
			if data then
				w.dataRow = data
				w.alt = (dataIdx % 2 == 0)
				w.bg:SetColorTexture(1, 1, 1, w.alt and 0.04 or 0)
				w.icon:SetTexture(data.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
				w.qty:SetText("x" .. (shiftHeld and (data.stackCount or 1) or 1))
				local cr, cg, cb = Theme.QualityColor(data.quality)
				w.name:SetTextColor(cr, cg, cb)
				w.name:SetText(data.name or "...")
				-- iLvl: blank for items where it isn't meaningful (0 / -1 / nil)
				if data.itemLevel and data.itemLevel > 0 then
					w.ilvl:SetText(tostring(data.itemLevel))
				else
					w.ilvl:SetText("")
				end
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
	end
	FauxScrollFrame_Update(scrollFrame, #filteredOut, visible, ROW_H)
end

local function UpdateSortIndicators()
	if not hdrName then return end
	local function apply(header, key)
		if state and state.sortKey == key then
			header.indicator:Show()
			if state.sortAscending ~= false then
				header.indicator:SetTexCoord(0, 1, 0, 1) -- normal: arrow up
			else
				header.indicator:SetTexCoord(0, 1, 1, 0) -- flipped: arrow down
			end
		else
			header.indicator:Hide()
		end
	end
	apply(hdrName, "name")
	apply(hdrIlvl, "itemLevel")
	apply(hdrCost, "price")
end

local function Refresh()
	if not state then return end
	Filters.Apply(Scanner.GetRows(), state, filteredOut)
	if state.sortKey then
		Filters.SortRows(filteredOut, state.sortKey, state.sortAscending ~= false)
	end
	UpdateSortIndicators()
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
				Refresh()
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
			Refresh()
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
				Refresh()
			end
			UIDropDownMenu_AddButton(entry)
		end
	end)
	UIDropDownMenu_SetWidth(classDropdown, 130)
	UIDropDownMenu_SetText(classDropdown, ClassLabel(state.classID))
end

local function InitDemonDropdown()
	if not demonDropdown then return end
	UIDropDownMenu_Initialize(demonDropdown, function()
		local info = UIDropDownMenu_CreateInfo()
		info.text = "Any demon"
		info.value = nil
		info.checked = (state.demonType == nil)
		info.func = function()
			state.demonType = nil
			UIDropDownMenu_SetText(demonDropdown, "Any demon")
			Refresh()
		end
		UIDropDownMenu_AddButton(info)

		local demons = Filters.AvailableDemons(Scanner.GetRows())
		local sorted = {}
		for d in pairs(demons) do sorted[#sorted + 1] = d end
		table.sort(sorted)
		for _, d in ipairs(sorted) do
			local entry = UIDropDownMenu_CreateInfo()
			entry.text = d
			entry.value = d
			entry.checked = (state.demonType == d)
			entry.func = function()
				state.demonType = d
				UIDropDownMenu_SetText(demonDropdown, d)
				Refresh()
			end
			UIDropDownMenu_AddButton(entry)
		end
	end)
	UIDropDownMenu_SetWidth(demonDropdown, 130)
	UIDropDownMenu_SetText(demonDropdown, state.demonType or "Any demon")

	-- Only surface this filter when the current vendor actually sells tomes;
	-- otherwise it's clutter on every other vendor.
	local any = false
	for _, row in ipairs(Scanner.GetRows()) do
		if row.demonType then any = true; break end
	end
	if any then demonDropdown:Show() else demonDropdown:Hide() end
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
			Refresh()
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
				Refresh()
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
	state = state or Filters.NewState() -- always start fresh; filters reset per vendor visit

	local f = CreateFrame("Frame", "Coinscry_Panel", UIParent, "BackdropTemplate")
	f:SetSize(PANEL_W, PANEL_H)
	f:SetFrameStrata("DIALOG") -- above TSM's vendor frame (HIGH)
	NS.UI.ApplyTheme("ApplyToPanel", f)
	f:EnableMouse(true)

	-- Resize: bottom-right drag grip; bounds keep the panel usable. Restored
	-- size from CoinscryCharDB if previously dragged.
	f:SetResizable(true)
	if f.SetResizeBounds then
		f:SetResizeBounds(MIN_PANEL_W, MIN_PANEL_H)
	elseif f.SetMinResize then
		f:SetMinResize(MIN_PANEL_W, MIN_PANEL_H)
	end

	local resizeGrip = CreateFrame("Button", nil, f)
	resizeGrip:SetSize(16, 16)
	resizeGrip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
	resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	resizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	resizeGrip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
	resizeGrip:SetScript("OnMouseUp", function()
		f:StopMovingOrSizing()
		if CoinscryCharDB then
			CoinscryCharDB.panelSize = { width = f:GetWidth(), height = f:GetHeight() }
		end
	end)

	f:SetScript("OnSizeChanged", function() if Panel.Refresh then Panel.Refresh() end end)

	-- Restore previously saved size if present.
	if CoinscryCharDB and CoinscryCharDB.panelSize then
		local sz = CoinscryCharDB.panelSize
		if sz.width and sz.height and sz.width >= MIN_PANEL_W and sz.height >= MIN_PANEL_H then
			f:SetSize(sz.width, sz.height)
		end
	end

	-- Title + close button
	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
	title:SetText("Coinscry")
	title:SetTextColor(1, 0.82, 0)

	local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
	closeBtn:SetScript("OnClick", function() Panel.Hide() end)
	NS.UI.ApplyTheme("ApplyToCloseButton", closeBtn)

	-- Search box (SearchBoxTemplate provides magnifier icon, "Search" placeholder, and clear button)
	searchBox = CreateFrame("EditBox", "Coinscry_SearchBox", f, "SearchBoxTemplate")
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
		Refresh()
	end)
	searchBox:HookScript("OnEnterPressed", function(self) self:ClearFocus() end)
	searchBox:HookScript("OnEscapePressed", function(self) self:ClearFocus() end)
	NS.UI.ApplyTheme("ApplyToEditBox", searchBox)

	-- Row 1: Quality + Group dropdowns. Align left edge with search box (x=16).
	qualityDropdown = CreateFrame("Frame", "Coinscry_QualityDropdown", f, "UIDropDownMenuTemplate")
	qualityDropdown:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -56)
	groupDropdown = CreateFrame("Frame", "Coinscry_GroupDropdown", f, "UIDropDownMenuTemplate")
	groupDropdown:SetPoint("TOPLEFT", qualityDropdown, "TOPRIGHT", 12, 0)
	NS.UI.ApplyTheme("ApplyToDropDown", qualityDropdown, 100)
	NS.UI.ApplyTheme("ApplyToDropDown", groupDropdown, 130)

	-- Row 2: Type + Subtype dropdowns
	classDropdown = CreateFrame("Frame", "Coinscry_ClassDropdown", f, "UIDropDownMenuTemplate")
	classDropdown:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -86)
	subclassDropdown = CreateFrame("Frame", "Coinscry_SubclassDropdown", f, "UIDropDownMenuTemplate")
	subclassDropdown:SetPoint("TOPLEFT", classDropdown, "TOPRIGHT", 12, 0)
	NS.UI.ApplyTheme("ApplyToDropDown", classDropdown, 110)
	NS.UI.ApplyTheme("ApplyToDropDown", subclassDropdown, 130)

	-- Row 3: ilvl range + req level max
	local ilvlLabel = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	ilvlLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 26, -126)
	ilvlLabel:SetText("ilvl:")

	ilvlMinBox = MakeNumberBox(f, 36)
	ilvlMinBox:SetPoint("LEFT", ilvlLabel, "RIGHT", 6, 0)
	ilvlMinBox:SetText(state.ilvlMin and tostring(state.ilvlMin) or "")
	NS.UI.ApplyTheme("ApplyToEditBox", ilvlMinBox)
	local dash = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	dash:SetPoint("LEFT", ilvlMinBox, "RIGHT", 4, 0)
	dash:SetText("-")
	ilvlMaxBox = MakeNumberBox(f, 36)
	ilvlMaxBox:SetPoint("LEFT", dash, "RIGHT", 4, 0)
	ilvlMaxBox:SetText(state.ilvlMax and tostring(state.ilvlMax) or "")
	NS.UI.ApplyTheme("ApplyToEditBox", ilvlMaxBox)

	ilvlMinBox:SetScript("OnTextChanged", function(self)
		state.ilvlMin = ParseOptNum(self:GetText())
		Refresh()
	end)
	ilvlMaxBox:SetScript("OnTextChanged", function(self)
		state.ilvlMax = ParseOptNum(self:GetText())
		Refresh()
	end)

	local reqLabel = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	reqLabel:SetPoint("LEFT", ilvlMaxBox, "RIGHT", 18, 0)
	reqLabel:SetText("req lvl max:")
	reqLevelMaxBox = MakeNumberBox(f, 36)
	reqLevelMaxBox:SetPoint("LEFT", reqLabel, "RIGHT", 6, 0)
	reqLevelMaxBox:SetText(state.reqLevelMax and tostring(state.reqLevelMax) or "")
	NS.UI.ApplyTheme("ApplyToEditBox", reqLevelMaxBox)
	reqLevelMaxBox:SetScript("OnTextChanged", function(self)
		state.reqLevelMax = ParseOptNum(self:GetText())
		Refresh()
	end)

	-- Row 4: filter checkboxes, chained so labels don't overlap regardless of
	-- text length. ChatConfigCheckButtonTemplate's .Text FontString has a wider
	-- internal frame than its rendered text, so anchoring LEFT-to-RIGHT of the
	-- label puts the next checkbox far past where text actually ends. Use the
	-- measured GetStringWidth() to position explicitly.
	local CHECKBOX_W = 20
	local LABEL_PAD = 4 -- gap between checkbox right edge and label left edge
	local CHAIN_GAP = 16 -- gap between previous label end and next checkbox
	local function MakeFilterCheckbox(text, prevOrX, y, getter, setter)
		local c = CreateFrame("CheckButton", nil, f, "ChatConfigCheckButtonTemplate")
		c:SetSize(CHECKBOX_W, CHECKBOX_W)
		-- ChatConfigCheckButtonTemplate uses a NEGATIVE right hit-rect inset to
		-- make clicks on the (template-owned) label also toggle the checkbox.
		-- That extended hit area was eating clicks intended for the next
		-- checkbox in the row. Explicitly reset to the visible frame size.
		c:SetHitRectInsets(0, 0, 0, 0)
		-- Use our own FontString so we control its placement and can measure it.
		if c.Text then c.Text:Hide() end
		local label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		label:SetText(text)
		label:SetPoint("LEFT", c, "RIGHT", LABEL_PAD, 1)
		c.label = label
		if type(prevOrX) == "number" then
			c:SetPoint("TOPLEFT", f, "TOPLEFT", prevOrX, y)
		else
			local prevWidth = (prevOrX.label and prevOrX.label.GetStringWidth and prevOrX.label:GetStringWidth()) or 70
			c:SetPoint("TOPLEFT", prevOrX, "TOPLEFT", CHECKBOX_W + LABEL_PAD + prevWidth + CHAIN_GAP, 0)
		end
		c:SetChecked(getter() and true or false)
		c:SetScript("OnClick", function(self)
			setter(self:GetChecked() and true or nil)
			Refresh()
		end)
		return c
	end

	affordableCheck = MakeFilterCheckbox(
		"Affordable", 16, -154,
		function() return state.affordableOnly end,
		function(v) state.affordableOnly = v end
	)
	canUseCheck = MakeFilterCheckbox(
		"Can use", affordableCheck, nil,
		function() return state.canUseOnly end,
		function(v) state.canUseOnly = v end
	)
	knownCheck = MakeFilterCheckbox(
		"Hide known", canUseCheck, nil,
		function() return state.hideAlreadyKnown end,
		function(v) state.hideAlreadyKnown = v end
	)

	-- Row 5: demon-type dropdown (contextual — hidden when vendor has no tomes)
	demonDropdown = CreateFrame("Frame", "Coinscry_DemonDropdown", f, "UIDropDownMenuTemplate")
	demonDropdown:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -184)
	NS.UI.ApplyTheme("ApplyToDropDown", demonDropdown, 130)

	-- Column header strip (sits above the scroll area). Headers are clickable
	-- buttons; click toggles sort. Indicator FontString shows ▲/▼ on the
	-- active column.
	headerRow = CreateFrame("Frame", nil, f)
	headerRow:SetHeight(HEADER_H)
	headerRow:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -(TOP_RESERVED - HEADER_H))
	headerRow:SetPoint("TOPRIGHT", f, "TOPRIGHT", -28, -(TOP_RESERVED - HEADER_H))

	local hdrDivider = headerRow:CreateTexture(nil, "ARTWORK")
	hdrDivider:SetColorTexture(1, 1, 1, 0.10)
	hdrDivider:SetPoint("BOTTOMLEFT", headerRow, "BOTTOMLEFT", 0, 0)
	hdrDivider:SetPoint("BOTTOMRIGHT", headerRow, "BOTTOMRIGHT", 0, 0)
	hdrDivider:SetHeight(1)

	local function MakeHeader(text, justify)
		local b = CreateFrame("Button", nil, headerRow)
		b:SetHeight(HEADER_H)

		-- Anchor the label on the justify side only so its frame is exactly as
		-- wide as the rendered text. That lets the sort-indicator texture
		-- anchor immediately adjacent to the text (not to the column edge).
		b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		b.label:SetText(text)
		if justify == "RIGHT" then
			b.label:SetPoint("RIGHT", b, "RIGHT", 0, 0)
		else
			b.label:SetPoint("LEFT", b, "LEFT", 0, 0)
		end
		b.label:SetJustifyH(justify)

		-- UI-SortArrow is the standard Blizzard up-arrow texture; we flip its
		-- TexCoord vertically when the sort is descending.
		b.indicator = b:CreateTexture(nil, "OVERLAY")
		b.indicator:SetSize(10, 10)
		b.indicator:SetTexture("Interface\\Buttons\\UI-SortArrow")
		if justify == "RIGHT" then
			b.indicator:SetPoint("RIGHT", b.label, "LEFT", -2, 0)
		else
			b.indicator:SetPoint("LEFT", b.label, "RIGHT", 3, 0)
		end
		b.indicator:Hide()

		b:SetScript("OnEnter", function(self) self.label:SetTextColor(1, 1, 0.6) end)
		b:SetScript("OnLeave", function(self) self.label:SetTextColor(1, 1, 1) end)
		return b
	end

	hdrCost = MakeHeader("Cost", "RIGHT")
	hdrCost:SetWidth(COL_COST_W)
	hdrCost:SetPoint("RIGHT", headerRow, "RIGHT", -COL_RIGHT_PAD, 0)

	hdrIlvl = MakeHeader("ilvl", "RIGHT")
	hdrIlvl:SetWidth(COL_ILVL_W)
	hdrIlvl:SetPoint("RIGHT", hdrCost, "LEFT", -COL_GAP, 0)

	hdrName = MakeHeader("Item", "LEFT")
	hdrName:SetPoint("LEFT", headerRow, "LEFT", COL_ICON_W + COL_GAP + 2, 0)
	hdrName:SetPoint("RIGHT", hdrIlvl, "LEFT", -COL_GAP, 0)

	local function OnHeaderClick(key)
		return function()
			if state.sortKey == key then
				state.sortAscending = not (state.sortAscending ~= false)
			else
				state.sortKey = key
				state.sortAscending = true
			end
			Refresh()
		end
	end
	hdrName:SetScript("OnClick", OnHeaderClick("name"))
	hdrIlvl:SetScript("OnClick", OnHeaderClick("itemLevel"))
	hdrCost:SetScript("OnClick", OnHeaderClick("price"))

	-- Scroll frame + rows
	scrollFrame = CreateFrame("ScrollFrame", "Coinscry_ScrollFrame", f, "FauxScrollFrameTemplate")
	scrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -TOP_RESERVED)
	scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -28, BOT_RESERVED - 6)
	scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
		FauxScrollFrame_OnVerticalScroll(self, offset, ROW_H, UpdateRows)
	end)
	-- FauxScrollFrame's slider lives at _G[name.."ScrollBar"]; hand that to ElvUI.
	local sb = _G[scrollFrame:GetName() .. "ScrollBar"]
	if sb then NS.UI.ApplyTheme("ApplyToScrollBar", sb) end

	rowWidgets = {}
	for i = 1, MAX_ROWS do
		rowWidgets[i] = CreateRow(f, i, scrollFrame)
	end

	local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 8)
	hint:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -22, 8) -- room for the resize grip
	hint:SetJustifyH("LEFT")
	hint:SetText("clk: buy 1x -- shift-clk: buy stack -- rt-clk: enter qty")

	InitQualityDropdown()
	InitGroupDropdown()
	InitClassDropdown()
	InitSubclassDropdown()
	InitDemonDropdown()
	f:Hide()
	return f
end

---@param anchorFrame Frame the vendor frame (MerchantFrame or TSM's); panel anchors past its right edge
-- Display modes:
--   "attached" — panel floats beside the anchor frame (used for TSM's vendor frame)
--   "embedded" — panel replaces MerchantFrame's item grid inside MerchantFrame itself
local displayMode = "attached"
local savedMerchantWidth -- set while embedded; nil otherwise

-- Names of Blizzard MerchantFrame widgets to hide while we're embedded over
-- the item grid. Tabs (Buy/Buyback), money frame, and title stay visible so
-- the user can still switch tabs or read the merchant's name.
local HIDDEN_MERCHANT_WIDGETS = {
	"MerchantNextPageButton", "MerchantPrevPageButton", "MerchantPageText",
}
for i = 1, 12 do HIDDEN_MERCHANT_WIDGETS[#HIDDEN_MERCHANT_WIDGETS + 1] = "MerchantItem" .. i end

local EMBED_MERCHANT_WIDTH = PANEL_W + 36 -- width MerchantFrame gets resized to while embedded

local function EnterEmbedMode()
	if not MerchantFrame or savedMerchantWidth then return end
	savedMerchantWidth = MerchantFrame:GetWidth()
	MerchantFrame:SetWidth(EMBED_MERCHANT_WIDTH)
	for _, name in ipairs(HIDDEN_MERCHANT_WIDGETS) do
		local f = _G[name]
		if f and f.Hide then f:Hide() end
	end
end

local function ExitEmbedMode()
	if not savedMerchantWidth then return end
	if MerchantFrame then MerchantFrame:SetWidth(savedMerchantWidth) end
	savedMerchantWidth = nil
	for _, name in ipairs(HIDDEN_MERCHANT_WIDGETS) do
		local f = _G[name]
		if f and f.Show then f:Show() end
	end
	if _G.MerchantFrame_Update then _G.MerchantFrame_Update() end
end

---@param anchorFrame Frame the vendor frame (MerchantFrame or TSM's)
---@param mode? string "embedded" or "attached" (default)
function Panel.AttachTo(anchorFrame, mode)
	if not panelFrame then panelFrame = CreatePanel() end
	local newMode = mode or "attached"

	-- If we're switching away from embed while shown, restore MerchantFrame first.
	if displayMode == "embedded" and newMode ~= "embedded" then
		ExitEmbedMode()
	end

	displayMode = newMode
	panelFrame:ClearAllPoints()
	panelFrame:SetParent(anchorFrame)

	if displayMode == "embedded" then
		-- Anchor inside MerchantFrame's content area. Margins clear the title
		-- bar at the top and the money frame / tabs at the bottom.
		panelFrame:SetPoint("TOPLEFT", anchorFrame, "TOPLEFT", 12, -32)
		panelFrame:SetPoint("BOTTOMRIGHT", anchorFrame, "BOTTOMRIGHT", -12, 38)
		-- If we're currently visible in embed mode, make sure merchant items
		-- are hidden (e.g., after a frame switch while panel was already open).
		if panelFrame:IsShown() then EnterEmbedMode() end
	else
		panelFrame:SetPoint("TOPLEFT", anchorFrame, "TOPRIGHT", 32, 0)
		panelFrame:SetSize(PANEL_W, PANEL_H)
	end
end

function Panel.Show()
	if not panelFrame then return end
	if displayMode == "embedded" then EnterEmbedMode() end
	panelFrame:Show()
	-- Re-init the vendor-contextual dropdowns each show in case the vendor changed.
	if classDropdown then InitClassDropdown() end
	if subclassDropdown then InitSubclassDropdown() end
	if demonDropdown then InitDemonDropdown() end
	Refresh()
end

function Panel.Hide()
	if displayMode == "embedded" then ExitEmbedMode() end
	if panelFrame then panelFrame:Hide() end
end

function Panel.Toggle()
	if not panelFrame then return end
	if panelFrame:IsShown() then Panel.Hide() else Panel.Show() end
end

function Panel.GetDisplayMode() return displayMode end

function Panel.IsShown() return panelFrame and panelFrame:IsShown() end
function Panel.GetState() return state end
function Panel.GetFilteredCount() return #filteredOut end

---Clear all active filters and re-sync the widgets. Called on each MERCHANT_SHOW
---so a stale filter from a previous vendor doesn't silently hide items at the
---new one.
function Panel.ResetFilters()
	if not state then state = Filters.NewState(); return end
	-- Reset state in place so any references stay valid.
	for k in pairs(state) do state[k] = nil end

	if searchBox then searchBox:SetText("") end
	if qualityDropdown then UIDropDownMenu_SetText(qualityDropdown, QUALITY_CHOICES[1].label) end
	if classDropdown then UIDropDownMenu_SetText(classDropdown, "All types") end
	if subclassDropdown then
		UIDropDownMenu_SetText(subclassDropdown, "All subtypes")
		subclassDropdown:Hide()
	end
	if groupDropdown and groupDropdown.IsShown and groupDropdown:IsShown() then
		UIDropDownMenu_SetText(groupDropdown, "Any group")
	end
	if ilvlMinBox then ilvlMinBox:SetText("") end
	if ilvlMaxBox then ilvlMaxBox:SetText("") end
	if reqLevelMaxBox then reqLevelMaxBox:SetText("") end
	if affordableCheck then affordableCheck:SetChecked(false) end
	if canUseCheck then canUseCheck:SetChecked(false) end
	if knownCheck then knownCheck:SetChecked(false) end
	if demonDropdown then UIDropDownMenu_SetText(demonDropdown, "Any demon") end

	Refresh()
end
