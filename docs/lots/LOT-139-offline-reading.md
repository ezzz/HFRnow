# LOT-139 — Offline reading (app)

- **Module:** App
- **Difficulty / model:** medium (Sonnet → Opus; written by a Sonnet 5.5 Mac session, reviewed by another model)
- **Issue:** [#229](https://github.com/ezzz/HFRnow/issues/229)
- **Depends on:** LOT-068 (#93): `OfflineTopicStore`, merged in #479; LOT-083 (#101): the reader.
- **Implements:** GAP-180 (class `a`), Q-5. Inputs from LOT-068's reviews: [the #229 comment](https://github.com/ezzz/HFRnow/issues/229).

## Legacy sources

Legacy repository <https://github.com/ezzz/HFRnow> at `2440d79` (an ancestor of `origin/master`). **Legacy had no offline reading in use** (see LOT-068): the download is commented out (`Classes/OfflineStorage.m:145-294`) and no screen lists the saved topics.

| Legacy @ 2440d79 | What it gives this lot |
|---|---|
| `Classes/OfflineStorage.m:41-82`, `:88-143` | the set of offline topics and its archive: what the list shows (title, pages); LOT-068 replaced the storage |
| `OfflineStorage.m:145-294` (commented out) | the intended download: the current page and the following ones, up to `offline_max_pages` (a key nothing writes), the topic's last page fetched again |
| `Classes/OfflineMessagesTableViewController.m:1787-1844` | **not an offline screen**: a copy of the messages controller that opens a followed link in a nested reader (`isViewed`); it never reads `OfflineStorage` |
| `Classes/PageViewController.m:39-41`, `:149-154` | `isModeOffline` and `updateOfflineTopic:`, run only when `currentOfflineTopic` is set, which nothing does |
| `HFRswift/Wrapped/MessagesTableViewController.m:996` | sets `currentOfflineTopic` in an initializer with no caller |
| `Classes/OfflineStorage.m:430-437` | `getDataFromTopicOffline:page:`, the read of a saved page's bytes (`<post>/<post>-<page>/index.html`); no caller. `HFRswift/Swift/Common.swift:1962-1976` (`OfflineStorageTopicPageRenderer`) is **not** a read of saved pages: it writes rendered HTML to a temporary cache file |

## Legacy counterpart (app lots)

| SwiftHFR | Legacy @ 2440d79 |
|---|---|
| `Offline/OfflinePageSource.swift` (`OfflinePageSource`) | `Classes/OfflineStorage.m (getDataFromTopicOffline)` `:430`, no caller |
| `Offline/OfflineSaveModel.swift` (`OfflineSaveModel`) | `Classes/OfflineStorage.m` commented-out download `:145-294` |
| `Offline/OfflinePageFetching.swift` (`LiveOfflinePageFetcher`) | same download, fetch side |
| `Offline/OfflineTopicsModel.swift`, `Offline/OfflineTopicsView.swift` | none @ 2440d79 (no list in legacy) |
| `Offline/ReaderOfflineSave.swift` | none @ 2440d79 (the toggle `OfflineStorage.toggleOfflineTopics:` has no caller) |

## UX evolutions (app lots)

Legacy has no offline screen, so the entry points are this lot's choice. The GAP row (GAP-180, class `a`) says only "Save, list and evict offline pages"; no UXD row covers it. The operator confirms the choices below in the PR.

| What | Choice | Class |
|---|---|---|
| Where the list lives | Réglages, section "Hors ligne", row "Sujets enregistrés" (Maintenance, GAP-152, is LOT-120's and does not exist yet) | `a` (the row's place, GAP-180) |
| How to save | A "…" menu entry in the reader: "Enregistrer cette page hors ligne" and "Enregistrer cette page et les 4 suivantes" (5 pages in all, `ReaderOfflineSave.pagesInBatch`; legacy's `offline_max_pages` was never written) | `a` |
| Size on disk | In the list ("Espace utilisé"); LOT-120's Maintenance reads the same `CacheDirectory.size(of: .offlineTopics)` | `a` |
| Open a saved topic | A read-only reader, on its first saved page, with no composer and no save menu | `a` |

## Behaviour

Code in `App/SwiftHFR/Offline/`, on LOT-068's `OfflineTopicStore` (the saved pages, the 50-page and 200 MB limits, the refusal of a page that holds a session token); nothing in HFRKit changes.

### Saving

- **Always cookie-less.** `LiveOfflinePageFetcher` asks `PageFetcher.topicPage(…, as: .anonymous)` for every page, **the page on screen included**: the reader keeps the parsed page, not the HTML, and the session's copy carries the account's `hash_check` which the store refuses (`R21`). So the flags never move (HFR-PROTOCOL §7 E25, LOT-045). This is stricter than the issue's "pages other than the current one".
- Pages are saved one after the other, from the page on screen up to `min(current + 4, last)`. A failure (network, a page that is not a topic page, a refusal of the store) stops the run; what was saved stays.
- **Only a topic page is handed to the store.** The page is parsed (`LiveTopicPageSource.parse`) and must hold a message: a maintenance page or a login form (`W00`) would otherwise be kept as the topic's page.
- **The page number is the one HFR served**, read from the canonical URL (`R24`: page 2202 asked, 2201 served). A URL that is not canonical is `unreadable`.
- **The refusal reason is shown** (LOT-068 leftover 2): `containsSessionToken` reads "Page non enregistrable : elle contient des données de session." instead of failing silently. A member who posts the text `codehex=x` makes that page unsavable for everyone: the check fails closed by design.
- **Off the main actor** (leftover 1). `LiveOfflineStore` is `@concurrent`: `save` decodes the whole page's character references (89–170 ms a captured page in LOT-068's Linux debug build, about 0.9 s for 100,000 references), and `topics()` decodes one page per topic. A test calls the store from the main actor and checks it ran elsewhere. **Release-build figure:** a whole `save` (decode, check, encode, atomic write) of the captured pages `R20`, `R22a`, `R28` (101–143 KB) takes 30–41 ms each in a release build on the maintainer's Mac (Apple silicon, macOS host, average of 20 saves, 2026-11-06); that is two to three frames of a 60 Hz screen (16.7 ms) if it ran on the main actor, and more in a debug build, hence the off-main rule.
- The member can stop a run ("Arrêter l'enregistrement"): the page being saved finishes, the rest is not fetched.
- Saving a page again replaces it (the last page of a topic grows). **No automatic re-save on refresh**: the reader does not keep the page's HTML, and a silent write on each refresh is a surprise; the menu does it on demand. Legacy's design re-fetched the last page (`OfflineStorage.m:145-294`).
- A private conversation cannot be saved (menu hidden, `invalidTopic` in the store).

### Reading

- `OfflinePageSource` is a `TopicPageSource`: the saved HTML goes through the same parsers as a live page (`LiveTopicPageSource.parse`), so a parser fix also applies to pages saved earlier. The page URL given to the parser is the `forum2.php` URL of the topic and page (`HFREndpoint.topicPage`), which gives the page number; the category slug of the canonical URL is not saved (**pending**: share links of an offline page are the `forum2.php` ones).
- Navigation inside the topic (page bar, swipe, "Aller à la page", links to the same topic) works on saved pages; a page not saved is "Page non enregistrée" and the page on screen stays (`ListLoadError.notSaved`). A link naming a message (`numreponse`, R25) is not saved: HFR picks the page, and there is nobody to ask.
- No reading position is recorded and no reply is offered (`positions = nil`, no composer); the images are not saved (LOT-068), so the reader shows its usual placeholders without network.
- **List**: title, "pages 4 à 8" or "3 pages", relative save date; swipe "Supprimer", "Tout supprimer" with a confirmation, and the size on disk. Order: most recently saved first, then forum number, then topic number (LOT-068 leftover 4: the store's own tie-break ignores the forum, so two topics saved at the same instant could swap places between two reads; `OfflineTopicsModel.displayOrder`).
- **Eviction.** The 200 MB budget of LOT-068 had no caller in the app: `LiveOfflineStore.evict()` (`CacheDirectory.evictAll`, off the main actor) runs at launch (`SwiftHFRApp`, a `.utility` task) and after every save run, whatever its outcome. Tested: the model calls it after a finished and after a failed run (`EvictionSpy`); the launch call is a Mac check. The policy itself is LOT-066's and is tested there.
- **A run follows its topic.** The save button starts a run that `OfflineSaveModel` holds. `TopicReaderView.onDisappear`, which already ignores a pushed linked reader and the image viewer, calls `leave()`: the run stops after the page in progress and keeps what was saved. Nothing else starts a run, so a finished or stopped batch never restarts when the member comes back (a `.task(id:)` did, measured on a probe: SwiftUI restarts the task of an id when the view reappears). Tested: `leavingStopsARunAndNothingButTheButtonStartsOne`.
- Everything the member reads is French; the list is empty with an explanation until a topic is saved.

## Edge cases

- Saving on the last page: "Enregistrer cette page et les 4 suivantes" is shown disabled; "Enregistrer cette page" works.
- A saved page the system evicted: "Page non enregistrée"; a damaged or other-version file: "Page enregistrée illisible", with the instruction to delete the topic from the list (`ListLoadError.savedPageUnreadable`).
- The same topic saved by two accounts is one entry: the pages carry no session.
- Over-broad guard (leftover 3: `name=a&amp;b` inside the `title` of an unrelated input refuses the page): left as it is, conservative and never a bypass. If false refusals show up, anchor the guard to the input's own `name=` (`OfflinePageRecord.swift:77`); the refusal message now makes them visible.

## Fixtures

Captures of the LOT-001 corpus, read in place: `R20`, `R22a` (topic pages without cookies), `R21` (with the session: refused, with its reason), `R24` (a page past the end, served as the last), `W00` (a page without any message). No new capture.

## Tests

`App/SwiftHFRTests/Offline/`:
- `OfflineSaveTests`: pages fetched without the session transport; a login form never handed on; the served page number files the page; a failure mid-run keeps the earlier pages; the logged-in capture is refused with its reason and nothing is written; a finished run's text; a stopped run; the store runs off the main thread; a page served as N-1 is filed as N-1; a page of another topic is never handed on; the batch stops at the last page and the title falls back; eviction after each run; `leave()` stops a run and nothing restarts it.
- `OfflineReadingTests`: a saved page reads like the live page of the same HTML; the saved page number is shown; a page never saved, a `numreponse` link and a damaged file; the reader moves between saved pages and says which is missing; the list loads, shows the size and deletes; the order of equal dates; page-count wording; delete all; a failed deletion keeps its reason through the reload; a damaged page asks to be deleted; a private conversation is not saved.

Shown to fail with the behaviour removed (six mutations applied together, seven tests failed, then reverted): session fetch instead of cookie-less (`pagesAreFetchedWithoutTheSessionWhateverThePage`, `theServedPageNumberFilesThePage`), no check that the page holds a message (`aPageThatIsNotATopicPageIsNeverHandedOn`), `numreponse` links read as pages (`aPageNeverSavedAndAMessageLinkAreNotSaved`), the store on the main actor (`theStoreRunsOffTheMainThread`), no forum in the order (`theListOrdersEqualDatesByForumThenTopic`), the refusal reason replaced (`aPageFetchedWithTheSessionIsRefusedWithItsReason`).

Round 1 and 2 tests, shown to fail the same way (seven mutations applied together, seven tests failed, then reverted): the page filed under the number asked (`theServedPageNumberIsTheOneSavedNotTheOneAsked`), no topic check on the served page (`aPageOfAnotherTopicIsNeverHandedOn`), no eviction after a run (`theBudgetIsAppliedAfterEachRun`), `leave()` doing nothing (`leavingStopsARunAndNothingButTheButtonStartsOne`), a fixed batch of five (`theBatchStopsAtTheLastPageAndTheTitleFallsBack`), the deletion reason wiped by the reload (`aFailedDeletionKeepsItsReasonThroughTheReload`), `invalidTopic` read as unreadable (`aPrivateConversationIsNotSaved`).

## Pending capture

- **A member-only forum fetched without cookies.** How HFR answers it is not captured and not guessed. The fetch is then refused as "not a topic page" (nothing is stored) and the member sees "Page illisible"; a capture would tell whether a clearer message is possible. To be opened as a `host: mac` capture issue by the lead.
- None other from HFR.

## Mac check needed

On a device or simulator: save a page and four more from a real topic (logged out and logged in: the topic's flag must not move); airplane mode; open from Réglages > Hors ligne; swipe pages; delete one and all; light, dark, Dynamic Type XL; iPad.

## Intentional differences from legacy

1. The save and the list exist (legacy's were commented out or unreachable); recorded in [CHANGELOG-LEGACY](../CHANGELOG-LEGACY.md) row 83.
2. Every page is fetched without cookies, the current one included.
3. A page that is not a topic page is never saved.

## Learnings

- A save that stores the page the reader just parsed would store the session's copy; fetch again without cookies and let the store refuse the rest.
