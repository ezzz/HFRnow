# LOT-172 — iCloud key-value sync store

- **Module:** HFRStorage (`Sources/HFRStorage/Sync/`, `Settings/Setting.swift`, `Settings/SettingKey.swift`)
- **Difficulty / model:** medium (Opus 5.5 author → Fable 5.1 reviewer; the plan routes Sonnet → Opus)
- **Issue:** [#311](https://github.com/ezzz/HFRnow/issues/311) · implements [ADR 0013](../adr/0013-storage-tiers.md) (§1-4, §9, appendix E-F) and the position part of FEAT-015 (#159)
- **Depends on:** LOT-060 (settings: `Setting`, `SettingKey`, `SettingsStore`), LOT-061 (allowlist), LOT-064 (`AccountKey`, small-store core), LOT-090 (reading positions), all done.
- **Delivery:** two PRs. **Part 1** (this one, `Refs #311`): the synced store, `Setting.scope`, the settings mirror and every ADR 0013 §3 rule. **Part 2** (`Closes #311`): the list envelopes (allowlist, super-favourites, smiley favourites), the bounded reading positions and the worst-case budget test.

## Sources
No legacy code: the legacy app has no iCloud (audit E §2, "No App Group, no iCloud"). The rules come from ADR 0013 (operator decisions of 2026-10-28/29) and Apple's `NSUbiquitousKeyValueStore` contract (1024 keys, 1 MB, last writer wins per key, `didChangeExternallyNotification` with the reasons server change, initial sync, quota violation, account change). No HFR fact is involved: no capture, no HFR-PROTOCOL subsection.

## Part 1

### `SyncedKeyValueStore` (protocol) and its two implementations
`value(forKey:)`, `set(_:forKey:)`, `removeValue(forKey:)`, `synchronize()`, `accountIdentity()`, `changes() -> AsyncStream<SyncedStoreChange>` (each call its own stream). Values are `SyncedValue`: the four settings shapes plus `data` for part 2's JSON documents.

- `UbiquitousKeyValueStore` wraps `NSUbiquitousKeyValueStore.default`, under `#if canImport(Darwin)` (not in swift-corelibs-foundation, ARCHITECTURE "Linux rules"); it compiles in the macOS and iOS CI jobs. Its `accountIdentity()` is a SHA-256 of the archived `ubiquityIdentityToken`: stable per Apple ID, never the token itself. The change reasons map one to one.
- `InMemorySyncedKeyValueStore`: tests, Linux, previews; `receive(_:updates:identity:)` plays what the system reports, an account switch included.

### `Setting.scope`
`SettingScope` `.device` (default) or `.synced`; `Setting.synced` returns the same setting synced. `SettingKey.all` lists every setting with its scope (`allKeys` derives from it), `SettingKey.syncedKeys` the synced ones. The scopes follow ADR 0013 appendix E key by key (table-driven test):

| Synced | Device |
|---|---|
| `vos_sujets`, `sujets_avec_cat`, `favorites_auto_refresh`, `HFRswiftStartupScreen`, `open_links_in_default_browser`, `auto_theme`, `theme`, `theme_style`, the 7 theme keys (`theme_{day,night}_color_{action,love,superfavori}`, `theme_night_brightness`, theme parity), `blacklist_hide_pseudo`, `filter_posts_quotes`, `filter_posts_min_quotes`, `display_sig`, `rehost_use_link`, `rehost_resize_before_upload` | `compact_mode`, `tabbar_minimize_on_scroll`, `text_size_scale`, `text_size_percent`, `haptics`, `landscape_mode`, `icon`, `mp_badge_enabled`, `display_images`, `recherche_categorie`; and, never synced because dropped or replaced: `size_smileys` (no reader, LOT-119), `embedded_videos` (removed from legacy by `d645f52`), `mpstorage_active` (becomes the per-account record of §7, LOT-130), `mpstorage_last_rw` (this device's last sync) |

`topic_page_swipe_navigation` and `reply_button_behavior` (synced in the matrix) are not in the LOT-060 catalogue yet; the lot that adds them gives them `.synced`.

### `SyncedSettingsStore` (the mirror)
A `SettingsStore` over the local store (the `UserDefaults` mirror `@AppStorage` reads), the cloud store and a device-only quarantine file (`SyncQuarantineDocument`, LOT-064's `SmallStorePersistence`). Reads always come from the local store: the engine never reads iCloud on the hot path (ADR 0013 §2). A write goes to the local store, and, for a synced key, to the cloud store too, stamping `schemaVersion`.

| Change (`apply`, or `run()` over `changes()`) | Rule (ADR 0013 §3) |
|---|---|
| server change | each synced key of the change takes the cloud value in the mirror (removed when the cloud removed it): last writer wins per key |
| initial sync | for every synced key, the cloud value wins; a key the cloud lacks is pushed from the mirror (a first device, or values imported from legacy, ADR 0013 §5 step 2) |
| account change (another Apple ID, or signed out) | the mirror's synced values are moved to the quarantine under the previous account's identity and removed from the mirror; until the new account's initial sync, synced writes stay local and server changes are ignored, so nothing of the previous account reaches the new one; device-scoped settings are untouched |
| initial sync after an account change | as above; if the now-active account has a quarantine, its values come back first (for the keys the mirror lacks), then the cloud wins where it has a value; the entry is removed. Another account's quarantine is never restored |
| quota violation | the local value is kept; the keys are reported in `quotaViolations` (the app logs them) |

- **Quarantine lifetime**: entries older than 90 days are deleted at creation of the store, at every account change and initial sync.
- **A quarantine that cannot be saved** (unreadable file, failed write) keeps its values in memory, never in the mirror: they are not uploaded, come back if their account returns during the process's life, and `quarantineFailure` says so.
- **Schema version**: while the cloud's `schemaVersion` is above this build's (1), the store neither applies cloud values nor writes to the cloud; it keeps working locally.
- **No account**: values written while no Apple ID is signed in belong to none: at the first sign-in they stay in the mirror, synced writes wait for the initial sync, then the cloud wins and the rest is pushed (as for a first device). Signing out quarantines the signed-out account's values; while signed out, synced writes stay local (no initial sync comes), which is the device-only behaviour ADR 0013 §4 asks for.
- **Pending writes**: a write the system has not uploaded yet is also in the mirror, so it is quarantined with it; the system's own upload queue cannot be cancelled from the app.

### Not secrets
No synced key holds a cookie, a token or a draft (test over `syncedKeys`); accounts and cookies stay in the Keychain (LOT-065, ADR 0013 §6).

### Account key
The per-account suffix of part 2's keys is `AccountKey.make` (LOT-064, ADR 0013 §7: U+200B removed, then lower-cased, nothing else), already pinned by `AccountKeyTests`; LOT-072 left it untouched.

## Edge cases
- A synced key the cloud holds as `data` (a newer format) is not a setting value: the mirror keeps its own value.
- `run()` ends when the store's stream ends; the app starts it once and calls `synchronize()` at launch and on foreground (ADR 0013 §4).
- Without the iCloud entitlement (LOT-160) or an iCloud account, `NSUbiquitousKeyValueStore` keeps values on the device; the mirror behaves the same.

## Fixtures
None: no HFR page; synthetic values.

## Intentional differences from legacy
Legacy had no sync at all: every synced key now follows the Apple ID (ADR 0013). `mpstorage_active` is never synced (its replacement is per account, §7).

## Tests (part 1)
`SettingScopeTests` (every catalogue key against the matrix, the theme keys, no secret or draft key, `synced` keeps codec and default) and `SyncedSettingsStoreTests` (synced and device writes, reads from the mirror only, server change, initial sync cloud-wins and push, account change quarantine and block, restore to the same account only, 90-day purge, unsaved quarantine kept in memory and never uploaded, quota violation, newer schema, first sign-in keeping values written without an account, `run()`, quarantine file round trip). Mutations are listed in the PR.

## Learnings
- A rule "never upload account A's values under account B" is easiest to hold by emptying the mirror at the change and blocking writes until the new initial sync, rather than by filtering every write.
