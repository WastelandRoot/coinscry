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
---@field canUseOnly? boolean only show items the player meets level + class/proficiency requirements for
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
		canUseOnly       = nil,
		hideAlreadyKnown = nil,
		demonType        = nil,
	}
end

-- TBC armor proficiency by class file string. Values per (subclassID):
--   true       = can wear at any level
--   <number>   = can wear at level >= <number> (TBC mail/plate gating: Warrior /
--                Paladin get plate at 40, Hunter / Shaman get mail at 40, etc.)
--   nil        = cannot wear
-- subclassIDs:
--   0=Misc/Cosmetic 1=Cloth 2=Leather 3=Mail 4=Plate 6=Shield 7=Libram 8=Idol
--   9=Totem 10=Sigil
local ARMOR_PROFICIENCY = {
	WARRIOR     = { [0] = true, [1] = true, [2] = true, [3] = 40, [4] = 40, [6] = true },
	PALADIN     = { [0] = true, [1] = true, [2] = true, [3] = 40, [4] = 40, [6] = true, [7] = true },
	DEATHKNIGHT = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [10] = true },
	HUNTER      = { [0] = true, [1] = true, [2] = true, [3] = 40 },
	SHAMAN      = { [0] = true, [1] = true, [2] = true, [3] = 40, [6] = true, [9] = true },
	ROGUE       = { [0] = true, [1] = true, [2] = true },
	PRIEST      = { [0] = true, [1] = true },
	MAGE        = { [0] = true, [1] = true },
	WARLOCK     = { [0] = true, [1] = true },
	DRUID       = { [0] = true, [1] = true, [2] = true, [8] = true },
}

-- TBC weapon proficiency by class file string. Includes max-trainable weapon
-- subclasses — anything the class can *eventually* train. Filter intent is
-- "shopping for a weapon I'd want to use later," so we don't gate on the
-- player's current training state (no easy API for that).
-- subclassIDs:
--   0=Axe1H 1=Axe2H 2=Bow 3=Gun 4=Mace1H 5=Mace2H 6=Polearm 7=Sword1H 8=Sword2H
--   10=Stave 13=Fist 15=Dagger 16=Thrown 18=Crossbow 19=Wand 20=FishingPole
-- 20 (FishingPole) is universal; included for every class.
local WEAPON_PROFICIENCY = {
	WARRIOR     = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [7] = true, [8] = true, [10] = true, [13] = true, [15] = true, [16] = true, [18] = true, [20] = true },
	PALADIN     = { [0] = true, [1] = true, [4] = true, [5] = true, [6] = true, [7] = true, [8] = true, [20] = true },
	DEATHKNIGHT = { [0] = true, [1] = true, [4] = true, [5] = true, [6] = true, [7] = true, [8] = true, [20] = true },
	HUNTER      = { [0] = true, [1] = true, [2] = true, [3] = true, [6] = true, [7] = true, [8] = true, [10] = true, [13] = true, [15] = true, [16] = true, [18] = true, [20] = true },
	SHAMAN      = { [0] = true, [1] = true, [4] = true, [5] = true, [10] = true, [13] = true, [15] = true, [20] = true },
	ROGUE       = { [2] = true, [3] = true, [4] = true, [7] = true, [13] = true, [15] = true, [16] = true, [18] = true, [20] = true },
	PRIEST      = { [4] = true, [10] = true, [15] = true, [19] = true, [20] = true },
	MAGE        = { [7] = true, [10] = true, [15] = true, [19] = true, [20] = true },
	WARLOCK     = { [7] = true, [10] = true, [15] = true, [19] = true, [20] = true },
	DRUID       = { [4] = true, [5] = true, [6] = true, [10] = true, [13] = true, [15] = true, [20] = true },
}

local function PlayerLevel()
	return (UnitLevel and UnitLevel("player")) or 1
end

local function PlayerClassFile()
	if not UnitClass then return nil end
	local _, cf = UnitClass("player")
	return cf
end

---Can the player wear this armor row? Returns nil for non-armor (caller treats
---non-armor as not-blocked).
---@param classID? number
---@param subclassID? number
---@return boolean|nil
local function CanWearArmor(classID, subclassID)
	if classID ~= 4 then return nil end -- Enum.ItemClass.Armor
	local cf = PlayerClassFile()
	if not cf then return nil end
	local profs = ARMOR_PROFICIENCY[cf]
	if not profs then return nil end
	local p = profs[subclassID]
	if p == nil then return false end
	if p == true then return true end
	return PlayerLevel() >= p
end

---Can the player ever use this weapon (max-trainable proficiency)? Returns nil
---for non-weapons.
---@param classID? number
---@param subclassID? number
---@return boolean|nil
local function CanUseWeapon(classID, subclassID)
	if classID ~= 2 then return nil end -- Enum.ItemClass.Weapon
	local cf = PlayerClassFile()
	if not cf then return nil end
	local profs = WEAPON_PROFICIENCY[cf]
	if not profs then return nil end
	return profs[subclassID] == true
end

---Can the player use this item right now? Combines:
---  - row.minLevel <= player level
---  - Class armor-proficiency table for Enum.ItemClass.Armor rows
---  - Class weapon-proficiency table (max trainable) for Enum.ItemClass.Weapon rows
---@param row table Scanner row
---@return boolean
function Filters.IsRowUsable(row)
	if not row then return false end
	if row.minLevel and row.minLevel > 0 and PlayerLevel() < row.minLevel then
		return false
	end
	if row.classID and row.subclassID then
		local armor = CanWearArmor(row.classID, row.subclassID)
		if armor == false then return false end
		local weapon = CanUseWeapon(row.classID, row.subclassID)
		if weapon == false then return false end
	end
	return true
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
	if state.canUseOnly then
		if not Filters.IsRowUsable(row) then return false end
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
