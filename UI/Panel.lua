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
-- TOP_RESERVED varies by collapse state. _COLLAPSED has search + checkboxes
-- + the collapsible "Filters" header; _EXPANDED additionally has 4 rows of
-- advanced filter widgets (quality/group, type/subtype, ilvl/req lvl, demon).
local TOP_RESERVED_COLLAPSED = 100 + HEADER_H
local TOP_RESERVED_EXPANDED  = 218 + HEADER_H
local BOT_RESERVED = 30
local PANEL_H = TOP_RESERVED_EXPANDED + DEFAULT_VISIBLE_ROWS * ROW_H + BOT_RESERVED
local MIN_PANEL_W = 420
local MIN_PANEL_H = TOP_RESERVED_EXPANDED + 3 * ROW_H + BOT_RESERVED -- enough for filters + 3 rows + hint

-- Column geometry. Icon + qty + ilvl + cost are fixed-width;
-- Name fills the remaining horizontal space.
local COL_ICON_W = 20
local COL_QTY_W  = 36 -- "x1" / "xN" buy-qty preview prefix (fits up to "x999")
local COL_ILVL_W = 40
local COL_COST_W = 100
local COL_RIGHT_PAD = 4 -- inside-the-row pad on the right
local COL_GAP = 6       -- gap between columns

-- ============================================================================
-- Vertical layout. Y-offsets are measured from the panel's TOPLEFT and are
-- the single source of truth for widget vertical position. The
-- TOP_RESERVED_* constants above must stay in sync: TOP_RESERVED_COLLAPSED
-- reserves space through `filtersHeader` (+ widget height), and
-- TOP_RESERVED_EXPANDED reserves space through `rowD_demon`.
-- ============================================================================
local LAYOUT_Y = {
	title          = -10,  -- panel title FontString
	closeBtn       = -4,   -- panel close X button (y from top, x from right)
	searchBox      = -32,  -- search box (always visible)
	checkboxRow    = -58,  -- can-use / affordable / hide-known row (always visible)
	filtersHeader  = -82,  -- collapsible "Filters" header button (always visible)
	rowA_quality   = -100, -- quality + group dropdowns (advanced)
	rowB_class     = -130, -- class + subclass dropdowns (advanced)
	rowC_ilvl      = -162, -- ilvl range + req-level max (advanced)
	rowD_demon     = -190, -- demon dropdown, contextual (advanced)
}

local state = nil
local filteredOut = {}

local panelFrame
local searchBox, qualityDropdown, classDropdown, subclassDropdown, groupDropdown, demonDropdown
local ilvlMinBox, ilvlMaxBox, reqLevelMaxBox
local affordableCheck, canUseCheck, knownCheck
local headerRow, hdrName, hdrIlvl, hdrCost
local scrollFrame
local closeBtn, resizeGrip -- hidden in embed mode; shown in attached mode
local rowWidgets = {}

-- Collapsible "Filters" section: search + the three usage checkboxes are
-- always visible; quality / group / type / subtype / ilvl / req-lvl / demon
-- live in a collapsible block that toggles via a header button.
local filtersHeaderBtn, filtersChevron
local advancedWidgets = {} -- all advanced filter widgets, hide/show as a group
local advancedCollapsed = true -- default to collapsed; loaded from CoinscryCharDB on first CreatePanel

local function CurrentTopReserved()
	return advancedCollapsed and TOP_RESERVED_COLLAPSED or TOP_RESERVED_EXPANDED
end

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

---Aggregate free bag slots across the player's bags. Uses the modern
---CalculateTotalNumberOfFreeBagSlots when available, falling back to a
---per-bag GetContainerNumFreeSlots loop on older clients.
local function GetFreeBagSlots()
	if _G.CalculateTotalNumberOfFreeBagSlots then
		return _G.CalculateTotalNumberOfFreeBagSlots() or 0
	end
	local total = 0
	if _G.GetContainerNumFreeSlots then
		for bag = 0, (_G.NUM_BAG_SLOTS or 4) do
			total = total + (_G.GetContainerNumFreeSlots(bag) or 0)
		end
	end
	return total
end

---Estimate the worst-case number of *new* bag slots needed to buy `qty` of
---this row, accounting for any partial stack of the same item already in
---bags that the purchase can merge into. For stackSize=1 items, no merging
---is possible and every unit needs its own slot. For stackable items, the
---purchase first fills any existing partial stack, then needs
---ceil((qty - partialSpace) / stackSize) fresh slots.
---@param row table Scanner row (has .link, .stackCount)
---@param qty number desired purchase count
---@return number
local function EstimateRequiredBagSlots(row, qty)
	local ss = row.stackCount or 1
	if ss < 1 then ss = 1 end
	local existing = 0
	if row.link and _G.GetItemCount then
		local itemID = tonumber(row.link:match("item:(%d+)"))
		if itemID then existing = _G.GetItemCount(itemID) or 0 end
	end
	local partialSpace = 0
	if ss > 1 and existing > 0 then
		partialSpace = (ss - (existing % ss)) % ss
	end
	local newSpaceNeeded = math.max(0, qty - partialSpace)
	return math.ceil(newSpaceNeeded / ss)
end

local function BuyRow(row, qty)
	if not row or not row.index then return end
	qty = qty or 1
	-- BuyMerchantItem caps at one natural stack per call. Asking for more
	-- than stackSize in a single call triggers WoW's "Internal Bag Error"
	-- before any bag slot is allocated, so we split into stackSize-sized
	-- chunks. Examples: meat stackSize=20, qty=35 -> two calls (20 then 15);
	-- arrows stackSize=200, qty=200 -> one call; armor stackSize=1, qty=5
	-- -> five calls (one per bag slot).
	local stackSize = row.stackCount or 1
	if stackSize < 1 then stackSize = 1 end

	-- Bag-space precheck. BuyMerchantItem doesn't enqueue a confirmation —
	-- it fails silently per-call with "Internal Bag Error" if there's no
	-- room. Particularly nasty for stackSize=1 items split across many
	-- calls: the first few succeed, then the rest fail mid-purchase. Bail
	-- up front if we know it won't fit.
	local needed = EstimateRequiredBagSlots(row, qty)
	local free = GetFreeBagSlots()
	if needed > free then
		local label = (row.link or row.name or "?")
		print(("|cff66ccffCoinscry|r: %dx %s needs %d free bag slot%s, only %d free. Purchase cancelled — free up bags or buy fewer.")
			:format(qty, label, needed, needed == 1 and "" or "s", free))
		return
	end

	local remaining = qty
	while remaining > 0 do
		local thisCall = math.min(remaining, stackSize)
		BuyMerchantItem(row.index, thisCall)
		remaining = remaining - thisCall
	end
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

-- Popup data shape: { row = ScanRow, link = string } where `link` is the
-- row's itemLink captured at right-click time, used as a fingerprint in
-- OnAccept to detect MERCHANT_UPDATE-induced row reshuffles between popup
-- open and accept.
StaticPopupDialogs["Coinscry_BUY_QTY"] = {
	text = "Buy how many?\n%s",
	button1 = ACCEPT,
	button2 = CANCEL,
	hasEditBox = 1,
	maxLetters = 5,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
	-- enterClicksFirstButton isn't honored on every classic-derived StaticPopup
	-- fork; EditBoxOnEnterPressed below is the explicit fallback.
	enterClicksFirstButton = 1,
	OnShow = function(self)
		local data = self.data
		local row = data and data.row
		local default = (row and row.stackCount) or 1
		if row and row.numAvailable and row.numAvailable > 0 then
			default = math.min(default, row.numAvailable)
		end
		local eb = PopupEditBox(self)
		if not eb then return end
		eb:SetNumeric(true)
		eb:SetText(tostring(default))
		eb:HighlightText()
		eb:SetFocus()
	end,
	OnAccept = function(self)
		local data = self.data
		local row = data and data.row
		if not row or not row.index then return end
		local eb = PopupEditBox(self)
		local qty = tonumber((eb and eb:GetText()) or "")
		if not qty or qty < 1 then return end

		-- Verify the merchant slot still holds the item we right-clicked. If
		-- MERCHANT_UPDATE fired between right-click and accept (e.g. an item
		-- limit refreshed, an inventory event from another source), the row
		-- objects may have been wiped and the slot at row.index may now hold
		-- something else. Bail before spending gold on the wrong item.
		local currentLink = GetMerchantItemLink(row.index)
		if data.link and currentLink and currentLink ~= data.link then
			print("|cff66ccffCoinscry|r: vendor inventory changed; purchase cancelled. Re-select the item.")
			return
		end

		-- Re-read numAvailable for the cap rather than trusting the snapshot
		-- — same race-window concern.
		local _, _, _, _, liveAvailable = GetMerchantItemInfo(row.index)
		if liveAvailable and liveAvailable > 0 then
			qty = math.min(qty, liveAvailable)
		end
		BuyRow(row, qty)
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	EditBoxOnEnterPressed = function(self)
		-- Explicit submit; some StaticPopup forks ignore enterClicksFirstButton.
		StaticPopup_OnClick(self:GetParent(), 1)
	end,
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
			-- Pass data as the 4th arg so it's available in OnShow (which
			-- StaticPopup_Show invokes synchronously). Capture the current
			-- itemLink as a fingerprint so OnAccept can detect inventory
			-- reshuffles that would otherwise have us buy the wrong slot.
			local popupData = { row = self.dataRow, link = self.dataRow.link }
			StaticPopup_Show("Coinscry_BUY_QTY", label, nil, popupData)
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
-- Collapsible-section layout. Lifted out of CreatePanel so the filters-header
-- OnClick (wired in BuildFiltersHeader) can call it as an upvalue and the
-- initial-state apply at the end of CreatePanel can share the implementation.
-- Safe to call once panelFrame and the advanced widgets have been built.
-- ============================================================================
local function ApplyCollapsedLayout()
	-- Chevron texture: + when collapsed, - when expanded.
	if filtersChevron then
		filtersChevron:SetTexture(advancedCollapsed
			and "Interface\\Buttons\\UI-PlusButton-Up"
			or "Interface\\Buttons\\UI-MinusButton-Up")
	end
	-- Show/hide all advanced filter widgets.
	for _, w in ipairs(advancedWidgets) do
		if advancedCollapsed then w:Hide() else w:Show() end
	end
	-- The demon dropdown is contextual on top of being advanced; re-run its
	-- initializer when expanding so it stays hidden at vendors without
	-- tomes even though the rest of the section is visible.
	if not advancedCollapsed and InitDemonDropdown then InitDemonDropdown() end
	-- Re-anchor scroll area + header strip to the appropriate y-offset.
	local top = CurrentTopReserved()
	if scrollFrame and panelFrame then
		scrollFrame:ClearAllPoints()
		scrollFrame:SetPoint("TOPLEFT", panelFrame, "TOPLEFT", 10, -top)
		scrollFrame:SetPoint("BOTTOMRIGHT", panelFrame, "BOTTOMRIGHT", -28, BOT_RESERVED - 6)
	end
	if headerRow and panelFrame then
		headerRow:ClearAllPoints()
		headerRow:SetPoint("TOPLEFT", panelFrame, "TOPLEFT", 10, -(top - HEADER_H))
		headerRow:SetPoint("TOPRIGHT", panelFrame, "TOPRIGHT", -28, -(top - HEADER_H))
	end
	Refresh()
end

-- ============================================================================
-- Panel construction. Each Build* helper builds one logical section and
-- stores any widgets it needs to expose into module-level upvalues, so the
-- helpers can stay parameter-light. CreatePanel below is the orchestrator
-- (one call per section + dropdown init + collapsed-state apply).
-- ============================================================================

---Build the panel frame: backdrop, sizing, resize grip + size persistence,
---title, close button.
---@return Frame the constructed panel frame
local function BuildFrame()
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

	resizeGrip = CreateFrame("Button", nil, f)
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
	title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, LAYOUT_Y.title)
	title:SetText("Coinscry")
	title:SetTextColor(1, 0.82, 0)

	closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, LAYOUT_Y.closeBtn)
	closeBtn:SetScript("OnClick", function() Panel.Hide() end)
	NS.UI.ApplyTheme("ApplyToCloseButton", closeBtn)

	return f
end

---Search box (SearchBoxTemplate provides magnifier icon + "Search" placeholder
---+ clear button). Hooks into nameSubstring filter state on text change.
local function BuildSearchBox(f)
	searchBox = CreateFrame("EditBox", "Coinscry_SearchBox", f, "SearchBoxTemplate")
	searchBox:SetPoint("TOPLEFT", f, "TOPLEFT", 16, LAYOUT_Y.searchBox)
	searchBox:SetPoint("TOPRIGHT", f, "TOPRIGHT", -28, LAYOUT_Y.searchBox)
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
end

---Three always-visible filter checkboxes (Can use / Affordable / Hide known).
---Chained left-to-right; each anchors off the previous one's label width so
---they stay visually adjacent regardless of locale.
local function BuildCheckboxRow(f)
	local CHECKBOX_W = 20
	local LABEL_PAD = 4 -- gap between checkbox right edge and label left edge
	local CHAIN_GAP = 16 -- gap between previous label end and next checkbox
	local function MakeFilterCheckbox(text, prevOrX, y, getter, setter)
		local c = CreateFrame("CheckButton", nil, f, "ChatConfigCheckButtonTemplate")
		c:SetSize(CHECKBOX_W, CHECKBOX_W)
		c:SetHitRectInsets(0, 0, 0, 0)
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

	canUseCheck = MakeFilterCheckbox(
		"Can use", 16, LAYOUT_Y.checkboxRow,
		function() return state.canUseOnly end,
		function(v) state.canUseOnly = v end
	)
	affordableCheck = MakeFilterCheckbox(
		"Affordable", canUseCheck, nil,
		function() return state.affordableOnly end,
		function(v) state.affordableOnly = v end
	)
	knownCheck = MakeFilterCheckbox(
		"Hide known", affordableCheck, nil,
		function() return state.hideAlreadyKnown end,
		function(v) state.hideAlreadyKnown = v end
	)
end

---Collapsible "Filters" header button. OnClick toggles `advancedCollapsed`,
---persists it to CoinscryCharDB, and re-applies the collapsed layout via the
---module-level ApplyCollapsedLayout helper.
local function BuildFiltersHeader(f)
	filtersHeaderBtn = CreateFrame("Button", nil, f)
	filtersHeaderBtn:SetSize(110, 20)
	filtersHeaderBtn:SetPoint("TOPLEFT", f, "TOPLEFT", 14, LAYOUT_Y.filtersHeader)
	filtersChevron = filtersHeaderBtn:CreateTexture(nil, "ARTWORK")
	filtersChevron:SetSize(16, 16)
	filtersChevron:SetPoint("LEFT", filtersHeaderBtn, "LEFT", 0, 0)
	filtersHeaderBtn.label = filtersHeaderBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	filtersHeaderBtn.label:SetPoint("LEFT", filtersChevron, "RIGHT", 4, 0)
	filtersHeaderBtn.label:SetText("Filters")
	filtersHeaderBtn.label:SetTextColor(1, 0.82, 0)
	filtersHeaderBtn:SetScript("OnEnter", function(self) self.label:SetTextColor(1, 1, 0.6) end)
	filtersHeaderBtn:SetScript("OnLeave", function(self) self.label:SetTextColor(1, 0.82, 0) end)
	filtersHeaderBtn:SetScript("OnClick", function()
		advancedCollapsed = not advancedCollapsed
		if CoinscryCharDB then CoinscryCharDB.advancedCollapsed = advancedCollapsed end
		ApplyCollapsedLayout()
	end)
end

---Advanced filter widgets (quality, group, type, subtype, ilvl range,
---req-level max, demon-type). All hidden as a group when the Filters header
---is collapsed; populates the module-level `advancedWidgets` list.
local function BuildAdvancedFilters(f)
	-- Row A: Quality + Group dropdowns
	qualityDropdown = CreateFrame("Frame", "Coinscry_QualityDropdown", f, "UIDropDownMenuTemplate")
	qualityDropdown:SetPoint("TOPLEFT", f, "TOPLEFT", 16, LAYOUT_Y.rowA_quality)
	groupDropdown = CreateFrame("Frame", "Coinscry_GroupDropdown", f, "UIDropDownMenuTemplate")
	groupDropdown:SetPoint("TOPLEFT", qualityDropdown, "TOPRIGHT", 12, 0)
	NS.UI.ApplyTheme("ApplyToDropDown", qualityDropdown, 100)
	NS.UI.ApplyTheme("ApplyToDropDown", groupDropdown, 130)

	-- Row B: Type + Subtype dropdowns
	classDropdown = CreateFrame("Frame", "Coinscry_ClassDropdown", f, "UIDropDownMenuTemplate")
	classDropdown:SetPoint("TOPLEFT", f, "TOPLEFT", 16, LAYOUT_Y.rowB_class)
	subclassDropdown = CreateFrame("Frame", "Coinscry_SubclassDropdown", f, "UIDropDownMenuTemplate")
	subclassDropdown:SetPoint("TOPLEFT", classDropdown, "TOPRIGHT", 12, 0)
	NS.UI.ApplyTheme("ApplyToDropDown", classDropdown, 110)
	NS.UI.ApplyTheme("ApplyToDropDown", subclassDropdown, 130)

	-- Row C: ilvl range + req-level max
	local ilvlLabel = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	ilvlLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 26, LAYOUT_Y.rowC_ilvl)
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

	-- Row D: demon-type dropdown (contextual — hidden when vendor has no tomes)
	demonDropdown = CreateFrame("Frame", "Coinscry_DemonDropdown", f, "UIDropDownMenuTemplate")
	demonDropdown:SetPoint("TOPLEFT", f, "TOPLEFT", 16, LAYOUT_Y.rowD_demon)
	NS.UI.ApplyTheme("ApplyToDropDown", demonDropdown, 130)

	-- Track all advanced filter widgets so we can toggle them as a group.
	advancedWidgets = {
		qualityDropdown, groupDropdown,
		classDropdown, subclassDropdown,
		ilvlLabel, ilvlMinBox, dash, ilvlMaxBox, reqLabel, reqLevelMaxBox,
		demonDropdown,
	}
end

---Column header strip above the scroll area. Headers are clickable buttons;
---click toggles sort, second click on the active column flips direction.
---Indicator FontString shows the up/down arrow on the active column.
local function BuildHeaderStrip(f)
	headerRow = CreateFrame("Frame", nil, f)
	headerRow:SetHeight(HEADER_H)
	headerRow:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -(CurrentTopReserved() - HEADER_H))
	headerRow:SetPoint("TOPRIGHT", f, "TOPRIGHT", -28, -(CurrentTopReserved() - HEADER_H))

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
				-- Flip direction. Treat nil as ascending; if explicitly false, flip back to ascending.
				state.sortAscending = (state.sortAscending == false)
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
end

---Scrolling row area: a FauxScrollFrame backed by a MAX_ROWS widget pool, plus
---the bottom-of-panel click-mode hint.
local function BuildScrollArea(f)
	scrollFrame = CreateFrame("ScrollFrame", "Coinscry_ScrollFrame", f, "FauxScrollFrameTemplate")
	scrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -CurrentTopReserved())
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
end

-- ============================================================================
-- Panel
-- ============================================================================

local function CreatePanel()
	state = state or Filters.NewState() -- always start fresh; filters reset per vendor visit

	local f = BuildFrame()
	-- Assign module-level panelFrame early so ApplyCollapsedLayout (called
	-- below, before CreatePanel returns) finds the frame as an upvalue. The
	-- external `panelFrame = CreatePanel()` in Panel.AttachTo becomes a no-op
	-- assignment of the same value.
	panelFrame = f

	BuildSearchBox(f)
	BuildCheckboxRow(f)
	BuildFiltersHeader(f)
	BuildAdvancedFilters(f)
	BuildHeaderStrip(f)
	BuildScrollArea(f)

	InitQualityDropdown()
	InitGroupDropdown()
	InitClassDropdown()
	InitSubclassDropdown()
	InitDemonDropdown()

	-- Initial collapsed-state: load from SavedVariables (default `true` from
	-- the module-level declaration; only override if SavedVariables has an
	-- explicit value).
	if CoinscryCharDB and CoinscryCharDB.advancedCollapsed ~= nil then
		advancedCollapsed = CoinscryCharDB.advancedCollapsed and true or false
	end
	ApplyCollapsedLayout()

	f:Hide()
	return f
end

---@param anchorFrame Frame the vendor frame (MerchantFrame or TSM's); panel anchors past its right edge
-- Display modes:
--   "attached" — panel floats beside the anchor frame (used for TSM's vendor frame)
--   "embedded" — panel replaces MerchantFrame's item grid inside MerchantFrame itself
local displayMode = "attached"
local savedMerchantWidth -- set while embedded; nil otherwise
-- Tracks whether the user has the Coinscry view turned on in embed mode.
-- A click on MerchantFrame's Buyback tab temporarily hides the panel but
-- keeps this flag true so we restore the panel when they switch back to
-- the Merchant tab. Cleared on user-initiated Panel.Hide or merchant close.
local embedToggleOn = false

-- Names of Blizzard MerchantFrame widgets to hide while we're embedded over
-- the item grid. Tabs (Buy/Buyback), money frame, and title stay visible so
-- the user can still switch tabs or read the merchant's name.
local HIDDEN_MERCHANT_WIDGETS = {
	"MerchantNextPageButton", "MerchantPrevPageButton", "MerchantPageText",
	"MerchantBuyBackItem", -- "your last sold item" icon; would otherwise float inside our panel
	-- Repair UI shown at vendors that can repair (armor/weapon vendors).
	-- Same problem as the buyback slot — Blizzard's MerchantFrame_Update
	-- re-shows them on each tick and they float inside our panel.
	"MerchantRepairItemButton", "MerchantRepairAllButton", "MerchantRepairText",
	"MerchantGuildBankRepairButton",
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
	-- Hide our own decorations that don't make sense inside MerchantFrame:
	-- the X-close button (tab toggles the view) and the resize grip (size is
	-- dictated by the merchant frame's content area).
	if closeBtn then closeBtn:Hide() end
	if resizeGrip then resizeGrip:Hide() end
end

local function ExitEmbedMode()
	if not savedMerchantWidth then return end
	if MerchantFrame then MerchantFrame:SetWidth(savedMerchantWidth) end
	savedMerchantWidth = nil
	for _, name in ipairs(HIDDEN_MERCHANT_WIDGETS) do
		local f = _G[name]
		if f and f.Show then f:Show() end
	end
	if closeBtn then closeBtn:Show() end
	if resizeGrip then resizeGrip:Show() end
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

-- Show panel + run vendor-context re-init. Separate from Panel.Show so the
-- MerchantFrame-tab hook can re-show transparently without touching the
-- user-toggle state (embedToggleOn).
--
-- Note: dropdown Init* calls used to live here, but ShowVisible runs on
-- every Buyback↔Merchant tab toggle in embed mode — so the dropdowns got
-- rebuilt on each toggle even though the inventory hadn't changed.
-- Inventory-driven re-init is now triggered by MERCHANT_SHOW /
-- MERCHANT_UPDATE via Panel.OnMerchantInventoryChange().
local function ShowVisible()
	if not panelFrame then return end
	if displayMode == "embedded" then EnterEmbedMode() end
	panelFrame:Show()
	Refresh()
end

local function HideVisible()
	-- Order matters: hide our panel *first*, then exit embed mode.
	-- ExitEmbedMode triggers MerchantFrame_Update, which fires our hook
	-- (OnMerchantFrameUpdate). That hook re-hides MerchantItem1..12 if the
	-- panel is still visible — so if we exited embed first, the merchant
	-- items would be unhidden by ExitEmbedMode and then immediately
	-- re-hidden by the hook, leaving an empty merchant frame after the user
	-- clicked the Coinscry tab to close the view.
	if panelFrame then panelFrame:Hide() end
	if displayMode == "embedded" then ExitEmbedMode() end
end

function Panel.Show()
	if displayMode == "embedded" then embedToggleOn = true end
	ShowVisible()
end

function Panel.Hide()
	if displayMode == "embedded" then embedToggleOn = false end
	HideVisible()
end

function Panel.Toggle()
	if not panelFrame then return end
	if panelFrame:IsShown() then Panel.Hide() else Panel.Show() end
end

-- Hook MerchantFrame_Update once. When the user clicks the Buyback tab, hide
-- our panel so Blizzard's buyback view is visible. When they switch back to
-- the Merchant tab, restore the panel if they had it open.
local function OnMerchantFrameUpdate()
	if displayMode ~= "embedded" then return end
	local mf = _G.MerchantFrame
	local tab = mf and mf.selectedTab or 1
	if tab == 1 then
		-- Merchant tab. Restore panel if user had it open.
		if embedToggleOn and panelFrame and not panelFrame:IsShown() then
			ShowVisible()
		end
		-- Re-hide any widgets Blizzard's MerchantFrame_Update may have
		-- re-shown after we hid them (notably MerchantBuyBackItem, which
		-- the buyback-slot update unhides each refresh). Cheap idempotent
		-- loop; only runs while the panel is actually embedded + visible.
		if panelFrame and panelFrame:IsShown() then
			for _, name in ipairs(HIDDEN_MERCHANT_WIDGETS) do
				local f = _G[name]
				if f and f:IsShown() then f:Hide() end
			end
		end
	else
		-- Buyback (or future tabs). Hide our panel without clearing
		-- embedToggleOn so we can restore when they come back.
		if panelFrame and panelFrame:IsShown() then
			HideVisible()
		end
	end
end

if _G.hooksecurefunc and _G.MerchantFrame_Update then
	hooksecurefunc("MerchantFrame_Update", OnMerchantFrameUpdate)
end

function Panel.GetDisplayMode() return displayMode end

---Called from MERCHANT_SHOW / MERCHANT_UPDATE handlers. Only the demon
---dropdown's visibility depends on the current vendor's inventory (it's
---shown only at vendors selling warlock tomes); the class/subclass/quality
---dropdowns are inventory-agnostic for their *visible* state and lazily
---re-fetch rows when the user opens them, so they don't need a rebuild on
---every inventory change.
function Panel.OnMerchantInventoryChange()
	if not panelFrame then return end
	if demonDropdown and InitDemonDropdown then InitDemonDropdown() end
end

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
