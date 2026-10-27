# LOT-024 — Favourites page parser

- **Module:** HFRParsing (one minimal HFRModels addition, see Behaviour)
- **Difficulty / model:** medium (Sonnet → Opus)
- **Issue:** none (lot tracked in `docs/LOTS.md`); old issue `francoisgn/ios-app_SwiftHFR#64` (read-only history)

## Legacy sources
Legacy repository <https://github.com/francoisgn/hfrnow>, `master` (the file paths are those of commit `2440d79`).

| Legacy | Replaced by |
|---|---|
| `Classes/ObjCFavoritesLoaderWorker.m:74-139` (`-parseFavoritesFromData:`): not-logged-in `:82-90`, MP badge `:92-98`, `hash_check` `:100-101`, section and row walk `:103-130`, sorting `:132-136`, `:141-151` | `FavoritesParser.parse` |
| `Classes/Favorite.m:31-47` (`-parseNode:`, category header) | `FavoritesParser.header(of:)` |
| `Classes/Favorite.m:49-210` (`-addTopicWithNode:`, topic row) | `TopicListRowParser.summary` (LOT-022) then `FavoritesParser.resuming` |
| `Classes/ObjCFavoritesLoaderWorker.m:37-51` (request: `forum1f.php?owntopic={1,3}`) | the fetcher (LOT-045), not this parser |

## Behaviour
`FavoritesParser.parse(_ html: String) throws(ListPageFailure) -> FavoritesPage`. Pure: no side effects, no clock, no display strings.

Reuse: page status, the MP badge, the unreadable-rows check, the page body and each row are `TopicListParser.parseRows` (LOT-022)
(one parse of the page: the section walk reads the rows of its `ParsedTopicList`, whose `body` field is new), because `forum1f.php` serves the topic list markup (`<body id="category__topics_listing__listing_topic">`,
`tr.sujet.ligne_booleen`, cells `sujetCase1`-`sujetCase10`, R10).

| Output | Rule (source) |
|---|---|
| status | a bare `<body>` whose first element is `<p>` throws `.maintenance` (legacy `:82-90`, not captured); a `.hop` page is an empty `FavoritesPage` carrying `notice` = HFR's message (R12, LOT-022's rule): a login wall and an empty `owntopic=1` list may be the same page (R08-1 is that shape on a logged-in list), so the caller decides from its session. An account without favourite on `owntopic=3` gets the list body with no row (R11, P03e), no notice; neither list nor message: `.malformed` (R20) |
| `sections` | one per `tr.fondForum1fCat` of the first `table.main`, in page order, with the `tr` rows that follow it (legacy `:103-130`). Title and `path` from the header's `a.cHeader` (`Favorite.m:33-45`); `categoryID` from its `cat=`. A header without a usable link leaves its rows unplaced: any readable row not placed under a readable header throws `.malformed` (LESSONS 44), never a partial list (legacy crashed at `Favorite.m:35`) |
| `topics` | each row as `TopicListRowParser.summary`, then: `firstPagePath` = the title link, `path` = the resume path (flag link, else last post link; `Favorite.m:101-102, 163-178`), `currentPage` = `page=` of that path (`:181-199`), `readState` = `.unknown` |
| `unreadPrivateMessages` | `TopicListParser.unreadPrivateMessages` (legacy `:92-98`; R10 0, P03c 1) |
| `hashCheck` | first non-empty `hash_check` field (`:100-101`), same rule as `ForumListParser`. A secret: kept out of `description`, `debugDescription` and reflection |
| `topicsByLastPost` (computed) | all topics, last post date descending, undated last, page order on ties (legacy `:132-136`, `topicsSortedByLastPostDesc` in the oracle) |

**Model change (minimal):** `FavoritesPage` (HFRModels/Lists) holds `sections: [FavoriteSection]`, the badge, the token and `notice`. `FavoriteSection`
and `TopicSummary.firstPagePath` already existed (LOT-010); the doc comments of `TopicSummary.path` and `firstPagePath` now say what a favourites
row holds. `ForumListParser.hashCheck(in:)` became internal to be shared; `ParsedTopicList` (internal) gained `body`.

Rows pass through LOT-022's `HFRURL.forumRelativePath` (links to another host or scheme are dropped, LESSONS 37, 43). A flag link that is dropped
makes the row resume at its last post.

## Edge cases
- Non-regression (`docs/LOTS.md`, issues to open #1): a link without `href` must not break the parser. The favourites page has no pager; the
  equivalent is the last-page link of a row, tested without `href` (row kept, one page). A header link without `href` is tested too.
- The oracle's `isViewed` is true only for a row with no flag link; every captured row has one.
- Flag colour differs by page: `flag1.gif` (blue) on `owntopic=1` (R10), `favoris.gif` (yellow) on `owntopic=3` (P03c).
- An empty favourites list is a list page (R11, P03e), not a failure: `sections` is empty.

## Fixtures
Captures in `Packages/HFRKit/Tests/HFRParsingTests/Fixtures/captures/`; oracles in `Fixtures/LOT-002/` (`oracle-map.json`, kind `favorites`).

| Capture | Covers |
|---|---|
| R10 | `owntopic=1`, one category, two flagged topics (thousands of pages, `#t` anchors), badge 0 |
| P03c | `owntopic=3`, one favourite, yellow flag, badge 1 |
| R11, P03e | `owntopic=3`, no favourite: list body, no row |
| R12 | logged out: `.hop` "Aucun sujet que vous avez lu n'est connu", legacy raised `FavoritesLoadError`; here an empty page with `notice` |

**Oracle coverage:** the 4 parsed `favorites` cases are compared field by field (`FavoritesDifferentialTests`, guarded by a test that the case
list equals the map's `favorites` list, R12 included); R12's legacy exception and the port's `notice` are asserted. Display-only and session fields are not compared (`aDateOfLastPost`,
`isLocallyViewedInApp`, `isSuperFavorite`, `isViewedFromForumAtLoad`, category order preferences, notifications). `FavoritesDifferentialTests` is
in `FavoritesParserTests.swift`; the mutations of captures there (last-page link without `href`, foreign flag link, header without link, a second header inserted before R10's second row, the same header without link) are the
only derived pages and are built by replacing or inserting one element in a capture.

**Pending capture** (no page is hand-built, the derived ones are listed above; `captures/MANIFEST.md` says R10 has "two categories"; the capture has one category with two topics (the MANIFEST is the capture owner's file, left as is)):
- favourites spanning two or more categories (section order, grouping, the second header);
- a favourites row without flag link (resume at the last post, legacy `isViewed`), a single-page topic, a sticky, closed or poll topic;
- `forum1f.php?owntopic=1` logged in with no flagged topic: either the list body (as R11 for `owntopic=3`) or a `.hop` page. The parser returns an empty
  page either way (with a `notice` for `.hop`); the capture settles what HFRClient may assume (logged out vs empty);
- the maintenance page (shared with LOT-022).

## Intentional differences from legacy
Each is asserted by the differential tests against the oracle or independent evidence (regexes over the raw capture).

| # | Legacy | Port | Why |
|---|---|---|---|
| D1 | `isViewed` = true when the row has no flag link | `readState` = `.unknown` | LOT-010 decision: favourites rows carry no read information |
| D2 | `aURLOfFlag`, `aTypeOfFlag` left empty | `flagPath` and `flag` (blue, red, yellow) set from the flag cell | the page states them; `path` keeps legacy's resume rule |
| D3 | `aAuthorOrInter` left empty | `starterOrInterlocutors` read | the page has the starter (R10, P03c) |
| D4 | `filterTU` rewrites the title | raw title | presentation concern (LOT-022 D4) |
| D5 | `.hop` or non-list body: exception with the message | `.hop` → empty page with `notice` (LOT-022 D1); `.maintenance`, `.malformed` thrown | typed failures (audit B §5); a `.hop` cannot be told from an empty list without the session |
| D6 | `hash_check` and the MP badge pushed into the app delegate | returned in `FavoritesPage` | pure parser; `HFRClient` refreshes the session |
| D7 | a row with a missing node raised and lost the page | the row is skipped (LOT-022 D11); a header without link throws `.malformed` | a malformed row must not hide the list, a lost section must not look like a shorter one |
| D8 | `catID`/`postID` from hidden inputs `valuecat`/`topic` | `topicID` from row links (`cat=`, `post=`) | same values on every capture; no dependence on the logged-in checkbox cell |
| D9 | links copied as is | forum paths only | LESSONS 37, 43 |
| D10 | relative date label | none | LOT-022 D12 |

## Learnings
To copy into AGENTS.md §11 when the lot closes:

- SwiftSoup `Element.ownerDocument()` is nil on elements of a document kept only through its rows: keep the `Document` or `body`, and never mix elements of two parses of the same page.
