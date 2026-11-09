# LOT-187 — Cache clearing (M5)

- **Module:** App
- **Difficulty / model:** easy (Sonnet → Opus)
- **Issue:** [#689](https://github.com/ezzz/HFRnow/issues/689) · **Milestone:** M5 (UX evolutions)
- **Depends on:** LOT-179 (#419, cache sizes)
- **Split from:** LOT-179, on 2026-11-09 ([#655](https://github.com/ezzz/HFRnow/issues/655)): the sizes went to M4 as a backport of legacy evolution; clearing has no reachable legacy counterpart, so it stays the (b) half of LOT-120.

Stub; the author of the lot completes it before coding (AGENTS.md §5).

## Legacy sources
None reachable. At `2fe43da3`, `HFRswift/Swift/AppSettingsView.swift` has `clearCaches` (`:272-286`: resets the tabs, removes `ImageCache` and `SmileCache`) and a "Vider le cache ?" alert ("Tous les onglets seront réinitialisés.", `:637-644`), but `showClearCacheConfirmation` (`:118`) is never set to true, so no user reaches it. At `2440d79` the row was commented out (GAP-152). The ObjC "EmptyCacheButton" (`Classes/PlusSettingsViewController.m:308-313` @ `2fe43da3`) belongs to a settings screen the SwiftUI app no longer routes.

## Legacy counterpart (app lots)
None @ 2fe43da3 (new UX). The code says so in its `// Port of …` header (AGENTS.md §4).

## UX evolutions (app lots)
- The whole lot: class `b`, optional, never the default ([UX principles](../FEATURES.md#ux-principles-operator)). GAP-152 now describes the M4 sizes (LOT-179, `a·master`); this lot adds its own row (`gap-new`, id #689) when it is specced.

## Behaviour, edge cases, fixtures
To write. No HFR request.

## Intentional differences from legacy
The whole lot is one: it is the evolution.

## Learnings
To copy into AGENTS.md §11 when the lot closes.
