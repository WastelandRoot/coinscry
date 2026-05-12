# coinscry — Design

Status: **draft, pre-implementation** (2026-05-11)
Target client: WoW TBC Anniversary, Interface `20505`
Repo: `git.kal.run/kaltec/coinscry`

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
5. Filter by **TSM group membership** (the unique value-add — no other vendor-filter addon can do this). Active only when TSM is loaded.
6. Toggle "**can afford only**" (gold + extended cost currencies).
7. Work alongside TSM without modifying or forking it.
8. **Function standalone without TSM.** TSM is the primary integration target (and the headline feature), but is a soft dependency. With no TSM loaded: filters F1–F4, F6, F8 still work; F5 (group) is hidden. The addon attaches to `MerchantFrame` only.

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

**Side-tab + slide-out panel.** Visual idiom borrowed from Clique and WhatsTraining: a small tab juts out of the left edge of the active vendor frame; clicking it expands a filter panel to the left. The tab persists on the frame; the panel is hidden by default and remembered per-character.

**Both vendor frames are always present (when TSM is loaded).** TSM's vendor window doesn't *hide* `MerchantFrame` — it covers it. So the question isn't "which frame exists" but "which frame is on top right now." When `TSM_API.IsUIVisible("VENDORING")` is true, our tab anchors to TSM's vendor frame; otherwise it anchors to `MerchantFrame`. The tab itself migrates between anchors as visibility flips.

**Without TSM loaded**, the addon falls back to `MerchantFrame` as the only anchor. The group dropdown is hidden; all other filters work identically. This is enforced once at load (`CheckTSM()`) — there's no runtime mode switching.

Data comes from WoW's native merchant API (`GetMerchantNumItems`, `GetMerchantItemLink`, `GetMerchantItemInfo`), not TSM's scanner DB. Purchases go through `BuyMerchantItem(index, qty)` directly. Group filter uses `TSM_API.GetGroupPathByItem` and is the only feature that touches `TSM_API`.

## 4. Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  WoW Client                                                  │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │  Native merchant data (GetMerchantNumItems, …)          │ │
│  └────────────────┬────────────────────────────────────────┘ │
│                   │                                          │
│  ┌────────────────▼────────────────────────────────────────┐ │
│  │  coinscry                                 │ │
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
coinscry.toc           -- single-flavor, Interface 20505
Core.lua                              -- addon entry, event dispatch, slash commands
Scanner.lua                           -- reads merchant items via WoW API, caches per session
Filters.lua                           -- pure filter predicates (quality, ilvl, class, group, …)
UI/Tab.lua                            -- the side tab (button) that lives on the vendor frame
UI/Panel.lua                          -- the slide-out panel: dropdowns + scroll list
UI/Anchor.lua                         -- decides which frame the tab/panel attach to (TSM vs MerchantFrame)
UI/Themes/Default.lua                 -- vanilla Blizzard skin (backdrop, fonts, textures)
UI/Themes/ElvUI.lua                   -- ElvUI skin (StripTextures + Backdrop) — loaded only if ElvUI present
Util/ItemCache.lua                    -- async resolves item info (GetItemInfo queue)
Saved.lua                             -- SavedVariables shape + migration
```

### Event flow

1. **`MERCHANT_SHOW`** fires → `Scanner.Rescan()` builds in-memory list of `{ index, itemLink, itemString, price, stackSize, numAvailable, costItems }`. `Anchor.Reattach()` runs to place the tab on the right frame.
2. **`MERCHANT_UPDATE`** fires → re-scan (vendor inventory can change, e.g., after buying limited-supply items).
3. **`MERCHANT_CLOSED`** → tab + panel hide.
4. Each row, when not yet resolved, queues a `GetItemInfo(itemID)` call. `GET_ITEM_INFO_RECEIVED` events trigger a refresh of any unresolved rows.
5. `Anchor` listens for TSM-vendor visibility transitions. Since TSM doesn't expose an event for this, we poll via `OnUpdate` throttled to ~4 Hz **while the merchant is open**:
   - If `TSM_API.IsUIVisible("VENDORING")` and the anchor isn't already TSM's frame: reparent the tab to TSM's frame.
   - Else if `MerchantFrame:IsShown()` and the anchor isn't already MerchantFrame: reparent the tab to MerchantFrame.
   - Else (merchant closed entirely): hide tab + panel, stop polling.
6. Tab click → `Panel:Toggle()`. Panel slide direction depends on free space (left by default; right if covered by ChatFrame/etc.).
7. Filter UI is dropdowns + a scroll list. Filter state changes → `Filters.Apply(scanResults)` → `Panel:Refresh()`.
8. Buy button on a row → `BuyMerchantItem(row.index, qty)`. Shift-click for stack; right-click for quantity dialog.

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

## 5. UI: side tab + slide-out panel

### Idiom

WhatsTraining and Clique both add a left-side tab to an existing Blizzard frame. WhatsTraining (`WhatsTrainingUI.lua:192–225`) gets it cheap by hijacking `SpellBookSkillLineTab` — a Blizzard-provided tab strip on the SpellBook frame. `MerchantFrame` exposes no such strip, so we build the tab ourselves. The closest reusable visual reference is the `PaperDollSidebar`-style tab (PaperDollFrame's character/inventory/skills tabs on the left edge).

### Tab

- A `Button` frame parented to the active vendor frame (the *anchor*; see §4).
- Anchored `TOPRIGHT` to the anchor's `TOPLEFT`, with a small Y-offset (~-32px below the title bar).
- Texture: a vertical "tab" graphic — 32x64ish — with our addon icon centered, rotated for the orientation. We ship our own texture in `Media/`.
- States: normal / highlighted (on mouseover) / pushed (panel open). Tooltip on hover: "Coinscry — vendor filters".
- Click → `Panel:Toggle()`.

### Panel

- A `Frame` parented to the tab. Anchored `TOPRIGHT` to the tab's `TOPLEFT` so it expands leftward.
- Width ~340px; height matches anchor's height. Optional `OnUpdate` to track anchor resize (TSM's frame can be resized).
- Layout:

```
┌──────────────────────────────┐                   ┌──┐
│  Coinscry                  [×]│                   │  │
│  Search: [_______________]   │                   │  │
│  Quality:  [Rare+        ▾]  │                   │T │ <— tab on the right edge
│  Class:    [Armor        ▾]  │                   │S │     (panel sits to its left;
│  Subclass: [Mail         ▾]  │                   │M │      tab is glued to the
│  Group:    [Vendor Buys  ▾]  │                   │V │      anchor frame)
│  iLvl:     [__] – [__]       │                   │F │
│  ☐ Can afford only           │                   │P │
│  ────────────────────────────│                   │  │
│  [icon] Item name      1500g │                   │  │
│  [icon] Item name        25g │                   │  │
│   …                          │                   │  │
└──────────────────────────────┘                   └──┘
                                                   ↑
                          parent vendor frame (TSM or MerchantFrame)
```

- Quality dropdown: "Any / Common+ / Uncommon+ / Rare+ / Epic+ / Legendary".
- Class dropdown: lists classes present at *this* vendor (computed from scan), plus "All". Subclass dropdown appears when a class is selected.
- Group dropdown: lists all TSM groups + a "Multi-select…" sub-menu.
- Item row: `[icon] [name colored by quality] [price/cost]` + Buy button. Right-click → quantity dialog.

### Theming

We support two themes detected at load:

**Default (vanilla Blizzard).** Standard `BackdropTemplate` with the "Tooltip-Border" backdrop, `GameFontNormal` fonts, native Blizzard textures for the dropdowns and scroll bar. This is the only theme that always works.

**ElvUI.** Detected by `IsAddOnLoaded("ElvUI")` *and* `unpack(ElvUI)` returning the ElvUI engine table. If present, on `PLAYER_ENTERING_WORLD` we call ElvUI's skinning API: `E.Skins:HandleFrame`, `E.Skins:HandleButton`, `E.Skins:HandleScrollBar`, etc. Reference: ElvUI's own `Modules/Skins/Blizzard/Merchant.lua` shows the exact pattern for the merchant frame.

Theme files (`UI/Themes/Default.lua`, `UI/Themes/ElvUI.lua`) expose the same interface:

```lua
Theme.ApplyToFrame(frame)
Theme.ApplyToButton(button)
Theme.ApplyToDropdown(dropdown)
Theme.ApplyToScrollFrame(scroll)
Theme.GetRowHeight()  -- different per theme
Theme.GetColors()     -- { bg, border, text, textHighlight, textDisabled, qualityTints }
```

`Core.lua` picks the right theme module at load time. No runtime theme switching for v0.x — that's not worth the complexity.

### What we do *not* attempt

- Matching TSM's Montserrat theme. TSM's font registry is unreachable from outside (see §3), and matching badly looks worse than not matching at all. Default theme on a TSM-anchored panel will look visually distinct from TSM — acceptable.
- Skinning support for other UI replacers (NDui, KkthnxUI, Tukui). Add later by request; the theme module interface is the extension point.

## 6. Filter list and priorities

| # | Filter | Data source | Priority | Notes |
|---|---|---|---|---|
| F1 | Text search (name) | `GetItemInfo(itemID).name` | P0 | Duplicates TSM's existing one; needed when our panel is the active UI. |
| F2 | Quality min/max | `select(3, GetItemInfo)` | P0 | First filter implemented (vertical-slice anchor). |
| F3 | Item class | `GetItemInfoInstant(itemID)` (sync) | P0 | Drives the class dropdown. |
| F4 | Item subclass | `GetItemInfoInstant(itemID)` | P1 | Nested under class dropdown. |
| F5 | Item level range | `select(4, GetItemInfo)` | P1 | Async; gated until item info resolves. |
| F6 | Required level max | `select(5, GetItemInfo)` | P1 | |
| F7 | TSM group | `TSM_API.GetGroupPathByItem` | P0 (TSM required) | **The unique value-add.** Vertical-slice + 1. Dropdown hidden if TSM not loaded. |
| F8 | Can afford only | `GetMoney()` + currency reads | P2 | Extended cost items make this nontrivial; defer to v0.4. |
| F9 | "Not in bags" | `TSM_API.GetBagQuantity` | P3 | Convenience for collectors / re-stockers. |

P0 ships in v0.1 vertical slice. P1 in v0.2. P2+ in v0.3+.

## 7. Open questions (resolve during M0 → M1)

1. **TSM vendor frame global name / parent reference.** TSM creates the frame dynamically; identify it in-game (`/dump` on candidate names like `TSMVendoringUIFrame`, or iterate visible top-level frames when `TSM_API.IsUIVisible("VENDORING")` flips true). Capture the discovery in `UI/Anchor.lua` as a single function with a name-fallback list.
2. **Extended cost handling.** `BuyMerchantItem` with currency-cost items — does it trigger Blizzard's confirmation popup, or do we need to call `MerchantFrame_ConfirmExtendedItemCost`? Test in-game.
3. **`numAvailable` semantics in TBC.** Confirm `-1` means unlimited (as TSM treats it) vs. some other value on Anniversary realms.
4. **Group filter scale.** If user has 200+ groups, the dropdown UX needs a search field or hierarchical tree. Defer; punt if first user has <30 groups.
5. **Coexistence with `VendorFilter` addon.** Either disable our panel when `VendorFilter`'s dropdown is set to anything other than "ALL," or do nothing (let them stack). Decide after v0.1 testing.
6. **TSM frame title-bar height.** Y-offset for the tab depends on the anchor frame's title-bar/header height, which differs between TSM's frame and MerchantFrame. Pull from the anchor at attach time rather than hard-coding.
7. **Tab graphic.** Ship a placeholder 32×64 texture in M0; revisit asset quality in M3 polish. WhatsTraining's `left.blp` / `right.blp` are usable references for proportions.
8. **ElvUI skin re-application.** ElvUI's skinning happens on `PLAYER_ENTERING_WORLD`. If our panel is created after that (lazy on first merchant open), we need to apply the skin directly. Wrap skin calls in a one-shot helper.

## 8. Milestones

### M0 — Skeleton (0.5 day)
- TOC, `Core.lua` entry, `MERCHANT_SHOW/HIDE/UPDATE` handlers.
- Slash command `/coinscry` opens/closes panel (visible-only stub).
- Print debug: count of merchant items + TSM vendor visibility.
- **Verifies:** addon loads on TBC Anniversary, events fire, `TSM_API` is reachable.

### M1 — Vertical slice (1–2 days)
- `Scanner.lua` builds the in-memory row list.
- `Util/ItemCache.lua` async-resolves item info.
- `UI/Tab.lua` creates the side tab anchored to `MerchantFrame` (TSM frame discovery deferred to M2).
- `UI/Panel.lua` slides out with:
  - Quality dropdown (F2)
  - Group dropdown (F7)
  - Scrollable filtered list with Buy buttons
- `UI/Themes/Default.lua` only — ElvUI deferred to M2.
- **Verifies:** the hard parts (filter pipeline, TSM_API group lookup, BuyMerchantItem, tab/panel anchoring) all work end-to-end with two filters and one anchor. If this slice ships clean, the remaining work is fan-out.

### M2 — Filter fan-out + TSM anchor + ElvUI (1.5 days)
- F1 (text search), F3 (class), F4 (subclass), F5 (item level), F6 (required level).
- `UI/Anchor.lua` migrates the tab to TSM's vendor frame when `TSM_API.IsUIVisible("VENDORING")` is true (resolve open question #1).
- `UI/Themes/ElvUI.lua` implementation; theme picked at load.
- SavedVariables: remember last anchor override (persistent across reloads). **Filter state is reset on each MERCHANT_SHOW** rather than persisted — leaving a filter on across vendor visits hid items at the next vendor and was confusing in testing.

### M3 — Polish (0.5 day)
- F8 "can afford only" with extended-cost handling.
- Right-click → quantity dialog. Shift-click → buy stack (when affordable).
- Tooltips on item rows.
- Slash command surface: `/coinscry reset`, `/coinscry show/hide`, `/coinscry anchor [tsm|merchant|auto]`.

### M4 — Optional stretch
- F9 "not in bags."
- Multi-flavor TOC (`_TBC.toc` + retail variant) — only if there's demand.
- Detection / coexistence rule with `VendorFilter`.

## 9. Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| TSM removes `GetGroupPathByItem` or breaks `TSM_API`. | Low (it's their stable public API). | Pin behavior behind a feature check at load; degrade gracefully if missing. |
| TSM's vendor frame's name/position changes across versions. | Medium. | Discover at runtime with a fallback list; if not found, the tab stays on `MerchantFrame` (visible underneath TSM, so still reachable). |
| ElvUI's skinning API breaks our calls (rename, signature change). | Low–medium. | All ElvUI calls go through `UI/Themes/ElvUI.lua`; wrap each in `pcall` and fall back to the default theme silently if a skin call errors. |
| Tab graphic clashes with ElvUI's flatter aesthetic. | Medium. | Provide two textures (one beveled-classic, one flat) and pick per theme. |
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
- A side tab is visible on `MerchantFrame` (TSM frame anchoring lands in M2 — not blocking v0.1).
- Click the tab → panel slides out, filter controls visible.
- Set Quality = Rare+, see only rare+ items in the panel's list.
- Set Group = "<some TSM group>", see only items in that group.
- Click an item's Buy button, get the item, gold goes down, panel refreshes.
- Close the merchant → tab + panel hide. Re-open another merchant → tab + panel reappear with filters **reset to defaults** (per the M2-B decision; persisting filter state across vendors caused confusion in early testing).
- No errors in BugSack/BugGrabber across a 20-minute vendor session at three different vendors (general goods, reagent vendor, faction quartermaster).
- **No-TSM smoke test:** disable TSM in the addons menu, reload, open a vendor — tab + panel appear on `MerchantFrame`, quality filter works, group dropdown is absent, no errors.

That's the bar. Everything past that is fan-out and polish.
