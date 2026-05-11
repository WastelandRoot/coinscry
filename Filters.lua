local _, NS = ...
local Filters = {}
NS.Filters = Filters

---@class FilterState
---@field qualityMin? number row.quality must be >= this
---@field groupPath? string row.groupPath must equal this exactly (TSM-only)
---@field nameSubstring? string case-insensitive substring of row.name

---Default empty filter state — no filters applied.
function Filters.NewState()
	return {
		qualityMin = nil,
		groupPath = nil,
		nameSubstring = nil,
	}
end

---@param row table Scanner row
---@param state FilterState
---@return boolean true if row passes all active filters
local function MatchOne(row, state)
	if state.qualityMin ~= nil then
		if row.quality == nil or row.quality < state.qualityMin then
			return false
		end
	end
	if state.groupPath ~= nil then
		if row.groupPath ~= state.groupPath then
			return false
		end
	end
	if state.nameSubstring and state.nameSubstring ~= "" then
		if not row.name then return false end
		if not row.name:lower():find(state.nameSubstring:lower(), 1, true) then
			return false
		end
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
