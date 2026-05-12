# Roadmap

Coinscry is **feature-complete** as of v0.5.0 in the sense that I'm done shipping core scope and waiting for real users to surface real issues. This document collects ideas I'd consider for a future v0.6 if the addon gets traction or a contributor wants to take one on.

None of these are committed work. Open an issue if you want to discuss / claim one.

## Candidate features

### TSM market-value column

When TSM is loaded, show its market value next to merchant cost. Items priced below market are arbitrage opportunities (or just good buys for AH flipping). TSM_API already exposes the data via `TSM_API.GetCustomPriceValue("dbmarket", itemString)` (and similar) — the implementation is mostly a new column + a setting to toggle it.

- **Effort:** small
- **Risk:** low; falls back gracefully if TSM is absent
- **Open questions:** which price source (DBMarket / DBMinBuyout / VendorBuy)? Probably make it a setting.

### Wishlist / favorites

Right-click → "Add to wishlist". Wishlisted items get a star icon and float to the top of the row order. Saved per-character (or account, TBD). When you open a vendor that sells a wishlisted item, the side tab pulses or the panel auto-opens.

- **Effort:** medium (UI for managing the list, persistence schema, attention-grabbing UX)
- **Risk:** scope creep — needs a clear "what's the minimum useful version" decision before building
- **Open questions:** item-link based or itemID based? (itemID is more robust to caching but loses suffixes / random enchants — for vendor items that's fine.)

### Stack-buy planner

"Buy enough to reach N of X in my bags" — useful for arrow farming, regs, anything stack-consumed. Right-click → "Buy until I have N…" → quantity dialog → buys `N - current_bag_count` items, capped at the vendor's available supply.

- **Effort:** small (one new context menu entry + arithmetic against bag scan)
- **Risk:** low
- **Open questions:** include bank when the bank is open? (Probably not in v1.)

### Filter presets

Save the current filter state as a named preset; recall via `/coinscry preset <name>` or a presets dropdown. Power-user feature for people who repeatedly hit the same vendor with the same filter shape ("affordable arrows under 50s", "any green+ leather of my level").

- **Effort:** medium (persistence + UI for managing presets)
- **Risk:** low
- **Open questions:** account-wide or per-character?

## Probably won't do

- **Telemetry / usage stats.** WoW addon users rightly hate it.
- **Cross-realm wishlist sync.** Way out of scope; would require an out-of-game service.
- **In-game guide for new users.** README + CurseForge description should be enough.
- **Localization framework.** Until a contributor offers translations for a specific locale, the small handful of English strings stay hardcoded. Demon-type tooltip parsing is the main locale barrier (called out in the README).
