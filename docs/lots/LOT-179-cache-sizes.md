# LOT-179 — Cache sizes (M4)

- **Module:** App
- **Difficulty / model:** easy (Sonnet → Opus)
- **Issue:** [#419](https://github.com/ezzz/HFRnow/issues/419) · **Milestone:** M4, backport of legacy evolution (operator, 2026-11-09, [#655](https://github.com/ezzz/HFRnow/issues/655))
- **Depends on:** LOT-120 (#211, Réglages > Maintenance), LOT-066 (#91, done, the caches and their eviction)
- **History:** created on 2026-11-02 as the (b) half of LOT-120, "cache sizes and clearing", M5 ([#379](https://github.com/ezzz/HFRnow/issues/379)). On 2026-11-09 the sizes went to M4 because the legacy reference `2fe43da3` shows them; clearing, which legacy cannot reach there, is now **LOT-187** ([#689](https://github.com/ezzz/HFRnow/issues/689), M5).

Stub; the author of the lot completes it before coding (AGENTS.md §5).

## Legacy sources
Absent at `2440d79` (GAP-152: the "Vider le cache" row of `AppSettingsView.swift:264-280, 476-486` was commented out). Added at `2fe43da3` by `c7693a88`:

| Legacy @ `2fe43da3` | Behaviour |
|---|---|
| `HFRswift/Swift/AppSettingsView.swift:547-577` (`maintenanceSection`) | section "Maintenance": "Caches de l'app" (total), "Pages HTML" (size, "N fichiers" below), a spinner until measured, "Ouvrir les réglages système"; footer "Les pages HTML de plus de 7 jours sont supprimées automatiquement. Leur cache est limité à 50 Mo." |
| `AppSettingsView.swift:288-297` (`refreshCacheStorage`, `formattedStorageSize`) | measured off the main thread; sizes as `.byteCount(style: .file)` |
| `HFRswift/Swift/HTMLPageCacheManager.swift:39-55` (`storageSnapshot`), `:108-146` (`cachedHTMLFiles`), `:148-177` (`directoryAllocatedSize`) | total = allocated size of every non-hidden regular file under `Caches`, recursively (hidden files and folders skipped); "Pages HTML" = only the non-hidden regular files directly under `Caches/cache` named `topic-*` with an `htm` extension (case-insensitive) |

Clearing is not in this lot: the "Vider le cache ?" alert (`AppSettingsView.swift:637-644`) is never presented at `2fe43da3` (`showClearCacheConfirmation`, `:118`, is never set), and the ObjC settings screen that had "EmptyCacheButton" (`Classes/PlusSettingsViewController.m:308-313`) is not routed in the SwiftUI app. That is LOT-187.

## Legacy counterpart (app lots)
To write by the author (`// Port of HFRswift/Swift/AppSettingsView.swift (maintenanceSection) @ 2fe43da3. Differences: …`, GAP-152).

## UX evolutions (app lots)
None planned: same UX as legacy at `2fe43da3`.

## Behaviour
To write, on top of the merged LOT-120. The figures come from LOT-066's caches (`HFRStorage/Caches`), not from legacy's folders. Legacy's total is the whole `Caches` folder (`HTMLPageCacheManager.swift:40-46` @ `2fe43da3`); LOT-066's areas live under `Caches/cache`, so the author either measures the whole folder or records the narrower total as an intentional difference.

## Edge cases
To write.

## Fixtures
None: no HFR request.

## Intentional differences from legacy
- The footer states SwiftHFR's own rule for topic pages: LOT-066's topic-page preset is one day and 20 MB (`topicPages`, `Packages/HFRKit/Sources/HFRStorage/Caches/CacheEvictionPolicy.swift:23-24`), tighter than legacy's 7 days and 50 MB (`HTMLPageCacheManager.swift:21-22` @ `2fe43da3`; LOT-066 spec, "Legacy at `2fe43da3`"). Its changelog row is in the `### Ledger` section of #690, the PR that moved this lot to M4.

## Learnings
To copy into AGENTS.md §11 when the lot closes.
