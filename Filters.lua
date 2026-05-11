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

---Default empty filter state — no filters applied.
function Filters.NewState()
	return {
		qualityMin    = nil,
		groupPath     = nil,
		nameSubstring = nil,
		classID       = nil,
		subclassID    = nil,
		ilvlMin       = nil,
		ilvlMax       = nil,
		reqLevelMax   = nil,
	}
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
	return true
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
