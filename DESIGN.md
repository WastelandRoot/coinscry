# tsm-vendor-filter-plus — Design

Status: **draft, pre-implementation** (2026-05-11)
Target client: WoW TBC Anniversary, Interface `20505`
Repo: `git.kal.run/kaltec/tsm-vendor-filter-plus`

---

## 1. Problem statement

TradeSkillMaster's Vendoring → Buy UI ships with a "Filters" button that is a literal TODO in their source:

```lua
-- TradeSkillMaster/Core/UI/VendoringUI/Buy.lua:78-90
:AddChild(UIElements.New("Button", "filterBtn")
    :SetText(FILTERS)
    -- TODO
    -- :SetScript("OnClick", private.FilterButtonOnClick)
)
```

Only the text-search box is functional. There is no way to filter by quality, item class, item level, price, or — most usefully — TSM group membership. Vendor browsing on long lists (e.g., reagent vendors, faction quartermasters) is tedious.

## 2. Goals & non-goals

### Goals
1. Filter vendor items by **quality** (poor → legendary).
2. Filter by **item class / subclass** (Armor/Weapon/Consumable/Trade Goods/Recipe/…).
3. Filter by **item level range** (min / max).
4. Filter by **required character level**.
5. Filter by **TSM group membership** (the unique value-add — no other vendor-filter addon can do this).
6. Toggle "**can afford only**" (gold + extended cost currencies).
7. Work alongside TSM without modifying or forking it.

### Non-goals
- Replacing TSM's vendor UI.
- Filtering Sell or Buyback tabs (Buy only for v1).
- Retail / Wrath / Cata / Mists builds. Single-flavor TBC Anniversary first; multi-flavor is post-1.0.
- Integrating with the user's existing `VendorFilter` addon (third-party, Blizzard merchant frame only). We coexist; we don't combine.

## 3. Critical architectural constraint

**TSM is sealed.** Despite the comprehensive internal architecture (LibTSMUI, ItemInfo, Theme, UIElements, VendorBuyScrollTable), exactly one symbol is global:

```lua
-- TradeSkillMaster/Core/API.lua:26-27
-- luacheck: globals TSM_API
TSM_API = {}
```

Every module — `ItemInfo`, `UIElements`, `Theme`, `VendorBuyScrollTable`, the scanner DB, the Buy frame tree — is reached via `local TSM = select(2, ...)`, which is per-file and **not accessible from outside the TradeSkillMaster addon's own loaded files** (`Core/UI/VendoringUI/Buy.lua:7`, `Core/API.lua:10`, etc.).

What `TSM_API` exposes that matters to us (`Core/API.lua`):
- `TSM_API.IsUIVisible("VENDORING")` (line 58–71) — yes/no on TSM vendor frame visibility.
- `TSM_API.GetGroupPaths(result)` (121) — list all TSM group paths.
- `TSM_API.GetGroupPathByItem(itemString)` (159) — group for an item, or nil.
- `TSM_API.GetGroupItems(path, includeSubGroups, result)` (172) — items in a group.
- `TSM_API.RegisterGroupItemCallback(addonTag, func)` (187) — notification on group changes.
- `TSM_API.ToItemString(item)`, `TSM_API.GetItemName(itemString)`, `TSM_API.GetItemLink(itemString)` (item helpers).

What `TSM_API` does **not** expose:
- ItemInfo for quality/classID/subclassID/itemLevel/requiredLevel. We use WoW's `GetItemInfo` / `GetItemInfoInstant` directly.
- Any way to inject UI into TSM's frames. `RegisterUICallback` exists but is hard-coded to `CRAFTING` only (`Core/API.lua:85-89`).
- The VendoringUI frame tree, scroll table, or query DB.
- TSM's UIElements framework (no way to construct TSM-styled widgets from outside).

### Consequence

**We cannot put filters inside TSM's vendor frame.** Any addon that claims otherwise is either (a) forking TSM, (b) patching TSM's loaded files at runtime (brittle), or (c) lying. This is a real ceiling, set by TSM, not us.

Three escape hatches were considered and rejected:

| Approach | Verdict |
|---|---|
| Fork TSM and patch `Buy.lua`'s filter button. | Rejected. Brittle, every TSM update overwrites it. The user already manages one such patch (tsm-app issue #9) and considers it a maintenance burden. |
| Runtime-patch TSM's loaded files (read `Buy.lua` from disk, eval modifications). | Rejected. Hacky, no way to reach TSM's `private` table from outside, can't access UIElements to build matching widgets. |
| `hooksecurefunc` + `debug.getupvalue` to reach TSM internals. | Rejected. `debug.getupvalue` is unavailable in WoW's addon sandbox. `hooksecurefunc` works on `TSM_API.*` but those don't include UI builders. |

### Adopted approach

**Companion overlay addon.** A floating filter panel that anchors near (not inside) the active vendor UI — TSM's when it's open, Blizzard's `MerchantFrame` when it's not — and feeds a filtered buy list. Items come from WoW's native merchant API (`GetMerchantNumItems`, `GetMerchantItemLink`, `GetMerchantItemInfo`), not TSM's scanner DB. Purchases go through `BuyMerchantItem(index, qty)` directly. Group filter uses `TSM_API.GetGroupPathByItem`.

## 4. Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  WoW Client                                                  │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │  Native merchant data (GetMerchantNumItems, …)          │ │
│  └────────────────┬────────────────────────────────────────┘ │
│                   │                                          │
│  ┌────────────────▼────────────────────────────────────────┐ │
│  │  tsm-vendor-filter-plus                                 │ │
│  │  ┌──────────┐  ┌────────────┐  ┌──────────────────┐    │ │
│  │  │ Scanner  │→ │  Filters   │→ │ Floating panel   │    │ │
│  │  │ (Wow API)│  │  (Lua)     │  │ (custom frame)   │    │ │
│  │  └──────────┘  └─────┬──────┘  └────────┬─────────┘    │ │
│  │                      │                  │              │ │
│  │                      ▼                  ▼              │ │
│  │              ┌───────────────┐   ┌──────────────┐      │ │
│  │              │ TSM_API.Get   │   │ Anchor:      │      │ │
│  │              │ GroupPath…    │   │ TSMVendor    │      │ │
│  │              │ (group only)  │   │ or Merchant  │      │ │
│  │              └───────────────┘   └──────────────┘      │ │
│  └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### Module breakdown (Lua files)

```
tsm-vendor-filter-plus.toc           -- single-flavor, Interface 20505
Core.lua                              -- addon entry, event dispatch, slash commands
Scanner.lua                           -- reads merchant items via WoW API, caches per session
Filters.lua                           -- pure filter predicates (quality, ilvl, class, group, …)
UI/Panel.lua                          -- floating frame, dropdowns, scroll list
UI/Anchor.lua                         -- finds & follows TSM's vendor frame or MerchantFrame
Util/ItemCache.lua                    -- async resolves item info (GetItemInfo queue)
Saved.lua                             -- SavedVariables shape + migration
```

### Event flow

1. **`MERCHANT_SHOW`** fires → `Scanner.Rescan()` builds in-memory list of `{ index, itemLink, itemString, price, stackSize, numAvailable, costItems }`.
2. **`MERCHANT_UPDATE`** fires → re-scan (vendor inventory can change, e.g., after buying limited-supply items).
3. Each row, when not yet resolved, queues a `GetItemInfo(itemID)` call. `GET_ITEM_INFO_RECEIVED` events trigger a refresh of any unresolved rows.
4. `Anchor` polls (`OnUpdate`, throttled to ~4 Hz):
   - If `TSM_API.IsUIVisible("VENDORING")`: find TSM's vendor frame by global frame name (TBD — research needed once installed; see §7) and anchor right of it.
   - Else if `MerchantFrame:IsShown()`: anchor right of MerchantFrame.
   - Else: hide our panel.
5. Filter UI is dropdowns + a scroll list. Filter state changes → `Filters.Apply(scanResults)` → `Panel:Refresh()`.
6. Buy button on a row → `BuyMerchantItem(row.index, qty)`. Shift-click for stack; right-click for quantity dialog.

### Data shape (in-memory)

```lua
ScanRow = {
    index       = 7,                       -- merchant slot
    itemLink    = "|cffa335ee|Hitem:...",
    itemID      = 30183,
    itemString  = "i:30183",               -- via TSM_API.ToItemString
    name        = "Nether Vortex",         -- from GetItemInfo (async)
    quality     = 4,                       -- 0..5 in TBC
    classID     = 7,                       -- ItemClass.Tradegoods
    subclassID  = 4,
    itemLevel   = 70,
    requiredLevel = 70,
    price       = 1500000,                 -- copper (0 if currency-only)
    costItems   = { {itemID=29024, qty=4} },
    stackSize   = 1,
    numAvailable = -1,                     -- -1 = unlimited
    groupPath   = "Crafting>Nether",       -- from TSM_API, nil if ungrouped
}
```

### Filter contract

`Filters.Apply(rows, state) → filteredRows` where `state` is:

```lua
{
    quality       = { min = 2, max = 5 },        -- nil = no filter
    classIDs      = { [2]=true, [4]=true },      -- whitelist; nil = all
    subclassIDs   = nil,                          -- {classID -> {subclassID -> true}}
    itemLevel     = { min = nil, max = nil },
    requiredLevel = { max = nil },
    canAffordOnly = false,
    groupPaths    = { ["Crafting>Nether"] = true }, -- nil = all
}
```

All filter clauses are AND-ed. Within a clause (e.g., classIDs), it's OR (any whitelisted match passes).

## 5. UI sketch

```
┌────────────────────────────────┐     ┌────────────────────────────────┐
│  TSM Vendoring / Merchant      │     │  TSM-VFP                       │
│  (untouched)                   │ →   │  Search: [_______________]     │
│                                │     │  Quality: [Rare+      ▾]       │
│                                │     │  Class:   [Armor      ▾]       │
│                                │     │  Group:   [Vendor Buys ▾]      │
│                                │     │  ☐ Can afford only             │
│                                │     │  ─────────────────────────     │
│                                │     │  [icon] Item name      1500g   │
│                                │     │  [icon] Item name        25g   │
│                                │     │   …                            │
│                                │     │  [Buy 1] [Buy stack]           │
└────────────────────────────────┘     └────────────────────────────────┘
```

- Panel width: ~340px. Resizable vertically.
- Quality dropdown: "Any / Common+ / Uncommon+ / Rare+ / Epic+ / Legendary".
- Class dropdown: lists classes present at *this* vendor (computed from scan), plus "All".
- Group dropdown: lists all TSM groups + a "Multi-select…" sub-menu.
- Visual style: plain Blizzard frame (BackdropTemplate). No attempt to match TSM's Montserrat theme — out of reach without TSM's font/icon registry, and matching badly looks worse than not matching at all.

## 6. Filter list and priorities

| # | Filter | Data source | Priority | Notes |
|---|---|---|---|---|
| F1 | Text search (name) | `GetItemInfo(itemID).name` | P0 | Duplicates TSM's existing one; needed when our panel is the active UI. |
| F2 | Quality min/max | `select(3, GetItemInfo)` | P0 | First filter implemented (vertical-slice anchor). |
| F3 | Item class | `GetItemInfoInstant(itemID)` (sync) | P0 | Drives the class dropdown. |
| F4 | Item subclass | `GetItemInfoInstant(itemID)` | P1 | Nested under class dropdown. |
| F5 | Item level range | `select(4, GetItemInfo)` | P1 | Async; gated until item info resolves. |
| F6 | Required level max | `select(5, GetItemInfo)` | P1 | |
| F7 | TSM group | `TSM_API.GetGroupPathByItem` | P0 | **The unique value-add.** Vertical-slice + 1. |
| F8 | Can afford only | `GetMoney()` + currency reads | P2 | Extended cost items make this nontrivial; defer to v0.4. |
| F9 | "Not in bags" | `TSM_API.GetBagQuantity` | P3 | Convenience for collectors / re-stockers. |

P0 ships in v0.1 vertical slice. P1 in v0.2. P2+ in v0.3+.

## 7. Open questions (resolve during M0 → M1)

1. **TSM vendor frame global name.** TSM creates the frame dynamically; need to identify it in-game (`/dump TSMVendoringUIFrame` etc.) for anchoring. Fallback: anchor to `MerchantFrame` always (it's hidden behind TSM's UI but its position is the same).
2. **Extended cost handling.** `BuyMerchantItem` with currency-cost items — does it trigger Blizzard's confirmation popup, or do we need to call `MerchantFrame_ConfirmExtendedItemCost`? Test in-game.
3. **`numAvailable` semantics in TBC.** Confirm `-1` means unlimited (as TSM treats it) vs. some other value on Anniversary realms.
4. **Group filter scale.** If user has 200+ groups, the dropdown UX needs a search field or hierarchical tree. Defer; punt if first user has <30 groups.
5. **Coexistence with `VendorFilter` addon.** Either disable our panel when `VendorFilter`'s dropdown is set to anything other than "ALL," or do nothing (let them stack). Decide after v0.1 testing.

## 8. Milestones

### M0 — Skeleton (0.5 day)
- TOC, `Core.lua` entry, `MERCHANT_SHOW/HIDE/UPDATE` handlers.
- Slash command `/tvfp` opens/closes panel (visible-only stub).
- Print debug: count of merchant items + TSM vendor visibility.
- **Verifies:** addon loads on TBC Anniversary, events fire, `TSM_API` is reachable.

### M1 — Vertical slice (1–2 days)
- `Scanner.lua` builds the in-memory row list.
- `Util/ItemCache.lua` async-resolves item info.
- `Panel.lua` floats a basic frame with:
  - Quality dropdown (F2)
  - Group dropdown (F7)
  - Scrollable filtered list with Buy buttons
- `Anchor.lua` attaches panel to `MerchantFrame` (TSM frame name discovery deferred to M2).
- **Verifies:** the hard parts (filter pipeline, TSM_API group lookup, BuyMerchantItem) all work end-to-end with two filters. If this slice ships clean, the remaining work is fan-out.

### M2 — Filter fan-out (1 day)
- F1 (text search), F3 (class), F4 (subclass), F5 (item level), F6 (required level).
- Anchor to TSM vendor frame when visible (resolve open question #1).
- SavedVariables: remember last filter state per-character.

### M3 — Polish (0.5 day)
- F8 "can afford only" with extended-cost handling.
- Right-click → quantity dialog. Shift-click → buy stack (when affordable).
- Tooltips on item rows.
- Slash command surface: `/tvfp reset`, `/tvfp show/hide`, `/tvfp anchor [tsm|merchant|auto]`.

### M4 — Optional stretch
- F9 "not in bags."
- Multi-flavor TOC (`_TBC.toc` + retail variant) — only if there's demand.
- Detection / coexistence rule with `VendorFilter`.

## 9. Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| TSM removes `GetGroupPathByItem` or breaks `TSM_API`. | Low (it's their stable public API). | Pin behavior behind a feature check at load; degrade gracefully if missing. |
| TSM's vendor frame's name/position changes across versions. | Medium. | Anchor to `MerchantFrame` by default; opt-in TSM-frame anchoring via slash. |
| Extended-cost items behave unexpectedly with `BuyMerchantItem`. | Medium. | Test on real vendor (e.g., Honor Hold quartermaster) during M1; reuse VendorFilter's `BuyMerchantItem` strategy as reference. |
| Long item-info resolution makes filters feel laggy on first vendor open. | Medium. | Show items as soon as `GetItemInfoInstant` returns (class/subclass sync); update rows when `GET_ITEM_INFO_RECEIVED` fills in details. Sort stability matters here. |
| User's existing `VendorFilter` and this addon both modify the merchant flow. | Low (different frames, but overlap if `VendorFilter` is set to "ALL"). | Document coexistence; possibly detect at load and warn. |
| TSM rewrites Vendoring UI in a future version and lands their own filter button. | Low–medium. | This addon becomes obsolete by design at that point. Acceptable. |

## 10. Out-of-scope decisions captured for later

- **Localization.** English-only for v0.x. Move strings to a Locale table in v1.0 if anyone else uses the addon.
- **Saved-variable migrations.** Single-version schema for v0.x; introduce a `version` field once a breaking change is needed.
- **Packaging.** No `.pkgmeta` / CurseForge release in v0.x. Repo clone or zip-from-Forgejo only.
- **Telemetry.** None. WoW addons don't get analytics without violating the API.

## 11. Definition of "v0.1 done"

- Load the addon at a vendor with TSM open.
- Open the panel via `/tvfp`.
- Set Quality = Rare+, see only rare+ items.
- Set Group = "<some TSM group>", see only items in that group.
- Click an item's Buy button, get the item, gold goes down, panel refreshes.
- No errors in BugSack/BugGrabber across a 20-minute vendor session at three different vendors (general goods, reagent vendor, faction quartermaster).

That's the bar. Everything past that is fan-out and polish.
