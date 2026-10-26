# LOT-066 — Caches: avatars, temporary files, eviction

- **Module:** HFRStorage
- **Difficulty / model:** easy (Sonnet → Opus)
- **Issue:** none (lot tracked in `docs/LOTS.md`)

## Legacy sources
Legacy repository <https://github.com/francoisgn/hfrnow> at `2440d79`. Audit: [E §2.4, §7.8-7.10, §8 (E-8)](../audit/E-storage-vendors.md), [C §C17](../audit/C-message-parsing.md).

| Legacy | What it gives the caches |
|---|---|
| `Classes/HFRplusAppDelegate.m:539-585` | launch pruning of `Caches/cache/avatars`: files created more than 25 days ago are removed |
| `HFRswift/Wrapped/ParseMessagesOperation.m:124-140` | avatars live in `Caches/cache/avatars/`, created when missing |
| `docs/audit/C-message-parsing.md` C17 (`ParseMessagesOperation.m:423-467`) | key = md5 of the lower-cased pseudo, no extension, re-download after 24 h, a failed download drops a valid stale file (bug) |
| `HFRswift/Swift/Common.swift:1962-1976` | `Caches/cache/topic-<UUID>.htm` written for every page view and never removed |
| `HFRswift/Swift/AppSettingsView.swift:264-278` | "Clear caches" deletes `ImageCache` / `SmileCache` folders nobody writes any more |

## Behaviour
Code in `Sources/HFRStorage/Caches/`, tests in `Tests/HFRStorageTests/Caches/`. No image decoding (ImageIO stays in the app).

- **`CacheDirectory`**: root (default `Library/Caches/cache`, the legacy folder) and two `CacheArea`s: `avatars` and `pages` (rendered topic pages). `prepare(_:)` creates a folder, `evictAll(now:)` applies every area's policy (run at launch), `size(of:)` and `clear(_:)` back the "clear caches" action.
- **`CacheEvictionPolicy`**: maximum age and/or maximum total bytes. Age first, then the oldest files go until the total fits. Presets: avatars 25 days + 50 MB (age is the legacy rule, the bound is new), pages 1 day + 20 MB.
- **`CacheEvictor`**: recursive, removes regular files only (never folders, never symbolic links), order is oldest first with the path as tie-break, a failure on one file is reported in `CacheEvictionReport.failures` and the pass goes on (expired files that could not be removed still count towards the size bound). A cache folder that is itself a symbolic link is ignored and reported. `CacheDirectory.safeURL(for:)` checks that neither the root nor the area is a link and that the area resolves inside the root; `prepare`, `clear`, `evictAll`, `size`, `AvatarCache` and `TemporaryFileCache` all go through it (`CacheError.unsafeFolder`), so a link can never redirect a read, write or removal. Linked files inside an area are ignored. Age is the file's modification date.
- **`AvatarCache`** (value type, no memory state): `entry(forPseudo:)` returns the file, whether fresh (24 h) or stale; the caller downloads again when stale. `store(_:forPseudo:)` writes atomically and refuses empty data. `remove(forPseudo:)`.
- **`TemporaryFileCache`**: `write(_:prefix:pathExtension:)` creates `topic-<UUID>.htm` (default) in `pages`; prefix and extension accept only ASCII letters, digits, `-` and `_` (at most 32), otherwise `CacheError.invalidFileName`, so a file can never leave the folder the policy cleans; `directoryURL` is the read-access root for the web view.

Decisions:

1. **Key encoding, not a hash.** Foundation has no MD5 and a non-cryptographic hash would let a member register a pseudo that collides with another's and show the wrong avatar. The file name is the hex of the lower-cased, ZWSP-free UTF-8 pseudo, which is injective and safe for any file system. Keys over 100 bytes are rejected (`keyTooLong`); HFR pseudos are far shorter.
2. **Age by modification date**, not creation date: creation dates are not reliably available on every file system (Linux) and an atomic rewrite is a new write anyway.
3. **"No deletion of a valid stale file on failure" (C17) holds by construction**: there is no delete-on-miss path, and empty data is refused, so a failed or empty download leaves the old file.
4. **Bundle resources (CSS/JS copied into the cache so the HTML can use relative URLs, `OfflineStorage.m:439-497`) are not copied here.** The app can grant the web view read access to the bundle folder or to `directoryURL` plus the bundle; copying on every launch is what made the legacy cache fragile. The renderer lot decides.
5. **Not ported**: `ImageCache` / `SmileCache` purge (dead since SDWebImage), offline reading (LOT-068, Q-5).

## Edge cases
- A missing folder is an empty cache, not an error.
- A file exactly at the maximum age is kept; one second older is removed.
- The size bound counts every file still on disk after age eviction, including expired files whose removal failed.
- Symbolic links inside a cache folder are ignored, so a link can never make the evictor touch a file outside it.
- Keys: empty after normalisation throws `emptyKey`; path-like keys (`../x`) are harmless because only hex reaches the file name.
- `clear(_:)` is an eviction with `CacheEvictionPolicy.everything` (`removesEverything`, an explicit mode): it removes files whatever their date or size, future-dated and empty ones included, and keeps the folder.

## Fixtures
None: temporary directories with files whose modification date is set by the test.

## Intentional differences from legacy
- Modification date instead of creation date; atomic writes instead of in-place downloads.
- A 50 MB bound on avatars and 20 MB / one day on topic pages, which legacy did not have.
- Avatar file names are hex, not MD5: old files are not reused, they age out through the 25-day rule.

## Learnings
To copy into AGENTS.md §11 when the lot closes.
- `URL.cachesDirectory` does not exist in swift-corelibs-foundation: use `FileManager.urls(for:in:)`.
