local _, NS = ...
local ItemCache = {}
NS.ItemCache = ItemCache

local pending = {}
local listeners = {}

local frame = CreateFrame("Frame")
frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
frame:SetScript("OnEvent", function(_, _, itemID, success)
	if not pending[itemID] then return end
	pending[itemID] = nil
	if success then
		for _, cb in ipairs(listeners) do cb(itemID) end
	end
end)

---Resolve item info. Sync fields (classID, subclassID) always returned if itemID is valid.
---Async fields (quality, itemLevel, minLevel) return nil until WoW caches them; an
---OnResolved listener fires once they're available.
---@param link string|number Item link or itemID
---@return number? quality 0–7 (Poor → Heirloom), nil if uncached
---@return number? itemLevel nil if uncached
---@return number? minLevel required level, nil if uncached
---@return number? classID always sync
---@return number? subclassID always sync
function ItemCache.Get(link)
	if not link then return nil end
	local itemID, _, _, _, _, classID, subclassID = GetItemInfoInstant(link)
	if not itemID then return nil end
	local _, _, quality, itemLevel, minLevel = GetItemInfo(link)
	if quality == nil then
		pending[itemID] = true
		return nil, nil, nil, classID, subclassID
	end
	return quality, itemLevel, minLevel, classID, subclassID
end

---Register a callback fired when any previously-pending item becomes resolved.
function ItemCache.OnResolved(cb)
	table.insert(listeners, cb)
end
