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
A `SettingsStore` over the local store (the `UserDefaults` mirror `@AppStorage` reads), the cloud store and a device-only state file (`SyncDeviceStateDocument`, LOT-064's `SmallStorePersistence`): the last iCloud account seen and the quarantine. Reads always come from the local store: the engine never reads iCloud on the hot path (ADR 0013 §2). A write goes to the local store, and, for a synced key, to the cloud store too, stamping `schemaVersion`. Each write and each change runs as one critical section, so a write and a change never interleave; the local store must not call back synchronously.

| Change (`apply`, or `run()` over `changes()`) | Rule (ADR 0013 §3) |
|---|---|
| server change | each synced key of the change takes the cloud value in the mirror (removed when the cloud removed it): last writer wins per key |
| initial sync | for every synced key, the cloud value wins; a key the cloud lacks is pushed from the mirror (a first device, or values imported from legacy, ADR 0013 §5 step 2) |
| account change (another Apple ID, or signed out) | the mirror's synced values move to the quarantine under the previous account and leave the mirror, so nothing of that account is ever uploaded under the new one; the new account's own quarantine comes back for the keys the mirror lacks; then the initial-sync rule runs on the store's content, which the system has already replaced. No wait for an initial-sync notification: Apple does not guarantee one after an account change (ADR 0013 Amendment 1). Device-scoped settings are untouched |
| account change while the app was not running | the device file keeps the last account seen (Apple's archived `ubiquityIdentityToken`, compared with `isEqual(_:)`); at launch a different account runs the account-change rule. **Known limitation**: if the token is already the new account's while the system has not replaced the store's content yet, the old account's cloud values can reach the mirror under the new identity, and the later account-change notification (same token) does not quarantine them; a small window inherent to Apple's API |
| first launch (no device file) | the account is recorded and the initial-sync rule runs: device values first (defaults set, the LOT-067 legacy import, which must therefore run before the store is built), then the cloud (ADR 0013 §5 step 2) |
| quota violation | the local value is kept; the keys are reported in `quotaViolations` (the app logs them) |

- **Quarantine lifetime**: entries older than 90 days are deleted at creation of the store, at every account change and initial sync.
- **A device file that cannot be written** keeps a quarantine in memory, never in the mirror: it is not uploaded, comes back if its account returns during the process's life, and `deviceStateFailure` says so.
- **Schema version**: while the cloud's `schemaVersion` is above this build's (1), the store neither applies cloud values nor writes to the cloud; it keeps working locally.
- **No account**: values written while no Apple ID is signed in belong to none: at the first sign-in they stay in the mirror and meet the new account's values (cloud wins, the rest is pushed). Signing out quarantines the signed-out account's values; while signed out, writes go to the store's device-local copy, which the system replaces at the next sign-in.
- **Identity**: `UbiquitousKeyValueStore.accountIdentity()` is the archived token, base64; a token that cannot be archived reads as "no account" (the change is then handled as a sign-out). The in-memory store compares identities as strings.
- **Pending writes**: a write the system has not uploaded yet is also in the mirror, so it is quarantined with it; the system's own upload queue cannot be cancelled from the app.
- **App wiring** (building this store instead of `UserDefaultsSettingsStore`, running `run()`, calling `synchronize()` at launch and on foreground, the device-state file location) needs the iCloud entitlement (LOT-160, ADR 0013 §9) and is [#447](https://github.com/ezzz/HFRnow/issues/447).

### Not secrets
No synced key holds a cookie, a token or a draft (test over `syncedKeys`); accounts and cookies stay in the Keychain (LOT-065, ADR 0013 §6).

### Account key
The per-account suffix of part 2's keys is `AccountKey.make` (LOT-064, ADR 0013 §7: U+200B removed, then lower-cased, nothing else), already pinned by `AccountKeyTests`; LOT-072 left it untouched.

## Edge cases
- A synced key the cloud holds as `data` (a newer format) is not a setting value: the mirror keeps its own value.
- `run()` ends when the store's stream ends; the app starts it once and calls `synchronize()` at launch and on foreground (ADR 0013 §4, #447).
- Without the iCloud entitlement (LOT-160) or an iCloud account, `NSUbiquitousKeyValueStore` keeps values on the device; the mirror behaves the same.

## Fixtures
None: no HFR page; synthetic values.

## Intentional differences from legacy
Legacy had no sync at all: every synced key now follows the Apple ID (ADR 0013). `mpstorage_active` is never synced (its replacement is per account, §7).

## Tests (part 1)
`SettingScopeTests` (every catalogue key against the matrix, the theme keys, no secret or draft key, `synced` keeps codec and default) and `SyncedSettingsStoreTests` (synced and device writes, reads from the mirror only, server change, initial sync cloud-wins and push, account change quarantine with the new account's values at once, restore to the same account only, an account change or a sign-out while the app was not running, first launch, first sign-in keeping values written without an account, 90-day purge, an unsavable quarantine kept in memory and never uploaded, quota violation, newer schema, a write and a server change never interleaving, `run()`, device-state file round trip). Mutations are listed in the PR.

## Learnings
- "Never upload account A's values under account B" holds by emptying the mirror at the change and taking the new account's content at once; waiting for an initial-sync notification is not safe, the system does not promise one. An account can change while the app is not running: keep the last one seen on the device.
