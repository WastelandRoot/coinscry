# Contributing to Coinscry

Thanks for your interest. Coinscry is a small project — bug reports and small focused PRs are the easiest way to help.

## Reporting a bug

Use the [GitHub bug-report form](https://github.com/WastelandRoot/coinscry/issues/new?template=bug_report.yml). The required fields are tuned to the things I usually need to ask before I can reproduce.

If you can include the output of `/coinscry status` and `/coinscry dump` from a vendor where the bug appears, that almost always shortens triage to one round-trip.

## Requesting a feature

Use the [feature-request form](https://github.com/WastelandRoot/coinscry/issues/new?template=feature_request.yml). Frame it around the concrete vendor scenario, not the implementation — I'll figure out the implementation. The [ROADMAP](ROADMAP.md) lists ideas already on my radar.

## Code contributions

### Setup

1. Clone the repo into your AddOns folder, or clone elsewhere and symlink `coinscry/` into `<WoW>/_anniversary_/Interface/AddOns/`.
2. Edit. `/console reloadui` (or `/rl`) inside the game picks up changes.

No build step. Lua source loads directly via `coinscry.toc`.

### Style

- Match what's already there — tabs for indent, single-line comments leading with `--`, file-scoped `local` declarations near the top.
- Functions and module exports use **PascalCase** (`Panel.Refresh`); locals use **camelCase** (`scrollFrame`); module-level constants use **UPPER_SNAKE_CASE** (`ROW_H`, `TOP_RESERVED_EXPANDED`).
- Comments explain *why*, not *what*. The Blizzard / TSM / ElvUI APIs we wrap have plenty of quirks worth documenting; a comment that just restates the code is noise.
- No dependencies beyond TSM_API (optional) and ElvUI (optional, theme only).

### Linting

`.luacheckrc` is in the repo and CI runs `luacheck .` on every push and PR. To run it locally:

```sh
luacheck .
```

A clean run prints nothing.

### Testing

Manual, in-game. Test matrix for any change that touches vendor / panel code:

- **Embedded mode** — vanilla merchant frame (TSM closed or not installed). Toggle the tab off and back on. Switch to Buyback tab and back. Visit a repair vendor.
- **Attached mode** — open TSM Vendoring, confirm the panel floats beside it.
- **At least one warlock-tome vendor** if your change touches dropdowns or filters (validates the contextual demon-type dropdown).
- **ElvUI on and off** if your change touches frame creation or theming.

When you open the PR, mention which of these you tested.

### Commits + PRs

- Conventional-ish messages: lead with `area: short summary` (`Panel: …`, `Scanner: …`). The body explains the *why*. Examples in `git log`.
- Keep PRs focused — one fix or one feature per PR is much easier to review than a bundle. Refactor commits separate from behavior changes when possible.
- The `main` branch is the default; tagged releases (`vX.Y.Z`) trigger CurseForge + GitHub Releases publishing via the `release.yml` workflow.

## Architecture

[DESIGN.md](DESIGN.md) covers the why behind the high-level shape (companion overlay, not TSM injection; dual-anchor logic; embed vs. attached display modes). Worth reading before touching anchoring or display-mode code.
