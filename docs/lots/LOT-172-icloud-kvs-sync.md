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

- `UbiquitousKeyValueStore` wraps `NSUbiquitousKeyValueStore.default`, under `#if canImport(Darwin)` (not in swift-corelibs-foundation, ARCHITECTURE "Linux rules"); it compiles in the macOS and iOS CI jobs. Its `accountIdentity()` is the archived `ubiquityIdentityToken`, base64 (Apple's way to remember the account across launches), and `isCurrentAccount(_:)` compares it with the current token with `isEqual(_:)`. The change reasons map one to one.
- `InMemorySyncedKeyValueStore`: tests, Linux, previews; `receive(_:updates:identity:)` plays what the system reports, an account switch included.

### `Setting.scope`
`SettingScope` `.device` (default) or `.synced`; `Setting.synced` returns the same setting synced. `SettingKey.all` lists every setting with its scope (`allKeys` derives from it), `SettingKey.syncedKeys` the synced ones. The scopes follow ADR 0013 appendix E key by key (table-driven test):

| Synced | Device |
|---|---|
| `vos_sujets`, `sujets_avec_cat`, `favorites_auto_refresh`, `HFRswiftStartupScreen`, `open_links_in_default_browser`, `topic_page_swipe_navigation`, `reply_button_behavior`, `mp_list_display`, `auto_theme`, `theme`, `theme_style`, the 7 theme keys (`theme_{day,night}_color_{action,love,superfavori}`, `theme_night_brightness`, theme parity), `blacklist_hide_pseudo`, `filter_posts_quotes`, `filter_posts_min_quotes`, `display_sig`, `rehost_use_link`, `rehost_resize_before_upload` | `compact_mode`, `tabbar_minimize_on_scroll`, `text_size_scale`, `text_size_percent`, `haptics`, `landscape_mode`, `icon`, `mp_badge_enabled`, `display_images`, `recherche_categorie`, `FavoritesShowCollapsedSections` (UI state); and, never synced because dropped or replaced: `size_smileys` (no reader, LOT-119), `embedded_videos` (removed from legacy by `d645f52`), `mpstorage_active` (becomes the per-account record of §7, LOT-130), `mpstorage_last_rw` (this device's last sync) |

A setting added to the catalogue later takes its scope from the ADR 0013 matrix; `SettingScopeTests` fails until it is listed there.

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

## Part 2

### What syncs, under which key
One cloud key per list, holding the whole list as JSON (`SyncedValue.data`; sorted keys, dates as seconds since 1970) in an envelope `{"version":1,"items":[…]}`; **last writer wins on the whole list** (ADR 0013 §3). The account key is `AccountKey.make` of the account's `md_user` (ADR 0013 §7).

| Cloud key | Local copy (master on the device) | Items |
|---|---|---|
| `allowlist` | `PseudoListStore` allowlist (LOT-061, global) | LOT-061 entries `{word, alias, mode}` |
| `superfavorites.<account key>` | `SuperFavoritesStore` (LOT-064) | `{topic: {category, topic}, addedAt}` |
| `smileyfavorites.<account key>` | `AppSmileyFavoritesStore` (LOT-064) | `{code, url, addedAt}` |
| `positions.<account key>` | `ReadingPositionStore` (LOT-090) | LOT-090 records `{topic, position: {page, messageNumber, offset, updatedAt}}`, the **200** most recently updated |

- **Allowlist entries carry no date**: LOT-061 never kept one, and a whole-list last-writer-wins needs none. The ADR's `{id, addedAt}` holds for the two per-account lists.
- **Empty is a value**: a push after a local change always writes the envelope, `{"version":1,"items":[]}` included, so removing the last item reaches the other devices; an empty cloud envelope replaces the local list. Only the seeding push of the initial-sync rule skips an empty local list.
- **A key longer than 64 bytes** (UTF-8; Apple's limit, a very long pseudo): an account whose longest key (`smileyfavorites.<account key>`) would exceed it syncs none of its lists, which stay on the device; it is reported in `unsyncedAccounts`. An account whose key is empty is skipped.
- **Accounts**: the sync is given the app's accounts (`Account.id`, the `md_user` value as `AccountBook` stores it, one account per key). Applies and pushes of per-account keys go through that spelling; `ReadingPositionStore` records under another spelling of the same key are neither pushed nor merged. A cloud key of an account the app does not have is left alone.

### `SyncedListsStore`
An actor over the cloud store, the four local stores, the accounts and its own device-state file (`SyncDeviceStateDocument`, separate from the settings mirror's: one writer per file). Its sources (the cloud's `changes()`, each store's `changes()`, the accounts, the reading-position timer) feed one internal `AsyncStream` of events from child tasks of a task group, and `run()` handles the events one at a time: a push never interleaves with an apply, and always starts from the local list as it is after every change already received. Store streams buffer the newest event only (a push reads the live list).

| Event | Rule |
|---|---|
| local change of a list (each store's `changes()`) | the list is pushed when it differs from the list **last synced** under its key (applied or pushed), whose digest the device file keeps; a cloud list that changed meanwhile is another device's, applied when its notification comes, never overwritten by an unchanged local list |
| local change of the reading positions | **debounced**: pushed `positionsDelay` (30 s) after the last change (one timer, restarted at each change), the 200 newest records; `flushPositions()` queues the pending push ahead of any later event (#447 calls it when the app goes to the background; the system uploads from its own queue) |
| server change of one of these keys | a list replaces the local copy (`replace`); positions are **merged** (below) |
| initial sync, first launch, accounts added | for each account and the allowlist: a list changed here since it was last synced is pushed (this device is its later writer); otherwise a cloud list replaces the local one (positions merge) and a non-empty local list the cloud lacks is pushed (first device, LOT-067 import) |
| account change | see "Account change" |
| quota violation | local copy kept; keys in `quotaViolations` |

- **Positions merge** (`ReadingPositionStore.merge`): per topic, the record with the newest `updatedAt` wins, **whatever its page** (a `reset` to an earlier page on another device is a newer point in time; `advance`'s forward-only rule is the reader's, not the sync's). On equal dates with different positions, the one ahead wins (`isAhead`), so every device converges on the same list and nothing ping-pongs. Dates are taken as recorded, never clamped to this device's clock: a clamped date would depend on each device's clock, so two devices would disagree on the winner and push in turn. **Known limitation**: a device whose clock runs ahead wins conflicts on a topic until the others' clocks pass its dates (iOS sets the clock from the network by default, so the skew is normally seconds). The local bound (500) applies after the merge, newest kept.
- **Unreadable envelope** (not JSON, another shape, or a `version` above 1): the local copy is kept and the key is not written, as the settings mirror does for `data` values.
- **Schema version**: the part 1 guard (`schemaVersion` above 1) stops these writes and applies too.
- **A local store that cannot load** (LOT-061/064/090 failure guard) is neither pushed nor overwritten while it fails. A replace or merge the store cannot save records nothing as synced and pushes nothing over the cloud.
- **Device file**: it keeps the owner, the stale stores, the quarantine and the digests of the lists last synced. Unreadable, it stops the sync (the owner is unknown); a save that fails pauses it until a save succeeds (a quarantine kept in memory meanwhile is written then), so the next launch never reads an owner older than the lists. Residual: if it stays unwritable for the whole session, the lists the user edits meanwhile are set aside under the previous owner at the next launch, which still names it.

### Account change
Operator decision (2026-11-06, ADR 0013 Amendment 2): **the lists stay on the device when the Apple ID signs out**; they are set aside only when a different Apple ID signs in. The device file keeps the **owner**: the Apple ID the local lists belong to (the last one signed in), recorded at the first sign-in seen.

- **Signed out**: nothing is applied or pushed; the lists stay as they are and local changes keep accumulating for the owner.
- **The owner signs in again**: nothing is set aside; the initial-sync rule runs: a list changed while signed out is pushed (the digests survive a relaunch), the others take the cloud's.
- **A different Apple ID signs in**, seen live or at launch: the local synced lists are enumerated **from the stores** (every account key they hold, not only the app's accounts, and the allowlist), saved under the owner as envelopes (positions in full, up to 500 per account), then removed from the stores. Device-scoped data (blocklists, drafts, histories) is never touched. The new Apple ID becomes the owner once the device file says so, its quarantine comes back where the local list is empty (a list that cannot come back stays in the quarantine), then the initial-sync rule. A quarantine lasts 90 days and is kept in memory when the file cannot be saved, as in part 1.
- **No owner yet** (first launch, or never signed in): the first Apple ID seen becomes the owner and the initial-sync rule runs: the lists made without an account seed it where the cloud has none (ADR 0013 §5 step 2).
- **A store that could not load or be emptied** at the change keeps its content; the device file remembers which owner it holds. When it can, that content is set aside under its owner before anything else, never pushed, and the current owner's quarantined lists come back into it; a store found empty (its unreadable data discarded, which signals it) only stops being stale. Residual: an add saved between the discard and the sync's handling of its signal is set aside under the previous owner.
- **Launch-time change**: after a change seen at launch, lists are neither applied nor pushed until the first notification of the store (`accountChange`, `initialSync` or `serverChange`) or 5 s after `synchronize()`, which narrows part 1's known limitation (the previous Apple ID's content still in the store under the new identity).
- **Local add racing an apply**: a user's add saved between the sync's read of the cloud and its `replace` is overwritten by the cloud list (whole-list last writer wins); the UI drops it at its next reload. Accepted: the window is one apply.
- The settings mirror (part 1) keeps its own rule: scalar preferences are set aside at a sign-out (ADR 0013 Amendment 1).

### Local store additions
- `SuperFavoritesStore.replace(_:account:)`, `AppSmileyFavoritesStore.replace(_:account:)`, `PseudoListStore.replaceAllowlist(with:)` (entries, aliases and modes kept), `ReadingPositionStore.merge(_:account:)`: each normalises what it receives with the store's own rules (duplicates, order, bound) and returns whether anything changed; plus the account keys each holds, for the quarantine.
- Each store gets `changes()`, yielded after a successful save (the account, or the allowlist); the blocklist (MPStorage's, not iCloud's) yields nothing. The app's screens can use the same streams to refresh after an apply (#447).

### Budget
Measured, not estimated (`SyncedBudgetTests`): the worst case of the ADR 0013 appendix, encoded as the stores write it with long pseudos, smiley codes and URLs and fractional-second dates, is about 293 KiB in 46 keys for 5 accounts (positions are the largest list): under Apple's 1 MB and 1024 keys, but above the appendix's "< 200 KiB" (its 40 B per position was about a third of the real size). The test checks < 320 KiB and ≤ 60 keys (ADR 0013 Amendment 2).

### Not in this lot
The app wiring (building `SyncedListsStore`, starting `run()`, `flushPositions()` on background, a notice after an account change) is #447, with the settings mirror. The MPStorage sync-state record of §7 belongs to LOT-130.

## Edge cases
- A synced key the cloud holds as `data` (a newer format) is not a setting value: the mirror keeps its own value.
- The settings mirror's `run()` ends when the store's stream ends; the list sync's `run()` ends when its task is cancelled. The app starts each once and calls `synchronize()` at launch and on foreground (ADR 0013 §4, #447).
- Without the iCloud entitlement (LOT-160) or an iCloud account, `NSUbiquitousKeyValueStore` keeps values on the device; the mirror behaves the same.

## Fixtures
None: no HFR page; synthetic values.

## Intentional differences from legacy
Legacy had no sync at all: every synced key now follows the Apple ID (ADR 0013). `mpstorage_active` is never synced (its replacement is per account, §7).

## Tests (part 1)
`SettingScopeTests` (every catalogue key against the matrix, the theme keys, no secret or draft key, `synced` keeps codec and default) and `SyncedSettingsStoreTests` (synced and device writes, reads from the mirror only, server change, initial sync cloud-wins and push, account change quarantine with the new account's values at once, restore to the same account only, an account change or a sign-out while the app was not running, first launch, first sign-in keeping values written without an account, 90-day purge, an unsavable quarantine kept in memory and never uploaded, quota violation, newer schema, a write and a server change never interleaving, `run()`, device-state file round trip). Mutations are listed in the PR.

## Learnings
- "Never upload account A's values under account B" holds by emptying the mirror at the change and taking the new account's content at once; waiting for an initial-sync notification is not safe, the system does not promise one. An account can change while the app is not running: keep the last one seen on the device.
- Part 2: "cloud wins" at an initial sync silently drops a list changed here since its last sync (while signed out, or a signal still queued): keep, on the device, a digest of each list last synced and push a list that differs from it. A position date clamped to each device's clock makes devices disagree on the winner and push in turn: take dates as recorded.
