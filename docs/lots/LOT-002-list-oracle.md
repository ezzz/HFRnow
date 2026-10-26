# LOT-002 — Oracle exporter: legacy list parsers to JSON

- **Module:** tooling (legacy app)
- **Difficulty / model:** medium (Sonnet → Fable)
- **Issue:** none (lot tracked in `docs/LOTS.md`; audit item B10 in [B](../audit/B-list-parsing-models.md))

Harness, patch and run instructions: [`tooling/legacy-oracle/`](../../tooling/legacy-oracle/README.md).
This lot covers the **list** parsers. Topic pages are LOT-003; forms, write responses and storage formats are LOT-004.

## Legacy sources
Legacy repository <https://github.com/francoisgn/hfrnow>, commit `2440d79`. All line numbers are `Classes/`.

| Kind | Parser entry point (what the loader workers call) | Source |
|---|---|---|
| `forums` | `-[ObjCForumsParser parseForumsFromData:]` | `ObjCForumsParser.m` (whole file), called from `ObjCForumsLoaderWorker.m:28` |
| `topics` | `-[ObjCTopicListParser parseData:currentURL:]` | `ObjCTopicListParser.m:59-470`, called from `ObjCForumTopicsLoaderWorker.m:163` |
| `mp` | same parser; the URL is `/forum1.php?config=hfr.inc&cat=prive&page=1` | `ObjCMPTopicsLoaderWorker.m:9` |
| `search` | the same parser on the results page; redirect step in `-forumSearchRedirectURLFromHTML:` and URL helpers | `ObjCForumSearchWorker.m:47`, `:242-257` (results), `:259-275` (page info), `:304-342` (redirect and URLs) |
| `favorites` | `-[ObjCFavoritesLoaderWorker parseFavoritesFromData:]`, which drives `-[Favorite parseNode:]` and `-addTopicWithNode:` | `ObjCFavoritesLoaderWorker.m:79-168`, `Favorite.m:31-210` |

Helpers the parsers depend on: `Topic -setATitle:` applies `-filterTU` (`Topic.m:90`, `Helpers/RangeOfCharacters.m:330`);
`-decodeSpanUrlFromString2` decodes `md_cryptlink` classes (`Helpers/RangeOfCharacters.m:116`).

Not covered here, on purpose: `MPStorage.m:692` (`findStorageMPFromPage:` re-parses the MP list inline to find the storage topic; LOT-004),
`ObjCTopicSearchWorker` (search inside a topic; LOT-003).

## Behaviour
The exporter feeds the HTML bytes to the parser exactly as the workers do (raw `NSData`, no re-encoding) and serializes what the
legacy model objects hold. `oracle-map.json` in the input folder maps each file to a kind and an optional `currentURL`.
Other map keys: `path` (page location relative to the map folder, so the oracle folder can point at the shared corpus instead of copying
it; `input.file` then holds that path) and `now` (ISO-8601, see below). Defaults when `currentURL` is absent: `topics` and `search` use `/forum1.php?config=hfr.inc&cat=13&page=1`, `mp` uses the MP URL above;
`forums` and `favorites` take no URL. Page numbers in the output depend on `currentURL` (`ObjCTopicListParser.m:88-110`), so a real capture
must record the URL it was fetched from.

### JSON schema (`schema` 1)
Keys are sorted; `null` means "nil in legacy" and is kept because nil and `""` differ in legacy.
The shapes below mirror the legacy objects field for field: the parser entry points are listed in **Legacy sources** above, and the fields come from the model classes `Topic` (`Classes/Topic.h`, setters in `Topic.m`), `Forum` (`Classes/Forum.h`), `Favorite` (`Classes/Favorite.h`, `Favorite.m:51-199`) and the list result built in `ObjCTopicListParser.m:95-110, 172-252, 378-447`. Each value is what those classes hold after parsing, serialized by the exporter (`OracleExport.swift` in `hfrnow.patch`).

Envelope, every kind:

| Key | Content |
|---|---|
| `schema`, `case`, `kind` | `1`, file name without `.html`, kind |
| `legacyCommit` | `HFR_ORACLE_LEGACY_COMMIT` (the script passes `2440d79`) |
| `input` | `file` (the map entry's `path` when given), `bytes`, `sha256`, `currentURL` (`null` for `forums` and `favorites`), `now` (`null` unless the entry has one) |
| `exception` | `"Name: reason"` when the parser raised, else `null`. The raise is part of the oracle (see quirks) |
| `result` | per kind below; `null` when `exception` is set |
| `sideEffects` | see next section |

`result` per kind:

| Kind | `result` |
|---|---|
| `forums` | array of forums `{aTitle, aURL, aID, subCats}`; `subCats` is `null` or an array of the same shape. `aID` is `""` (never set by this parser) |
| `topics`, `mp` | list object, below |
| `search` | either `{page: "redirect", redirectURL, absoluteURL, relativeURL}`, or a list object plus `page: "results"` and `pageInfo` (the dictionary `-forumSearchPageInfoWithResultCount:` builds; keys with empty values are absent) |
| `favorites` | `{favorites: [{forum: {aTitle, aURL, aID, subCats}, order, topics: [topic]}], topicsSortedByLastPostDesc: [{catID, postID, aTitle}]}`. `favorites` is what the worker returns (visible categories, sorted by `order`) |

List object (`ObjCTopicListParsingResult`): `currentUrl`, `currentCat`, `forumNewTopicUrl`, `forumBaseURL`, `forumFavorisURL`,
`forumFlag1URL`, `forumFlag0URL`, `firstPageUrl`, `lastPageUrl`, `nextPageUrl`, `previousPageUrl`, `sNewMPNumber` (strings or `null`);
`pageNumber`, `firstPageNumber`, `lastPageNumber` (ints); `needToUpdateMP` (bool); `statusInfo` (`null`, or `{status, statusName, message}` with
`statusName` in `maintenance`, `noResults`, `noAuth`); `topics` (array).

Topic: strings `aTitle`, `aURL`, `aURLOfFirstPage`, `aURLOfFlag`, `aTypeOfFlag` (`""`, `red`, `blue`, `yellow`), `aURLOfLastPost`,
`aURLOfLastPage`, `aAuthorOfLastPost`, `aAuthorOrInter`, `sLastSearchPostContent`, `sLastSearchPostURL`; ints `aRepCount`, `maxTopicPage`,
`curTopicPage`, `postID`, `catID`; bools `isViewed`, `isViewedFromForumAtLoad`, `isLocallyViewedInApp`, `isPoll`, `isSticky`, `isClosed`,
`isSuperFavorite`; `dDateOfLastPost` (UTC ISO-8601 or `null`); `aDateOfLastPost` and `aDateOfLastPostKind` (`absolute` or `relative`).
Legacy writes `aDateOfLastPost` as "il y a 5 min" / "il y a 2 h" for recent posts and `dd/MM/yy` otherwise (`ObjCTopicListParser.m:426-447`),
so the relative forms change with the run date: without `now` they are exported as `null` with kind `relative`. Use `dDateOfLastPost` for comparisons.

`now` (map key, ISO-8601) fixes the clock the parsers see: `+[NSDate date]` and `[[NSDate alloc] init]` (the form `ObjCTopicListParser.m:264` and
`Favorite.m:51` use) are replaced for the duration of the case. Real captures need it: a page captured on the day of the export has last-post dates
under 24 h old, so the same oracle would flip from "il y a 5 min" to `dd/MM/yy` the next day (found on the first real run: 50 of 55 rows of R04 are relative).
With `now`, the output is a function of the page and of that instant, so the relative strings are deterministic and are **exported as legacy wrote
them** (`aDateOfLastPost: "il y a 10 min"`, kind `relative`). Real cases use the capture's HTTP `Date` header (`<id>.meta.json`, `date`); `input.now`
records it (`null` when absent). The Swift port takes `now` as an input and must reproduce these strings or drop them on purpose.

### Side effects
Reset before every case, captured after it, in `sideEffects`:

| Key | Legacy write |
|---|---|
| `hashCheck` | `[HFRplusAppDelegate sharedAppDelegate].hash_check`: `ObjCForumsParser.m:42` (only when the `hash_check` input has a value), `ObjCFavoritesLoaderWorker.m:106` (always, `nil` when absent) |
| `nbMP` | `UserDefaults nb_mp`, set by `-updateMPBadgeWithString:` (`HFRplusAppDelegate.m:702`): from the home page `cat=prive` row (`ObjCForumsParser.m:516-525`) and the favorites page MP block (`ObjCFavoritesLoaderWorker.m:97-103`). `null` = never called. The topic list parser does not write it; it only reports `needToUpdateMP` / `sNewMPNumber` |
| `arrayCategoriesVisibleOrder`, `arrayCategoriesHiddenOrder` | `UserDefaults`, read as input and written back by the favorites parser (`ObjCFavoritesLoaderWorker.m:36-37,157-158`). Reset to empty, so a run behaves like a first launch (`order` follows page order) |
| `statusNotifications` | `kStatusChangedNotification` posted by the forums parser on a maintenance page (`ObjCForumsParser.m:20-26`) |

The SwiftUI app delegate adaptor is not an `HFRplusAppDelegate`, and `+sharedAppDelegate` is a bare cast (`HFRplusAppDelegate.m:430`), so the
exporter installs a real `HFRplusAppDelegate` as `UIApplication.delegate` for the run and restores the previous one.
`recherche_categorie` (`ObjCForumSearchWorker.m:28`) is written by the search entry, not by the parsing we export; the exporter saves and restores it.

## Edge cases
Legacy quirks observed on the synthetic samples (each is a sample file; `Q` numbers are for the review of the Swift port):

- Q1 `topics-page2`, `topics-page-last-spans`: the pager reads `.left` children by index, **text nodes included** (`ObjCTopicListParser.m:172-252`, children read at `:180-181,201`).
  Child 2 is the first page, the last child is the last page. A page that is the current one gets `currentUrl` as its URL
  (`lastPageUrl == currentUrl` on the last page).
- Q2 `topics-broken-pager`: fewer than 3 children raises `NSRangeException` (`exception` set, no result). In the app this is uncaught.
- Q3 `topics-single-page.html` with `currentURL=/forum-nodigit.php` (ad hoc run, not a sample): a `currentURL` without `page=` and without a digit
  raises `NSInvalidArgumentException` at `ObjCTopicListParser.m:102-103` (`substringWithRange` on `NSNotFound`; `Favorite.m:191-192` has the same pattern).
- Q4 `topics-bad-date`: an unparseable last-post date gives `dDateOfLastPost: null` and a **relative** display string, not an error
  (`timeIntervalSinceDate:nil`, `ObjCTopicListParser.m:421-447`).
- Q5 Pages without a charset declaration are decoded as Latin-1 by the HTML parser, which breaks `à` in the date format and so triggers Q4.
  The samples declare UTF-8. Real captures must be checked for the charset the live site sends.
- Q6 `Topic -setATitle:` rewrites "topic unique" (and 8 other spellings, case-insensitive) to `TU` before storing the title (`topics-page2`, row 102).
- Q7 Poll detection uses two different image URLs: `.../images/defaut/sondage.gif` in the topic list (`ObjCTopicListParser.m:331`) but
  `.../images_forum/1/sondage.gif` in favorites (`Favorite.m:70`, the comment above it shows the first URL). `favorites-multi-cat`, rows 402 and 403.
- Q8 Unread is `alt="On"` in `sujetCase1`; no image means read (`ObjCTopicListParser.m:378-390`). `isViewed` is also `true` for favorites rows without a flag link.
- Q9 `curTopicPage` is `0` when the row has no flag link; with a flag it is the `page` of the flag URL (`HFRTopicPageNumberFromURLString`, `:9-38`).
  Favorites compute it differently (`Favorite.m:182-199`, last digit of the URL when `page=` is absent).
- Q10 Early returns: a body without `id` gives `noAuth` (or `maintenance` when the first child is `<p>`) with most fields at their defaults
  (`forumBaseURL: null`, `forumNewTopicUrl: ""`, `currentCat: ""`); no rows gives `noResults` ("Aucun message") after the pager and filter fields are read.
  Favorites turns the same cases into a thrown `FavoritesLoadError` (`ObjCFavoritesLoaderWorker.m:87-95`).
- Q11 Home page: the `Apple` row is dropped unless `hash_check` has a value (`ObjCForumsParser.m:77-80`); the `cat=prive` row is not a forum, it only
  updates the MP badge; `AchatsVentes/Hardware` is rewritten (`:69`); `subCats[0]` repeats the parent; about 30 sub-forums are injected by URL
  (`:84-500`, samples: PHP gives Python and Ruby/Rails, minipc gives Bench). `aID` stays `""`.
- Q12 `subCats` is never `nil` in the export: forums without a `Tableau` link and the sub-forums themselves carry `[]` (the model initializes it), so `[]` does not mean "no sub-forums parsed".
- Q13 `forums-maintenance`: returns `[]` and posts a notification; a maintenance page is not an error for the parser.

Not exercised by the synthetic samples and still open after the real run: titles with entities and `&nbsp;`, `md_noclass_cryptlink` / `md_blank_cryptlink`
variants in list pages, replies counts with separators, a `sujetCase3` second link on a non-search page, an anonymous last author (`<b>` missing).

### Real-capture findings (`RC2.n`)
From the oracles on the LOT-001 corpus (see Fixtures). Each one contradicts or refines an assumption above.

- RC2.1 (Q1) **The pager is a window, not a range.** Real lists show pages 1..10, then jumps by tens (20, 30...), then by hundreds, around the current page
  (R04, R06: `Page : 1 2 ... 10 20 30 ...`). The parser's "last child" is the last *displayed* link, not the last page of the forum:
  R04 `lastPageNumber 500` on page 1, R05a (page 12) `400`, R05b (page 500) `700`. `lastPageUrl` is therefore not a page count; the Swift side must not
  present it as one (LOT-022). The index arithmetic of Q1 did not raise on any real page: the markup has the leading `<b>Page :</b>` and the text nodes the
  samples assumed. `firstPageUrl` is always page 1 (`.../liste_sujet-1.htm`), `previousPageUrl` is `""` on page 1.
- RC2.2 (Q1, Q9) **Pager links are obfuscated from the second page on**: R04 (page 1) has plain `<a class="cHeader">` links, R05a/R05b have `span.md_cryptlink...`
  except the current page and, on R05b, the links after it. The decoding of Q1 works on all of them (`previousPageUrl: /hfr/Discussions/liste_sujet-11.htm` on R05a).
- RC2.3 (Q7) **Polls are never detected in topic lists on the live theme.** The list parser matches `.../themes_static/images/defaut/sondage.gif` but the real
  icon is `.../themes_static/images_forum/1/sondage.gif` (14 on R04, 16 on R06, 3 on R27-list): `isPoll` is `false` on all 18 list oracles. Favorites matches the right
  URL (`Favorite.m:70`): R10 has one poll row. The Swift port should detect the real icon (a legacy bug fixed on purpose).
- RC2.4 (Q10) **Empty personal lists are `noAuth`, not `noResults`.** The body has no `id` on pages that only carry a `.hop` message, whatever the login state:
  R08-1 and R08-3 (logged in, `owntopic=1`/`3` empty) give `statusName: noAuth` with the page text as `message` ("Aucun sujet auquel vous avez participé n'est connu",
  "Aucun favori n'est repertorié"), and so does the empty search R50c ("Désolé, aucune réponse n'a été trouvée !"). `noResults` ("Aucun message") only appears for an
  empty MP list (R13c). `noAuth` therefore means "page without the list body"; the message tells the cases apart.
- RC2.5 (Q10) Favorites: R11 and P03e (logged in, no favorite) return an empty list without error, R12 (logged out, `forum1f.php`) throws
  `FavoritesLoadError: Aucun sujet que vous avez lu n'est connu`.
- RC2.6 **Pseudos keep their zero-width space.** `aAuthorOfLastPost` ends with U+200B on real rows (R05a, R05b, R13a). The anonymizer keeps it after the alias. Do not trim it
  in the model if the pseudo is later compared with the account's (LOT-003 Q20).
- RC2.7 **Search `currentURL`.** The results page of a search is `GET /forum1.php?recherches=1&cat=13&...&config=hfr.inc` (R50a gives it as meta-refresh target; the redirect
  extraction and both URL helpers return it unchanged). That URL has no `page=`, so the page number comes from the *last digit of the URL* (`ObjCTopicListParser.m:96-103`):
  `...&moderation=0` happens to give 0, hence page 1. A search URL ending in another digit would give another page number. The pager links of the results use another shape
  (`/forum1.php?config=hfr.inc&cat=13&page=2&...&search=PIZZA+NAPOLITAINE...`, upper-cased search words), so `nextPageUrl` and `lastPageUrl` are equal on a two-page result (R50b).
- RC2.8 (Q11) Home page: R01 (logged out) has 19 forums (no `Apple`), R02 and R03 (logged in, `hash_check` present) 20; 184 and 192 sub-forums after the injection. The MP badge
  is written only when the row shows a count: R02 `nbMP: 10` (10 unread conversations), R03 `nbMP: 0`. `hashCheck` is the corpus placeholder `REDACTED`
  (the anonymizer replaces the real 32-hex token), `null` logged out.
- RC2.9 **The MP block on a topic list without unread messages**: `needToUpdateMP` is `true` with `sNewMPNumber: "\u00a0Messages privés"` (R08-2, user2, no unread MP): the regex
  that extracts the count finds no digit and leaves the whole cell text (`ObjCTopicListParser.m:85-92`). With one unread MP (P03f) it is `"1"`. The list parser does not write
  `nbMP` (stays `null` in list cases).
- RC2.10 **Relative dates are the rule on a fresh capture** (see `now` above): R04 has 50 relative rows out of 55, R50b 29 of 50. The date parser worked on every row of every
  real page (`dDateOfLastPost` never `null`), so Q4/Q5 did not occur: the live site sends `Content-Type: text/html; charset=utf-8`.
- RC2.11 Row shape: `catID` and `postID` are `0` on topic-list rows (set by favorites only), `curTopicPage` is `0` without a flag link and the page of the flag URL with one
  (R08-2: 2, flag `red`, `#t<post>` anchor in `aURLOfFlag`), and MP rows carry `aAuthorOrInter: "Interlocuteurs multiples"` for group threads (R13u1) and the
  correspondent's alias otherwise (R13a).

## Fixtures
Synthetic, in `tooling/legacy-oracle/samples/` (fake pseudos `fakeuser1`..`fakeuser3`, fake hash `FAKEHASH0123456789`, no real data):

| File | Kind | Covers |
|---|---|---|
| `forums-loggedout`, `forums-loggedin`, `forums-maintenance` | forums | Apple censoring, MP row and badge, hash_check, sub-forum injection, URL rewrite, maintenance notification |
| `topics-page2`, `topics-page-last-spans`, `topics-single-page`, `topics-empty` | topics | pager with links and with `md_cryptlink` spans, sticky, closed, unread, poll, three flag colors, 12-page topic, 1234 replies, future date, TU rewrite, no pager, no rows |
| `topics-noauth`, `topics-maintenance`, `topics-broken-pager`, `topics-bad-date` | topics | status paths, raised exception (Q2), unparseable date (Q4) |
| `mp-list` | mp | MP block (`needToUpdateMP`, `sNewMPNumber`), `[non lu]`, multi-interlocutor author |
| `search-redirect`, `search-results` | search | meta refresh extraction and URL helpers; snippet (`s1`) and second link |
| `favorites-multi-cat`, `favorites-empty`, `favorites-noauth` | favorites | categories and order, flag link or not, polls (Q7), sticky, closed, empty category, thrown error |

Real captures (LOT-001 corpus, `Packages/HFRKit/Tests/HFRParsingTests/Fixtures/captures/`, anonymized): 27 oracles in `Fixtures/LOT-002/`, computed in place
(the map's `path` points at `../captures/<file>`; `currentURL` is the capture's `final_url`, `now` its HTTP date). `oracle-map.json` there is the only input.
Re-run: `tooling/legacy-oracle/run-oracle.sh -i Packages/HFRKit/Tests/HFRParsingTests/Fixtures/LOT-002 -o Packages/HFRKit/Tests/HFRParsingTests/Fixtures/LOT-002`.

| Kind | Cases (corpus ids) |
|---|---|
| `forums` | R01 (anon), R02 (user1, unread MP), R03 (user2) |
| `topics` | R04, R05a, R05b, R06, R07, R09, R27-list (public lists, anon); R08-1, R08-2, R08-3, P03f (`owntopic` lists, user2) |
| `favorites` | R10, R11, P03c, P03e (user2); R12 (anon) |
| `mp` | R13a, R13b, R13c (user2); R13u1, R13u1b (user1) |
| `search` | R50a (waiting page, redirect, user2); R50b, R50c (results, anon) |

`errors.json` is empty. The only legacy throw is R12 (data: `exception` set, `result` `null`). Not run: REST answers (R57, LOT-057), smiley search (R53, LOT-025) and `transsearch` (R52).

## Intentional differences from legacy
The exporter keeps parser behaviour as it is, except for the three reproducibility changes listed below. The Swift port documents its own differences against the quirks above (B §5 decisions:
no side effects, typed errors instead of `statusInfo` and exceptions, no display strings).
The exporter itself departs from legacy output in three places, all to make the files reproducible: relative date strings are dropped for cases without `now` (with `now`, the clock is frozen
at the capture date and they are exported as legacy wrote them; see schema), dates are ISO-8601 UTC, and the app delegate is replaced by a real `HFRplusAppDelegate` for the run.

## Learnings
To copy into AGENTS.md §11 when the lot closes:

- Xcode 27 cannot build Carthage dependencies with their own settings: pass `tooling/legacy-oracle/carthage-xcode27.xcconfig` through `XCODE_XCCONFIG_FILE`.
- `xcodebuild` forwards environment variables to the simulator test process only with the `TEST_RUNNER_` prefix.
- Legacy parsers raise `NSException` on malformed pages; Swift cannot catch it, so the oracle goes through an Objective-C `@try` helper and records the raise as data.
- HTML pages given to the legacy parser need a charset declaration, or accented characters are read as Latin-1 (Q5).
