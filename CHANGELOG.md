# Changelog

## v0.2.0 — 2026-05-12

Renamed from `tsm-vendor-filter-plus` to **Coinscry**. All public symbols, slash commands, and SavedVariables renamed accordingly:

- Slash command `/tvfp` → `/coinscry`
- SavedVariables `TSMVFPDB` / `TSMVFPCharDB` → `CoinscryDB` / `CoinscryCharDB` (existing users will see settings reset to defaults on first load; re-toggle via `/coinscry config`)
- Folder, .toc file, frame globals all match the new name

Other changes in this release:

- **Tab logo + AddOns list icon**: addon now ships with a magnifying-glass-over-coins TGA logo, replacing the placeholder "F" letter.
- **Filter checkboxes**: rewritten layout that constrains hit-rects so adjacent checkboxes don't swallow each other's clicks.
- **Can use filter**: switched from a hardcoded class/proficiency table to reading WoW's own `GetMerchantItemInfo.isUsable` flag — matches whatever WoW colors red in the merchant frame.

## v0.1.x — 2026-05-11

Initial feature-complete release (as `tsm-vendor-filter-plus`). Feature set:

- Side tab + slide-out filter panel attached to the merchant frame
- Dual anchor: follows TSM's vendor frame when visible, Blizzard's merchant frame otherwise
- Filters: search, quality, item-type/subtype, item-level range, required-level max, TSM group, affordable, can-use, hide-already-known, demon-type (warlock-tome contextual)
- ElvUI theme support, auto-detected at load
- Left/shift-left/right-click buying with quantity-dialog popup on right-click
- Settings panel via `/coinscry config` and Interface → AddOns
- Live refresh on `PLAYER_MONEY`, `BAG_UPDATE_DELAYED`, `CURRENCY_DISPLAY_UPDATE`, `SPELLS_CHANGED`
- Anchor pinning (`/coinscry anchor`) for setups where auto-detection misses
- Diagnostic slash commands: `status`, `poll`, `dump`, `scan`, `groups`, `debug`, `theme`, `trace`
