# tsm-vendor-filter-plus

Vendor-browsing filters for World of Warcraft TBC Anniversary. Built primarily as a companion for [TradeSkillMaster](https://www.tradeskillmaster.com/), but works standalone too.

TSM ships its vendor filter button as a stub (`-- TODO`), so vendor browsing on TSM is text-search only. This addon fills in the gap with quality, item-type, item-level, affordability, already-known, and demon-type filters — and, when TSM is loaded, **TSM-group filtering** (the unique value-add).

## Target

- World of Warcraft **TBC Anniversary** client (Interface `20505`).
- `TradeSkillMaster` is recommended (enables the group filter and the dual-anchor UI) but **not required**. Without TSM, the addon attaches to the standard Blizzard merchant window and provides all non-group filters.

## Filters

- **Search** — case-insensitive substring on item names
- **Quality** — Common+ through Legendary
- **Type / Subtype** — Armor (Cloth/Leather/Mail/Plate), Weapon (1H Sword/Polearm/Bow/…), Consumable, Trade Goods, Recipe, etc. Auto-populated from items present at the current vendor.
- **Item level** — min / max range
- **Required level** — max
- **TSM group** — exact match against a TSM group path (requires TSM)
- **Affordable** — checks both gold and any extended-cost items/currencies
- **Can use** — hides items the player doesn't meet level / class / weapon-skill requirements for (uses WoW's `IsUsableItem` plus a level check)
- **Hide known** — covers profession recipes (player spellbook) and warlock demon tomes (currently-summoned pet's spellbook)
- **Demon type** — Imp / Voidwalker / Succubus / Felhunter / Felguard. Contextual: only appears at vendors selling warlock demon tomes.

## Buying from the filtered list

- **Left-click** a row — buys 1
- **Shift-left-click** — buys a full stack (e.g., 200 arrows)
- **Right-click** — opens a quantity dialog (defaults to the stack size, capped at the merchant's remaining supply for limited items)

## Slash commands

- `/tvfp` (or `/tvfp toggle`) — toggle the filter panel at a vendor
- `/tvfp config` — open the settings window (also reachable from *Game Menu → Options → AddOns → TSM-VFP*)
- `/tvfp reset` — clear all active filters
- `/tvfp anchor [merchant|tsm|auto]` — manually pin the anchor or return to auto-detect
- `/tvfp trace [on|off]` — log anchor switches to chat (diagnostic)
- `/tvfp status` / `/tvfp poll` / `/tvfp dump` / `/tvfp groups` / `/tvfp scan` — diagnostics

## Known limitations

### Locale: English-only text patterns

A few filters depend on parsing English tooltip text:

- **Demon-type filter** matches `Teaches Imp …` / `Teaches Voidwalker …` etc. in the item tooltip. On non-English clients, the word "Teaches" and/or the demon name will be localized, so the pattern will not match and `row.demonType` stays nil. The dropdown will simply not appear at warlock trainers, and the filter as a whole degrades to "off."
- **Already known** uses WoW's own `ITEM_SPELL_KNOWN` constant, which IS localized — so this filter works on all locales out of the box.

If you run a non-English client and want demon-type detection, file an issue or PR with the appropriate `Teaches <Demon>` patterns for your locale and we'll add them to the allow-list in `Scanner.lua`.

### Warlock demon tomes: only the currently summoned demon is checked

The WoW API only exposes the spellbook of the **currently summoned** pet. So "Hide already known" can correctly hide tomes the *summoned* demon already knows, but tomes for other demons (e.g., a Voidwalker tome while you have your Imp out) will always appear as not-yet-known — even if your Voidwalker has actually learned them.

Standard workflow: summon the relevant demon before visiting that demon's trainer.

### TSM vendor frame disambiguation

When you have multiple TSM application UIs open at once (Vendoring + Crafting, etc.), the anchor logic picks the first matching `TSM_FRAME:LargeApplicationFrame:*` it finds — there's no clean way to distinguish them from outside TSM. In practice this is rare; if you hit it, pin manually with `/tvfp anchor merchant` or `/tvfp anchor tsm`.

## License

[MIT](LICENSE).
