local _, NS = ...
NS.UI = NS.UI or {}
NS.UI.Themes = NS.UI.Themes or {}
local Theme = {}
NS.UI.Themes.ElvUI = Theme

-- ElvUI exposes its addon-table as a global array: { E, L, V, P, G }.
-- Skinning lives on E.Skins (often aliased as S internally). We're lenient:
-- if ElvUI isn't fully loaded yet at first use, IsActive() returns false and
-- the theme is silently inactive for that session.

local function GetSkins()
	-- Don't rely on IsAddOnLoaded — it was moved to C_AddOns.IsAddOnLoaded in
	-- retail-era clients (and TBC Anniversary inherits that). Existence of the
	-- _G.ElvUI engine table with a Skins member is the only signal we need.
	local raw = _G.ElvUI
	if type(raw) ~= "table" then return nil end
	local E = raw[1]
	if type(E) ~= "table" then return nil end
	return E.Skins
end

function Theme.IsActive()
	return GetSkins() ~= nil
end

-- ElvUI's Skin handlers occasionally error on frames they don't expect; pcall
-- around each call so a single skin failure doesn't crash widget creation.
local function safeCall(method, ...)
	local S = GetSkins()
	if not S or not S[method] then return end
	pcall(S[method], S, ...)
end

function Theme.ApplyToPanel(frame)        safeCall("HandleFrame", frame, true) end
function Theme.ApplyToButton(button)      safeCall("HandleButton", button) end
function Theme.ApplyToTab(button)         safeCall("HandleButton", button) end
function Theme.ApplyToCloseButton(button) safeCall("HandleCloseButton", button) end
function Theme.ApplyToEditBox(editBox)    safeCall("HandleEditBox", editBox) end
function Theme.ApplyToDropDown(dropdown)  safeCall("HandleDropDownBox", dropdown) end
function Theme.ApplyToScrollBar(scroll)   safeCall("HandleScrollBar", scroll) end

-- Convenience: apply Default then layer ElvUI on top if active. Tab/Panel
-- call this rather than touching either theme directly.
function NS.UI.ApplyTheme(method, ...)
	local d = NS.UI.Themes.Default
	if d and d[method] then d[method](...) end
	if Theme.IsActive() and Theme[method] then Theme[method](...) end
end
