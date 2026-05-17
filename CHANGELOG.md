# Changelog

## v0.5.4 — 2026-05-16

**Internal refactor — no user-visible changes.** Second in the contributor-prep series after v0.5.1.

- **`CreatePanel` split into `Build*` helpers.** The ~280-line block became a ~20-line orchestrator calling `BuildFrame` / `BuildSearchBox` / `BuildCheckboxRow` / `BuildFiltersHeader` / `BuildAdvancedFilters` / `BuildHeaderStrip` / `BuildScrollArea`. Each helper is short enough to read end-to-end and now carries its own doc comment.
- **`ApplyCollapsedLayout` lifted to module scope.** Was a closure inside `CreatePanel`; pulling it out lets the filters-header `OnClick` and the initial-apply share one implementation instead of redefining it on every panel creation.
- **Y-offset magic numbers centralized.** The scattered `-32` / `-58` / `-82` / `-100` / `-130` / `-162` / `-190` y-offsets in `CreatePanel` are now a single `LAYOUT_Y` table near the top of `UI/Panel.lua`, with a comment tying them to the `TOP_RESERVED_*` collapse-state constants.

## v0.5.3 — 2026-05-16

**Right-click qty dialog hardening.** Three latent bugs in the right-click quantity-buy popup, found during the v0.5.1/v0.5.2 contributor-prep review.

- **Default qty in the dialog was always 1.** `dialog.data` was assigned *after* `StaticPopup_Show` returned, but `StaticPopup_Show` invokes `OnShow` synchronously — so by the time `OnShow` read `self.data` for the row's stackCount, the field was still nil (or worse, the stale row from a previous right-click). The default fell through to `1` and the `numAvailable` cap in `OnShow` silently no-op'd. Data is now passed as the documented 4th arg to `StaticPopup_Show`.
- **Buy-wrong-item race.** If `MERCHANT_UPDATE` fired between right-click and accept, `Scanner.Rescan()` would `wipe()` the row table; the popup still held a reference to the old row, but `row.index` could now point at a different merchant slot. `OnAccept` now verifies the slot's current itemLink against a fingerprint captured at right-click time and aborts the purchase with a chat message if they don't match. The `numAvailable` cap is also re-read live rather than trusted from the snapshot.
- **Popup outlived its merchant.** Closing the merchant window left the right-click dialog open; accepting it after walking to a different vendor would fire `BuyMerchantItem` against an unrelated slot. `MERCHANT_CLOSED` now dismisses the dialog.
- **Enter-to-submit reliability.** `enterClicksFirstButton` isn't honored by every classic-derived StaticPopup fork. Added an explicit `EditBoxOnEnterPressed` handler as a fallback.

## v0.5.2 — 2026-05-12

**Bug fix.**

- **"Internal Bag Error" when right-click qty > stackSize.** Asking the right-click quantity dialog for more than one natural stack of an item (e.g. 35 meat at a vendor where meat stacks to 20) caused WoW to refuse the purchase entirely with an "Internal Bag Error" — no items bought even though bag space was available. `BuyMerchantItem` caps at one stack per call; the buy path now splits into stackSize-sized chunks so multi-stack purchases work as expected. Shift-left-click is unchanged (it was already passing exactly one stack).

## v0.5.1 — 2026-05-12

**Hardening release before opening the project to outside contributors. No user-visible features.**

- **Perf: dropdowns no longer rebuild on every panel show.** `Panel.ShowVisible` was re-running `InitClassDropdown` / `InitSubclassDropdown` / `InitDemonDropdown` every time the panel surfaced — including the Buyback↔Merchant tab toggle in embed mode, which was wasteful since the merchant inventory hadn't changed. Inventory-driven re-init now hooks `MERCHANT_SHOW` / `MERCHANT_UPDATE` via a new `Panel.OnMerchantInventoryChange()` export, and only the demon dropdown (whose visibility depends on what the vendor sells) rebuilds.
- **Repo: GitHub issue forms** for bug reports and feature requests (`.github/ISSUE_TEMPLATE/`). Required fields catch the things I'd normally have to ask about first.
- **Repo: luacheck CI** runs on every push and PR (`.github/workflows/lint.yml`). `.luacheckrc` declares the addon's own globals; reads of Blizzard API surface are tolerated.
- **Repo: `CONTRIBUTING.md`** with setup, style, lint, manual-test matrix, and PR guidance.
- **Repo: `ROADMAP.md`** sketching four candidate features for a future v0.6 (TSM market-value column, wishlist, stack-buy planner, filter presets).

## v0.5.0 — 2026-05-12

**M3-F — collapsible filters + tighter default layout.**

- **Search + checkboxes always on top.** The search box and the three usage checkboxes (Can use / Affordable / Hide known) now live above a new **Filters** header and are always visible. The remaining controls (quality, group, type/subtype, ilvl, req lvl, demon type) collapse behind that header — click it to expand, click again to collapse. Default state is collapsed; toggle state persists per character.
- **Embed mode: repair widgets hidden.** Vendors that repair were leaking `MerchantRepairItemButton` / `MerchantRepairAllButton` / `MerchantRepairText` icons through the embedded panel; added them to the embed-mode hide list alongside the buyback slot.
- **Embed mode: closing via the tab restores merchant items.** Toggling Coinscry off via the side tab was leaving MerchantFrame visible but empty. Order-of-operations bug between `ExitEmbedMode` and our `MerchantFrame_Update` hook; fixed.
- **README screenshots refreshed** for the embedded vanilla mode and the new compact-by-default layout.

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
