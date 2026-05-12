-- luacheck configuration for Coinscry.
-- Run via: luacheck . (or via the lint.yml GitHub Action).
--
-- The WoW UI runtime exposes a huge number of globals. Rather than
-- enumerate every single one we use, we mark the ones the addon owns
-- (read = false → writes are also allowed) and tell luacheck not to
-- complain about *reading* any other unknown global. That keeps the
-- linter useful for typo-detection without drowning in noise about
-- Blizzard APIs.

std = "lua51"

-- Globals the addon defines / owns (writes allowed). Frames created via
-- CreateFrame(name, ...) end up in _G[name] but aren't lexically assigned,
-- so they don't need to be listed here.
globals = {
	"CoinscryDB",      -- account-wide SavedVariables
	"CoinscryCharDB",  -- per-character SavedVariables
	"SLASH_COINSCRY1", -- slash-command registration
	"SlashCmdList",    -- slash-command callback table (assigned key)
}

-- WoW API surface — too large to enumerate exhaustively. Allow reads of
-- any unknown global; flag *writes* to undeclared globals (those are
-- usually typos).
read_globals = { }

-- Catch-all: tolerate Blizzard's enormous global API and addon-namespace
-- conventions without per-symbol declarations.
ignore = {
	"113", -- accessing undefined variable (let WoW API reads through)
	"143", -- accessing undefined field of a global variable
	"212/self", -- unused argument self
	"212/...", -- unused varargs
	"542", -- empty if branch
}

-- The addon namespace argument that comes in via the loader: most files
-- start with `local ADDON, NS = ...`. Allow that.
self = false
unused_args = false
max_line_length = false
max_string_line_length = false
max_comment_line_length = false

