# 0013 — Where persisted data lives: MPStorage, iCloud key-value store, or the device

**Status:** Accepted — 2026-10-28 (operator decisions of 2026-10-28; drafted by session `mac/storage-adr-fable`)

## Context

The legacy app keeps its data in four places (audit [E §2–3](../audit/E-storage-vendors.md)): the Keychain (accounts), `UserDefaults` (≈ 60 keys: preferences, counters, UI state, the composer draft), files in `Documents/` (blacklist, allowlist, smiley favourites, rehost history) and **MPStorage**, a private-message thread used as a JSON document (`Classes/MPStorage.m`, [HFR-PROTOCOL §3.3](../HFR-PROTOCOL.md#33-mpstorage-bookmarks-synced-blacklist-mp-flags)). MPStorage is the only store that follows the **HFR account** across devices and clients: the document is also written by web userscripts (DTCloud and others, 13+ namespaces in one real document) and read by the Android client redface2 ([research](../research/redface2-comparison.md) E23, C8). It is also the most fragile: one thread, whole-document read-modify-write, a 64 KiB cap shared by every writer, no locking (LOT-062 adds a three-way merge).

Nothing follows the **Apple ID** today: no App Group, no iCloud (audit E §2). A user with an iPhone and an iPad configures the app twice and loses the allowlist, super-favourites and smiley favourites on a new device (audit E §4.2).

The operator asked (2026-10-28) for a matrix deciding what belongs in MPStorage and what can live on the phone and be backed up or synced through iCloud, by transferability from one platform to another, with simplifications. The lots that persist data (LOT-060 settings, 061 lists, 063 drafts, 064 small stores, 065 accounts, 066 caches, 067 import, 090 reading positions, 091 notification ledger, 119 settings screen, 130 MPStorage sync) need one rule instead of one decision each.

Constraints: AGENTS.md rule 3 (no new dependency), rule 4 (no secrets outside the Keychain), the module boundaries of [ADR 0001](0001-modular-swift-packages.md) and [ADR 0008](0008-hfrclient-orchestration-module.md) (HFRStorage stays Foundation-only and builds on Linux), the Keychain accessibility decided for accounts (Q-9: this device only), the `NSUbiquitousKeyValueStore` limits (1 MB and 1024 keys per app, last-writer-wins per key).

## Decision

### 1. Four tiers, chosen by transferability first

| Tier | Follows | Used for |
|---|---|---|
| **MPStorage** | the HFR account, every client | data another HFR client already reads or writes under the v0.1 schema: `blacklist`, `bookmarks`, `mpFlags`; every foreign namespace is preserved verbatim and never modelled |
| **iCloud key-value store** (`NSUbiquitousKeyValueStore`) | the Apple ID, SwiftHFR on iPhone/iPad/Mac | small, low-churn **content preferences**, the three Apple-only lists (allowlist, super-favourites, app-local smiley favourites) and the **fine reading position** (page, last message seen, scroll offset) |
| **Device, backed up** (UserDefaults, `Application Support/`, `Documents/`) | one device, restored by a device backup | device presentation and capability preferences, transient UI state, drafts, counters, histories, local copies and merge bases of the two tiers above |
| **Device, not backed up** (`Library/Caches/`, Keychain `ThisDeviceOnly`) | one device | caches, offline pages, **accounts and cookies** (plus an opt-in synchronizable copy, §6) |

The rules, in order:

1. **Transferability.** If another platform reads or writes the item today under a known schema, it goes to MPStorage, wire-compatible, and nowhere else as a master. If no other platform has the feature, it never enters MPStorage on our own initiative: a new namespace in a document shared by 13 writers needs a contract with the other clients first ([#310](https://github.com/ezzz/HFRnow/issues/310) for the allowlist and super-favourites, with the Android app's maintainers; the userscripts' `superFavs` and `lastRead` namespaces are revisited once a real document is captured, [#272](https://github.com/ezzz/HFRnow/issues/272)).
2. **Privacy.** Secrets (cookies, `hash_check`) stay in the Keychain and never enter MPStorage or iCloud KVS. Personal data that identifies other members (blacklist, allowlist) may sync because both stores are private to the user; unsent drafts and upload histories do not leave the device.
3. **Size and churn.** iCloud KVS gets only values that stay far under the quota (budget in the appendix: < 200 KiB, < 60 keys for five accounts) and that change at human speed. The fine reading position is the one exception, admitted because the operator wants it on every Apple device: it is debounced and bounded (LOT-172). Drafts, counters and histories are device-only. Anything large or rebuildable (caches, offline pages) is device-only and excluded from backup.
4. **Device semantics.** A preference whose right value depends on the device (icon, haptics, rotation, density, text size, cellular policy, badges) stays on the device even if small.

The item-by-item application is the matrix in the appendix: the registry of persisted items. A lot that persists something new picks a tier by these rules and adds its row. The split for settings becomes an attribute of `Setting<Value>` (LOT-060): `scope: .synced | .device`.

### 2. One master per item

An item has exactly one authoritative store and at most one local copy:

- MPStorage items: the forum document is the master; the device keeps the last document read (`base` for LOT-062's merge) and the pending edits. Reads come from the local copy; writes are local-first and synced when a session is available (legacy's sync-first add, which aborted the local change on a network error, is dropped: audit E §7 item 6). On a successful remote read the local list is **merged**, not replaced (legacy `MPStorage.m:202-215` replaced it; audit Q-4).
- iCloud KVS items: KVS is the master; `UserDefaults` is the mirror that `@AppStorage` and the synchronous `SettingsStore` read. A write goes to both; an external-change notification updates the mirror. The engine never reads KVS on the hot path.
- A device-only item has no copy.

### 3. Conflict policy

| Store | Policy | Why |
|---|---|---|
| MPStorage | per-item three-way merge of LOT-062 (`base`, `ours`, `theirs`), ours wins when both changed, tombstones off until other writers are known to keep them | already decided (LOT-062, Q-6) |
| iCloud KVS, scalar preferences | **last writer wins per key**, as the store does; on the initial sync (`NSUbiquitousKeyValueStoreInitialSyncChange`) the cloud value wins over the local one | the only conflict is the same setting changed on two devices while offline; the later tap is the user's intent |
| iCloud KVS, lists (allowlist, super-favourites, smiley favourites) | **last writer wins on the whole list**, each list one key holding `{version, items:[{id, addedAt}]}`; a union merge with tombstones is the documented upgrade if users report lost adds | simplification: these lists change a few times a month; a merge layer would duplicate LOT-062 for three tiny lists |
| iCloud KVS, reading positions | last writer wins per topic key; the newest `updatedAt` is kept when both devices wrote | a position is a point in time |
| iCloud account change (`NSUbiquitousKeyValueStoreAccountChange`, sign-out) | the system replaces the store's content with the new Apple ID's data: the app **quarantines** the previous mirror values and any pending KVS write (moved to a device-only file, never uploaded under the new Apple ID), blocks synced reads and writes until the new account's initial sync has completed, then applies the new account's values to the mirror. Device-scoped settings are untouched. The quarantined values are restored only if that Apple ID becomes active again, and deleted after 90 days. A schema version key lets an older build ignore values it cannot read | one Apple ID's data never reaches another Apple ID's store; nothing is lost because the Apple ID changed |

### 4. Offline behaviour

- MPStorage: read from the local copy; edits are queued in the local document and merged on the next successful sync; the UI shows the last sync from `mpstorage_last_rw` (persisted for real, LOT-060). A failed sync never undoes a local edit.
- iCloud KVS: writes land in the local mirror and in the store's on-device queue; the system uploads later. The app calls `synchronize()` at launch and on foreground, and treats a missing iCloud account as "device-only" without a warning.
- Device tiers: unaffected.

### 5. Migration from the legacy app (LOT-067 and LOT-158; same bundle id, Q-1)

SwiftHFR ships as an in-place update of `hfrplus.red.super` under the ezzz team, so the legacy container is readable and the legacy data is **kept** (operator 2026-10-28):

1. Import everything into the **device** tiers first, with the LOT-067 plan: UserDefaults keys under their legacy names, `blackListDico.plist` / `whiteList.plist` into the LOT-061 document, `smiley_favorites_cache2` into LOT-064, `composerDraftText` into `DraftContext.legacyGlobal`, Keychain accounts into LOT-065 (device-only item). The legacy super-favourites and app-local smiley favourites are **global** (`SuperFavoritesIds` is one `UserDefaults` key: `HFRswift/Swift/Favorites.swift:133-155`, `Classes/FavoritesTableViewController.m:81-82, 1657`; `smiley_favorites_cache2` is one file in `Documents/`: `Classes/SmileyCache.m:18, 353-354`) while SwiftHFR keeps them **per HFR account** (operator 2026-10-29): both are imported into the account that is active at the first import, once, and every other account starts empty ([CHANGELOG-LEGACY](../CHANGELOG-LEGACY.md) row 30). The steward chose that default; the operator may override it in the LOT-067 spec.
2. Then enable the KVS mirror: for each synced key, if the cloud has no value, push the imported one; if it has one (another device migrated first), the cloud wins (initial-sync rule). Lists follow the same rule, whole list.
3. MPStorage needs no migration: same thread, same schema `0.1`; the document is re-read on first sync and becomes the merge base.
4. The legacy keys dropped by LOT-060 are read once where a migration exists (`size_text_topics`), otherwise ignored; nothing is deleted from the legacy container (LOT-067 rule).

### 6. Accounts: device-only by default, opt-in iCloud Keychain sync, optional app lock (Q12)

Accounts stay in a device-only Keychain item (LOT-065, Q-9). Two options, both off by default, are added by LOT-173 ([#312](https://github.com/ezzz/HFRnow/issues/312)):

- **"Synchroniser mes comptes via le trousseau iCloud"**: when on, the credential envelope is also written to a second, **synchronizable** Keychain item (`kSecAttrSynchronizable`, `AfterFirstUnlock`), which iCloud Keychain carries to the user's other devices end to end encrypted. The setting explains what travels and how to stop. Rules of the copy (one item, one envelope, `updatedAt` in the envelope):
  - *Master.* The device-only item stays the master on each device; every change to it (login, re-login, deletion, main account) is pushed to the synchronizable item while the switch is on.
  - *Bootstrap.* A device with no device-only item that finds a **full envelope** (accounts present, no `deletedAt`) in the synchronizable item, whose `enabledAt` is **later than every `deletedAt` the device knows** (its `honouredDeletedAt`, when it has one), imports it into a new device-only item, adopts its `enabledAt` and turns the switch on; the imported accounts are not logged in again (the cookies are the session). A **tombstone** bootstraps nothing: the switch stays off, the device records the tombstone's `deletedAt` as `honouredDeletedAt`, creates **no** device-only item, and the user logs in. An absent item bootstraps nothing either and records nothing. A full envelope whose `enabledAt` is not later than a known `deletedAt` is a raced envelope (*Race repair*), never a bootstrap source.
  - *Divergence.* On launch and on foreground, when both items exist and differ, the **newer `updatedAt` wins the whole envelope** (last writer wins, like the KVS lists): a credential refreshed on another device replaces the local copy, a device that was offline longer loses its stale copy. `AccountBook.init(accounts:)` repairs duplicates and the main flag after a replacement; accounts are never silently merged into more than the user had on the winning side.
  - *Switching off.* Replaces the synchronizable item's envelope with a dated **tombstone** (`{"version":1,"deletedAt":<date>,"accounts":[]}`, no credential) instead of deleting the item, so the other devices receive a positive signal: a device whose switch is on and that reads a tombstone whose `deletedAt` is **not earlier** than its `enabledAt` (a tie switches off too: the *Write side* rule) turns its switch off and keeps its device-only item; turning the switch on again anywhere overwrites the tombstone with a full envelope. The **absence** of the item (`errSecItemNotFound`) proves nothing: iCloud Keychain may not have delivered it yet, or the user may have cleared it. It leaves the switch and the device-only item as they are, is retried at the next launch and foreground, and is never a reason to push the local envelope. Switching off never deletes a device-only item anywhere.
  - *Write side (every push).* A push is a read-compare-write on the synchronizable item, never a blind write. The envelope carries `enabledAt`, the date of the last explicit switch-on: the **logical version** of the sharing, held by every device whose switch is on (set by its own switch-on, or adopted at *Bootstrap* or *Divergence*) and carried unchanged by every credential push. Each device also remembers `honouredDeletedAt` (the newest tombstone it acted on). Wall-clock write times are never compared. Before writing, the device reads the item: a **tombstone** whose `deletedAt` is not earlier than the device's `enabledAt` (`deletedAt >= enabledAt`: a tie fails closed) wins, so the device does not push, turns its own switch off, records `honouredDeletedAt` and keeps its device-only item (the local `updatedAt` and the wall-clock time of the device's last write play no part, and there is no `lastPushed`: an opt-out is never undone by a credential change, whatever its date); a full envelope newer than the local one is applied first (*Divergence*), then the local change is pushed on top with the same `enabledAt`; an **absent** item is not re-created by a credential change (the push is skipped and retried later). **Only the explicit switch-on action overwrites a tombstone**, writing a full envelope whose `enabledAt` is strictly later than that `deletedAt` (and than the device's `honouredDeletedAt`).
  - *Race repair.* iCloud Keychain has no conditional write, so a device that read a full envelope just before another device wrote the tombstone can still overwrite it. Its envelope betrays the race: `enabledAt` older than the tombstone's `deletedAt`. A device that honoured the tombstone keeps reading the item at launch and foreground while its switch is off; when it finds a full envelope with `enabledAt < honouredDeletedAt`, it re-writes the tombstone (same `deletedAt`). The racing device's next read-compare then sees a tombstone whose `deletedAt` is not earlier than its `enabledAt` and switches off, whatever the wall-clock order of the writes (a stale write at 160 over a tombstone at 150 is still caught, because the stale envelope's `enabledAt` is older than 150). The writer of the tombstone counts as having honoured it (its `honouredDeletedAt` is its own `deletedAt`), so it takes part in the repair like any other switched-off device. Tombstone dominance is therefore monotonic: a tombstone yields only to a later explicit switch-on, never to a push. The repair is eventual, not atomic: between the stale write and the next read of a switched-off device, the credentials can be visible again in the synchronizable item (encrypted, on the user's own devices); no device bootstraps from them (*Bootstrap* refuses an envelope that is not later than a known tombstone). LOT-173 tests this interleaving (stale read, tombstone, stale write, repair, switch-off) and the tie case against an in-memory item.
  - *Clock skew (accepted residual risk, operator 2026-10-29).* `enabledAt` and `deletedAt` are the wall-clock dates of two user actions on two devices, not a generation counter: if a device's clock runs ahead, an earlier switch-on can outrank a later opt-out. The fail-closed rules (a tie switches off, bootstrap only above every known tombstone, no push ever re-creates sharing) and the user's own devices running on network time keep that window small. A generation counter was rejected: it needs a shared sequence, which an item with no conditional write cannot provide.
  These rules are confirmed by the maintainer in the LOT-173 spec before implementation; the ADR records the default.
- **App lock** (Face ID / Touch ID / device code, `LocalAuthentication`) with a grace delay, covering every scene.

Nothing else about secrets changes: no password is stored, no cookie leaves the Keychain.

### 7. MPStorage sync: on when the account already has a storage thread, else asked at the first write (Q14)

Blacklist and bookmarks stay in MPStorage. The legacy app-wide boolean `mpstorage_active` becomes a **per-HFR-account record** `mpstorage.<account key>` = `{state, decidedAt}` with `state` in `unasked` (default), `on`, `declined`, `off` (turned off in Settings), kept in iCloud KVS (one small key per account, same scope rules as the lists).

**Account key** (every per-account KVS key: this record, the lists, the reading positions): the `PseudoNormalizer.normalize` form of LOT-061, that is the account's `md_user` pseudo with every U+200B removed, then lower-cased (`Alice` and `alice` share a key, as they share a blocklist), used as is as the key suffix. It is the one normalisation the engine already has for account-keyed documents; LOT-065's stricter `AccountBook` normalisation (format characters, trimming) applies before an account is stored, so a stored pseudo is already trimmed. The key form is **frozen** at this two-step definition (U+200B removed, then lower-cased, nothing else): LOT-172 keeps its own `accountKey` function pinned by a table-driven test, and when LOT-072 ([#96](https://github.com/ezzz/HFRnow/issues/96)) replaces the engine's normalisers it leaves that function alone, so no stored KVS key ever changes. Frozen rather than migrated, because a key migration would have to run on every device of the Apple ID at once while KVS is last-writer-wins per key with no ordering across devices: a device on an older build would keep writing the old keys and the two key sets would diverge silently. The rules of the record:

- At login or first sync, while the record is `unasked`, LOT-130 looks for the account's storage thread (the LOT-038 scan, read-only). **Found → `on`** for that account: the user already chose it in another client, and reading the document costs nothing.
- **Not found → the app asks** at the first bookmark or blacklist write, because creating the thread is a write to the forum (a private message to `MultiMP`); until the user answers, the list stays device-only. Declining sets `declined` for that account only; Settings shows the state per account and can set `on` or `off` later.
- Sync runs for an account only when its record is `on`; one account's state never applies to another. The legacy `mpstorage_active` key is read once by the import (LOT-067): `true` → every imported account starts `on`, `false` → `unasked`; the key is not written any more.

### 8. Simplifications (settings dropped or merged)

| Change | Legacy keys | Replacement |
|---|---|---|
| One appearance picker | `auto_theme` + `theme` | one `appearance` value (`system`, `light`, `dark`), still stored under the two legacy keys for import and `@AppStorage` compatibility |
| Theme parity, no merge (operator 2026-10-29) | `theme_day_color_action`, `theme_night_color_action`, `theme_day_color_love`, `theme_night_color_love`, `theme_day_color_superfavori`, `theme_night_color_superfavori`, `theme_night_brightness` | the 7 keys unchanged, each synced (LOT-121 "Theme parity"): every colour already decided is kept, they are only accents and ship together; FEAT-010's single accent colour is out of scope |
| One text size | `size_text`, `size_text_topics`, `size_text_reply`, `text_size_scale` | `text_size_percent` (LOT-119, LOT-169), device-only |
| Dropped, no reader | `embedded_videos` (removed from legacy by `d645f52`), `shake_to_refresh`, `theme_noel_*`, `noel_first_time_2022`, `version`, `default_tab` (superseded by `HFRswiftStartupScreen`), `adv_ssl`, `mpstorage_reset`, `EmptyCacheButton`, `theme_*_adjust`, `theme_*_tintcolor`, `force_manual_theme`, `auto_theme_*_time`, `arrayCategoriesVisibleOrder`, `arrayCategoriesHiddenOrder`, `forumsCache.plist`, `HFRswiftOpenMessagesFromNotificationPending` | — |
| Dropped unless the reader reads it | `size_smileys` | the reader's CSS decides smiley size (LOT-083/106); keep the key only if the renderer reads it |
| Kept as legacy | `vos_sujets`, `sujets_avec_cat`, `favorites_auto_refresh` | unchanged (the FEAT-001 Home proposal is not implemented, operator 2026-10-28) |
| No user-facing "sync with iCloud" switch for KVS | — | on whenever the device has an iCloud account, like Apple's own apps; the data is private to the Apple ID and small. (The Keychain sync of accounts is the one opt-in switch, §6.) |
| No per-account settings | — | preferences stay app-wide (as legacy); only the lists, the reading positions, the MPStorage sync state (§7) and the MPStorage items are per HFR account |
| Four keys added on `master` after the audit | `HFRswiftStartupScreen`, `topic_page_swipe_navigation`, `open_links_in_default_browser`, `reply_button_behavior` | in the LOT-060 catalogue (two of them by LOT-119), synced |

### 9. Needs

- **iCloud capability** on the App ID `hfrplus.red.super` (team of ezzz) with the *Key-value storage* service only (no CloudKit container), and the entitlement `com.apple.developer.ubiquity-kvstore-identifier` = `$(TeamIdentifierPrefix)$(CFBundleIdentifier)` in `App/SwiftHFR/SwiftHFR.entitlements` (LOT-160). Enabling the capability is a developer-portal action for the maintainer; automatic signing then carries it (ADR 0012). CI's unsigned builds (`CODE_SIGNING_ALLOWED=NO`) are unaffected; the LOT-161 archive and TestFlight upload need the capability on the App ID or signing fails. Privacy manifest: `NSUserDefaults` already needs its required-reason entry (CA92.1); `NSUbiquitousKeyValueStore` has none; the app lock adds `NSFaceIDUsageDescription`.
- **No third-party dependency**: `NSUbiquitousKeyValueStore` (Foundation), `Security` and `LocalAuthentication` only. In HFRKit the store sits behind a protocol in `HFRStorage` (`SyncedKeyValueStore`), with the Apple implementation under `#if canImport(Darwin)` (the class is not in swift-corelibs-foundation) and an in-memory implementation for tests, the same pattern as the Keychain store ([ARCHITECTURE, Linux rules](../ARCHITECTURE.md#linux-rules)).
- **Lots**: LOT-172 ([#311](https://github.com/ezzz/HFRnow/issues/311), HFRStorage: the synced store, the mirror, `Setting.scope`, the list envelopes, the bounded reading positions); LOT-173 ([#312](https://github.com/ezzz/HFRnow/issues/312), App: opt-in Keychain sync and app lock); LOT-130 ([#220](https://github.com/ezzz/HFRnow/issues/220)) carries §7; LOT-067/158 carry §5; LOT-119 the settings scopes; #310 the shared namespace contract.

## Alternatives rejected

| Option | Why not |
|---|---|
| Everything in MPStorage (one cross-platform store) | 64 KiB shared with 13+ writers, no locking, needs a live HFR session; adding Apple-only data to a community document without a contract breaks the other clients' assumptions; secrets could never go there anyway |
| CloudKit private database (records, server-side merge, unlimited size) | a container, a schema to deploy per environment, async reads on every hot path, and far more code than the KVS budget needs; revisit only if drafts must sync |
| iCloud Keychain for accounts by default | Q-9 decided this-device-only: a session token that appears on a second device is a token that can leak with it. Kept as an explicit opt-in (§6), with the user told what travels |
| A cloud copy of the blacklist (iCloud KVS next to MPStorage) | a third master (device, iCloud, forum) that LOT-062's three-way merge cannot arbitrate; with sync off the blacklist stays per device, as legacy |
| iCloud Drive document / `UIDocument` | file-level conflicts the user must resolve; built for documents, not preferences |
| Device-only everywhere (no iCloud) | the status quo users complain about (reconfigure on every device, lose the allowlist); costs little to improve for small data |
| A user-facing "sync" switch for KVS | one more setting to explain and test for data that is already private to the Apple ID |
| Syncing drafts through KVS | drafts can be tens of KiB and change per keystroke; KVS throttles frequent writers and the quota is 1 MB |

## Consequences

- Every persisted item has one declared store (appendix); a lot that persists something new picks a tier by the four rules and records it there.
- `Setting<Value>` gains a `scope`; `SettingsStore` stays synchronous; the KVS mirror is the only addition on the write path. The settings screen (LOT-119) has no KVS switch; LOT-173 adds the two account options.
- Users with an iPhone and an iPad get the same filters, appearance, posting preferences, lists and reading positions; device-specific settings stay distinct on purpose; accounts follow only when the user opts in.
- Parity with other platforms is unchanged for everything in MPStorage. The allowlist, super-favourites and app-local smiley favourites are Apple-only until the #310 contract exists; a unilateral namespace is never written.
- MPStorage sync turns on by itself for members who already use it elsewhere (§7); a thread is never created without asking. Legacy behaviour changes recorded in [CHANGELOG-LEGACY](../CHANGELOG-LEGACY.md): blacklist merged instead of replaced on load, sync on when a thread exists.
- Developer-portal work (capability) and the LOT-161 signing path become a prerequisite of LOT-172's app integration; the engine lot lands and is tested in memory before that.
- Legacy import order matters: device first, then cloud, so a first device never overwrites a cloud value a second device already pushed.

## Appendix — matrix of persisted items

Legacy citations are read on `origin/master` of ezzz/HFRnow at `21173e7` (2026-10-27) with `git show origin/master:<path>`; line numbers differ from the audit's `2440d79` citations. "Audit E" = [`docs/audit/E-storage-vendors.md`](../audit/E-storage-vendors.md). "Other platforms?" says **unknown** unless the legacy code or the redface2 study proves a reader or writer. ⚑ marks a row where the chosen store means another platform (web userscripts, Android) does not see the data.

### A. Accounts and secrets

| Item | Legacy store | Other platforms? | Sensitivity | Size / churn | Store | Rationale |
|---|---|---|---|---|---|---|
| Accounts: pseudo, display name, cookies, `hash_check`, avatar bytes, main flag | Keychain item `HFR_COMPTES_KEY`, `AfterFirstUnlock`, not synchronizable (`Classes/Constants.h:115-121`, `Classes/MultisManager.m:49-86`; audit E §2.1) | No: each client keeps its own session (rf2: cookies only, `allowBackup=false`) | **Secret** | < 10 KiB per account; login/logout | **Device, not backed up**: Keychain `AfterFirstUnlockThisDeviceOnly` (LOT-065, Q-9) + **opt-in synchronizable copy** (§6, LOT-173) | Decided (Q-9, Q12). Without the opt-in, the user logs in on each device, as on every other platform. |
| Active session cookies (`HTTPCookieStorage`) | system jar rebuilt from the Keychain (audit E §2.5) | No | Secret | tiny | **Device, not backed up**: in-memory jar per `HFRSession` (LOT-042), persisted only through the account | A derived copy; never stored twice. |
| Account avatar image | inside the Keychain blob (`AVATAR`) | No | Public | a few KiB | with the account (LOT-065); large images → avatar cache (LOT-066) | Not worth a store. |

### B. MPStorage document (shared with other clients)

| Item | Legacy store | Other platforms? | Sensitivity | Size / churn | Store | Rationale |
|---|---|---|---|---|---|---|
| Blacklist (ignored pseudos), per HFR account | Local `Documents/blackListDico.plist` keyed by account (`Classes/BlackList.m:163-181`, `Constants.h:92`); mirrored to MPStorage `blacklist.list[{username, createDate}]` **only when `mpstorage_active`** (`MPStorage.m:23-26, 740`); on remote load the local list is **replaced** (`MPStorage.m:202-215`) | **Unknown.** The v0.1 template with `blacklist` appears in documents written by DTCloud (rf2 E23: `"blacklist":{}`), no userscript is known to read it; redface2 keeps its blacklist local (rf2 §3, unverified) | Personal (social graph) | ≤ 100 entries, ~50 B each; rare | **MPStorage when sync is on** (merge three-way, LOT-062; never replace); **device-only file** (LOT-061) as local copy and merge base. **Not in iCloud KVS.** | Cross-platform is the point of the legacy design. A second master in iCloud would race with the LOT-062 merge. ⚑ With sync off, Apple devices do not share it either (as legacy). |
| Bookmarks (post + label) per HFR account | MPStorage only, `bookmarks.list[{createDate, post, author, numreponse, cat, label}]` (`MPStorage.m:740`; D §2.10) | **Unknown for userscripts**; redface2: planned, not implemented (rf2 §3) | Personal | ~120 B each, 100+ seen; rare | **MPStorage** (unchanged) + device-only cached copy (read model, merge base) | Parity with legacy iOS and redface2's plan. |
| MP flags (`mpFlags.list[{post, p, href, page, uri}]`) = read position of group conversations | MPStorage (`MPStorage.m:463-525`); written by DTCloud (`sourceName` `DTCloud_GM`), read by redface2 (rf2 C8, E23) | **Yes**: DTCloud writes, redface2 reads | Personal | ~150 B each; per MP open | **MPStorage** (unchanged) | The only item with proven cross-platform consumers. |
| Other clients' namespaces (`hfrChat`, `superFavs`, `hfr4k`, `egoQuote`, `egoPost`, `lastRead`, `ezzziDrap`, `fastDelete`, `fastValid`, `catMP`, `oemMP`, ...) | not read by legacy iOS; preserved on rewrite (`MPStorage.m:886, 908`) | Yes (theirs) | Unknown | counts towards the shared 64 KiB | **MPStorage, verbatim** (LOT-013/062) | Never modelled, never dropped. `superFavs` and `lastRead` may overlap ours: schema pending capture (#272). |
| MPStorage location cache: thread `post` id per pseudo/alias | UserDefaults `dicMPStorage_postid` (`MPStorage.m:82-86, 670-688`) | redface2 caches the same per account (rf2 §2) | Low (own pseudos) | < 1 KiB; rare | **Device-only**, per account (LOT-052's store) | A cache, rebuilt by a scan. |
| MPStorage sync state (legacy app-wide `mpstorage_active`, now `mpstorage.<pseudo>` = `{state, decidedAt}` per HFR account) | UserDefaults, default off (`AppSettingsView.swift:112`, `MPStorage.m:83`) | n/a | Low (own pseudos) | 1 key per account | **iCloud KVS**; `on` when a thread exists, else asked at first write (§7); the legacy key is read once by the import | Enabling it on one Apple device enables it on the others; LOT-062 handles two writers; one account's choice never applies to another. |
| `mpstorage_last_rw` (last successful sync) | UserDefaults via `registerDefaults:` (volatile, `MPStorage.m:969-978`); shown in Settings (`AppSettingsView.swift:113`) | n/a | None | 1 key; every sync | **Device-only**, per account | A fact about *this device's* last sync. |

### C. User lists that are not in MPStorage today

| Item | Legacy store | Other platforms? | Sensitivity | Size / churn | Store | Rationale |
|---|---|---|---|---|---|---|
| Allowlist / "love list" (global) | `Documents/whiteList.plist` (`BlackList.m:163-181`, `Constants.h:93`); no server copy (audit E §4.2) | **No**: redface2 has no whitelist (rf2 §3); no userscript namespace known | Personal (social graph) | ≤ 100 entries; rare | **iCloud KVS**, one key (LOT-061 document = local copy) | Lost today on a new device; no other platform has the feature. ⚑ A shared namespace is #310's contract, never written unilaterally. |
| Super-favourites (topic ids) | UserDefaults `SuperFavoritesIds` (`Favorites.swift:133`; legacy ObjC `FavoritesTableViewController.m:1657`) | **Unknown**: a `superFavs` namespace exists in real documents (rf2 E23), schema not captured (#272); redface2 keeps them local (rf2 §2) | Low | ≤ 200 ints; rare | **iCloud KVS**, one key per HFR account (account key, §7) | Cheap to sync, painful to lose. ⚑ Revisit after #272 / #310. |
| App-local favourite smileys (`{sCode, sRawUrl, dateAdded}`) | `Documents/smiley_favorites_cache2`, `NSKeyedArchiver` (`Classes/SmileyCache.m:18`; `ReplySmileyCatalog.swift:42-72`) | **No**: the forum-side favourite smileys are the cross-platform set (refetched) | None | ≤ 100 × ~80 B; rare | **iCloud KVS**, one key per HFR account (account key, §7; LOT-064 store = local copy) | Same reasoning; per account like the super-favourites (operator 2026-10-29), the legacy file was global (§5). ⚑ Minor. |
| Forum-side favourite smileys (`arrFavoritesSmileysForum`) | memory only (`ReplySmileyCatalog.swift:42`), refetched | Yes (HFR) | None | — | **Not persisted** (cache at most) | Server data. |
| Topic favourites, flags (cyan/red) | server (`forum1f.php`) | Yes (HFR) | — | — | **Not persisted** (cache only) | Server data. |

### D. Reading state, counters, drafts

| Item | Legacy store | Other platforms? | Sensitivity | Size / churn | Store | Rationale |
|---|---|---|---|---|---|---|
| Reading position per topic (page, last message seen, scroll offset) — LOT-090 | none in legacy (resume = server first-unread anchor) | The **server** keeps the coarse position (flags page, `last_post_read_id` in REST, rf2 E1); `lastRead` userscript namespace exists, schema unknown | Low | one record per topic; **high churn** | **Device-only store (LOT-090) + iCloud KVS mirror** (operator Q13): debounced, bounded to the most recent topics per account (LOT-172) | HFR's flags stay the cross-platform position; the fine position follows the Apple ID. ⚑ None: the server is the shared position. |
| State restoration (current tab, forum, topic, page; multi-window) — FEAT-015 | `HFRswiftGlobalTopicListFlag` (`MainWindow.swift:301`), otherwise none | No | None | tiny; high churn | **Device-only** (`SceneStorage` / UserDefaults) | Per-device by nature. |
| Notification ledger (already-notified MPs/flags) — LOT-091 | `nb_mp`, `nb_mp_failure` (`MPBackgroundService.swift:73-97`, `MPListView.swift:442`, `HFRplusAppDelegate.m:255-259, 706`) | No | Low | small; every check | **Device-only** | Badges and notifications are per device; a duplicate on a second device is acceptable. |
| AQ counter and last check (`nb_aq`, `last_check_aq`) | UserDefaults (`AQPlusView.swift:30, 42, 313`; `Classes/AQTableViewController.m:71, 222, 300`) | No | None | 2 keys; every check | **Device-only** | Same. |
| Drafts per context — LOT-063 | single global `composerDraftText` (`AnswerView.swift:277-305`; audit E §3.2) | redface2: per-account local drafts with TTL (rf2 §2) | **Personal** (unsent text) | up to tens of KiB each, ≤ 100, 30-day TTL; per keystroke burst | **Device-only** (file, LOT-063) | Would exceed the KVS budget and churns; CloudKit is not worth a container. |
| `HFRswiftOpenMessagesFromNotificationPending` | UserDefaults (`Common.swift:57`, `HFRplusAppDelegate.m:43`) | No | None | 1 key | **Dropped**: in-memory route | A process flag, not data. |

### E. Preferences

Rule applied: a **content** preference syncs through iCloud KVS; a **device presentation or capability** preference and **transient UI state** stay on the device. Legacy keys are kept as the local UserDefaults names (LOT-060) so `@AppStorage` and the LOT-067 import work unchanged; the KVS key is the same string.

| Item (legacy key) | Legacy store | Other platforms? | Sensitivity | Size / churn | Store | Rationale |
|---|---|---|---|---|---|---|
| `vos_sujets` (favourites tab: flags + favourites vs favourites only) | UserDefaults (`AppSettingsView.swift:89`) | HFR `owntopic` filter | None | 1 | **iCloud KVS** | Content preference, kept as legacy. |
| `sujets_avec_cat` (group favourites by category) | `AppSettingsView.swift:90` | No | None | 1 | **iCloud KVS** | Content layout. |
| `favorites_auto_refresh` | `AppSettingsView.swift:91` | No | None | 1 | **iCloud KVS** | Behaviour. |
| `HFRswiftStartupScreen` (start tab) — added on `master` after `2440d79` | `Common.swift:33`, `AppSettingsView.swift:88`, `MainWindow.swift:1358` | No | None | 1 | **iCloud KVS** | Replaces the dead `default_tab` seed; in the LOT-060 catalogue by LOT-119. |
| `compact_mode` | `Common.swift:228`, `AppSettingsView.swift:92` | No | None | 1 | **Device-only** | Density depends on the screen (LOT-169). |
| `tabbar_minimize_on_scroll` | `Common.swift:232`, `AppSettingsView.swift:93` | No | None | 1 | **Device-only** | Presentation; the iPad sidebar has no tab bar. |
| `topic_page_swipe_navigation` — added on `master` | `Common.swift:236`, `AppSettingsView.swift:94` | No | None | 1 | **iCloud KVS** | Behaviour; to add to LOT-060. |
| `open_links_in_default_browser` — added on `master` | `Common.swift:240`, `AppSettingsView.swift:95` | No | None | 1 | **iCloud KVS** | Behaviour; in LOT-060 by LOT-119. |
| `reply_button_behavior` (`quick`/`forum`/`hidden`) — added on `master` | `Common.swift:244`, `AppSettingsView.swift:106` | No | None | 1 | **iCloud KVS** | Behaviour; to add to LOT-060. |
| `text_size_percent` (replaces `text_size_scale` 100-130, `Common.swift:266`, `AppSettingsView.swift:96`) | UserDefaults | No | None | 1 | **Device-only** | Like Dynamic Type: per screen and distance (LOT-169). |
| `haptics` | `AppSettingsView.swift:97` | No | None | 1 | **Device-only** | Capability differs (iPad, Mac). |
| `landscape_mode` (rotation) | `Common.swift:168`, `AppSettingsView.swift:98` | No | None | 1 | **Device-only** | iPhone-specific. |
| `icon` (alternate app icon) | `AppSettingsView.swift:99` | No | None | 1 | **Device-only** | `setAlternateIconName` runs per device; no icon change under the user. |
| `auto_theme` (3 system / 0 manual) + `theme` (0 light / 1 dark) | `AppSettingsView.swift:101-102` | No | None | 2 | **iCloud KVS**, one `appearance` picker stored under the legacy keys | Simplification; legacy keys remain the storage shape. |
| `theme_style` (classic / modern) | `AppSettingsView.swift:103` | No | None | 1 | **iCloud KVS** | Content rendering. |
| `theme_day_color_action`, `theme_night_color_action`, `…_love` ×2, `…_superfavori` ×2, `theme_night_brightness` | `Common.swift:463-469` | No | None | 7 | **iCloud KVS**, the 7 legacy keys unchanged (LOT-060 `colorSetting`) | Theme parity (LOT-121, operator 2026-10-29): every decided colour is kept; FEAT-010's single accent is out of scope. |
| `blacklist_hide_pseudo` | `AppSettingsView.swift:105` | No | None | 1 | **iCloud KVS** | Content filter. |
| `filter_posts_quotes`, `filter_posts_min_quotes` | `AppSettingsView.swift:107-108` | No | None | 2 | **iCloud KVS** | Content filter. |
| `size_smileys` (`double`/`default`) | `AppSettingsView.swift:109`; no reader found (audit E §3.1) | No | None | 1 | **iCloud KVS** if the reader honours it, else **dropped** | Q8. |
| `display_sig` | `AppSettingsView.swift:110` | No | None | 1 | **iCloud KVS** | Content rendering. |
| `embedded_videos` | removed from `master` by `d645f52` ("désactive les vidéos intégrées": picker and key deleted from `AppSettingsView.swift`); no reader nor writer at `21173e7` | No | None | — | **Dropped**: the LOT-060 catalogue key `embeddedVideos` gets `scope: .device` until LOT-060's "not ported" list removes it; never synced | Legacy dropped the feature after the audit (`2440d79` still had it). |
| `display_images` (`yes`/`no`/`wifi`) | forced `yes` in legacy (audit E §3.1); default `wifi` (LOT-060, policy C) | No | None | 1 | **Device-only** | Network policy differs per device. |
| `mp_badge_enabled` | `AppSettingsView.swift:114`, `MainWindow.swift:1349` | No | None | 1 | **Device-only** | Badges are per device. |
| `recherche_categorie` (last search category) | `ForumSearchView.swift:111` | No | None | 1 | **Device-only** | Transient UI state. |
| `rehost_use_link`, `rehost_resize_before_upload` | `ReplyService.swift:1837`; `RehostImageViewController.m:84-99, 580-622` | No | None | 2 | **iCloud KVS** | Posting preference. |
| `CollapsedFavoriteSectionIDs`, `FavoritesShowCollapsedSections` | `Favorites.swift:160, 447` | No | None | small | **Device-only** | UI state. |
| `AnswerView.smileys.*.expanded` ×3, `AnswerView.smileys.search.allKeywords`, `MessageSmileySheetCompactImage` | `AnswerView.swift` (`@AppStorage`), `MessagesView.swift:6020` | No | None | 5 | **Device-only** | UI state. |
| `smileySearchHistory_v1` (≤ 50 entries) | UserDefaults JSON (`SmileySearchService.swift:89`) | No | Low | ~2 KiB; every search | **Device-only** | Churn, marginal value. |
| Rehost upload history (`rehostImagesSwiftUI.json`) | `Documents/` (`ReplyService.swift:1936`) | No | **Personal** (uploaded image URLs) | grows | **Device-only** (backed up) | Personal, unbounded, no consumer elsewhere. |
| `arrayCategoriesVisibleOrder` / `HiddenOrder`, `forumsCache.plist` | legacy-only ObjC (`FavoritesTableViewController.m:65-81, 495-496`; `Constants.h:97`, read by `ForumSearchView.swift:456`) | No | None | small | **Dropped** (LOT-014 catalogue) | No HFRswift writer. |
| Offline topics, `offline_max_pages` | `Classes/OfflineStorage.m:163`; unused in HFRswift | No | Personal (page contents) | large | **Device, not backed up** (LOT-068, `isExcludedFromBackup`) | Large, rebuildable. |
| Legacy seed-only / forced keys (`size_text*`, `force_manual_theme`, `auto_theme_*_time`, `shake_to_refresh`, `theme_noel_*`, `version`, `default_tab`, `adv_ssl`, `mpstorage_reset`, `EmptyCacheButton`, `theme_*_adjust`, `theme_*_tintcolor`) | audit E §3.3; LOT-060 "not ported" | No | None | — | **Dropped** (read once by LOT-067 where a migration exists) | Decided by LOT-060. |

### F. Caches and bookkeeping

| Item | Legacy store | Other platforms? | Sensitivity | Size / churn | Store | Rationale |
|---|---|---|---|---|---|---|
| Avatar cache, rendered topic pages, page/list caches | `Library/Caches/cache/…` (LOT-066) | No | None / personal (page contents) | MBs | **Device, not backed up** | Rebuildable. |
| Legacy import marker (`migration.legacyImport.version`, LOT-067) | new | No | None | 1 | **Device-only** | Describes this device's container. |
| KVS bookkeeping: `schemaVersion`, last external-change token | new | No | None | 2 | **iCloud KVS** (`schemaVersion`) + device-only (token) | A newer app never downgrades a cloud value it does not understand. |

### Budget check (iCloud KVS)

≈ 32 scalar preference keys (< 100 B each, the 7 theme keys included), one schema version, per HFR account: 2 list keys (≤ 10 KiB each), 1 reading-position key (≤ 200 topics × ~40 B ≈ 8 KiB); 1 global allowlist key. Worst case with 5 accounts (plus one sync-state key per account): ≈ 50 keys, < 200 KiB. Limits: 1024 keys, 1 MB. Drafts, histories and caches are excluded because they would not fit or would churn.
