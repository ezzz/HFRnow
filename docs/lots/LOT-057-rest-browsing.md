# LOT-057 — REST browsing client

- **Module:** HFRClient (`Sources/HFRClient/REST/`), plus two small public helpers in HFRParsing (`HFRText.decodingHTMLEntities`, `HFRDate.restDate`)
- **Difficulty / model:** medium (Opus 5.5 author → Fable 5.2 reviewer)
- **Issue:** [#83](https://github.com/ezzz/HFRnow/issues/83) (audit item redface2 E1; old issue francoisgn/ios-app_SwiftHFR#85)
- **Builds on:** LOT-010 (list models), LOT-021 (`ForumListParser`), LOT-022 (`TopicListParser`), LOT-041 (`HFREndpoint.rest`, `topicPage`, `topicList`), LOT-042 (`AnonymousTransport`), LOT-045 (`PageFetcher`), LOT-095 (`ForumCatalogue.forumPath`), all done.
- **Partial:** #356 shipped the anonymous part, the second PR the logged-in flag buckets (`R335a`-`R335e`, #335); both `Refs #83`. Left, all waiting on captures: the sub-categories ([#285](https://github.com/ezzz/HFRnow/issues/285)), anonymous list pages after the first, `results_per_page` and the error answers ([#355](https://github.com/ezzz/HFRnow/issues/355)); a bucket row's resume link and read state, the bucket count against the flags page and a bucket without a valid session are captured since ([#830](https://github.com/ezzz/HFRnow/issues/830)) and wait for a PR that uses them.

## Sources
The legacy app never called the REST API: there is no `rest_api` in ezzz/HFRnow at `2440d79` nor on `origin/master`, so there is no legacy oracle for the JSON side. The facts come from:

- redface2 finding E1 (`docs/research/redface2-comparison.md:289`): the URL shape, `/api/…` hrefs answering 404 and rewritten to `rest_api.php?uri=…`, `total_pages` = ceil(posts count / per page), `/posts/` always 500, auth by the normal session cookies;
- HFR-PROTOCOL §7 (REST API row) and the captures `R57a` (categories), `R57b` (last topics of category 13) and `R57c` (one topic), anonymous GETs of 2026-10-26;
- the HTML side, captured six minutes before `R57b`: `R04` (category 13, page 1, anonymous) and its LOT-002 oracle, and `R01` (home) for the categories;
- for the flag buckets: `R335a`-`R335e` and `R603f` (logged in, #335, aliased by position) and HFR-PROTOCOL §6c "Flag buckets, logged in"; the favourites pages `R10` (`owntopic=1`), `R603e` (`owntopic=2`), `R12` (logged out) and `R70b` (stale session) for the fallback; redface2 C12 (`flag_owntopic` numbers the flags as `owntopic` does) as a secondary source only (ADR 0015).

## Behaviour

### `RESTBrowsingClient` (HFRClient)
A `Sendable` struct over **one cookie-less transport** (`AnonymousTransport` by default): every capture is anonymous, and what HFR answers to a session is not captured. Sending no cookie also means no cookie is ever written back to an account.

| Call | REST request (`HFREndpoint.rest`) | Result |
|---|---|---|
| `categories()` | `uri=forums/hardwarefr/categories/` | `RESTBrowsingResult<[ForumCategory]>` |
| `lastTopics(in:)` | `uri=forums/hardwarefr/categories/<cat>/topics/last/`, no `page` | `RESTBrowsingResult<TopicListPage>` |
| `topic(_:)` | `uri=forums/hardwarefr/categories/<cat>/topics/<post>/` | `TopicSummary` |

- **One GET** per call, redirects not followed (`R57a`-`R57c` answer 200 without a redirect; a 3xx is a failure), never retried. A `/posts/` uri is never built (HFR answers 500, E1). The category must be a forum category (`cat` ≥ 1).
- **Fallback** (`categories`, `lastTopics`): when the REST exchange or its JSON fails, the same list is read from its HTML page with the existing parser, on the same cookie-less transport through `PageFetcher` (`.anonymous`): the home page and `ForumListParser` (LOT-021) for the categories, the topic list page 1 (`HFREndpoint.topicList`) and `TopicListParser` (LOT-022) for the last topics. The result says where the value came from: `.rest`, or `.html(RESTFallbackReason)` with the REST failure (`network(NetworkError)` or `response(ParsingError)`). A failed fallback throws `RESTBrowsingError.network` or `.page(ListPageFailure)`.
- **No fallback** on cancellation, offline or timeout (`.network(.cancelled | .offline | .timedOut)`: the HTML page would meet the same network; nothing more is sent), nor for `topic(_:)`: no HTML page summarises one topic. Its failures throw `.network` or `.response(ParsingError)`. A private or impossible target (`cat` < 1, `cat=prive`, topic < 1) is `.invalidTarget` before any request.

### `RESTFlagBucketClient` (HFRClient)
The account's flag buckets, read with its cookies: `topics(in: RESTFlagBucket, postsPerPage: Int) -> RESTBrowsingResult<FavoritesPage>`, `RESTFlagBucket` = `participated`, `read`, `favorites`. `postsPerPage` is the account's `topicpp` (profile page 3, `R55-p3`, E19, HFR-PROTOCOL §7 "Posts per page"); below 1 it is `.invalidTarget` before any request. The JSON's own 40 (`links.posts.href`) is not the account's page size. **No reader of `topicpp` exists yet** ([#833](https://github.com/ezzz/HFRnow/issues/833)): it is a prerequisite of any app caller, which until then has only the anonymous 40, wrong for an account with another setting.

**The two sources may not list the same topics**: `forum1f.php?owntopic=1` showed only the topics with news (44 of 57 in one category, §6c "What `forum1f.php` drops", run observation); how a bucket compares is observed since (run observation, #830, HFR-PROTOCOL §6c LOT-057: the global bucket lists only the topics with news, the flat one every topic), not used by this client yet. The result's `source` says which one the caller got.

| Bucket | REST request (`HFREndpoint.rest`) | Fallback page | `owntopic` |
|---|---|---|---|
| `participated` | `uri=forums/hardwarefr/topics/participated/` (`R335a`) | `/forum1f.php?owntopic=1` (`R10`) | 1 |
| `read` | `uri=forums/hardwarefr/topics/read/` (`R335b`) | `/forum1f.php?config=hfr.inc&owntopic=2&new=0&nojs=0` (`R603e`) | 2 |
| `favorites` | `uri=forums/hardwarefr/topics/favorites/` (`R335c`) | `/forum1f.php?owntopic=3` (LOT-024, legacy `ObjCFavoritesLoaderWorker.m:46-48`) | 3 |

- **Session** (as `FlaggedTopicsPoll`, LOT-092): every request runs in an ephemeral probe `HFRSession` seeded with a snapshot of the account's cookies and keeping its host policy; nothing is written back (the REST answers set no cookie, `R335a`-`R335e`; a logged-in `forum1f.php` sets `md_user` and `md_passs` again, `R10`). The account session is only read.
- **One GET** of the global bucket, no `page` or `results_per_page` (HFR ignores them, `R335d`, `R335e`), redirects not followed, never retried.
- **Fallback**: on a REST failure (as `RESTBrowsingClient`: not on cancellation, offline or timeout) the favourites page of the same `owntopic`, read with `FavoritesParser` (LOT-024). It is sent with `redirectPolicy = .doNotFollow` and must be served in place (2xx at the requested URL), else `.page(.malformed)`: the cookies never reach a topic page, the only page known to move a flag (E25). HFR's stale-session page (`R70b`) is `.sessionExpired`, under `FlaggedTopicsPoll`'s rule (only while the account still holds the cookies sent); the logged-out page (`R12`) comes back as its `notice`, and the caller decides from its session, as with `FavoritesParser`.
- `HFREndpoint.favorites(filter: .read)` builds `R603e`'s URL; it was refused before ("`forum1f.php` only knows those two"), which `R603e` disproves. `.all` stays refused.

**Global bucket → `FavoritesPage`** (`R335a`-`R335c`): `resource.list_type` = `list`, `page` = 1, `href` names the bucket asked for (a `participated` answer is never read as `read`), at least one group, `results_count` = the number of groups. Each group: `list_type` = `topic`, `page` = 1, `links.category.href` names a forum category (once per answer), `href` names the same bucket of that category, at least one row, `results_count` = its number of rows, `links.category.title` not blank. A group becomes a `FavoriteSection`: `categoryID` `.forum(cat)`, `forum` = the title (entities decoded) and `ForumCatalogue.topicListPath(cat, filter: owntopic)`, the category list on the same filter that the page's header names (`R10`, `R603e`), in its short form (without the header's `sondage` … `subcatgroup` parameters, as every list path the app builds). `unreadPrivateMessages`, `hashCheck` and `notice` are nil: the JSON has none.
- The counts are a consistency check of the answer: a level whose `results_count` differs from its entries is refused, never returned (LESSONS 44). They cannot prove HFR left nothing out (in every capture they equal the entries; redface2 E1 calls the global bucket "truncated by recency"): #830 observed it is a filter on news, not a cut (run observation, HFR-PROTOCOL §6c LOT-057 "Completeness"). An answer with no group is not "nothing flagged": what HFR answers an anonymous or stale session is observed since (#830, HFR-PROTOCOL §6c LOT-057; the stale session is `R830t`, the no-cookie answer is pending publication, #885) but not read by this client yet, so the favourites page, which tells them apart (`R12`, `R123g`), is read.
- The flat form of one category (`R335e`, `R603f`) is not requested; given as an answer, it is refused.

**Bucket rows** are the topic rows below, with:

| `TopicSummary` | From | Evidence |
|---|---|---|
| `flag` | `flag_owntopic`: 3 `.yellow`, 1 `.blue`, 0 `.red` in `read` and nil elsewhere, 2 nil; another value or none fails the decode | `flag_owntopic` is the topic's strongest flag, not the bucket's (HFR-PROTOCOL §6c): 3 for a favourite, 1 for a topic only participated in, as the `owntopic=1` list shows `favoris.gif` on favourites and `flag1.gif` on the others (`R603a`); 0 on every `read` row (`R335b`), where the `owntopic=2` page shows `flag0.gif` on every row (`R603e`). 2 is the red flag in redface2 C12 only: never captured, so no flag (ADR 0015 point 4). The page shows a flag image only on a row with news (`R603a`); the JSON gives one on every row |
| `path`, `firstPagePath`, `currentPage`, `flagPath` | `lastPagePath`, page 1, `pageCount`, nil | `FavoritesParser` opens a row at its flag link, else its last post; the JSON has no flag link, and what `last_post_read_id` and `last_position` point to is observed since (run observation, #830, HFR-PROTOCOL §6c LOT-057) but not read by this client yet, so the row opens at its last page, like an HTML row without a flag link |
| `readState` | `.unknown` | as `FavoritesParser`; what `is_read` means against the page's news marker is observed since (run observation, #830, HFR-PROTOCOL §6c LOT-057) but not read by this client yet |
| `isSticky` | false | `is_sticky` is never true in the raw buckets, while `R603e` shows a sticky row: not read, as for `topic(_:)` |
| `pageCount`, `lastPagePath` | ⌈`links.posts.count` / `postsPerPage`⌉ and its `forum2.php` page | the account's page size (E19); at 40 it is the `page=` of HFR's own `links.posts.href` (`…/posts/?page=126&results_per_page=40` for 5001 posts, `R335a`) |

### JSON → LOT-010 models (internal DTOs, `RESTDocument`)
Every value is checked; a missing, ill-typed or refused field is `ParsingError.invalidValue(field:)` naming the field by its whole JSON path (`resource.resources.links.posts.count`), never the value (the JSON holds pseudos); a body that is not JSON is `.malformedDocument`.

**Hrefs** (`RESTHref`): an href is accepted only as `https://forum.hardware.fr/api/<uri>` (scheme, host, no port, no user, path under `/api/`); `<uri>` is what `rest_api.php?uri=` takes, and the href's own `page` / `results_per_page` become the request's (E1 reports that the `/api/` URL itself answers 404; not tested, #355). A `posts` resource is refused, href or built uri. Each resource's `href` must name the resource asked for, and a topic's category comes from its `links.category.href` (`…/categories/<cat>/`). A topic's `href` is `…/categories/<cat>/topics/<post>/` (`R57c`, the first `R57b` row) or `…/categories/<cat>/subcategories/<sub>/topics/<post>/` (the 29 other `R57b` rows); the sub-category number is not mapped to a sub-forum (pending #285).

**Categories** (`R57a`): `resource.resources[]` in order, each `id` ≥ 1, `name`, `href` = `…/categories/<id>/`.

| `ForumCategory` | From |
|---|---|
| `categoryID` | `.forum(id)` |
| `title` | `name`, HTML entities decoded (`Overclocking, Cooling &amp; Modding`) |
| `path` | `ForumCatalogue.forumPath(for:)`: the same path as the home page link. A category the catalogue does not know fails the decode, so the home page is read instead |
| `subforums` | empty: the sub-category resource is not captured (#285); the home page keeps them |

**Topic rows** (`R57b` rows, `R57c`):

| `TopicSummary` | From | Evidence |
|---|---|---|
| `topicID` | `.forum(<cat of links.category.href>)`, `id` | `R57b`, `R57c` |
| `title` | `title`, entities decoded, then trimmed like an HTML list title (topic 115425 comes with a leading space in `R57b` and in `R04`; both readers drop it). A blank title fails the decode | `R57b`, `R04` |
| `path` | `HFREndpoint.topicPage(topic:page: 1)`, forum-relative: the `forum2.php` URL the network layer sends, which HFR redirects to the canonical page | LOT-041, LOT-045 |
| `repliesCount` | `links.posts.count` − 1 | equals `R04` on the 28 rows whose last post predates both captures |
| `pageCount` | ⌈`links.posts.count` / 40⌉ | equals `R04` (anonymous); 40 is the anonymous page size, an account may set another (`topicpp`, E19) |
| `lastPagePath` | `topicPage(topic:page: pageCount)` | |
| `lastPost` | author `links.last_author.title`, path `lastPagePath`, date `last_post_date` | dates equal `R04`'s; the HTML row's link ends with `#bas`, the JSON names no message, so the path is the last page |
| `starterOrInterlocutors` | `links.author.title` | |
| `isSticky`, `isClosed` | `is_sticky`, `is_closed` of a list row; `topic(_:)` reads `is_closed` only | equal `R04`. `R57c` calls topic 28563 sticky where `R57b`, `R04` and its sub-forum list `R06` do not: what a single topic's flag means is not known, so `topic(_:)` returns `isSticky` false |
| `isPoll`, `flag`, `readState` | `false`, nil, `.unknown`: the JSON has no such field | |

`last_post_date` is `yyyy-MM-dd HH:mm`, French wall-clock time (`HFRDate.restDate`, the `HFRDate` rules: Europe/Paris, a skipped time is nil, a repeated one its first occurrence): `2026-10-26 04:10` is `03:10Z` in `R57b` and `R04`, `2003-01-15 14:53` is `13:53Z`.

**Last topics list** (`R57b`): `resource.list_type` = `topic`, `page` ≥ 1, `results_per_page` ≥ 1, at least one row (an empty answer is read from the HTML page, which tells an empty list from a failure, LESSONS 44; HFR's answer for an unknown category is not captured, #355), every row of the requested category. `TopicListPage(topics:, navigation: PageNavigation(current: page, last: page), categoryID: .forum(cat))`: the next page is not offered and `isExact` stays false, because no page after the first is captured. `R57b` holds 30 rows for `results_per_page` 25: the 5 sticky topics come on top of the 25.

## Edge cases
- The REST order of the last topics can differ from the HTML list by the posts of the minutes between two reads (`R57b` and `R04`: topic 101586 moved).
- Titles carrying a pseudo differ between `R57b` and `R04` only by anonymization (one pseudo map per file); the comparison skips them.
- A category id with no catalogue path (a forum HFR adds later) makes the REST categories fail over to the home page, which carries every row.
- Pseudos are the JSON's `title` values as served; `HFRText.normalizedPseudo` is the caller's, as for HTML lists.

## Fixtures
| Fixture | Covers |
|---|---|
| `R57a` + `LOT-002/R01.oracle.json`, `R01` | 20 categories: id, title, path equal to the home page's (`ForumListParser`), in its order; titles equal to the legacy oracle's, which leaves Apple out (legacy hid it) |
| `R57b` + `R04` | 30 rows: id, replies, pages, sticky, closed, last post date equal to `TopicListParser`'s rows of the same topics when no post came between the captures |
| `R57c` | one topic: the `R57b` row of the same topic (same count), pseudos aside, `isSticky` false |
| `R57a`-`R57c` meta | the requests sent equal the captured URLs; no cookie; every href of the three answers rewritten on the forum origin, the 31 `posts` ones refused |
| `R335a`-`R335c` | The global buckets, logged in (#335), aliased by position, 2 groups of 1 topic each: sections, rows and flags equal what the JSON says when walked on its own (`JSONSerialization`, not the decoder); the requests sent equal the captured URLs; each answer is refused as another bucket |
| `R335d` | The global `participated` asked for page 2 of 5: decodes exactly as `R335a` (paging ignored) |
| `R335e`, `R603f` | The flat form of one category: refused as a global answer (its rows are not groups) |
| `R10`, `R603e`, `R12`, `R70b` | The fallback: `owntopic=1` and `2` read with `FavoritesParser` at their captured URLs; the logged-out notice; the stale-session page is `.sessionExpired` |

**Pending capture** (never hand-built, LESSONS 35-36):
- The sub-categories of a category ([#285](https://github.com/ezzz/HFRnow/issues/285)).
- A list page 2, a `results_per_page` answer, an `/api/…` href requested as is (E1 says 404), and a REST error answer ([#355](https://github.com/ezzz/HFRnow/issues/355)). Until then the client asks for page 1 only, and every failure is handled the same way: fallback.
- Any REST answer to a session other than the flag buckets (`R335a`-`R335e`): `RESTBrowsingClient` sends no cookie.
- **Captured since, not used yet**: a bucket row against the flags page row of the same topic (`last_post_read_id`, `last_position`, `is_read` against the flag link and the news marker), the bucket's topics against the flags page's, the completeness of a large global bucket, and a bucket without a valid session ([#830](https://github.com/ezzz/HFRnow/issues/830), `R830t`, HFR-PROTOCOL §6c LOT-057; the no-cookie answer is pending publication, #885). Until a LOT-057 PR uses them, a REST row opens at its last page, its read state is unknown, and an empty bucket is read from the HTML page.

## Intentional differences
No legacy code: none from legacy. From the issue text:
1. **Page size**: the issue's "per page, default 25" is the topic list's page size (`R57b`); a topic's page count in `RESTBrowsingClient` uses 40 posts per page, the anonymous HTML size (`R04`, E19), which is also the `results_per_page` of every `links.posts.href`; bucket rows use the account's `topicpp`, passed by the caller (#833).
2. **Two clients**: the issue reads everything with the account's cookies. `RESTBrowsingClient` sends none (categories and lists are captured anonymous only); `RESTFlagBucketClient` sends the account's, from a probe, and writes none back.
3. **`last_position`, `last_post_read_id`, `is_read`** are not read: they were not tied to the flags page when this was written; #830 observed the comparison since (run observation, HFR-PROTOCOL §6c LOT-057), to use in a later LOT-057 PR. A REST bucket row therefore opens at its last page where the favourites page opens at the flag link: the favourites page stays the better source for resuming until a LOT-057 PR uses it.
4. **Paging of the buckets**: none. The issue's paging criterion applies to lists HFR pages; it serves a bucket whole (`R335d`, `R335e`).

## Tests
`RESTDocumentTests` (differential against `R01`, `R04`, the `R01` legacy oracle; one edited capture per checked field), `RESTHrefTests`, `RESTBrowsingClientTests` (scripted transport: captured requests, fallbacks, no fallback on cancellation, offline or timeout, invalid targets, the cookie-less transport), `RESTTextTests` (dates across both DST changes, entities). Twenty mutations, each applied and reverted, each failed a named test: replies = count, 25 posts per page, a page count `(posts + 39) / 40` that traps near `Int.max` (CodeRabbit), sticky read on a single topic, no category check on a list row, no host check, `posts` allowed, redirects followed, fallback on cancellation, no fallback to the home page, a redirect accepted as an answer, and, after the first review, each of `list_type`, `page`, `results_per_page`, `posts` ≥ 1, topic id ≥ 1, the empty list, the title trim and the paging checks of the category and topic hrefs dropped. The category id and the fallback's cancellation need no guard of their own: no id below 1 has a catalogue path, and `PageFetcher` sends nothing for a cancelled task (`cancelledBeforeFallback`).

`RESTFlagBucketDocumentTests` (`R335a`-`R335e`, `R603f`; one edited capture per checked field) and `RESTFlagBucketClientTests` (scripted probe: captured requests, the probe's seed, the account untouched, the host policy kept, every fallback reason, no fallback on cancellation, offline or timeout, the fallback served elsewhere, `R70b`, `R12`). Twenty-two mutations, each applied and reverted, each failed a named test: either count check dropped, flag 1 read as nil, flag 2 read as red, flag 0 of `read` not red, `is_sticky` read, a category twice, list or group page other than 1 accepted, `currentPage` not set, the account's page size ignored (in the decoder, and in the client's forwarding), no page size guard, the fallback following redirects, no stale-session verdict, a verdict without the account's check, either cancellation check dropped, a fallback on offline, a page served elsewhere accepted, the `favorites` fallback on `owntopic=1`, `R603e`'s URL replaced by the short form.

## Learnings
- `R04` and `R57b` were captured six minutes apart: rows whose last post predates both are a free differential oracle between the HTML and REST sides.
- The same topic carries two href shapes (with and without its sub-category) and two sticky values across REST resources: check one resource against another before trusting a field.
