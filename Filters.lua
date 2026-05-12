local _, NS = ...
local Filters = {}
NS.Filters = Filters

---@class FilterState
---@field qualityMin? number
---@field groupPath? string TSM group path; exact match
---@field nameSubstring? string case-insensitive substring of row.name
---@field classID? number Enum.ItemClass value
---@field subclassID? number subclass within classID (ignored if classID nil)
---@field ilvlMin? number row.itemLevel must be >= this
---@field ilvlMax? number row.itemLevel must be <= this
---@field reqLevelMax? number row.minLevel must be <= this
---@field affordableOnly? boolean only show items the player can afford right now
---@field hideAlreadyKnown? boolean hide spell-teaching items the player or current pet already knows
---@field demonType? string only show warlock-tome rows whose Teaches line names this demon (Imp/Voidwalker/Felhunter/Succubus/Felguard)

---Default empty filter state — no filters applied.
function Filters.NewState()
	return {
		qualityMin       = nil,
		groupPath        = nil,
		nameSubstring    = nil,
		classID          = nil,
		subclassID       = nil,
		ilvlMin          = nil,
		ilvlMax          = nil,
		reqLevelMax      = nil,
		affordableOnly   = nil,
		hideAlreadyKnown = nil,
		demonType        = nil,
	}
end

---Can the player afford row right now (gold + any extended currency/item cost)?
---@param row table Scanner row (must have .index, .price)
---@return boolean
function Filters.IsRowAffordable(row)
	if not row or not row.index then return true end
	if (row.price or 0) > 0 then
		if (GetMoney() or 0) < row.price then return false end
	end
	local costCount = GetMerchantItemCostInfo and GetMerchantItemCostInfo(row.index) or 0
	for i = 1, costCount do
		local _, requiredAmount, link = GetMerchantItemCostItem(row.index, i)
		if requiredAmount and requiredAmount > 0 then
			local have = 0
			if link then
				local currencyID = link:match("currency:(%d+)")
				if currencyID and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
					local info = C_CurrencyInfo.GetCurrencyInfo(tonumber(currencyID))
					have = (info and info.quantity) or 0
				else
					local itemID = link:match("item:(%d+)")
					if itemID and GetItemCount then
						have = GetItemCount(tonumber(itemID)) or 0
					end
				end
			end
			if have < requiredAmount then return false end
		end
	end
	return true
end

---Does this row teach a spell the player or current pet already knows?
---Backed by Scanner's tooltip scan for the "Already known" line, which is
---what WoW itself uses to render the tooltip warning. Reliable for player
---spells, pet spells (currently summoned only), and profession recipes.
---@param row table Scanner row (Scanner.Rescan populates .alreadyKnown)
---@return boolean
function Filters.IsRowAlreadyKnown(row)
	return row and row.alreadyKnown == true
end

---@param row table Scanner row
---@param state FilterState
---@return boolean true if row passes all active filters
local function MatchOne(row, state)
	if state.qualityMin ~= nil then
		if row.quality == nil or row.quality < state.qualityMin then return false end
	end
	if state.groupPath ~= nil then
		if row.groupPath ~= state.groupPath then return false end
	end
	if state.nameSubstring and state.nameSubstring ~= "" then
		if not row.name then return false end
		if not row.name:lower():find(state.nameSubstring:lower(), 1, true) then return false end
	end
	if state.classID ~= nil then
		if row.classID ~= state.classID then return false end
		if state.subclassID ~= nil and row.subclassID ~= state.subclassID then return false end
	end
	if state.ilvlMin ~= nil then
		if not row.itemLevel or row.itemLevel < state.ilvlMin then return false end
	end
	if state.ilvlMax ~= nil then
		if not row.itemLevel or row.itemLevel > state.ilvlMax then return false end
	end
	if state.reqLevelMax ~= nil then
		if row.minLevel and row.minLevel > state.reqLevelMax then return false end
	end
	if state.affordableOnly then
		if not Filters.IsRowAffordable(row) then return false end
	end
	if state.hideAlreadyKnown then
		if Filters.IsRowAlreadyKnown(row) then return false end
	end
	if state.demonType ~= nil then
		if row.demonType ~= state.demonType then return false end
	end
	return true
end

---Distinct demon types present in the scan. Used by the panel to decide
---whether to show the demon-type dropdown.
---@return table demons[name] = true
function Filters.AvailableDemons(rows)
	local d = {}
	for _, row in ipairs(rows) do
		if row.demonType then d[row.demonType] = true end
	end
	return d
end

---@param rows table list from Scanner.GetRows()
---@param state FilterState
---@param out? table optional table to reuse; will be wiped
---@return table filtered rows
function Filters.Apply(rows, state, out)
	out = out or {}
	wipe(out)
	for _, row in ipairs(rows) do
		if MatchOne(row, state) then
			out[#out + 1] = row
		end
	end
	return out
end

---Distinct (classID, subclassID) pairs present in the scan, used to populate dropdowns.
---@return table classes[classID] = { [subclassID] = true }
function Filters.AvailableClasses(rows)
	local classes = {}
	for _, row in ipairs(rows) do
		if row.classID then
			classes[row.classID] = classes[row.classID] or {}
			if row.subclassID then
				classes[row.classID][row.subclassID] = true
			end
		end
	end
	return classes
end
