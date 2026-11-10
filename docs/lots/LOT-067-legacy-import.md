# LOT-067 — Legacy data import on update

- **Module:** HFRStorage
- **Difficulty / model:** difficult (Opus 5.5 → Fable 5.1)
- **Issue:** [#92](https://github.com/ezzz/HFRnow/issues/92)
- **Depends on:** LOT-060 (#85, settings), LOT-061 (#86, pseudo lists), LOT-064 (#89, small stores), LOT-065 (#90, accounts), LOT-004 (#41, legacy formats); LOT-063 (drafts) and LOT-066 (caches) provide the other destinations.
- **App side:** LOT-158 (#248) runs the import at first launch, shows its progress and summary, and retries.
- **Placement:** [ADR 0013](../adr/0013-storage-tiers.md) §5 (device tiers first, then the KVS mirror) as amended by Amendment 3 (drafts, super-favourites, account of the global items), §7 (`mpstorage_active` read once), appendix F (`migration.legacyImport.version`, device-only).
- **Retirement:** [#708](https://github.com/ezzz/HFRnow/issues/708) removes this code and the pending lists once the in-place update has shipped for long enough (operator, 2026-11-09).

## Legacy sources

Legacy reference `legacy/duo-inner-cover` @ `2fe43da3` (AGENTS.md §2, `git show 2fe43da3:<path>`). SwiftHFR ships as an in-place update of `hfrplus.red.super` (Q-1), so every item below is in the same container and the same `UserDefaults` standard suite. On-device data only: no HFR request, no HFR fact, so no HFR-PROTOCOL subsection.

| Item | Legacy store and format | Legacy file:line @ `2fe43da3` |
|---|---|---|
| Accounts | Keychain generic password, service = bundle id, account `HFR_COMPTES_KEY`; value = `NSKeyedArchiver` of an `NSArray` of `NSMutableDictionary` with `PSEUDO` (`md_user` value), `PSEUDO_DISPLAY`, `COOKIES` (`NSArray<NSHTTPCookie>`), `HASH`, `AVATAR` (`NSData`), `MAIN` (`NSNumber` bool) | `Classes/Constants.h:116-122`; `Classes/MultisManager.m:43-47` (read, insecure `unarchiveObjectWithData`, unreadable → empty), `:49-86` (write); `Carthage/Checkouts/SimpleKeychain/SimpleKeychain/A0SimpleKeychain.m:32, 87, 213` (default service = `[[NSBundle mainBundle] bundleIdentifier]`) |
| Main account | the **last** dictionary whose `MAIN` is true | `Classes/MultisManager.m:168-188` (`getMainCompte`, `getCurrentPseudo` returns its `PSEUDO_DISPLAY`) |
| Blocklist | `Documents/blackListDico.plist`, XML plist written by `NSDictionary writeToFile:`: `{<display name of the main account>: [{word, alias, mode}]}` | `Classes/BlackList.m:43` (entry), `:91-103` (keyed by `PSEUDO_DISPLAY` of the main account for both read and write), `:162-171` (save), `:173-202` (load) |
| Blocklist v0 | `Documents/blackList.plist`, a plain array of entries, used only when `blackListDico.plist` is absent, assigned to the main account | `Classes/BlackList.m:184-190`, `Constants.h:91` |
| Allowlist | `Documents/whiteList.plist`, array of `{word, alias, mode}`, global | `Classes/BlackList.m:51, 197-202`, `Constants.h:93` |
| Super-favourites | `UserDefaults` `SuperFavoritesIds`: array of numbers (topic number alone, no category); the loader also accepts numeric strings and drops ids ≤ 0 | `HFRswift/Swift/Favorites.swift:132-157`; `Classes/FavoritesTableViewController.m:81-82, 1657` |
| Collapsed favourites sections | `UserDefaults` `CollapsedFavoriteSectionIDs`: array of strings, trimmed, empty dropped | `HFRswift/Swift/Favorites.swift:159-175` |
| App smiley favourites | `Documents/smiley_favorites_cache2`: `NSKeyedArchiver` (binary plist) of `NSMutableDictionary<code, SmileyFavorite{sCode, sRawUrl, dateAdded}>`, global, top key `$0` (`encodeObject:` without a key) | `Classes/SmileyCache.m:18, 26-40` (coder keys), `:350-380` (load, sorted by `dateAdded` ascending: LOT-004 quirk 22), `:388-439` (save) |
| Smiley search history | `UserDefaults` `smileySearchHistory_v1`: JSON `Data` of `[{text, count, lastDate}]` (`JSONEncoder` default dates) | `HFRswift/Swift/SmileySearchService.swift:78-118` |
| Rehost upload history | `Documents/rehostImagesSwiftUI.json`: JSON `[{fullWidth?, fullHeight?, fullURL, mediumURL?, previewURL?, miniURL?, timeStamp}]`, newest first | `HFRswift/Swift/ReplyService.swift:1852-1870, 1935-1960` |
| Drafts (Swift composer) | `UserDefaults` `reply_active_drafts_by_topic_v1`: JSON `[{topicID, topicTitle, text, updatedAt}]`, ≤ 50 topics, newest first; `reply_drafts_by_topic_v1`: JSON `[ReplyDraftItem{id, topicID, topicTitle, source, text, createdAt}]`, ≤ 3 archived drafts per topic. `topicID` is `post-<topic number>`: no category, no page | `HFRswift/Swift/AnswerView.swift:102-272`; `HFRswift/Swift/MessagesView.swift:3245-3262` (`post-<n>`) |
| Draft (ObjC composer) | `UserDefaults` `brouillon`: one string | `Classes/AddMessageViewController.m:69, 483` |
| `composerDraftText` | **not persisted** at the reference: `@State` | `HFRswift/Swift/MessagesView.swift:3081`, `MainWindow.swift:312` |
| MPStorage switch | `UserDefaults` `mpstorage_active`, bool, default false | `HFRswift/Swift/AppSettingsView.swift:112`; `Classes/MPStorage.m:83` |
| Preferences | `UserDefaults` under their legacy names | LOT-060 catalogue (same keys, same suite) |
| HTML page cache | `Library/Caches/cache/topic-<UUID>.htm` (and `topic-<page>.htm` from the ObjC renderer) at the root of `Caches/cache`; legacy itself removed only files whose name starts with `topic-` and whose extension is `htm` (any case) | `HFRswift/Swift/Common.swift:2166-2180`; `Classes/OfflineStorage.m:500-512, 521-530`; `HFRswift/Swift/HTMLPageCacheManager.swift:103-130` |

LOT-004 quirk 23 (`MultisManager.m:44-101`) and the #347 samples (`tooling/legacy-oracle/samples/legacy-stores/`, MANIFEST "Legacy on-device samples") give the byte formats of the small stores; the account archive is decoded by Apple's own `NSKeyedUnarchiver`, the same API legacy reads it with (see Behaviour, Accounts).

## Behaviour

Code in `Sources/HFRStorage/LegacyImport/`, tests in `Tests/HFRStorageTests/LegacyImport/`. Foundation only; the Keychain read and the `NSKeyedUnarchiver` decode of the account archive are under `#if canImport(Security)` / `#if canImport(Darwin)` behind `LegacyAccountSource`, as LOT-065 does (ARCHITECTURE, Linux rules).

### Shape

- **`LegacyContainer`**: where legacy data is read: `documentsDirectory`, `cachesDirectory`, `defaults` (`LegacyDefaults`: `UserDefaultsLegacyDefaults` over the standard suite, `InMemoryLegacyDefaults` for tests) and `accounts` (`LegacyAccountSource`: `KeychainLegacyAccountSource` on Darwin, `InMemoryLegacyAccountSource`). None of them can write, so "never deletes the source" holds by construction; the page-cache step is the one deletion, and only of rebuildable files.
- **`LegacyImportDestinations`**: LOT-065 `CredentialStore`, LOT-061 `PseudoListStore`, LOT-064 stores, LOT-063 `DraftStore`, `LegacyPendingStore`, and the LOT-060 `SettingsStore` (for `mpstorage_active`). Every write goes through the store's public API, so its guards, normalisation and atomic saves apply.
- **`LegacyImporter`** (actor): `run(currentAccount:now:) async -> LegacyImportReport`. The app (LOT-158) calls it at launch and after each login until `report.isComplete`; `currentAccount` is the account logged in now (decision D3). Runs are serialized (each waits for the previous one), so two overlapping calls never save over each other's state.
- **`LegacyImportReport`**: one `LegacyImportOutcome` per step (`imported(n)`, `nothingToImport`, `alreadyDone`, `waitingForAccount`, `failed(LegacyImportError)`), `rejectedItems` (accounts or pseudos LOT-061/065 refuse), `mpStorageSwitch` (`notRead`, `active`, `inactive`, kept in the import state so every report gives it). Counts only: no pseudo, cookie, token or text.
- **`LegacyImportError`**: `sourceUnreadable` (the legacy data is not in a legacy format: the legacy app would have shown nothing either; done, not retried), `sourceUnavailable` (cannot be read now: retried), `destinationFailed` (a SwiftHFR store refused or failed: retried). No associated value.
- **`LegacyPendingStore`** (actor, decisions D1, D2): the pending super-favourites and reply drafts, per account key (one `LegacyPendingDocument`, LOT-064 core: failure guard, atomic write). `resolveSuperFavorites(listed:account:into:now:)` (the app calls it at each favourites-list load), `discardPendingSuperFavorites(account:)` (the user emptied super-favourites), `resolveReplyDraft(for:account:into:now:)` (the app calls it when it opens a topic). Each resolve writes the destination first, then forgets the entry; a failing destination keeps it pending.
- **`SmileySearchHistoryStore.merge(_:)`** (added to LOT-064's store): adds entries with their counts and dates; the stored entry wins on the same text in any case; the 50 most recent are kept.

### Idempotence

- **`LegacyImportStateDocument`** (device-only, ADR 0013 appendix F): `importVersion` (`migration.legacyImport.version`, 1), the steps done, `globalAccount` (the pseudo receiving the global items, once known) and `mpStorageSwitch` (so a kill before LOT-130 reads the report loses nothing). Stored through `SmallStorePersistence`.
- A step is marked done only after its destination saved and the state saved; a done step never runs again, so an item the user removes after the import does not come back. A step that failed with `sourceUnavailable` or `destinationFailed`, or waits for an account, runs at the next call; the others are not redone.
- When the destination already holds data (a second run after a partial failure, or a SwiftHFR beta used before the update): union, the destination's entry wins on identity (same account pseudo, same blocked pseudo, same section, same smiley code, same upload id, same search text ignoring case, same draft context), never a replacement.
- The state store itself unreadable: every step reports `failed(.destinationFailed)` and nothing runs.

### Steps

| # | Step | Mapping |
|---|---|---|
| 1 | `accounts` | Each legacy record → `Account` (pseudo = `PSEUDO`, display = `PSEUDO_DISPLAY`, cookies → `StoredCookie`, `hashCheck` = `HASH`, `avatarData` = `AVATAR`) in one `CredentialStore.update`, through `AccountBook.add(_:makeMain: false)`. A record without `PSEUDO` and every record LOT-065 refuses (empty or `deleted` pseudo, `md_user` naming another pseudo) is counted in `rejectedItems`. An account SwiftHFR already stores is left as it is (its cookies are newer). The legacy main account (the **last** `MAIN`, `MultisManager.m:168-176`) becomes main only when SwiftHFR stored no account before; it is also the global account (D3). `HFR_COMPTES_KEY` is read only |
| 2 | `pseudoLists` | Waits (`waitingForAccount`) until step 1 is done, and fails (`destinationFailed`) when the stored accounts cannot be read: the key mapping needs them. Each `blackListDico.plist` key is matched to a stored account with `AccountBook.account(matching:)` (pseudo, then display name, ignoring case) and filed under its pseudo; an unmatched key is filed under itself (reachable if that account logs in later). The v0 `blackList.plist` is read only when the dictionary file is absent, into the global account (waits for one). `whiteList.plist` → allowlist. Each file is read on its own, as legacy did (`BlackList.m:173-202`): an unreadable one counts as empty and the other is still imported; `sourceUnreadable` only when nothing readable was found. Entries go through `block`/`allow` (legacy entries are always `alias` "" and `mode` 0, `BlackList.m:43, 51`: nothing is lost); empty pseudos are counted as rejected |
| 3 | `superFavorites` | `SuperFavoritesIds` read as legacy's loader → `LegacyPendingStore.addSuperFavorites` for the global account (D2) |
| 4 | `collapsedSections` | `CollapsedFavoriteSectionIDs` read as legacy's loader → `FavoritesLayoutStore.setCollapsed(true, …)` |
| 5 | `smileyFavorites` | `smiley_favorites_cache2` read by `BinaryPropertyList` (a reader of the public `bplist00` format: `PropertyListSerialization` returns keyed-archive references as an opaque class on Darwin and Linux, and corelibs' `NSKeyedUnarchiver` aborts the process on this archive) and resolved by hand (`$top.$0` → `NS.keys`/`NS.objects` → `{sCode, sRawUrl, dateAdded.NS.time}`; `NSMutableString` `{NS.string}` accepted); no class is instantiated, and at most `BinaryPropertyList.maximumNodes` (100 000) objects are read, references counted each time, so a small file of shared references cannot make the read exponential. Oldest first, equal dates by code; `AppSmileyFavoritesStore.add(code:url:account:at: dateAdded)` for the global account; a URL Foundation cannot parse is skipped, a blank code is counted as rejected and the next favourites still go in |
| 6 | `smileySearchHistory` | `smileySearchHistory_v1` decoded with legacy's `Codable` shape and `JSONDecoder` defaults → `merge` |
| 7 | `uploadHistory` | `rehostImagesSwiftUI.json` → `RehostedImage` (`previewURL` has no counterpart, legacy's only uploader leaves it nil, MANIFEST); added oldest first so the store's newest-first order is the file's |
| 8 | `drafts` | D1: `brouillon` → `.legacyGlobal` for the global account unless that context has a draft; `reply_active_drafts_by_topic_v1` (`post-<n>` ids, blank texts dropped) → `LegacyPendingStore.addReplyDrafts` (one per number, expired ones skipped); `reply_drafts_by_topic_v1` not imported |
| 9 | `mpStorageSwitch` | `mpstorage_active` read once through the LOT-060 store (`SettingKey.mpStorageActive`, tolerant coercion) into `report.mpStorageSwitch`; LOT-130 turns it into each account's record (ADR 0013 §7). Never written |
| 10 | `pageCache` | Removes the regular files directly in `Caches/cache` whose name starts with `topic-` and whose extension is `htm` in any case, the files legacy's own clean-up selected; never follows a link (the caches folder, `cache` and each entry), never enters a folder (`avatars` and LOT-066's areas live there), never removes anything else. A removal that fails leaves the step pending |

Preferences need no step: SwiftHFR reads the same keys in the same suite (LOT-060), and `LegacySettingsNormalizer` already runs at launch (LOT-119).

### Decisions (operator, 2026-11-09, [#92](https://github.com/ezzz/HFRnow/issues/92); ADR 0013 Amendment 3)

- **D1 — Drafts.** `composerDraftText` is not persisted at `2fe43da3`. Active Swift drafts go to a temporary device-only pending list keyed by topic number, resolved into an ordinary `.reply` draft when a topic with that number opens; no new permanent `DraftContext` case, no legacy logic in the composer; 30-day expiry from legacy's `updatedAt`. Archived drafts are not imported (GAP row, `### Ledger` of the PR). `brouillon` → `.legacyGlobal`.
- **D2 — Super-favourites** through the same pending mechanism: resolved at each favourites-list load in every category where the number appears; dropped after 90 days or when super-favourites are emptied.
- **D3 — Global items** go to the legacy main account (the last `MAIN`); with no legacy account they wait and go to the first account that logs in, once (`globalAccount` is then fixed).

## Edge cases

- Keychain item absent → `nothingToImport`; present but not an array of dictionaries → `sourceUnreadable` (legacy returned an empty array, `MultisManager.m:46`); not readable now (`errSecInteractionNotAllowed` and other statuses) → `sourceUnavailable`, retried.
- Several `MAIN` → the last; none → no main is set, LOT-065's book keeps its rule (the first account becomes main), and the global items go to `currentAccount`.
- Two legacy records with the same `md_user` → the first is stored, the second is an account SwiftHFR already stores (left as it is).
- A blocklist keyed by a display name matching no stored account → filed under that name.
- A plist or JSON that is not of the expected type → `sourceUnreadable` for that step, as legacy's `try?` / `dictionaryWithContentsOfFile:` showed nothing; the bytes stay in place.
- `SuperFavoritesIds` with numeric strings, booleans, reals, zero, negatives, duplicates → read as legacy's loader (`Favorites.swift:135-150`); `CollapsedFavoriteSectionIDs` with one non-string element → ignored as a whole (`as? [String]`).
- Upload history: the same id twice → once (LOT-064 identity).
- Smiley codes differing only by case → two favourites; equal dates → code order (the archived dictionary has no order).
- A destination in its failure state (LOT-061/064 `loadFailed`, newer version) → `destinationFailed`, pending; never overwritten.
- App killed mid-step → the step runs again; its writes are unions, so nothing is added twice.
- A linked `Caches/cache`, or a `topic-x.htm` that is a link or a folder → left as is.
- A pending draft or super-favourite for an account that never comes back → is dropped, once expired (30 / 90 days), by the next resolve call of any account; what remains goes with the code (#708).

## Secrets

Cookies and `hash_check` go from the legacy Keychain item to LOT-065's item and nowhere else: no log, no report value, no error payload, no temporary file. `LegacyAccountRecord`'s description hides them, as `Account`'s does. The account archive is decoded in memory.

## Fixtures

- **Small stores** (#347): read in place from `tooling/legacy-oracle/samples/legacy-stores/` (real legacy output on synthetic data): `defaults-*.plist`, `smiley-favorites-*.archive`, `search-history-*`, `upload-history-*`. The expected smiley favourites were read from the same archives by Python's `plistlib`, an independent decoder.
- **Pseudo lists, drafts**: built in the tests from the legacy shapes (`BlackList.m:43, 51`; `ReplyDraftStore.ActiveDraftItem`, `AnswerView.swift:143-148`, `JSONEncoder` defaults); synthetic pseudos only.
- **Accounts**: the `storage-keychain.json` synthetic accounts (LOT-004). On macOS, `LegacyAccountArchiveTests` replays legacy's writer (`NSKeyedArchiver` of `NSArray<NSMutableDictionary>` holding `HTTPCookie`s, `MultisManager.m:49-80`) and decodes it; Linux tests use `InMemoryLegacyAccountSource`.
- **Caches**: temporary folders.

## Tests

`LegacyFormatsTests` (each legacy loader on the #347 samples: super-favourites, sections, search history, upload history, smiley archive against `plistlib`, unreadable inputs), `LegacyPageCacheTests` (only `topic-*.htm` at the root, links never followed), `LegacyPendingStoreTests` (resolution in every category, unlisted numbers kept, 90/30-day expiry, discard, existing draft wins, failing destination keeps the entry), `SmileySearchHistoryMergeTests`, `LegacyImporterTests` and `LegacyImporterRecoveryTests` (20: full import from the samples, source bytes unchanged, idempotence with a removed item, failed step retried, waiting for an account then the first login once, existing account and main kept, last `MAIN`, rejected accounts, v0 blocklist, display-name keys, unreadable sources not retried, failing destination retried, no secret in the report, absent switch; after the review: pseudo lists waiting for the accounts step, a blank smiley code rejected alone, the switch kept across runs, overlapping runs; then the stored accounts unreadable at the pseudo-lists step, a state written before the switch existed; after CodeRabbit: each pseudo-list file read on its own, both ways) and `BinaryPropertyListTests` (node budget on a shared-reference graph, `LegacyAccountArchiveTests` (Darwin).

Shown to fail with the behaviour removed (20 mutations, each caught): done steps redone, a step marked done before its destination saved, an existing account overwritten, the first `MAIN` taken, the legacy main forced over SwiftHFR's own, display-name keys not mapped, uploads added newest first, super-favourite numbers unsorted or duplicated, a pending number resolved in one category only, an existing draft overwritten, the merge letting the legacy entry win, links followed at the folder level; after the review, pseudo lists run before the accounts step, the first blank code ending the step, the switch read from the run only, an unreadable account book read as empty, the switch required when decoding the state; after CodeRabbit, an unreadable allowlist or blocklist ending the step, no node budget (the 13-level, fan-out 4 graph then takes six minutes to read). The serialization of runs is not caught (the race needs a store `await` to interleave; the reviewer could not reproduce it in 600 tries): `overlappingRuns` only checks the end state. The per-entry link check is covered by the regular-file check on Linux (a link is not a regular file there) and kept for platforms that follow it.

## Pending capture / Mac checks

- **M1** (Mac, LOT-158's install-over test): decode a real legacy `HFR_COMPTES_KEY` written by the legacy app with synthetic accounts, and measure whether `NSHTTPCookie` decodes with `requiresSecureCoding = true` and an explicit class list. Until then the decode keeps legacy's insecure read, limited to this one item of the app's own Keychain.
- None for the small stores: #347 covers them.
- **Capture wanted** (Fable round 1, Low): legacy-written samples of `blackListDico.plist`, `whiteList.plist`, `blackList.plist` (v0), `brouillon` and `reply_active_drafts_by_topic_v1`, produced by the legacy code on synthetic data like #347; the tests build them from the legacy shapes meanwhile (`BlackList.m:43, 51`, `AnswerView.swift:143-148`). A `host: mac` capture issue, opened by the orchestrator.

## Retirement

[#708](https://github.com/ezzz/HFRnow/issues/708): remove `LegacyImport/`, the pending lists and their app call sites once the in-place update has shipped for long enough (operator, 2026-11-09).

## Intentional differences from legacy

- Legacy never migrated its own data between formats except the buggy v0 blocklist (E §7.3); SwiftHFR imports once, never deletes or rewrites the legacy source.
- Super-favourites and smiley favourites become per account (ADR 0013 §5, CHANGELOG-LEGACY row 30); super-favourites gain a category (D2).
- Archived reply drafts are not imported (D1, GAP row in the PR's `### Ledger`).
- Unreadable legacy data is reported (`sourceUnreadable`), not silently replaced by an empty list.

## Learnings

To copy into AGENTS.md §11 when the lot closes.
- The legacy reference moved (#655): `composerDraftText`, which ADR 0013 §5 planned to import, is not persisted at `2fe43da3`; re-read every legacy key at the reference before porting a migration.
