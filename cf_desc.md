# Coinscry

Vendor-browsing filters for World of Warcraft **TBC Anniversary**. A companion overlay for [TradeSkillMaster](https://www.tradeskillmaster.com/) — but it works standalone, too.

TSM ships its vendor filter button as a stub (literal `-- TODO` in `Core/UI/VendoringUI/Buy.lua`), so vendor browsing inside TSM is text-search only. Coinscry layers on quality, item-type, item-level, affordability, can-use, already-known, demon-type, and TSM-group filters — accessible via a side tab + slide-out panel that follows whichever vendor frame (TSM's or Blizzard's) is in front.

![attached to TSM's vendor frame](https://raw.githubusercontent.com/WastelandRoot/coinscry/main/Media/screenshots/02-tsm-attached.png)

## Two display modes

- **Embedded mode (no TSM)** — Coinscry replaces Blizzard's merchant grid in-place. The MerchantFrame widens to fit, the vanilla item buttons hide, and the filter panel fills that area. Click the side tab to flip back to the normal merchant view at any time. Blizzard's *Buyback* and *Repair* tabs still work — clicking them yields the embed automatically.
- **Attached mode (with TSM)** — when TSM's vendoring UI is up, Coinscry floats beside it as a slide-out panel. TSM's own vendor frame is untouched.

![embedded inside the Blizzard merchant frame](https://raw.githubusercontent.com/WastelandRoot/coinscry/main/Media/screenshots/01-embed-compact.png)

The panel auto-detects which frame is in front and re-anchors as you open and close them.

## Filters

Compact by default — only search and the three usage checkboxes are shown until you expand the **Filters** header.

- **Search** — case-insensitive substring on item names.
- **Can use** — hides items WoW marks red in the merchant frame (wrong class, wrong proficiency, level too low, missing profession, etc.). Driven by `GetMerchantItemInfo`'s `isUsable` flag, so it matches WoW's own determination exactly.
- **Affordable** — checks both gold and any extended-cost items/currencies.
- **Hide already known** — recipes the player has learned, and warlock demon tomes the currently-summoned pet has learned.
- **Quality** — Common+ through Legendary.
- **Item type / subtype** — Armor (Cloth/Leather/Mail/Plate), Weapon (1H Sword / Polearm / Bow / …), Consumable, Trade Goods, Recipe, etc. Auto-populated from items present at the current vendor.
- **Item level** — min / max range.
- **Required level** — max.
- **TSM group** — exact match against a TSM group path (requires TSM).
- **Demon type** — Imp / Voidwalker / Succubus / Felhunter / Felguard. Contextual: only appears at vendors selling warlock demon tomes.

![quality + weapon-type narrowing](https://raw.githubusercontent.com/WastelandRoot/coinscry/main/Media/screenshots/03-quality-type.png)

## Buying from the filtered list

- **Left-click** a row — buys 1
- **Shift-left-click** — buys a full stack (e.g., 200 arrows)
- **Right-click** — quantity dialog, pre-filled with the stack size and capped at the merchant's remaining supply for limited items

Hold **Shift** while hovering and each row's qty preview updates live to `xN` so you can see what a stack-click would actually buy.

## ElvUI support

Detected automatically at load. With ElvUI present, the panel, dropdowns, checkboxes, and edit boxes pick up ElvUI's skinning. No configuration required.

## Slash commands

- `/coinscry` — toggle the filter panel at a vendor
- `/coinscry config` — open the settings window (also reachable from *Game Menu → Options → AddOns → Coinscry*)
- `/coinscry reset` — clear all active filters
- `/coinscry anchor [merchant|tsm|auto]` — manually pin the anchor or return to auto-detect

## Requirements

- WoW **TBC Anniversary** client (Interface `20505`)
- TradeSkillMaster — *optional*; without it, all non-group filters still work and Coinscry attaches to Blizzard's merchant frame
- ElvUI — *optional*; detected at load

## Known limitations

### Demon-type filter is English-only

The demon-type filter matches `Teaches Imp …` / `Teaches Voidwalker …` etc. in the item tooltip. On non-English clients the word "Teaches" and/or the demon name is localized, so the pattern doesn't match and the dropdown won't appear at warlock trainers. PRs welcome adding patterns for other locales in `Scanner.lua`.

The other filters use WoW's localized internals (e.g., `ITEM_SPELL_KNOWN` for already-known) and work on all locales out of the box.

### Warlock demon tomes: only the currently summoned demon is checked

The WoW API only exposes the currently summoned pet's spellbook. "Hide already known" can correctly hide tomes the summoned demon already knows, but tomes for other demons (e.g., a Voidwalker tome while you have your Imp out) always appear unknown — the API can't see Voidwalker's spellbook unless Voidwalker is the active pet.

Standard workflow: summon the relevant demon before visiting that demon's trainer.

## Issues and source

- Bug reports / feature requests: [github.com/WastelandRoot/coinscry/issues](https://github.com/WastelandRoot/coinscry/issues)
- Source: active development on [Forgejo](https://git.kal.run/kaltec/coinscry); GitHub is the release mirror
