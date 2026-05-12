local _, NS = ...
local Scanner = {}
NS.Scanner = Scanner

local ItemCache = NS.ItemCache

local rows = {}

-- Hidden tooltip used to detect WoW's own "Already known" line and the
-- "Teaches <Demon>..." line on warlock demon tomes. The known line covers
-- profession recipes, demon tomes (current pet), and generic spell-teaching
-- items — far more reliable than matching GetItemSpell to IsSpellKnown.
local DEMON_NAMES = {
	Imp        = true,
	Voidwalker = true,
	Succubus   = true,
	Felhunter  = true,
	Felguard   = true,
}

local scanTip
---@param link string item link
---@return boolean alreadyKnown
---@return string? demonType one of the DEMON_NAMES keys, or nil
local function ScanItemDetails(link)
	if not link then return false, nil end
	if not scanTip then
		scanTip = CreateFrame("GameTooltip", "Coinscry_Scanner", UIParent, "GameTooltipTemplate")
		scanTip:SetOwner(UIParent, "ANCHOR_NONE")
	end
	scanTip:ClearLines()
	if not pcall(function() scanTip:SetHyperlink(link) end) then return false, nil end
	local known = false
	local demon = nil
	local target = _G.ITEM_SPELL_KNOWN or "Already known"
	for i = 1, scanTip:NumLines() do
		local fs = _G["Coinscry_ScannerTextLeft" .. i]
		if fs then
			local text = fs:GetText() or ""
			if text == target then known = true end
			local captured = text:match("Teaches (%S+)")
			if captured and DEMON_NAMES[captured] then demon = captured end
		end
	end
	return known, demon
end

local function ResolveRow(row)
	if not row.link then return end
	local q, ilvl, minLvl, classID, subclassID = ItemCache.Get(row.link)
	row.quality, row.itemLevel, row.minLevel = q, ilvl, minLvl
	row.classID, row.subclassID = classID, subclassID
	row.alreadyKnown, row.demonType = ScanItemDetails(row.link)
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
		-- Retail-era signature (Anniversary): name, texture, price, stackCount,
		-- numAvailable, isPurchasable, isUsable, extendedCost. isPurchasable is
		-- always true for items at a vendor, so reading position 6 as isUsable
		-- always came back truthy. The actual "can use" flag is position 7.
		local name, texture, price, stackCount, numAvailable, _, isUsable =
			GetMerchantItemInfo(i)
		-- GetMerchantItemCostInfo gives the count of *currency/token* costs;
		-- the `extendedCost` flag from GetMerchantItemInfo is unreliable (flags non-currency oddities too).
		local costCount = GetMerchantItemCostInfo(i) or 0
		local row = {
			index = i,
			link = link,
			name = name,
			texture = texture,
			price = price or 0,
			stackCount = stackCount or 1,
			numAvailable = numAvailable or -1,
			isUsable = isUsable,
			hasExtendedCost = costCount > 0,
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
