# LOT-068 — Offline reading

- **Module:** HFRStorage
- **Difficulty / model:** medium (the plan routes Sonnet → Opus; taken by an Opus contributor, `ext/bybifok-opus-1`, so the reviewer is Fable)
- **Issue:** [#93](https://github.com/ezzz/HFRnow/issues/93)
- **Depends on:** LOT-011 (#44): `TopicID`; LOT-066 (#91): `CacheDirectory`, `CacheArea`, `CacheEvictionPolicy`, `CacheEvictor`.
- **Audit:** E-8 (`docs/audit/E-storage-vendors.md:339`), superseded by decision Q-5 ("in scope", `docs/audit/README.md`); ADR 0013 (offline pages: device, not backed up).

## Legacy sources

Legacy app: `francoisgn/hfrnow` at `2440d79` (an ancestor of `origin/master`). **Legacy had no working offline reading**: the download method is inside a `/* … */` block (`OfflineStorage.m:145-294`), and nothing outside the file calls the list toggles (audit E §2, `docs/audit/E-storage-vendors.md:72`: "compiled, effectively unused"; no HFRswift UI). The rows below describe the shipped list code and the intended design the commented-out method shows.

| Legacy | What it gives this lot |
|---|---|
| `Classes/OfflineStorage.m:41-82` | compiled, never called: a set of offline topics keyed by the topic number alone (`postID`) |
| `OfflineStorage.m:88-143` | compiled: the set archived with `NSKeyedArchiver` in `Documents/offlineTopicsDico.plist` (backed up), read back without any version or error handling |
| `OfflineStorage.m:145-294` | **commented out**: the intended download into `Documents/cache/<post>/<post>-<page>/index.html`, up to `offline_max_pages` pages (a key written nowhere) from the current one, the topic's last page fetched again, images rewritten to local copies |
| `OfflineStorage.m:336-437` | compiled, never reached from the app: erase all, an integrity pass that walks pages until the first missing one, reading a saved page back |
| `Classes/Topic.m:101-157` | the archived topic fields (title, URLs, pages loaded) |

## Behaviour

Code in `Sources/HFRStorage/Offline/`, plus the `offline` area in `Sources/HFRStorage/Caches/`. HFRStorage imports neither HFRNetwork nor HFRParsing: fetching pages is the app's job (LOT-139), and the parser reads the saved HTML back.

### What is saved

The page's **HTML as HFR served it to a visitor** (decoded text), with its topic, page number, the title the caller read, and the save date (`OfflinePage`). A parsed `TopicPage` is not stored, for three reasons:
- the current parser reads the HTML at display time, so a parser fix also applies to pages saved earlier;
- the stored format does not follow the HFRModels types, which change with the core;
- legacy's commented-out design kept HTML too.

Images are not saved (the commented-out design copied them): the app's image cache or a later lot decides.

### Where, and for whom

- In the LOT-066 cache, area `offline` (`Library/Caches/cache/offline/`): device-only and never backed up (ADR 0013). Like every cache, the system may reclaim it; the list shows what is on disk.
- **Shared by the accounts of the device**. The pages carry no session, so they are the same for every account. `save` refuses a page in which any `hash_check` input has a value (`containsSessionToken`), because such a page was fetched with the session and would put the account's token on disk. A page fetched without cookies has every such input empty (`R20`, `R22a`, `R28`: four inputs); a logged-in page has the token in each (`R21`: six, `R32b`: eight). An input whose value cannot be read counts as a token (fail closed). Fetching without cookies is also what keeps the read flag where it is (HFR-PROTOCOL §7 E25).
- Only forum topics: a private conversation cannot be read without the session (`invalidTopic`).

### Format and versions

- **One file per page**: `offline/<category>-<topic>/<page>.json`. Numbers are written in decimal with no sign or leading zero, so one page has exactly one file name. The JSON has sorted keys and fields `version`, `category`, `topic`, `page`, `title`, `html` and `savedAt` (the default date strategy, which round-trips a `Date` exactly).
- **No index file**: the list is read from the folder names and file names, so a file the evictor or the system removed never leaves the other pages unreadable. Each topic's title comes from its highest readable page, and its date from the newest page file. `topics()` decodes one page per topic (about 56 ms for 40 topics of 138 KB pages): the app must call it off the main actor (LOT-139).
- **Regular files only**: a page is a regular `<page>.json` file; a directory or a symbolic link of that name is ignored by the list and never read.
- **Versions**: `version` is read first. A file of another version gives `unsupportedVersion(n)`, older or newer (version 1 is the first, so nothing migrates yet); a damaged file, or one whose fields name no forum topic or page, gives `unreadable`. In both cases `page(_:of:)` throws, `topics()` still lists the page number, and nothing crashes. Such a file goes with `remove`, `removeAll` or the evictor. A file whose content names another topic or page than its place is `unreadable` too.

### Pages per topic, last page, eviction

- **Per-topic limit**: `maximumPagesPerTopic`, 50 by default (2,000 messages, a few megabytes). Legacy had no limit in use: the commented-out design read `offline_max_pages`, a key nothing writes.
  - Saving one more page removes the topic's lowest-numbered pages, because the reader moves forward.
  - A page lower than every page of a full topic is refused (`beyondPageLimit`), since it would be the one removed.
- **Last page**: saving a page that exists replaces it atomically. The topic's last page grows, so the app saves it again on each refresh, as the commented-out legacy design intended. `OfflineTopic.lastSavedAt` and the per-page `savedAt` tell how old the copy is.
- **Eviction**: the `offline` area's policy (`CacheEvictionPolicy.offlineTopics`) keeps pages whatever their age, because the user chose to save them. Past 200 MB, the pages saved longest ago go first. It is applied by LOT-066's `CacheDirectory.evictAll()` at launch, with LOT-066's guards (no symbolic links, files only). `removeAll()` is LOT-066's `clear`.
- **Folder safety**: every path goes through `CacheDirectory.safeURL(for: .offlineTopics)`. A topic folder that is a symbolic link is refused (`unsafeFolder`), and linked page files are ignored.

## Edge cases

- `topics()` leaves out folders whose name is not `<category>-<topic>` (`prive-3`, `13-0`, `013-28563`), files that are not `<page>.json` (`01.json`, `-1.json`, `1.txt`), and topic folders without any page file.
- A topic whose pages are all unreadable is listed with an empty title.
- Saving page 0, a topic number 0, category 0 or an empty page is refused before anything is written.
- `maximumPagesPerTopic` below 1 reads as 1.

## Fixtures

Captures only, nothing new: topic pages fetched without cookies `R20`, `R22a`, `R22b`, `R23`, `R24`, `R28` (round trip, replacement) and with the session `R21`, `R32b` (refused). File-level edges (versions, damage, stray names, links) use files written by the tests in a temporary cache. No legacy oracle: `tooling/legacy-oracle/samples/storage-offline.json` only matters to the LOT-067 importer.

## Tests

- `OfflineTopicStoreTests`:
  - round trip of five captured pages, byte for byte;
  - the list's order, pages and title, and replacement of the last page;
  - refusal of the two logged-in captures, with no file written;
  - the token check's quoting and fail-closed forms;
  - invalid topics and an empty page;
  - the per-topic limit;
  - the area's policy, with the oldest page evicted and the rest still readable;
  - removal of one topic and of all.
- `OfflinePageFormatTests`:
  - the file format (sorted keys, exact date);
  - other versions (0, 2, -1);
  - six damaged files;
  - misplaced content and records with no topic or page;
  - stray files and folders;
  - a linked topic folder and a linked page file;
  - a directory named like a page.
- `TemporaryFileCacheTests`: the area list now includes `offline`.

Shown to fail with the behaviour removed (19 mutations, each caught):
- no token check, single quotes ignored, a missing value read as no token;
- any version accepted, record fields not checked, misplaced files accepted;
- no beyond-limit check, the highest pages removed instead of the lowest;
- leading zeros accepted, a linked topic folder accepted, `prive` accepted, an empty page accepted, page 0 accepted;
- an age limit on the area;
- the oldest topic listed first, the title taken from the lowest page;
- after the review: the token check not quote-aware, an unclosed quote read as no token, no regular-file check, a linked page file read (listing one needs both the link and the regular-file guard removed, since either excludes it).

## Pending capture

- None from HFR. A topic fetched without cookies whose page holds a `hash_check` with a value has not been seen. If one exists, that page is refused, and nothing is stored.

## Intentional differences from legacy

1. **Offline reading works**: the legacy app had none in use (download commented out, list never called).
2. **Caches instead of Documents**: device-only, not backed up, reclaimable (ADR 0013); legacy's list code archived to `Documents/`, backed up.
3. **No session token on disk**: a page fetched with the session is refused.
4. **Topics by category and number** (legacy keyed them by the number alone, `:41-82`, as for super-favourites, CHANGELOG row 41).
5. **No separate list file**: the list is read from the files, so an evicted or damaged page never breaks the others; legacy's list design could hold topics whose pages were gone, which its integrity pass then repaired (`:375-406`).
6. **A page limit** (50) and a 200 MB budget; legacy's design had neither in use.
7. **No images and no copied resources**: the parser and the app's caches handle them.

Recorded in [CHANGELOG-LEGACY](../CHANGELOG-LEGACY.md) row 47.

## Learnings

- A store that the system or an evictor may trim file by file keeps no index: every file says what it is, and the list is read from the files.
