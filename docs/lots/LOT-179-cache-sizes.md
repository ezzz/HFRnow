# LOT-179 — Cache sizes (M4)

- **Module:** App
- **Difficulty / model:** easy (Sonnet → Opus)
- **Issue:** [#419](https://github.com/ezzz/HFRnow/issues/419) · **Milestone:** M4, backport of legacy evolution (operator, 2026-11-09, [#655](https://github.com/ezzz/HFRnow/issues/655))
- **Depends on:** LOT-120 (#211, Réglages > Maintenance), LOT-066 (#91, done, the caches and their eviction)
- **History:** created on 2026-11-02 as the (b) half of LOT-120, "cache sizes and clearing", M5 ([#379](https://github.com/ezzz/HFRnow/issues/379)). On 2026-11-09 the sizes went to M4 because the legacy reference `2fe43da3` shows them; clearing, which legacy cannot reach there, is now **LOT-187** ([#689](https://github.com/ezzz/HFRnow/issues/689), M5).

## Legacy sources
Absent at `2440d79` (GAP-152: the "Vider le cache" row of `AppSettingsView.swift:264-280, 476-486` was commented out). Added at `2fe43da3` by `c7693a88`:

| Legacy @ `2fe43da3` | Behaviour |
|---|---|
| `HFRswift/Swift/AppSettingsView.swift:547-577` (`maintenanceSection`) | section "Maintenance": "Caches de l'app" (total), "Pages HTML" (size, "N fichiers" below), a spinner until measured, "Ouvrir les réglages système"; footer "Les pages HTML de plus de 7 jours sont supprimées automatiquement. Leur cache est limité à 50 Mo." |
| `AppSettingsView.swift:288-297` (`refreshCacheStorage`, `formattedStorageSize`) | measured off the main thread; sizes as `.byteCount(style: .file)` |
| `HFRswift/Swift/HTMLPageCacheManager.swift:39-55` (`storageSnapshot`), `:108-146` (`cachedHTMLFiles`), `:148-177` (`directoryAllocatedSize`) | total = allocated size of every non-hidden regular file under `Caches`, recursively (hidden files and folders skipped); "Pages HTML" = only the non-hidden regular files directly under `Caches/cache` named `topic-*` with an `htm` extension (case-insensitive) |

Clearing is not in this lot: the "Vider le cache ?" alert (`AppSettingsView.swift:637-644`) is never presented at `2fe43da3` (`showClearCacheConfirmation`, `:118`, is never set), and the ObjC settings screen that had "EmptyCacheButton" (`Classes/PlusSettingsViewController.m:308-313`) is not routed in the SwiftUI app. That is LOT-187.

## Legacy counterpart (app lots)
`App/SwiftHFR/Settings/MaintenanceSection.swift` (`MaintenanceModel`, `MaintenanceSection`) and `CacheStorageSnapshot.swift` start with `// Port of HFRswift/Swift/AppSettingsView.swift (maintenanceSection, refreshCacheStorage) @ 87fe0d1c` and `HTMLPageCacheManager.swift (storageSnapshot, …) @ 87fe0d1c`, naming their differences (GAP-152). Both legacy files are identical at `2fe43da3` and `87fe0d1c`.

## UX evolutions (app lots)
None planned: same UX as legacy at `2fe43da3`.

## Behaviour
On top of the merged LOT-120, in Réglages > Maintenance, above "Ouvrir les réglages système":

- **"Caches de l'app"**: allocated size of every non-hidden regular file under `Library/Caches`, recursively, so the whole folder as legacy (`HTMLPageCacheManager.swift:40-46`), not only LOT-066's areas (WebKit and URL caches count too).
- **"Pages HTML"**: allocated size of the non-hidden regular `topic-*.htm` files (extension case-insensitive) directly in LOT-066's `pages` area (`Caches/cache/pages`, the folder `CacheEvictionPolicy.topicPages` purges), with "N fichiers" below.
- A spinner replaces the rows until the first measure ends; the measure runs off the main actor, on each appearance of the section. Overlapping measures: the last one started wins.
- Sizes use `.byteCount(style: .file)`.
- The footer is derived from `CacheEvictionPolicy.topicPages`: "Les pages HTML de plus d’un jour sont supprimées automatiquement. Leur cache est limité à 20 Mo." (a megabyte is 1 000 000 bytes, as legacy).

## Edge cases
- Missing or unreadable folder: counts as empty (0, "0 fichier"), never an error row.
- Hidden files and folders (leading dot) are skipped in both figures.
- Symbolic links are not followed or counted, in either figure; a `pages` area that is a link or leaves the cache (`CacheDirectory.safeURL`) reads as empty.
- Directories named like pages (`topic-x.htm/`), other prefixes or extensions (`.html`), and files in sub-folders of `pages` are not pages.
- Size is the allocated size (`totalFileAllocatedSize`, then `fileAllocatedSize`, then `fileSize`), so a small page shows a whole block, as legacy.

## Fixtures
None: no HFR request.

## Intentional differences from legacy
- The footer states SwiftHFR's own rule for topic pages: LOT-066's topic-page preset is one day and 20 MB (`topicPages`, `Packages/HFRKit/Sources/HFRStorage/Caches/CacheEvictionPolicy.swift:23-24`), tighter than legacy's 7 days and 50 MB (`HTMLPageCacheManager.swift:21-22` @ `2fe43da3`; LOT-066 spec, "Legacy at `2fe43da3`"). Its changelog row is in the `### Ledger` section of #690, the PR that moved this lot to M4.

- "Pages HTML" reads `Caches/cache/pages` (LOT-066's area), where legacy read `topic-*.htm` directly under `Caches/cache`; legacy-era files there are in the total only.
- "fichier" is singular for 0 and 1 (legacy wrote "1 fichiers").

## Learnings
To copy into AGENTS.md §11 when the lot closes.
