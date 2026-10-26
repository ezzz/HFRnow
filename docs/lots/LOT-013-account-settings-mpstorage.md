# LOT-013 — Account, StoredCookie, settings enums, MPStorage document types

- **Module:** HFRModels
- **Difficulty / model:** easy (Sonnet → Opus)
- **Issue:** none (lot tracked in `docs/LOTS.md`)

## Legacy sources
Legacy repository <https://github.com/francoisgn/hfrnow> at `2440d79`. Audit: [E §2.1, §2.6, §3.1, §8 (E-3, E-6)](../audit/E-storage-vendors.md) and review finding F2 (network lots need `Account`/`StoredCookie` only), [redface2 comparison](../research/redface2-comparison.md) §4.3 E23, E24.

| Legacy | What it gives the models |
|---|---|
| `Classes/MultisManager.m:49-86`, `Classes/Constants.h:115-121` | account dictionary keys: `PSEUDO`, `PSEUDO_DISPLAY`, `COOKIES`, `HASH`, `AVATAR`, `MAIN` |
| `HFRswift/Swift/LoginService.swift:81-127` | cookies harvested on login (`md_user`, domain `hardware.fr`) |
| `Classes/MPStorage.m:21-24, 249-355, 540-558, 629-630` | document template, subject, recipient, entry shapes |
| `HFRswift/Swift/Common.swift:1360-1366` | Swift side of the entry shapes |
| `HFRswift/Swift/AppSettingsView.swift:86-109`, `Common.swift:144-318`, `HFRplusAppDelegate.m:95-116` | settings keys and their raw values (E §3.1) |

## Behaviour
Value types, `Sendable`, `Hashable`, `Codable`.

- **`StoredCookie`**: name, value, domain, path, `expiresDate?`, `isSecure`, `isHTTPOnly`. Never `HTTPCookie`; HFRNetwork converts. `jarKey` = name + lower-cased domain without leading dot + path.
- **`Account`**: `pseudo` (= `md_user`, also the `id`), `displayName`, `cookies`, `hashCheck?`, `avatarData?`, `isMain`. No password field exists on purpose (E §5.1). The versioned Keychain envelope is HFRStorage's (LOT-065).
- **Settings enums** with the legacy raw values, so persisted defaults keep working: `EmbeddedVideosMode` (`no/yes/both`), `ImageDisplayMode` (`yes/no/wifi`), `LandscapeMode` (`galerie_message/none`), `AutoThemeMode` (0, 3), `ThemeVariant` (0, 1), `ThemeStyle` (0, 1), `TextSizeScale` (100...130), `RehostMaxDimension` (400...1200). Key names, defaults and normalisation (`auto_theme` clamp, tolerant booleans) are the settings store's (E-1).
- **MPStorage document**: `MPStorageDocument` (root, `data`, writer metadata) > `MPStorageEntry` (version, three sections, other namespaces) > `MPStorageSection<Item>` (`list`, writer metadata) with items `MPStorageBlocklistEntry`, `MPStorageMPFlag`, `MPStorageBookmark`. `JSONValue` keeps what is not modelled. Constants: `subject`, `recipient`, `schemaVersion`.

Decisions:

1. **Decoding never destroys data** (redface2 E23: the original library resets to default on a missing key). Every level keeps unknown keys in `extra` and writes them back; items that fail to decode stay in `undecodableItems` as raw JSON and are re-encoded after the good ones. A missing `data` key throws instead of producing an empty document.
2. **Lenient reading, legacy-shaped writing.** `post`, `numreponse`, `page`, `cat` accept numbers or numeric strings (other clients differ); writing follows the legacy shape (`post` and `cat` strings, `numreponse` number for bookmarks, `post` number for flags). Timestamps are integer milliseconds.
3. **`{}` sections** (real documents) decode to an empty list and re-encode as `{"list":[]}`: the only normalisation, harmless for readers.
4. **`Bookmark` lives here** (`MPStorageBookmark`), not in LOT-010: it is the wire type. Its `id` includes the category because `numreponse` is unique per category only (E18).
5. **No mutation, merge, `lastUpdate` conflict logic or pseudo normalisation** in this lot: mutation, merge and write guards are LOT-062 (HFRModels), pseudo normalisation LOT-061 (E-2, E-3). No 64 KiB cap or non-BMP guard either: those belong to the writer (E24, Q-3).
6. **Secrets.** `StoredCookie` and `Account` implement `CustomStringConvertible`, `CustomDebugStringConvertible` and `CustomReflectable` without cookie values or token. `customMirror` redacts them in `dump` and the debugger as well. `Codable` output contains the secrets by design: only the Keychain store may persist it.
7. **Naming.** SwiftLint's `inclusive_language` rule rejects `blacklist` in declarations, so Swift names say "blocklist" (`MPStorageBlocklistEntry`, `MPStorageEntry.blocklist`) while the wire key stays `blacklist`. For the same reason (`identifier_name` minimum of 3 characters) the legacy `no` value is `EmbeddedVideosMode.never`, `ImageDisplayMode.never`, with the legacy strings as raw values.
8. **Not in this lot:** `MPStorageIndex` (cached storage topic id) and the 30-odd UserDefaults keys: HFRStorage.

## Edge cases
- Number versus string for every id-like field; decimal whole numbers (`56.0`) accepted, fractions rejected.
- `blacklist` as `{}`; unknown namespaces (`hfrChat`, `superFavs`, ...) and unknown root keys survive a round trip.
- A bookmark without `post`, `cat` or `numreponse`, or a blacklist entry without `username`, is kept raw, never dropped.
- Unknown `version` strings are preserved as text; deciding whether to write is the store's job.
- Timestamps must be finite and within +/-8.64e15 ms (Foundation's `Date` span): anything else is a decoding error, so a bad item date lands in `undecodableItems`, and encoding a `Date` outside that span throws `EncodingError` instead of trapping (CodeRabbit round 1).
- Integers above 2^53 inside `JSONValue` lost precision here; LOT-062 keeps every number's exact text through `MPStorageCodec`.

## Fixtures
None (synthetic documents in the tests). Real MPStorage documents (empty, 100+ bookmarks, nbsp-polluted, malformed, future version) arrive with LOT-004 and LOT-062.

## Intentional differences from legacy
- Legacy `MPStorage.m` rebuilt the JSON from its own fields and so dropped other clients' namespaces; here they are preserved.
- Legacy `NSKeyedArchiver` account dictionaries become `Codable` values; `NSHTTPCookie` becomes `StoredCookie`.

## Learnings
To copy into AGENTS.md §11 when the lot closes.
- A shared, multi-writer document must be modelled as "known fields + everything else verbatim"; a strict struct would silently delete other clients' data on the next write.
