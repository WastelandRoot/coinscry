local _, NS = ...
local Scanner = {}
NS.Scanner = Scanner

local ItemCache = NS.ItemCache

local rows = {}

local function ResolveRow(row)
	if not row.link then return end
	local q, ilvl, minLvl, classID, subclassID = ItemCache.Get(row.link)
	row.quality, row.itemLevel, row.minLevel = q, ilvl, minLvl
	row.classID, row.subclassID = classID, subclassID
	if TSM_API and TSM_API.ToItemString then
		local ok, itemString = pcall(TSM_API.ToItemString, row.link)
		if ok and itemString then
			row.itemString = itemString
			if TSM_API.GetGroupPathByItem then
				local ok2, path = pcall(TSM_API.GetGroupPathByItem, itemString)
				row.groupPath = (ok2 and path) or nil
			end
		end
	end
end

function Scanner.Rescan()
	wipe(rows)
	local n = GetMerchantNumItems() or 0
	for i = 1, n do
		local link = GetMerchantItemLink(i)
		local name, texture, price, stackCount, numAvailable, isUsable, extendedCost =
			GetMerchantItemInfo(i)
		local row = {
			index = i,
			link = link,
			name = name,
			texture = texture,
			price = price or 0,
			stackCount = stackCount or 1,
			numAvailable = numAvailable or -1,
			isUsable = isUsable,
			hasExtendedCost = extendedCost and true or false,
		}
		ResolveRow(row)
		rows[#rows + 1] = row
	end
end

---@return table list of row tables (do not mutate)
function Scanner.GetRows()
	return rows
end

---Re-resolve fields for any row whose itemID just got cached.
function Scanner.OnItemInfoResolved(itemID)
	for _, row in ipairs(rows) do
		if row.link then
			local rowID = GetItemInfoInstant(row.link)
			if rowID == itemID then
				ResolveRow(row)
			end
		end
	end
end

ItemCache.OnResolved(Scanner.OnItemInfoResolved)
