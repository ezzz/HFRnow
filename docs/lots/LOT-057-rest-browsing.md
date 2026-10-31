# LOT-057 — REST browsing client

- **Module:** HFRClient (`Sources/HFRClient/REST/`), plus two small public helpers in HFRParsing (`HFRText.decodingHTMLEntities`, `HFRDate.restDate`)
- **Difficulty / model:** medium (Opus 5.5 author → Fable 5.1 reviewer)
- **Issue:** [#83](https://github.com/ezzz/HFRnow/issues/83) (audit item redface2 E1; old issue francoisgn/ios-app_SwiftHFR#85)
- **Builds on:** LOT-010 (list models), LOT-021 (`ForumListParser`), LOT-022 (`TopicListParser`), LOT-041 (`HFREndpoint.rest`, `topicPage`, `topicList`), LOT-042 (`AnonymousTransport`), LOT-045 (`PageFetcher`), LOT-095 (`ForumCatalogue.forumPath`), all done.
- **Partial:** this PR ships the anonymous part (`Refs #83`). Left: the flag buckets ([#335](https://github.com/ezzz/HFRnow/issues/335)), the sub-categories ([#285](https://github.com/ezzz/HFRnow/issues/285)), list pages after the first, `results_per_page` and the error answers ([#355](https://github.com/ezzz/HFRnow/issues/355)).

## Sources
The legacy app never called the REST API: there is no `rest_api` in francoisgn/hfrnow at `2440d79` nor on `origin/master`, so there is no legacy oracle for the JSON side. The facts come from:

- redface2 finding E1 (`docs/research/redface2-comparison.md:289`): the URL shape, `/api/…` hrefs answering 404 and rewritten to `rest_api.php?uri=…`, `total_pages` = ceil(posts count / per page), `/posts/` always 500, auth by the normal session cookies;
- HFR-PROTOCOL §7 (REST API row) and the captures `R57a` (categories), `R57b` (last topics of category 13) and `R57c` (one topic), anonymous GETs of 2026-10-26;
- the HTML side, captured six minutes before `R57b`: `R04` (category 13, page 1, anonymous) and its LOT-002 oracle, and `R01` (home) for the categories.

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

**Pending capture** (never hand-built, LESSONS 35-36):
- The flag buckets `topics/{participated,read,favorites}`, logged in ([#335](https://github.com/ezzz/HFRnow/issues/335)); with them, `last_position`, `last_post_read_id` and `flag_owntopic`.
- The sub-categories of a category ([#285](https://github.com/ezzz/HFRnow/issues/285)).
- A list page 2, a `results_per_page` answer, an `/api/…` href requested as is (E1 says 404), and a REST error answer ([#355](https://github.com/ezzz/HFRnow/issues/355)). Until then the client asks for page 1 only, and every failure is handled the same way: fallback.
- Any REST answer to a session: the client sends no cookie.

## Intentional differences
No legacy code: none from legacy. From the issue text:
1. **Page size**: the issue's "per page, default 25" is the topic list's page size (`R57b`); a topic's page count uses 40 posts per page, the anonymous HTML size (`R04`, E19), which is also the `results_per_page` of every `links.posts.href`.
2. **Anonymous only**: the issue reads with the account's cookies; with no capture of a logged-in REST answer, the shipped part sends none (the buckets need them and wait for #335).
3. **`last_position`** is not read: it is absent from every anonymous answer.

## Tests
`RESTDocumentTests` (differential against `R01`, `R04`, the `R01` legacy oracle; one edited capture per checked field), `RESTHrefTests`, `RESTBrowsingClientTests` (scripted transport: captured requests, fallbacks, no fallback on cancellation, offline or timeout, invalid targets, the cookie-less transport), `RESTTextTests` (dates across both DST changes, entities). Nineteen mutations, each applied and reverted, each failed a named test: replies = count, 25 posts per page, sticky read on a single topic, no category check on a list row, no host check, `posts` allowed, redirects followed, fallback on cancellation, no fallback to the home page, a redirect accepted as an answer, and, after the first review, each of `list_type`, `page`, `results_per_page`, `posts` ≥ 1, topic id ≥ 1, the empty list, the title trim and the paging checks of the category and topic hrefs dropped. The category id and the fallback's cancellation need no guard of their own: no id below 1 has a catalogue path, and `PageFetcher` sends nothing for a cancelled task (`cancelledBeforeFallback`).

## Learnings
- `R04` and `R57b` were captured six minutes apart: rows whose last post predates both are a free differential oracle between the HTML and REST sides.
- The same topic carries two href shapes (with and without its sub-category) and two sticky values across REST resources: check one resource against another before trusting a field.
