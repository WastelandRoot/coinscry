# Changelog

## v0.4.1 — 2026-05-12

**Patch on top of v0.4.0.**

- **Buyback slot was reappearing inside the embedded view.** Blizzard's `MerchantFrame_Update` re-shows `MerchantBuyBackItem` after our initial `Hide()` whenever the merchant data refreshes. Extended the hook to re-hide our targeted widgets idempotently on every update while embedded and visible.
- **Settings panel trimmed.** Dropped the subtitle hints under the two Behavior checkboxes; they were noise. Lower sections shift back to their pre-hint y-positions.

## v0.4.0 — 2026-05-12

**M3-E — embed Coinscry view inside Blizzard's MerchantFrame in vanilla mode.**

- **Embedded vanilla view.** When a vendor is open without TSM's vendoring UI, clicking the Coinscry tab now *replaces* the Blizzard item grid in-place: MerchantFrame widens to fit, the item buttons + page nav + last-sold buyback icon are hidden, and the filter panel fills that area. Clicking the tab again restores the native grid. TSM4 vendor frame behavior is unchanged (panel still floats beside it).
- **Buyback tab honored.** Clicking Blizzard's *Buyback* tab hides Coinscry's embedded view so the buyback grid is visible; clicking back to *Merchant* restores the panel if you had it open.
- **Auto-show setting clarified.** "Auto-open filter panel when a vendor opens" renamed to "Show Coinscry view on vendor open" with a subtitle clarifying that Blizzard / TSM view shows by default.
- **Reset-filters wording.** "Reset filters when opening a vendor" tweaked to "Clear filters when opening a vendor" plus a subtitle explaining the carry-over alternative.
- Close `×` button and drag-to-resize grip on our panel are hidden in embedded mode (the tab is the toggle; the panel is sized to MerchantFrame). Both return in attached mode.

## v0.3.0 — 2026-05-12

**M3-D — columns, sort, drag-to-resize, qty preview, colored prices.**

- **Column layout.** Rows now display `icon | qty | Name | iLvl | Cost` with a clickable header strip above the scroll area. iLvl is blank for items where it isn't meaningful (food, reagents).
- **Sortable headers.** Click *Item* / *ilvl* / *Cost* to sort ascending by that column; click again to flip to descending. Active column shows a `▲` / `▼` arrow texture next to its label.
- **Drag-to-resize.** Bottom-right grip resizes the panel in both axes. Vertical drag shows more rows; horizontal drag widens the Name column. Min size enforced; resized dimensions persisted per-character in `CoinscryCharDB.panelSize`.
- **Per-row buy-qty preview.** New column between icon and name shows `x1` by default, switches live to `xN` (item's stack size) while Shift is held — preview of what clicking will buy.
- **TSM-style colored prices.** `g` / `s` / `c` denomination letters tinted yellow / silver / copper; digits white. Easier to scan at a glance.

## v0.2.1 — 2026-05-12

Packaging-only release; no functional code changes from v0.2.0.

- README screenshots section.
- TOC: `X-Website` (GitHub) and `X-Curse-Project-ID` for CurseForge.
- `.pkgmeta` + GitHub Action: tag pushes automatically build the zip and publish to CurseForge and GitHub Releases.

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
