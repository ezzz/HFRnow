# LOT-067 — Legacy data import on update

- **Module:** HFRStorage
- **Difficulty / model:** difficult (Opus 5.5 → Fable 5.1)
- **Issue:** [#92](https://github.com/ezzz/HFRnow/issues/92)
- **Depends on:** LOT-060 (#85, settings), LOT-061 (#86, pseudo lists), LOT-064 (#89, small stores), LOT-065 (#90, accounts), LOT-004 (#41, legacy formats); LOT-063 (drafts) and LOT-066 (caches) provide the other destinations.
- **App side:** LOT-158 (#248) runs the import at first launch, shows its progress and summary, and retries.
- **Placement:** [ADR 0013](../adr/0013-storage-tiers.md) §5 (device tiers first, then the KVS mirror), §7 (`mpstorage_active` read once), appendix F (`migration.legacyImport.version`, device-only).

**Status: spec only, blocked on decisions D1–D3 below.** The reference `2fe43da3` keeps drafts in another shape than ADR 0013 §5 assumed (D1), and two items need the operator's choice before code.

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
| App smiley favourites | `Documents/smiley_favorites_cache2`: `NSKeyedArchiver` (binary plist) of `NSMutableDictionary<code, SmileyFavorite{sCode, sRawUrl, dateAdded}>`, global | `Classes/SmileyCache.m:18, 350-380` (load, sorted by `dateAdded` ascending: LOT-004 quirk 22), `:388-439` (save) |
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

Code in `Sources/HFRStorage/LegacyImport/`, tests in `Tests/HFRStorageTests/LegacyImport/`. Foundation only; the Keychain read and the `NSKeyedUnarchiver` decode of the account archive are under `#if canImport(Darwin)` behind a protocol, as LOT-065 does (ARCHITECTURE, Linux rules).

### Shape

- **`LegacyContainer`**: where legacy data is read: `documentsDirectory`, `cachesDirectory`, a read-only `LegacyDefaults` view (`object(forKey:)` over the standard suite; an in-memory one for tests) and a `LegacyAccountSource` (Keychain on Darwin, in-memory in tests). Nothing in it can write, so "never deletes the source" holds by construction, except the cache step, which takes the caches directory separately.
- **`LegacyImporter`** (actor): `run(into: Destinations, now:) async -> LegacyImportReport`. `Destinations` holds the SwiftHFR stores (LOT-065 `CredentialStore`, LOT-061 `PseudoListStore`, LOT-064 stores, LOT-063 `DraftStore`, a `LegacyImportStateStore`). One step per item, in the order of the table below; each step reads, maps, then writes through the destination store's public API (so its guards, normalisation and atomic saves apply).
- **`LegacyImportReport`**: per step `imported(count)`, `nothingToImport`, `skipped(reason)`, `failed(LegacyImportError)`, plus `mpStorageWasActive: Bool?` for LOT-130 (ADR 0013 §7). No value in the report or in an error carries a pseudo, cookie, hash or draft text (counts and step names only).

### Idempotence

- **`LegacyImportState`** (device-only, ADR 0013 appendix F): `version` (`migration.legacyImport.version`, 1 for this lot) and the set of steps done. Stored as a small JSON document through `SmallStorePersistence` (LOT-064 core: failure guard, atomic write).
- A step is marked done only after its destination saved. A done step never runs again, so an item the user removes after the import does not come back. A failed step stays pending and runs at the next `run`; the others are not redone.
- A step waiting for an account (D3) stays pending without being an error.
- When the destination already holds data (a second run after a partial failure, or a SwiftHFR beta used before the update): union, the destination's entry wins on identity (same pseudo, same topic, same smiley code, same upload id, same search text ignoring case), never a replacement.

### Steps

| # | Step | Mapping |
|---|---|---|
| 1 | Accounts | Each legacy dictionary → `Account` (pseudo = `PSEUDO`, display = `PSEUDO_DISPLAY`, cookies → `StoredCookie`, `hashCheck` = `HASH`, `avatarData` = `AVATAR`) through `CredentialStore.update` + `AccountBook.add(_:makeMain: false)`; then `setMain` on the legacy main account (the last `MAIN`, `MultisManager.m:168-176`). LOT-065's rules apply: invalid pseudos and `md_user` mismatches are skipped and counted, an account already stored keeps its newer cookies. Legacy `HFR_COMPTES_KEY` is read only: never written or deleted |
| 2 | Pseudo lists | Each `blackListDico.plist` key is matched to an imported account with `AccountBook.account(matching:)` (pseudo, then display name, ignoring case); unmatched keys are imported under their own `AccountKey` (the list stays reachable if that account logs in later). v0 `blackList.plist` only when the dictionary file is absent, into the main account (`BlackList.m:184-190`). `whiteList.plist` → allowlist. Entries keep `{word, alias, mode}` (LOT-061 document shape); `block`/`allow` reject empty pseudos and duplicates as usual |
| 3 | Super-favourites | D2 |
| 4 | Collapsed sections | `CollapsedFavoriteSectionIDs` → `FavoritesLayoutStore.setCollapsed(true, …)` for each id (store trims and drops empty ones, as legacy) |
| 5 | App smiley favourites | archive decoded (keyed-archive plist read with `PropertyListSerialization`: `$top.root` → `NS.keys`/`NS.objects` → `SmileyFavorite{sCode, sRawUrl, dateAdded.NS.time}`), then `AppSmileyFavoritesStore.add(code:url:account:at: dateAdded)` in `dateAdded` order, into the account of D3 |
| 6 | Smiley search history | JSON decoded with legacy's `Codable` shape and `JSONDecoder` default dates; each entry written with its count and date (a store-level `importEntries` that keeps counts, since `record` adds 1 per call); legacy's 50-entry cap already holds |
| 7 | Upload history | JSON decoded into `RehostedImage` (same fields, same date strategy, LOT-064 "Dates"); added oldest first so the store's "newest first" order matches legacy's file order |
| 8 | Drafts | D1 |
| 9 | MPStorage switch | `mpstorage_active` read once into the report (`true`/`false`, `nil` when absent); LOT-130 turns it into each account's record (ADR 0013 §7). The key is not written |
| 10 | Preferences | nothing to copy (same keys, same suite, LOT-060); the step runs `LegacySettingsNormalizer.run(on:)` so the import does not depend on launch order |
| 11 | Legacy page cache | removes the regular files at the root of `Caches/cache` whose name starts with `topic-` and whose extension is `htm` (any case), as legacy's own cleanup selected them; never follows a symlink (the root, `Caches/cache` itself, and each entry are checked with `lstat`, LESSONS 29), never descends into a folder (`avatars`, LOT-066's `pages` and `offline` are areas of the same root), never removes anything else. A missing folder is `nothingToImport`. A removal that fails is counted, not fatal; the step is done once the folder holds no such file |

### Decisions needed before code (operator)

- **D1 — Drafts.** ADR 0013 §5 maps `composerDraftText` to `DraftContext.legacyGlobal`, but at `2fe43da3` `composerDraftText` is not persisted; the Swift composer keeps one active draft per topic number (`reply_active_drafts_by_topic_v1`, ≤ 50) and up to three archived drafts per topic (`reply_drafts_by_topic_v1`), keyed `post-<n>` without category or page, which `DraftContext.reply(topic: TopicID, page:)` needs. **Proposed default:** (a) `brouillon` (ObjC) → `.legacyGlobal` for the D3 account; (b) each active draft → a new `DraftContext.legacyTopic(number: Int)` (an `HFRStorage` type, not `HFRModels`), which the composer (LOT-084 follow-up or LOT-158) offers when it opens a topic whose number matches, then moves to `.reply(…)`; (c) archived drafts are **not imported** (no SwiftHFR counterpart; they stay in `UserDefaults`, never deleted) and become a GAP row (`b·operator`). Alternatives: import archived drafts as extra `.legacyTopic` drafts when no active one exists; or keep ADR §5 and import nothing but `brouillon`. An ADR 0013 amendment records the choice.
- **D2 — Super-favourites without a category.** Legacy stores the topic number alone; `SuperFavoritesStore` needs a `TopicID` (LOT-064 spec: "the favourites list gives the category"), which only the network knows. **Proposed default:** step 3 saves the numbers in a pending device-only document (`LegacySuperFavoritesPending{account, numbers}`); `resolvePendingSuperFavorites(with: [TopicID], account:)` (called by the app each time the favourites list loads) adds every listed topic whose number is pending, **in every category** where it appears (legacy matched the number alone, so it was a super-favourite in each), and removes the resolved numbers. A number never seen in the favourites list stays pending; it is dropped after 90 days or when the user empties super-favourites. Alternative: resolve once at the first favourites load and drop the rest.
- **D3 — Account of the global items.** ADR 0013 §5 imports the global super-favourites, smiley favourites (and D1's drafts) into the account active at the first import. **Proposed default:** that account is the legacy main account (step 1). With no legacy account (logged out), those steps stay pending (no error) and run for the first account that logs in, once.

## Edge cases

- Keychain item absent → `nothingToImport`; present but unreadable (not an archive, wrong root type) → `failed(.unreadable)` without detail, retried at the next run; the SwiftHFR item is never written from a partial decode.
- Several `MAIN` true → legacy's choice (the last); none → LOT-065's repair (the first becomes main).
- Two legacy accounts with the same `md_user` → LOT-065 keeps the first, the second's newer cookies refresh it (LOT-065 "refresh in place").
- `blackListDico.plist` keyed by a display name that matches no imported account (renamed or removed account) → imported under that key, reachable if it logs in.
- A plist or JSON file that is not of the expected type, or an entry with a missing field → that file's step fails as a whole (no partial list), retried at the next run; other steps go on.
- `SuperFavoritesIds` holding numeric strings, zero, negatives, duplicates → read as legacy's loader (`Favorites.swift:135-149`).
- Search-history data that does not decode (legacy's `try?` gives an empty list) → `nothingToImport`, as legacy would have shown nothing; the bytes stay in `UserDefaults`.
- Upload history: the same id twice in the file → once (LOT-064 identity).
- Smiley codes differing only by case → two favourites; equal dates → stored order (LOT-064).
- Destination store in its failure state (LOT-061/064 `loadFailed`) → the step fails and stays pending; the destination is never overwritten.
- App killed mid-import → the steps not marked done run again; steps 2–7 are unions, so a re-run after a save that landed before the crash adds nothing twice.
- A legacy `Caches/cache` that is a symlink, or a `topic-x.htm` that is a symlink or a folder → left as is.

## Secrets

Cookies and `hash_check` go from the legacy Keychain item to LOT-065's item and nowhere else: no log, no report value, no error payload, no temporary file. The account archive is decoded in memory. `LegacyImportError` carries no value (as `CredentialStoreError`).

## Fixtures

- **Small stores** (#347): `tooling/legacy-oracle/samples/legacy-stores/` (real legacy output on synthetic data): `defaults-*.plist` (super-favourites, sections, search history), `smiley-favorites-*.archive`, `search-history-*.json`, `upload-history-*.json`, and the two corrupt cuts. Copied into `Tests/HFRStorageTests/Fixtures/LegacyImport/` (or read in place) for differential tests: the importer must give the list legacy's loader gives (LOT-064 rules).
- **Pseudo lists**: XML plists built from the entry shape of `BlackList.m:43, 51` (an `NSDictionary`/`NSArray` of string and number values, standard plist format); synthetic pseudos only.
- **Accounts**: no committed bytes. On macOS the test replays legacy's writer (`NSKeyedArchiver` of `[NSMutableDictionary]` holding `HTTPCookie`s, `MultisManager.m:49-80`) with the `storage-keychain.json` synthetic accounts; Linux tests use an in-memory `LegacyAccountSource`.
- **Caches**: temporary directories.

## Pending capture / Mac checks

- **M1** (Mac, before merge or in LOT-158): decode a real legacy `HFR_COMPTES_KEY` written by the legacy app with synthetic accounts (the LOT-004 `storage-keychain` case with `tryKeychain`, or LOT-158's install-over test), and measure whether `NSHTTPCookie` decodes with `requiresSecureCoding = true` and an explicit class list; if not, the decode keeps legacy's insecure read, limited to this one item of our own access group.
- None for the small stores: #347 covers them.

## Intentional differences from legacy

- Legacy never migrated its own data between formats except the buggy v0 blocklist (E §7.3); SwiftHFR imports once, never deletes or rewrites the legacy source.
- Super-favourites and smiley favourites become per account (ADR 0013 §5, CHANGELOG-LEGACY row 30); super-favourites gain a category (D2).
- Unreadable legacy data is reported, not silently replaced by an empty list.

## Learnings

To copy into AGENTS.md §11 when the lot closes.
- The legacy reference moved (#655): `composerDraftText`, which ADR 0013 §5 planned to import, is not persisted at `2fe43da3`; re-read every legacy key at the reference before porting a migration.
