# LOT-070 — Parity gates

- **Module:** docs/tests (`Packages/HFRKit/Tests`, this spec, `docs/HFR-PROTOCOL.md` §3.4)
- **Difficulty / model:** medium (Opus → Fable)
- **Issue:** [#94](https://github.com/ezzz/HFRnow/issues/94). Depends on LOT-055 (#81) and LOT-057 (#83); LOT-168 (#286) and LOT-184 (#449) do not gate it (operator, 2026-11-12, on #94).
- **Audit:** C18 (differential roll-up, [C](../audit/C-message-parsing.md) §8), E-9 (persistence parity checklist, [E](../audit/E-storage-vendors.md) §8), D13 (write chapter of HFR-PROTOCOL, [D](../audit/D-posting.md) §8).
- **Closes:** M3 ([ROADMAP](../ROADMAP.md): "Every M3 lot done; LOT-070 parity gates green").

## Legacy sources

The legacy reference is `legacy/duo-inner-cover` @ `87fe0d1c` (AGENTS.md §2). The persistence gate covers what the app users run writes: the `HFRswift` target, measured on `SuperHFRplus.xcodeproj/project.pbxproj` @ `87fe0d1c` (the `PBXNativeTarget` "HFRswift", its Sources phase: 45 Objective-C files, plus every file of the synchronized folder `HFRswift/Swift/`; the same method as [E](../audit/E-storage-vendors.md) §1.1). Every legacy `file:line` below was read with `git grep -n <key> 87fe0d1c -- <those files>`. Files of `Classes/` outside that list (`AddMessageViewController.m`, `FavoritesTableViewController.m`, `InfosViewController.m`…) are the legacy `SuperHFRplus` target; their keys are listed only where SwiftHFR still reads them.

## Legacy counterpart (app lots)

None: an engine and docs lot.

## UX evolutions (app lots)

None: no user-visible change.

## Behaviour

Three gates. Each says what was measured, how to measure it again, and its state on 2026-11-16 (`dev-swift` @ `038af84` plus this lot's test changes).

### Gate A — differential roll-up (C18)

**Rule.** Every legacy oracle committed under `Packages/HFRKit/Tests/HFRParsingTests/Fixtures/<set>/<case>.oracle.json` is owned by the suite that compares the port's output with it (ADR 0004), or by a test that pins a documented deviation; and every M3 engine lot names the evidence its behaviour is checked against: a legacy oracle, captures, or, for on-device stores, the legacy formats of gate B.

**CI gate.** `OracleOwnershipTests.everyOracleIsOwned` (`Tests/HFRParsingTests/Parity/`) reads every `Fixtures/*/oracle-map.json` of the test bundle and fails when an `*.oracle.json` file has no map entry (or the reverse), when a (folder, kind) pair has no owner or two, or when an owner's case list differs from the map's cases of its pairs. Each owner is the static case list its suite runs (`TopicListDifferentialTests.allCases`, `HopFormOracleTests.composerCases`…), so a case is owned only if the suite's comparison takes it as an argument, except six literals tied to a test of their own: `LOT-002/R50a`, `R12`, `R70b`, `LOT-004/R46`, `W17b`, `LOT-028/T01`. Adding such a literal is visible in review, not blocked by CI. A new oracle therefore fails CI until a suite compares it.

**Second measure.** Opening is necessary, not sufficient (`HFRLinkRouteOracleTests` opens every file of `LOT-002` and `LOT-003` to read their URLs), but a file nobody opens is certainly not compared. Run the whole package suite under `strace` and list the oracle files no test opened:

```sh
cd Packages/HFRKit && swift build --build-tests
strace -f -qq -e trace=openat -e signal=none -o /tmp/oracles.strace swift test --skip-build
grep -v ENOENT /tmp/oracles.strace | grep -oE '"[^"]*/Fixtures/[^"]*\.oracle\.json"' \
  | sed -E 's/.*\/Fixtures\///; s/"//' | sort -u > /tmp/opened.txt
(cd Tests/HFRParsingTests/Fixtures && find . -name '*.oracle.json' | sed 's|^\./||' | sort) | comm -23 - /tmp/opened.txt
```

An empty last line means every oracle was opened. Rerun with `--skip HFRLinkRouteOracleTests` to see the files only the link router opens.

**Before this lot** (`038af84`, 2019 tests passing): 178 of 195 oracles opened, and 19 compared by no suite: the 17 never opened, plus `LOT-002/R70a` and `R72b`, opened only by the link router (Fable, round 1 on #930). What compares them now:

| Oracles | Kind | Now compared by |
|---|---|---|
| `LOT-004/W61`, `W62`, `W63`; `M2-misc/W130`; `M2-writes/W73` | write answers | `HopResponseParserTests.followsOracle` (kind, message, anchor); `casesCoverEveryResponseOracle` covers the `response` entries of the `LOT-004`, `M2-writes` and `M2-misc` maps |
| `M2-writes/R123b`, `R123d`, `R125`, `R129`, `R133`, `R134`, `R140` | group MP thread pages (#336, #507) | `MessageBlockOracleTests.matchesOracle`, `TopicPageMetadataOracleTests`; both coverage tests now include `M2-writes` |
| `M2-writes/R123g` | empty `owntopic=1` list (#109) | `FavoritesDifferentialTests` (sections, rows, order); its coverage test reads the `M2-writes` map too |
| `LOT-004/R96b` | another account's storage thread | `MPStoragePageParserTests.otherAccountsThreadFollowsOracle` (legacy "not found", the parser's `notAddressed`); `coversEveryStorageOracle` |
| `LOT-003-settings/R21-sig-noimg-novid`, `R26-sig` | topic pages, `display_sig=yes` (LOT-003) | `MessageContentOracleTests.signaturesFollowTheSettingsOracle`: the normalizer's signature text equals legacy's `span.signature`; `settingsCasesCoverTheMap` |
| `LOT-003-settings/R28-noimg-novid` | topic page, images and videos off | opened by the same test, only its block count meets the port: its settings are app policies (below) |
| `LOT-002/R72b` | home page after `unlog.php` without token | `ForumListParserTests.matchesOracle` (whole result) |
| `LOT-002/R70a` | stale-session home page | `ForumListParserTests.staleSessionPageThrowsWhereLegacyReturnedNothing`: legacy's empty list, the port's `malformed` (LOT-021 rule 9, LESSONS 44) |

**After**: **195 of 195** oracles opened and owned, every new comparison passing. Each new test was shown to fail with its change reverted: `W73` dropped from the case list, `R140` dropped from the M2 topic cases, `R123g` dropped from the favourites cases (each caught by its coverage test), a signature changed by the normalizer (caught on `R26-sig`); and `OracleOwnershipTests` fails on the three probes of round 1 (an `mp` case added to `M2-writes`, a `response` case to `M2-readonly`, an oracle file without a map entry in `LOT-002`).

**Owned but not compared field by field**, each pinned where it is owned:
- `LOT-002/R73b` (favourites, `defaut` theme): `FavoritesDifferentialTests.pendingCases`, #384.
- `LOT-002/R12`, `R70b` (legacy raised): their own tests in `FavoritesDifferentialTests` check the exception and the port's notice.
- `LOT-002/R50a` (the search waiting page, a redirect for the list parser): compared as LOT-005 `R50a` by `SmallParsersOracleTests`.
- `LOT-003-settings/R28-noimg-novid` and the image and video halves of `R21-sig-noimg-novid` (LESSONS 51): `display_images=no` and `embedded_videos=no` are rendering policies of the app (LOT-107 image loading setting, LOT-108 video placeholder; ADR 0006); the engine's `MessageContent` does not depend on them. The two lot specs now name these oracles.

**M3 lots** (the 43 of `tooling/roadmap/milestones.json` "M3"; all closed but LOT-070 itself and LOT-168, which does not gate). Evidence: **O** = differential against a legacy oracle; **C** = captures (no legacy oracle exists: legacy had no such code, or the flow is Swift-only in legacy, LESSONS 52); **S** = on-device store or pure value, no HFR page (its legacy formats are gate B).

| Lot | Evidence | Oracles or captures | Suites |
|---|---|---|---|
| LOT-023 MP list, badge | O | `LOT-002` `mp`, `M2-writes` `mp` | `PrivateMessageListParserTests`, `PrivateMessageBadgeParserTests` |
| LOT-026 poll | O | `LOT-005` `poll` | `PollOracleTests` |
| LOT-027 profile | O | `LOT-005` `profile`, `profile-edit` | `UserProfileOracleTests`, `UserProfileParserTests` |
| LOT-028 AQ parsers | O | `LOT-028/T01` | `AQParsersTests` |
| LOT-031 action links | O | `LOT-003` | `MessageActionsOracleTests` |
| LOT-032 quotes | O | `LOT-003` | `MessageQuoteOracleTests` |
| LOT-035 video embeds | O | `LOT-003` (iframes of `embedded_videos=yes`) | `MessageContentOracleTests`, `MessageEmbedDetectorTests` |
| LOT-038 MPStorage pages | O | `LOT-004` `storage` | `MPStoragePageParserTests` |
| LOT-046 search | O | `LOT-002` `search`, `LOT-005` `search-redirect` | `GlobalSearchFlowTests`, `TopicSearchFlowTests` |
| LOT-047 MP poll | O | `LOT-002` (`nbMP` side effect) | `MPUnreadPollTests` |
| LOT-049 quote engine | O | `LOT-004` `form` | `QuoteCaptureTests`, `QuoteFlowTests` |
| LOT-050 moderator alert | O + C | `LOT-004/R46`; `R88`, `R89`, `W46`, `W47` | `ModeratorAlertPrepareTests`, `ModeratorAlertSubmitTests` |
| LOT-051 flags | C | `P03a`-`P03q`, `R10`, `R21` | `FlagLinkWriteTests`, `FavoriteListAndReadTests`, `FlagSessionGateTests` |
| LOT-052 MPStorage transport | O + C | `LOT-004` `storage`, `form/R60b`; `W440a`-`W440c` | `MPStorageTransportReadTests`, `MPStorageTransportWriteTests` |
| LOT-053 smileys | O | `LOT-005` `smiley-search`, `smiley-keywords` | `SmileyLookupFlowTests` |
| LOT-054 poll vote | C | `R83`, `W42`-`W45` (legacy vote is Swift-only, no oracle) | `PollVoteFlowTests`, `HopResponsePollVoteTests` |
| LOT-055 AQ client | O + C | `LOT-028/T01`; `T50`-`T90` | `AQClientTests`, `AQCreateTests` |
| LOT-056 image hosts | C | `U01`, `U02`, `T10`-`T24`; legacy multipart body written out | `MultipartBodyTests`, `RehostClientCaptureTests` |
| LOT-057 REST browsing | C | REST captures; `LOT-002/R01` for the forum names | `RESTDocumentTests`, `RESTBrowsingClientTests`, `RESTFlagBucketClientTests` |
| LOT-058 MP actions | O + C | `M2-writes` (forms, answers, threads); `W18`, `W137a`, `W137b` | `GroupRosterTests`, `MPQuoteTests`, `MarkUnreadTests`, `HopResponseMPRefusalTests` |
| LOT-060 settings | S | gate B | `SettingKeyTests`, `UserDefaultsSettingsStoreTests`, `LegacySettingsNormalizerTests` |
| LOT-061 pseudo lists | S | gate B | `PseudoListStoreTests`, `FilePseudoListPersistenceTests` |
| LOT-062 MPStorage merge | S | synthetic documents; `LOT-004/R60a` via LOT-038 | `MPStorageCodecTests`, `MPStorageMergeTests`, `MPStorageMutationTests` |
| LOT-063 drafts | S | gate B | `DraftStoreTests`, `DraftStoreFileTests` |
| LOT-064 small stores | S | gate B | `SuperFavoritesStoreTests`, `AppSmileyFavoritesStoreTests`, `RehostUploadHistoryStoreTests`, `SmileySearchHistoryStoreTests` |
| LOT-066 caches | S | gate B | `AvatarCacheTests`, `CacheEvictorTests`, `TemporaryFileCacheTests` |
| LOT-067 legacy import | S | `tooling/legacy-oracle/samples/legacy-stores/` (legacy-written) | `LegacyImporterTests`, `LegacyFormatsTests`, `LegacyListsDraftsSamplesTests` |
| LOT-068 offline reading | S | — (no offline save in the `HFRswift` UI, gate B) | `OfflineTopicStoreTests`, `OfflinePageFormatTests` |
| LOT-072 pseudo normaliser | S | — | `PseudoNormalizerTests` |
| LOT-073 JSON tokenizer | S | `LOT-004/R60a` | `JSONTokenizerTests`, `MPStorageCodecTests` |
| LOT-090 reading positions | S | — (new store) | `ReadingPositionStoreTests` |
| LOT-091 notification ledger | S | — (replaces `nb_mp`, gate B) | `NotificationLedgerTests`, `NotificationLedgerStoreTests` |
| LOT-092 check updates | C | `R01`-`R03`, `R10`, `R12`, `R70a`, `R70b`, `R123g` | `CheckUpdatesFlowTests` |
| LOT-093 filtered posts | O | `LOT-003` | `FilteredPostsLegacyTests`, `FilteredPostsFlowTests` |
| LOT-094 MP thread delete | C | `R95k`, `W64`, `W65`, `W64x` | `DeletePrivateMessageFlowTests` |
| LOT-095 link router | O | `LOT-002`, `LOT-003` | `HFRLinkRouteOracleTests`, `HFRLinkRouteCorpusTests` |
| LOT-096 emoji table | S | — | `EmojiSmileyTableTests`, `PostCharacterCheckTests` |
| LOT-097 BBCode renderer | C | HFR's own rendering: `R95d`, `R95h`, `R20` (no legacy renderer) | `BBCodeRendererOracleTests`, `BBCodeRendererBatch2OracleTests` |
| LOT-098 Giphy | C | Giphy captures | `GiphyClientTests` |
| LOT-167 pager exactness | O | `LOT-002` `topics` | `TopicListDifferentialTests` |
| LOT-172 iCloud KVS | S | — (new store) | `SyncedSettingsStoreTests` |
| LOT-168 forum list completeness | — | open, does not gate (operator, 2026-11-12) | — |

The M1 engine lots (LOT-010 to LOT-045, LOT-048) are in M1, not in this table; their oracles are in the 195 above.

**State: 🟢 green.** Documented deviations stay in each lot's spec ("Intentional differences from legacy").

### Gate B — persistence parity checklist (E-9)

**Rule.** Every item the `HFRswift` app writes on the device at `87fe0d1c` has a row: where SwiftHFR keeps it, whether the update imports it, and the test that pins it. "In place" means SwiftHFR reads the same `UserDefaults` key in the same standard suite (in-place update of `hfrplus.red.super`, Q-1, [LOT-067](LOT-067-legacy-import.md)); "imported" means LOT-067 copies it once into a SwiftHFR store; "not kept" says why it may go.

**Keychain**

| # | Legacy item | Legacy @ `87fe0d1c` | SwiftHFR | Kept | Tests |
|---|---|---|---|---|---|
| B1 | Accounts: generic password `HFR_COMPTES_KEY`, `NSKeyedArchiver` of `[{PSEUDO, PSEUDO_DISPLAY, COOKIES, HASH, AVATAR, MAIN}]` | `Classes/MultisManager.m:44` (read), `:49-86` (write) | LOT-065 `CredentialStore` (Keychain on Darwin) | imported (LOT-067 step 1) | `LegacyImporterTests`, `CredentialStoreTests`; `LegacyAccountArchiveTests` (Darwin only) |

**`Documents/`**

| # | Legacy item | Legacy @ `87fe0d1c` | SwiftHFR | Kept | Tests |
|---|---|---|---|---|---|
| B2 | `blackListDico.plist` (per account) | `Classes/BlackList.m:179, 184` | LOT-061 `PseudoListStore`, blocklist | imported (step 2) | `LegacyImporterTests`, `LegacyListsDraftsSamplesTests` |
| B3 | `blackList.plist` (v0) | `Classes/BlackList.m:180` | same, global account | imported when B2 is absent (step 2) | `LegacyImporterTests`, `LegacyListsDraftsSamplesTests` |
| B4 | `whiteList.plist` (global) | `Classes/BlackList.m:167, 170` | `PseudoListStore`, allowlist | imported (step 2) | `LegacyImporterTests`, `LegacyListsDraftsSamplesTests` |
| B5 | `smiley_favorites_cache2` (keyed archive) | `Classes/SmileyCache.m:18` | LOT-064 `AppSmileyFavoritesStore` | imported (step 5) | `LegacyFormatsTests`, `BinaryPropertyListTests`, `AppSmileyFavoritesStoreTests` |
| B6 | `rehostImagesSwiftUI.json` | `HFRswift/Swift/ReplyService.swift:1936` | LOT-064 `RehostUploadHistoryStore` | imported (step 7) | `LegacyFormatsTests`, `RehostUploadHistoryStoreTests` |
| B7 | `forumsCache.plist` | read only, `HFRswift/Swift/ForumSearchView.swift:456`; written by the legacy-only `ForumsTableViewController` | LOT-014 catalogue and the live forum list | not kept: `HFRswift` never writes it | — |
| B8 | `offlineTopicsDico.plist`, `offlineImageCacheDico.plist` | `Classes/Constants.h:94-95`, `Classes/OfflineStorage.m:92, 125` | LOT-068 `OfflineTopicStore` (new format) | not kept: no `HFRswift` screen saves a topic ([E](../audit/E-storage-vendors.md) §2.3) | — |

**`UserDefaults` (standard suite)**

| # | Legacy item | Legacy @ `87fe0d1c` | SwiftHFR | Kept | Tests |
|---|---|---|---|---|---|
| B9 | Preferences of `AppSettingsView` and `Common.swift` (`vos_sujets` … `rehost_resize_before_upload`, the LOT-060 catalogue) | `HFRswift/Swift/AppSettingsView.swift`, `Common.swift:33-284, 408-556`, `ReplyService.swift:1836-1837` | LOT-060 `SettingKey`, same names | in place | `SettingKeyTests.keysAreUniqueAndKeepTheirLegacyNames`, `UserDefaultsSettingsStoreTests` |
| B10 | `size_text_topics`, `size_text`, `size_text_reply` (mirrors of `text_size_scale`) | `HFRswift/Swift/AppSettingsView.swift:357-359` | `text_size_scale` / `text_size_percent` | `size_text_topics` migrated once at launch and removed (`LegacySettingsNormalizer`); `size_text` and `size_text_reply` not kept: write-only mirrors, `text_size_scale` (B9) holds the value | `LegacySettingsNormalizerTests` |
| B11 | `force_manual_theme` and the other deprecated theme keys | `HFRswift/Swift/Common.swift:416, 448` | removed at launch, as legacy did (`SettingKey.deprecatedKeys`) | not kept (legacy removed them) | `LegacySettingsNormalizerTests` |
| B12 | `SuperFavoritesIds` | `HFRswift/Swift/Favorites.swift:133` | LOT-064 `SuperFavoritesStore` through `LegacyPendingStore` (decision D2) | imported (step 3) | `LegacyFormatsTests`, `LegacyPendingStoreTests` |
| B13 | `CollapsedFavoriteSectionIDs` | `HFRswift/Swift/Favorites.swift:160` | LOT-064 `FavoritesLayoutStore` | imported (step 4) | `LegacyFormatsTests`, `FavoritesLayoutStoreTests` |
| B14 | `FavoritesShowCollapsedSections`, `HFRswiftGlobalTopicListFlag`, `HFRswiftStartupScreen` | `HFRswift/Swift/Favorites.swift:448`, `MainWindow.swift:305`, `Common.swift:33` | `SettingKey`, same names | in place | `SettingKeyTests.keysAreUniqueAndKeepTheirLegacyNames` |
| B15 | `smileySearchHistory_v1` | `HFRswift/Swift/SmileySearchService.swift:89` | LOT-064 `SmileySearchHistoryStore` | imported (step 6, merge) | `LegacyFormatsTests`, `SmileySearchHistoryMergeTests` |
| B16 | `reply_active_drafts_by_topic_v1` | `HFRswift/Swift/AnswerView.swift:140` | LOT-063 `DraftStore` `.reply` through `LegacyPendingStore` (D1) | imported (step 8) | `LegacyPendingStoreTests`, `LegacyListsDraftsSamplesTests` |
| B17 | `reply_drafts_by_topic_v1` (archived replies) | `HFRswift/Swift/AnswerView.swift:139` | LOT-101 archived replies start empty | **not imported** (operator decision D1, 2026-11-09, #92; GAP row of LOT-067) | — (no SwiftHFR code reads the key) |
| B18 | `brouillon` | `Classes/AddMessageViewController.m:69` (legacy `SuperHFRplus` target only) | `DraftContext.legacyGlobal` | imported (step 8) | `LegacyImporterTests`, `LegacyListsDraftsSamplesTests` |
| B19 | `mpstorage_active` | `Classes/BlackList.m:39`, `Classes/MPStorage.m:83` | read once into the import report; LOT-130 makes it each account's record (ADR 0013 §7) | read (step 9) | `LegacyImporterTests` |
| B20 | `mpstorage_last_rw` | `Classes/MPStorage.m:975-976`: written with `registerDefaults:`, so never persisted (E §7) | `SettingKey.mpStorageLastSync`, same name, persisted now | nothing to keep: absent from the legacy plist | `SettingKeyTests.keysAreUniqueAndKeepTheirLegacyNames` |
| B21 | `dicMPStorage_postid` (storage thread id per pseudo) | `Classes/MPStorage.m:84-85` | LOT-052 `MPStorageCopy.postID` | not kept: a cache, found again by the MP list walk (LOT-052) | `MPStorageCopyStoreTests`, `MPStorageListWalkTests` |
| B22 | `nb_mp`, `nb_mp_failure` | `Classes/HFRplusAppDelegate.m:221-222, 251-255` | LOT-091 `NotificationLedger` per account; the badge is read again from the home page (LOT-047) | not kept: counters, rebuilt by the next poll | `NotificationLedgerTests` |
| B23 | `nb_aq`, `last_check_aq` | `HFRswift/Swift/AQPlusView.swift:30, 42` | the AQ feed's "new since" (LOT-055 engine; storage in the app, LOT-133, open, M4) | not kept: the count is recomputed from the feed | `AQClientTests` (count) |
| B24 | `HFRswiftOpenMessagesFromNotificationPending` | `HFRswift/Swift/Common.swift:57` | none | not kept: one-shot flag of a notification tap | — |
| B25 | `HFRswiftIPadSplitColumnVisibilityV3`, `MessageSmileySheetCompactImage` | `HFRswift/Swift/MainWindow.swift:1337`, `MessagesView.swift:6134` | none | not kept: layout state | — |
| B26 | `AnswerView.smileys.*.expanded`, `AnswerView.smileys.search.allKeywords` | `HFRswift/Swift/AnswerView.swift:2030` | app `@AppStorage`, same names (`App/SwiftHFR/Smileys/SmileyPickerView.swift:18-20`) | in place (app) | — (app) |
| B27 | `theme_noel_disabled`, `theme_noel_period`, `noel_first_time_2022`, `shake_to_refresh` | `Classes/HFRplusAppDelegate.m:102-103, 644-645` | seasons under `season.*` (`SettingKey+Seasons`) | not kept: legacy wrote `shake_to_refresh` = NO and `theme_noel_disabled` = YES at every launch (`HFRplusAppDelegate.m:102-103`); `theme_noel_period` and `noel_first_time_2022` are the 2022 season's window and one-shot alert, replaced by the per-year `season.noel.*` keys (LOT-166) | `SettingKeyTests` (season keys) |
| B28 | `composerDraftText` | `HFRswift/Swift/MessagesView.swift:3143` (`@State`) | — | nothing to keep: not persisted at `87fe0d1c` | — |

**`Library/Caches/`**

| # | Legacy item | Legacy @ `87fe0d1c` | SwiftHFR | Kept | Tests |
|---|---|---|---|---|---|
| B29 | `cache/avatars/<MD5 of the pseudo>` | `HFRswift/Wrapped/ParseMessagesOperation.m:124`, `HFRswift/Swift/MPListView.swift:929`, pruned at `Classes/HFRplusAppDelegate.m:544` | LOT-066 `AvatarCache` reads legacy names (`LegacyAvatarName`) | in place | `AvatarCacheTests` |
| B30 | `cache/topic-*.htm` (rendered pages) | `HFRswift/Swift/Common.swift`, `Classes/OfflineStorage.m` (LOT-067 table) | removed (rebuildable) | removed once (step 10) | `LegacyPageCacheTests` |
| B31 | the bundle's CSS and JS copied into `cache/` at every launch | `Classes/HFRplusAppDelegate.m:84`, `Classes/OfflineStorage.m:439` | none: no SwiftHFR code reads `Caches/cache/` files other than avatars (B29) | not kept: left in `Caches`, which the system may purge; nothing reads them | — |

**System**

| # | Legacy item | SwiftHFR | Kept |
|---|---|---|---|
| B32 | `HTTPCookieStorage.shared` | each account's own jar (LOT-042) from its Keychain record (B1) | not kept: the record holds the cookies |
| B33 | `BGTaskScheduler` id `com.hfrplus.refresh_mp` | app, LOT-140 (open, M4) | identifier to declare again |
| B34 | alternate app icon (`setAlternateIconName`, `HFRswift/Swift/AppSettingsView.swift:224`) | held by iOS, not by the app; the `icon` key (B9) names it and the app keeps the legacy names (`App/SwiftHFR/Settings/AppIconOption.swift:89-90`) | system state, not migrated: to observe on LOT-158's install-over check (#248) |
| B35 | notification authorization (`HFRswift/Swift/MPBackgroundService.swift:50`) | held by iOS for the bundle id | system state, not migrated: to observe on LOT-158's install-over check (#248) |

**Open on this gate**: B1's decode of a real legacy archive on a device is the LOT-067 Mac check M1 (pending capture, on LOT-158's install-over test, #248); B23 and B33 belong to open app lots (LOT-133, LOT-140); B34 and B35 are to observe on the same install-over check (#248). None is engine work.

**State: 🟢 green for the engine**, with the five app or system rows above (B1's Mac check, B23, B33, B34, B35) tracked on their lots.

### Gate C — write gates (D13)

The write chapter of [HFR-PROTOCOL](../HFR-PROTOCOL.md) gets §3.4 "Write gates": one row per state-changing request the engine sends, with the capture of its request, the answer that confirms it, the refusals captured, what is not captured, and the engine lot and tests. Its facts are the §6c and §7 entries it links: nothing new is claimed.

**Rule for a row to be green**: the request body is checked against a captured request (or legacy's body written out); the success answer is captured and confirmed by its own sentence or code; a missing session is either captured as a refusal or, where HFR answers it like a success or it is not captured, made impossible by a session check before sending (named test); and an answer that matches none of the captured ones is never read as a success (LOT-037's classifier and each flow's own check).

**State: 🟢 green** for every row; each row's "Not captured" cell lists the residual unknowns, none of which can turn into a false success.

## Edge cases

- A new oracle folder, kind or case, or an oracle file without a map entry: `OracleOwnershipTests` fails until a suite's case list takes it.
- A suite that lists a case but stops comparing a field: not caught by ownership; the suite's own tests and the review are the guard.
- `TopicPageFlagOracleTests` compares the flag links of `LOT-003`, `LOT-003-flag`, `M2-readonly` and `M2-misc` topic pages, not of the seven `M2-writes` group threads (their blocks and metadata are compared): not claimed by this gate.

## Fixtures

None added: every oracle and capture already exists. The new tests read `LOT-002`, `LOT-003-settings`, `LOT-004`, `M2-misc` and `M2-writes`.

## Intentional differences from legacy

None introduced. The `LOT-003-settings` signatures: the normalizer always returns the signature and the app decides to show it, where legacy dropped it from the HTML with `display_sig=no`; the comparison is on the `display_sig=yes` oracles.

## Learnings

To copy into AGENTS.md §11 when the lot closes.
- 2026-11-16 — LOT-070: 17 of 195 oracles were never read by any test, though every suite had a "case list covers the map" test: each covered only the folders its author knew (`M2-writes` and `LOT-003-settings` were missed). Measure what a test run opens instead of trusting per-suite coverage (LESSONS 60).
