# LOT-064 — Small stores: super-favourites, favourites layout, smiley favourites, histories

- **Module:** HFRStorage
- **Difficulty / model:** medium (Opus 5.5 → Fable; the plan routes Sonnet → Opus, this lot was taken by an Opus contributor, `ext/bybifok-opus-1`)
- **Issue:** [#89](https://github.com/ezzz/HFRnow/issues/89)
- **Depends on:** LOT-013 (#46): `Account.id`, the pseudo the account key is computed from; LOT-004 (#41): legacy quirk 22 (smiley favourites by date). `TopicID`, `CategoryID` and `RehostedImage` come from HFRModels, unchanged.
- **Placement:** [ADR 0013](../adr/0013-storage-tiers.md), appendix C and E. Super-favourites and app smiley favourites are per HFR account and are the local copy LOT-172 (#311) mirrors to iCloud; collapsed sections, the smiley search history and the upload history are device-only.

## Legacy sources

Legacy app: `francoisgn/hfrnow` at `2440d79` (an ancestor of `origin/master`). On-device data only: no HFR request, no HFR fact, so no HFR-PROTOCOL subsection.

| Legacy | What it gives this lot |
|---|---|
| `HFRswift/Swift/Favorites.swift:112-136` (`FavoritesSuperFavoriteStore`, `UserDefaults` key `SuperFavoritesIds`) | super-favourites: numbers, ints or numeric strings read, ids above 0 kept, a set saved sorted |
| `Classes/FavoritesTableViewController.m:81-82, 1163, 1639-1657`; `Favorites.swift:381` | the id is the topic number alone (`postID`), compared without the category |
| `Favorites.swift:139-155` (`FavoritesCollapsedSectionsStore`, `CollapsedFavoriteSectionIDs`) | collapsed sections: strings, trimmed, empty ones dropped, a set saved sorted |
| `Classes/FavoritesTableViewController.m:65-81, 495`; `Classes/ObjCFavoritesLoaderWorker.m:36-37, 170-185` | the visible/hidden category order (`arrayCategoriesVisibleOrder`, `arrayCategoriesHiddenOrder`): **not ported**, ADR 0013 §8 drops it |
| `Classes/SmileyCache.m:18, 24-41, 350-439, 444-449` (`smiley_favorites_cache2`, `SmileyFavorite`) | app smiley favourites: a dictionary keyed by the exact code, `{sCode, sRawUrl, dateAdded}`; adding a code already there returns `NO`; the list is sorted by `dateAdded`, oldest first (LOT-004 quirk 22) |
| `HFRswift/Swift/SmileySearchService.swift:78-140` (`SmileySearchHistoryStore`, `smileySearchHistory_v1`) | search history: at least 3 characters and one result, merged case-insensitively (`caseInsensitiveCompare`) with a counter and the last date, the 50 newest kept; `recentSuggestions` (by date, 5) and `topSuggestions` (by count, 10), filtered with `localizedCaseInsensitiveContains` |
| `HFRswift/Swift/AnswerView.swift:1278-1279, 1291` | the search is trimmed before the 3-character check and before it is recorded |
| `HFRswift/Swift/ReplyService.swift:1812-1920` (`RehostUploadedImage`, `RehostUploadHistoryStore`, `rehostImagesSwiftUI.json`); `AnswerView.swift:148, 271, 656, 1909` | upload history: inserted at the top, removed by identity (`fullURL` and upload instant), no limit |

## Behaviour

Code in `Sources/HFRStorage/SmallStores/`, tests in `Tests/HFRStorageTests/SmallStores/`.

- **Shared core** (`Core/`): every store is an actor over one versioned JSON document (`SmallStoreDocument`: `currentVersion`, `empty`, `version`) behind `SmallStorePersistence` (`load`, `save`, `quarantineUnreadableData`), with `FileSmallStorePersistence` (one file, `Data.write(options: .atomic)`) and `InMemorySmallStorePersistence`. Errors are `SmallStoreError`.
- **Account key** (`AccountKey`, ADR 0013 §7): the pseudo with every U+200B removed, then lower-cased, nothing else (no trimming). Frozen and pinned by a table-driven test; it does not call `PseudoNormalizer`, which LOT-072 (#96) may replace. A write whose key is empty throws `emptyAccount`; a read answers empty.
- **`SuperFavoritesStore`**, per account key: `favorites(for:)`, `contains(_:account:)`, `add(_:account:at:)`, `remove(_:account:)`. A topic is a `TopicID` (category and number). Each entry is `{topic, addedAt}`: the date is what LOT-172's iCloud list carries (`{id, addedAt}`, ADR 0013 §3). Lists are saved sorted (forum categories by number, private messages last, then topic number), without duplicates; a topic number ≤ 0 is refused (`invalidValue`). Removing an account's last topic removes the account from the document.
- **`FavoritesLayoutStore`**, device-wide: `collapsedSections()`, `isCollapsed(_:)`, `setCollapsed(_:section:)`. Identifiers are opaque strings, trimmed; an empty one is refused. Saved sorted, without duplicates.
- **`AppSmileyFavoritesStore`**, per account key: `favorites(for:)` (oldest first), `contains(code:account:)`, `add(code:url:account:at:)`, `remove(code:account:)`. Codes are compared exactly. Adding a code already there returns false and keeps the stored URL and date. A new favourite is inserted after every favourite of the same date or older, so the list stays oldest first even when the device clock moved back. An empty or blank code is refused.
- **`SmileySearchHistoryStore`**, device-wide: `record(_:resultCount:at:)`, `recent(matching:limit:)` (default 5), `top(matching:limit:)` (default 10). A search is trimmed; it is remembered only with at least `minimumLength` (3) characters and `resultCount > 0`, otherwise `record` returns false and saves nothing. The same text in another case adds 1 to the existing entry and updates its date; the entry keeps the text first typed. At most `maximumEntries` (50): the most recent are kept, and the entry just recorded is always kept. `recent` sorts by date, newest first; `top` by count, then the most recent first. Both filter with `localizedCaseInsensitiveContains` (every entry for an empty text) and answer nothing for a limit ≤ 0.
- **`RehostUploadHistoryStore`**, device-wide: `images()` (the last added first), `add(_:)`, `remove(id:)`. Entries are HFRModels' `RehostedImage`; identity is its `id` (full URL and upload instant), so an image already there is not added twice, and another upload of the same file is a new entry. No limit, as legacy.
- **Reading what another writer stored** (an older build, LOT-067's importer, LOT-172's mirror): every view applies legacy's load rules, so a list is never shown in another form than this store writes. Super-favourites: topic numbers above 0, each topic once (first entry kept), sorted (`Favorites.swift:115-131`). App smiley favourites: each code once (first entry kept), oldest first, equal dates in stored order (`SmileyCache.m:371-379`). Collapsed sections: trimmed, empty ones dropped (`Favorites.swift:142-150`). Search history: the views sort. A write starts from that normalised list and saves it; removing a topic or a code removes every entry of it.
- **Failure guard** (LOT-061's rule): a document that cannot be read or decoded, or whose `version` is newer than this code, makes reads answer nothing and every write throw (`loadFailed`, `unsupportedVersion`); nothing is saved over it. The file persistence reads `version` before the rest, so a newer document whose shape changed is still reported as `unsupportedVersion`. Ways out: `reload()`, or `discardUnreadableData()` after the user agreed (moves the file to `<name>.corrupt`, an earlier backup kept under a unique name, never deleted). A failed save throws `saveFailed` and leaves memory unchanged. A write that changes nothing returns false and saves nothing.
- **Dates** use `JSONEncoder`'s default form (seconds since 2001, a plain JSON number on Darwin and Linux). Seconds since 1970 does not read back the same `Date` (measured: 4 302 mismatches in 10 000 random dates), which would change `RehostedImage.id` after a relaunch and break `remove(id:)`. Legacy wrote its two JSON histories with the same default.

## Edge cases

- `User1`, `user1` and `us\u{200B}er1` share one list; `" user1"` is another key (no trimming, ADR 0013 §7: the stored pseudo is already trimmed by `AccountBook`).
- Same topic number in two categories, or a private-message thread with the number of a forum topic: different super-favourites.
- A second `add` of a super-favourite, a smiley code or an upload: false, nothing saved, the first date kept.
- Smiley codes differing only by case (`[:Exemple]`, `[:exemple]`) are two favourites, as in legacy.
- A search of 3 characters surrounded by spaces is remembered trimmed; 2 characters, blanks or zero results are not.
- History at 50 entries: a new search evicts the oldest; a search already there evicts nothing; a search recorded with a date older than every entry (clock moved back) is kept and the oldest other entry goes.
- A document written in another order, with duplicates, a topic number 0 or blank section ids (another writer) is read as legacy loaded its data (see Behaviour); the next write saves it in this store's form.
- Each write saves the whole document atomically. Sizes: super-favourites ≤ a few hundred topics per account, smiley favourites ≤ ~100 per account, history ≤ 50 entries, all a few KB; the upload history grows with every upload (~300 bytes each, about 300 KB after 1 000 uploads), as legacy's.

## Fixtures

None: on-device data, synthetic documents and temporary directories. No legacy oracle exists for these items, and none is needed here: reading the legacy formats (`SuperFavoritesIds`, `CollapsedFavoriteSectionIDs`, the `smiley_favorites_cache2` keyed archive, `smileySearchHistory_v1`, `rehostImagesSwiftUI.json`) is LOT-067's importer (#92), which needs the legacy samples generated on the Mac (`tooling/legacy-oracle/samples/storage-smileys.json`, LOT-004).

## Tests

- `AccountKeyTests`: the frozen key form, row by row (U+200B, case, no trimming, other format characters kept); an empty key refused.
- `FileSmallStorePersistenceTests`: missing file, exact JSON of a document, exact date and upload-id round trip, newer version with another shape, unreadable data (garbage, missing or mistyped version, missing field), quarantine keeping the earlier backup.
- `SmallStoreFailureTests`: unreadable data answers nothing and refuses writes, discard and reload, newer version never overwritten (in memory, and a file of another shape through a store), failed save leaves memory unchanged, and each of the five stores over the same corrupt file.
- `SuperFavoritesStoreTests`, `FavoritesLayoutStoreTests`, `AppSmileyFavoritesStoreTests`, `SmileySearchHistoryStoreTests`, `RehostUploadHistoryStoreTests`: the rules above, at their boundaries, and each over a list stored by another writer.

Shown to fail with the behaviour removed (41 mutations, each caught): a failed load treated as empty, no version probe, newer version accepted, memory published before the save, key not lower-cased or keeping U+200B, empty account accepted, unsorted lists, private messages first, topic 0 accepted, duplicates accepted, empty account left in the document, sections untrimmed or unsorted, no-op writes saved, smiley favourites appended or inserted before equal dates, codes compared case-insensitively, blank code accepted, history untrimmed, 2-character or zero-result searches recorded, case-sensitive merge, entry renamed on merge, no eviction, the just-recorded entry evicted, no recency tie-break in `top`, `recent` oldest first, case-sensitive filter, uploads appended or duplicated, dates written as seconds since 1970; after the review: each view or write over a stored list left as stored (super-favourites, smileys, sections), a removal of the first duplicate only, topic 0 kept, equal smiley dates reordered, duplicate codes kept, and the store mapping a newer file to `loadFailed`.

## Pending capture

None for this lot. LOT-067 needs legacy samples of the five legacy formats listed under Fixtures.

## Intentional differences from legacy

- **Super-favourites identify a topic by category and number** (legacy: the number alone, so two topics with the same number in two categories were super-favourites together). [CHANGELOG-LEGACY](../CHANGELOG-LEGACY.md) row 41. LOT-067 maps each legacy number to a `TopicID` (the favourites list gives the category).
- **Per HFR account** for super-favourites and app smiley favourites (legacy: global): ADR 0013 §5, CHANGELOG-LEGACY row 30.
- **Unreadable data is never overwritten**: legacy read the two JSON histories with `try?` and wrote the next change over an empty list, losing the whole history (`ReplyService.swift:1898-1911`, `SmileySearchService.swift:92-116`). CHANGELOG-LEGACY row 42.
- **Save failures are reported** (`saveFailed`) instead of being ignored (`try?` in both legacy JSON stores).
- **Collapsed sections, smiley favourites, histories in versioned JSON files** instead of `UserDefaults` arrays and an `NSKeyedArchiver` archive.
- **Search history**: `top` breaks equal counts by recency (legacy kept the stored order, which a trim at 50 re-sorted by date); the search just recorded survives the 50-entry trim even with an older date.
- **Upload history**: adding an image whose `id` is already there changes nothing (legacy would have listed it twice).

## Learnings

- `JSONEncoder.DateEncodingStrategy.secondsSince1970` does not round-trip a `Date` exactly (the conversion from the 2001 reference shifts the low bits). When a stored date is part of an identity or an equality check, keep the default strategy.
- A view sorted with a stable sort can hide a missing tie-break when the store already writes in that order: test the views over a document stored in another order.
