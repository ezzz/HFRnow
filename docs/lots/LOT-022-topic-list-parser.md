# LOT-022 — Topic list parser (forum lists, MP list, search results)

- **Module:** HFRParsing (one minimal HFRModels addition, see Behaviour)
- **Difficulty / model:** difficult (Opus → Fable)
- **Issue:** none (lot tracked in `docs/LOTS.md`; audit item B5 in [B](../audit/B-list-parsing-models.md))

## Legacy sources
Legacy repository <https://github.com/francoisgn/hfrnow>, commit `2440d79`.

| Legacy | Replaced by |
|---|---|
| `Classes/ObjCTopicListParser.m:59-470` (`-parseData:currentURL:`): status `:67-81`, MP block `:83-92`, page number `:94-114`, category `:116-131`, new-topic link `:133-135`, tabs `:139-168`, pager `:172-252`, rows `:254-467` | `TopicListParser`, `TopicListPager`, `TopicListRowParser` |
| `Classes/ObjCTopicListParser.m:9-38` (`HFRTopicPageNumberFromURLString`) | `HFRURL.page(in:)` (LOT-020) |
| `SuperHFRplus/Helpers/RangeOfCharacters.m:116-138` (`decodeSpanUrlFromString2`) | `ObfuscatedURL.decode(classAttribute:)` (LOT-020) |
| `SuperHFRplus/Helpers/RangeOfCharacters.m:330-343` (`filterTU`, via `Topic.m:90-94`) | not ported (presentation; a test-only copy feeds the differential tests) |
| Callers: `ObjCForumTopicsLoaderWorker.m:163`, `ObjCMPTopicsLoaderWorker.m:9`, `ObjCForumSearchWorker.m:242-257` | the app / `HFRClient` call `TopicListParser.parse` |

## Behaviour
`TopicListParser.parse(_ html: String, pageURL: String) throws(ListPageFailure) -> TopicListPage`. Pure: no side effects, no clock,
no display strings. `pageURL` is the URL the page was served from (LOT-045 final URL), absolute or forum-relative.

Page:

| Output | Rule (source) |
|---|---|
| status | a list page has `<body id="<section>__topics_listing__<kind>">` (R04, R13a, R50b); any other body is not a list: first element `<p>` → throws `.maintenance(<p> own text)` (`:70-73`, not captured); a `.hop` block → on the MP list URL (`cat=prive`) throws `.notAuthenticated(message)`, since an empty MP list keeps the list body (R13c); elsewhere an empty page whose `notice` is the block's own text (`:75-76`; R08-1, R08-3, R50c). For forum filters and search the parser cannot tell an empty result from a login wall (a `.hop` page has no header): callers treat `notice != nil` as "no list"; LOT-023/047 own the MP and session side. Neither → throws `.malformed` (R53a, and the topic page R20 and reply form R40a, whose body ids differ). A `topics_listing` body is a list, rows or not; if it has rows and none is readable, throws `.malformed("<n> rows, none readable")` |
| `navigation` | `TopicListPager`: in the `fondForum1PagesHaut` row, `div.left` children whose text is a page number are the pager entries: the `<b>` one is `current`, the first and last are `first`/`last`, their paths decoded from `md_cryptlink` classes or taken from `href`, and the current page's entry links to `pageURL`. `div.pagepresuiv` ×2 → `nextPath`, `previousPath` (disabled `span.cFondu` → nil). No pager: `current` from `pageURL` (`page=N`, else `liste_sujet-N.htm`), else 1. Legacy `ObjCTopicListParser.m:94-114, 172-252`; R04, R05a, R05b, R13u1, R50b; tests `pagerWindow`, `currentPageFromThePager`, `searchPageNumber` and the differential tests |
| `tabs` | first `div.cadreonglet`: `#onglet1` all, `#onglet2` favourites, `#onglet3` blue flag (`owntopic=1`), `#onglet4` red flag (`owntopic=2`). Legacy `:139-168`; R08-2, P03f (logged in), absent on R04, R13a; test `tabs` |
| `categoryID` | `cat=` of `#onglet9` in the tabs (legacy), else `form#fastsearch input[name=cat]`. Legacy `:116-131`; R08-2, P03f (tab), R04, R07, R27-list, R13a, R50b (form); differential tests (D2), `privateMessageRows` |
| `newTopicPath` | `#md_btn_new_topic` `href`. Legacy `:133-135`; R04, R06 (`message.php` form), R13a; differential tests, `tabs` |
| `unreadPrivateMessages` | first `.none` element with exactly 3 `td`: first integer of the middle cell, 0 when it has none; otherwise nil. Legacy `:83-92`; P03f (1), R08-2 (0), R04, R13a (nil); test `unreadPrivateMessages`, differential tests (D6) |
| `notice` (**new field**) | message of a `.hop` page (its own text), else nil. Legacy `:75-76`; R08-1, R08-3, R50c; tests `messagePage`, `emptyPrivateMessageList`, differential tests (D1) |

Rows: every `tr` with class tokens `sujet` and `ligne_booleen`, cells by class token (`TopicListRowParser`):

| `TopicSummary` | Rule |
|---|---|
| `path` | first `a` of `sujetCase3`; a row without a forum path there is **skipped** (all rows skipped → `.malformed`) |
| `title` | text of `sujetCase3` trimmed (keeps the MP `[non lu]` marker); on search rows (`.s1` present) the `.cCatTopic` link only. Raw: no "TU" rewrite |
| `searchHit` | rows with `.s1`: second `a` of `sujetCase3` + `.s1` text trimmed |
| `repliesCount` | first integer of `sujetCase7`, else 0 |
| `pageCount`, `lastPagePath` | `sujetCase4 a`: integer text and `href`; no link, or a refused `href` → 1 and `path` |
| `lastPost` | first child of `sujetCase9` when it is a link: `href`, `<b>` text as author (kept raw), date = `HFRDate.firstDate` of the link's own text |
| `starterOrInterlocutors` | `sujetCase6`: first `a` text, else first `span` text ("Interlocuteurs multiples"), else the cell text |
| `flag`, `flagPath`, `currentPage` | `sujetCase5 a`: image `flag0.gif` red, `flag1.gif` blue, `favoris.gif` yellow; `href`; `HFRURL.page` of the `href` |
| `readState` | `sujetCase1` image `alt="On"` → `.unread`, otherwise `.read` |
| `isSticky`, `isClosed`, `isPoll` | class token `ligne_sticky`; `img[alt=closed]` in `sujetCase3`; any row image whose file name is `sondage.gif` |
| `topicID` | first row link with `cat=` and `post=` (title, last page, last post, flag, search hit); else the canonical title path's topic with the category of its first segment (`ForumCatalogue`), else of the page |

Every emitted path goes through `HFRURL.forumRelativePath`: a single-`/` path is kept, anything else must resolve to `https://forum.hardware.fr`
(port 443 or none, no user info) and is reduced to its path, which must not start with `//` either; `javascript:`, other hosts, `//host`, `/\host`, `http://…:80/` give nil (LESSONS 37).
Text keeps whitespace as written (`Element.rawText`, legacy `allContents`); trimming removes Unicode `White_Space` only, so the U+200B HFR puts in long
pseudos survives (Foundation's `whitespacesAndNewlines` strips it on Linux).

**Model change (minimal):** `TopicListPage.notice: String?`. Without it a `.hop` page is either an error (legacy said "not authenticated") or an empty
list without its explanation; LOT-010 decision 6 reserved the field for when the UI needs the message, and empty favourites/filters/searches do.

**Extension points (internal, same module) for LOT-023 and LOT-024:** `TopicListParser.parseRows` returns `ParsedTopicList`, the page plus each row's
`Element` next to its `TopicSummary`, so the MP parser can read `span.red[title]` (`[non lu]`), `closedbp.gif`, the ignore-list cell, and turn the title
marker into a typed flag. `TopicListRowParser.summary(from:pageCategory:)` parses any `ligne_booleen` row, for the favourites parser to reuse and then
override (`readState: .unknown`, `firstPagePath`, flag-or-last-post `path`). `TopicListParser.unreadPrivateMessages(in:)` is the header half of
LOT-023's unified badge parser.

Measured (release, Linux x86-64, R04 with 55 rows): about 40 ms per page, 15 ms of which is SwiftSoup building the document. Two changes came from
the measure: a row's cells are indexed in one walk (one lookup per cell cost 0.6 ms per row), and `Element.firstDescendant` (LOT-020) now stops at
the first match instead of materializing the subtree (5 ms per whole-body search).

## Edge cases
- The pager is a window (1-10, then tens, hundreds): `last` is the last **linked** page, not the forum's page count (R04: 500 on page 1; R05b: 700 on page 500).
- Pager entries are obfuscated from page 2 on, except the current page and, on R05b, the pages after it (plain `a.cHeader`).
- Anonymous pages mark every row unread (`closedb_new.gif`, `alt="On"`) and print the starter as plain text; read state means something only logged in.
- MP list: own unread = `closedbp.gif` `alt="On"`, read = `closedp.gif` `alt="Off"`; `[non lu]` (the other party has not read) stays in the title.
- Search results: two-page result has `nextPath == lastPath` (R50b); the results URL has no `page=`, the page comes from the pager.
- A pager without links (one page) gives `first == last == current` with `pageURL` as both paths (R08-2, R13a).
- An empty MP list (R13c) is a list page (body `id`) with a `th.s2Tableau` "Aucun message posté": empty `topics`, no `notice`.
- `pageURL` off the forum is ignored (no path echoed), the page number then comes from the pager only.

## Fixtures
Captures in `Packages/HFRKit/Tests/HFRParsingTests/Fixtures/captures/`; oracles in `Fixtures/LOT-002/` (`oracle-map.json`).

| Capture | Covers |
|---|---|
| R04, R09 | Discussions page 1 anonymous (R09 is `owntopic=3` redirected): sticky, closed, 14 polls, plain pager links, ZWSP pseudos |
| R05a, R05b | middle page 12 and page 500: obfuscated pager, window, previous link |
| R06, R07, R27-list | sub-forum (new-topic link to `message.php`), small forums (cat 12, 10) |
| R08-1, R08-3 | empty `owntopic=1`/`3` lists: `.hop` page with refresh |
| R08-2, P03f | logged-in `owntopic=2`: tabs, red flag with `#t` anchor, `forum2.php` links, MP badge 0 and 1 |
| R13a, R13b, R13c, R13u1, R13u1b | MP lists: read/unread icons, `[non lu]`, group threads, 7-page pager, empty list |
| R50b, R50c | search results with snippets and a two-page pager; no result (`.hop`) |
| R53a | a non-list answer (smiley search fragment): `.malformed` |

**Oracle coverage:** all 18 list cases of the LOT-002 map (`topics` 11, `mp` 5, `search` results 2) are compared field by field
(`TopicListDifferentialTests`, guarded by a test that the case list equals the map's list cases). R50a (search waiting page) is LOT-025's.
Display-only and session fields of the oracle are not compared: `aDateOfLastPost` (relative label), `isLocallyViewedInApp`, `isSuperFavorite`,
`isViewedFromForumAtLoad` (equals `isViewed`), `catID`/`postID` (always 0 in lists; checked against `topicID` instead, D8).

**Pending capture:** maintenance page (`<body>` starting with `<p>`); a list behind a login wall (the MP list logged out: the `.notAuthenticated` rule is inferred from R13c and tested on R08-1's page with the MP URL); a `sujetCase3` with a second link
outside search results; replies counts with separators; a row without last-post link or without `<b>` author; a pager with a non-cryptlink
"Page Suivante"; search results across categories (pivot shapes, E12). None is hand-built.

**Follow-ups for other lots:**
- LOT-045 fetchers: single-slash paths are kept as served, so raw spaces or U+200B in them are not percent-encoded; encode them before building a request.
- LOT-023/024: W17c and W01 already hold HFR's logged-out `.hop` wordings, a starting point for telling a login wall from an empty result.
- LOT-023: the header badge reads the first integer of the middle cell ("Vous avez N nouveau message privé", P03f); confirm the rule on a count above 9 and on the plural sentence when the unified badge parser lands.

## Intentional differences from legacy
Each is asserted by the differential tests against independent evidence (regexes over the raw capture, `CaptureRowEvidence`), not against the parser.

| # | Legacy | Port | Why |
|---|---|---|---|
| D1 | body without `id` → `statusInfo` `noAuth` (`.hop`) or `maintenance`; no rows → `noResults` "Aucun message" | `.hop` → empty page + `notice`, except on the MP list URL → thrown `.notAuthenticated`; maintenance → thrown `ListPageFailure.maintenance`; no rows → empty page, no notice | every captured `noAuth` is an empty result (RC2.4), and an empty MP list keeps its list body (R13c), so a `.hop` there is a wall; the "Aucun message" text is a legacy constant, not from the page; typed errors (audit B §5) |
| D2 | `currentCat` only from the logged-in search tab (`""` on anonymous, MP and search pages) | falls back to the header search form's `cat` | the category is on every list page; needed for `topicID` |
| D3 | `aAuthorOrInter` `""` when `sujetCase6` is plain text | the cell text | anonymous pages print the starter as text (R04: all 55 rows were empty in legacy) |
| D4 | `filterTU` rewrites "topic unique" and 8 spellings to "TU" | raw title | presentation concern (LOT-010) |
| D5 | poll icon `…/images/defaut/sondage.gif` only | any `sondage.gif` | the live icon is `…/images_forum/1/sondage.gif`; legacy found no poll in any list (RC2.3) |
| D6 | `sNewMPNumber` = digits, or the whole cell text when it has none (`" Messages privés"`) | `Int`, 0 when no digit | typed count (RC2.9) |
| D7 | search snippet kept HFR's trailing space | trimmed | display noise |
| D8 | `catID`/`postID` 0 on list rows | `topicID` from row links or canonical path + catalogue | stable identity (LOT-010, audit B open question 9) |
| D9 | page number from the URL (`page=`, else **last digit of the URL**, `:94-114`) | the pager's bold entry, else `page=`/`liste_sujet-N.htm`, else 1 | the HTML states the page; the last-digit rule read `moderation=0` (RC2.7). Same values on all 18 cases |
| D10 | `""` vs `nil` for absent links, `curTopicPage` 0 | `nil` | optional types |
| D11 | one row without title link or with a missing node raised and lost the page (audit B §4.1) | the row is skipped; rows present but none readable → `.malformed` | a malformed row must not hide the list |
| D12 | relative date label in the parser | none (`LastPost.date` only) | display strings stay in the UI (audit B §3.3.5) |
| D13 | any `href` copied as is | only forum paths (`forumRelativePath`) | links are requested with the session (LESSONS 37, ADR 0006 am. 1) |
| D14 | pager entries by child index 2 and last child (raised below 3 children, Q2) | entries classified by content | robust to whitespace nodes; same result on every capture |
| D15 | any `<body id>` is a list | only an id `<section>__topics_listing__<kind>` | another page (login, topic) must not pass for an empty list |

## Learnings
To copy into AGENTS.md §11 when the lot closes:

- On Linux, `CharacterSet.whitespacesAndNewlines` trims U+200B, which HFR puts inside pseudos: trim with the Unicode `White_Space` property instead.
- Legacy `contents` is the element's own text (`.hop` message without its "Retour" link), `allContents` all of it; SwiftSoup's `text()` is neither (it collapses whitespace).
- Measure before keeping a selector helper: per-cell subtree walks were half of the parse time.
