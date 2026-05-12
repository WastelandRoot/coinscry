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

local function GetEMedia()
	local raw = _G.ElvUI
	if type(raw) ~= "table" then return nil end
	local E = raw[1]
	return E and E.media or nil
end

function Theme.ApplyToPanel(frame)
	safeCall("HandleFrame", frame, true)
	-- ElvUI's default backdrop is semi-transparent; force opaque so the world
	-- doesn't bleed through our panel (matches the default theme's look).
	if frame.backdrop and frame.backdrop.SetBackdropColor then
		local m = GetEMedia()
		local c = (m and m.backdropcolor) or { 0.06, 0.06, 0.06 }
		pcall(frame.backdrop.SetBackdropColor, frame.backdrop, c[1] or 0.06, c[2] or 0.06, c[3] or 0.06, 1)
	end
end
function Theme.ApplyToButton(button)      safeCall("HandleButton", button) end

function Theme.ApplyToTab(button)
	safeCall("HandleButton", button)
	-- ElvUI's HandleButton uses button:SetTemplate(...) by default, which puts
	-- the backdrop on the button itself (no button.backdrop child). So we set
	-- the color directly on the button. Cover the .backdrop case too in case a
	-- future ElvUI version switches to CreateBackdrop.
	local m = GetEMedia()
	local c = (m and m.backdropcolor) or { 0.06, 0.06, 0.06 }
	local r, g, b = c[1] or 0.06, c[2] or 0.06, c[3] or 0.06
	if button.SetBackdropColor then
		pcall(button.SetBackdropColor, button, r, g, b, 1)
	end
	if button.backdrop and button.backdrop.SetBackdropColor then
		pcall(button.backdrop.SetBackdropColor, button.backdrop, r, g, b, 1)
	end
end
function Theme.ApplyToCloseButton(button) safeCall("HandleCloseButton", button) end
function Theme.ApplyToEditBox(editBox)    safeCall("HandleEditBox", editBox) end
function Theme.ApplyToScrollBar(scroll)   safeCall("HandleScrollBar", scroll) end

function Theme.ApplyToDropDown(dropdown, width)
	safeCall("HandleDropDownBox", dropdown, width)
	-- Extend the underlying click target to span the visible flat box.
	-- ElvUI doesn't resize <name>Button; without this, only the small original
	-- area on the right edge is clickable (~16px), which is unintuitive.
	local name = dropdown.GetName and dropdown:GetName() or nil
	local btn = name and _G[name .. "Button"] or nil
	if btn then
		btn:ClearAllPoints()
		btn:SetPoint("TOPLEFT", dropdown, "TOPLEFT", 18, -2)
		btn:SetPoint("BOTTOMRIGHT", dropdown, "BOTTOMRIGHT", -2, 2)
	end
end

-- Convenience: apply Default then layer ElvUI on top if active. Tab/Panel
-- call this rather than touching either theme directly.
function NS.UI.ApplyTheme(method, ...)
	local d = NS.UI.Themes.Default
	if d and d[method] then d[method](...) end
	if Theme.IsActive() and Theme[method] then Theme[method](...) end
end
