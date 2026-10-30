# LOT-046 — Search flows (global and intra-topic)

- **Module:** HFRClient
- **Difficulty / model:** medium (Opus 5.5 → Fable; the plan routes Sonnet → Opus, this lot was taken by an Opus contributor, `ext/bybifok-opus-1`)
- **Issue:** [#72](https://github.com/ezzz/HFRnow/issues/72)
- **Depends on:** LOT-041 (#67): `HFREndpoint.globalSearch`, `HFREndpoint.topicSearch`, `GlobalSearchQuery`, `TopicSearchQuery`; LOT-025 (#53): `SearchRedirectParser`; LOT-040 (#66): `RedirectPolicy.doNotFollow`, `AnonymousTransport`. Also reads LOT-022's `TopicListParser` (search results) and LOT-037's `HopResponseParser` (refusals).
- **Audit:** NET-10, NET-11 (`docs/audit/A-network-sessions.md:265-266`); decision Q-7 (`docs/audit/README.md`).

## Legacy sources

Legacy app: `francoisgn/hfrnow` at `2440d79` (an ancestor of `origin/master`).

| Legacy | What it gives this lot |
|---|---|
| `Classes/ObjCForumSearchWorker.m:23-60` | global search: POST `search.php?config=hardwarefr.inc`, refresh read from the answer, error "Aucune page de résultats n'a été trouvée." without one |
| `ObjCForumSearchWorker.m:125-146` | the cookie-less session and request (`HTTPShouldHandleCookies = NO`, ephemeral, no cookie storage) |
| `ObjCForumSearchWorker.m:148-199` | fields in order, `hash_check` from the app-wide value (`:159`), banned words replaced by another query (`:150-156`), form encoding that leaves accented letters raw (`:194-199`) |
| `ObjCForumSearchWorker.m:211-240` | the results requested by a second POST of the same body to the refresh URL |
| `HFRswift/Swift/ForumSearchService.swift:10-127` | `ForumSearchParams` (ported by LOT-041 as `GlobalSearchQuery`) |
| `Classes/ObjCTopicSearchWorker.m:9-66` | intra-topic search: no criterion refused (`:14-21`), redirects off (`:33`), `Location` read (`:39-52`), any answer without one is "Aucun résultat n'a été trouvé" (`:46-51`) |

## Behaviour

Code in `Sources/HFRClient/Search/`, tests in `Tests/HFRClientTests/Search/`.

### `GlobalSearchFlow`

- `search(_:hashCheck:)`: refuses a text holding a banned word, then builds the LOT-041 POST, sends it, reads the waiting page's refresh (`SearchRedirectParser`), GETs that URL and reads the page with `TopicListParser`. Returns `GlobalSearchResult` (`url` served, `page`).
- **Banned words** (`bannedWords`: `jailbreak`, `cydia`, `pengu`, `apple jb`), matched as substrings of the lower-cased text, as legacy did (`:149-152`): `bannedWord(<word>)` before any request. The query is never replaced (Q-7); the app shows the warning.
- **Cookie-less**: the public `init()` sends everything through its own `AnonymousTransport` (no cookie sent, none stored; `R50b` and `R50c` answer `Set-Cookie: p`, which is dropped).
- **`hash_check`**: the caller passes the account's token when one is logged in, else an empty string, as legacy sent its app-wide value on the same cookie-less request. What HFR does with either on a cookie-less POST is not captured (Pending capture).
- **The POST never follows a redirect** (`doNotFollow`): it is the only request carrying `hash_check`, and a followed 307 or 308 would resend body and token wherever it points. A 3xx answer is `noResultsPage(.invalidValue("search answer redirect"))`.
- **The refresh URL is checked before the GET**: `SearchRedirectParser` accepts an `https` URL on the forum host; the flow also refuses a port other than 443 and user info (`PostingFlow.isForumPage`), as `page(atPath:)` does, so such a URL is never requested.
- **Results** by one **GET** of the refresh URL, with the global search timeout (15 s, LOT-041), redirects followed by the transport. A page served from outside the forum is `page(.malformed)`. "No result" is the page HFR serves with its notice (`R50c`): an empty `TopicListPage` whose `notice` is HFR's sentence, not an error.
- `page(atPath:)`: GETs another results page from a pager path of a result (`navigation.nextPath`…). Only an `https` forum URL (port absent or 443, no user info) at `/forum1.php` with `recherches=1` is requested; anything else is `invalidPage` before any request.
- **Errors** (`GlobalSearchError`): `bannedWord`, `invalidPage`, `network` (request not built: empty text, impossible date; transport failure; HTTP 4xx/5xx; cancellation), `noResultsPage` (the waiting page has no refresh, or one off the forum: `SearchRedirectParser`'s error), `page` (maintenance, unreadable list).

### `TopicSearchFlow`

- `search(_:in:)`: the session's `hash_check` is required (`missingToken` before sending); the LOT-041 builder refuses a query without word nor author (`network(.invalidRequest)`). One POST to `transsearch.php` in the account session, `RedirectPolicy.doNotFollow`.
- **Match**: a redirect (301, 302, 303, 307, 308) whose `Location`, resolved against the request, is an `https` forum page at `/forum2.php` naming the **searched topic** (category and number): `.match(url)`, the URL HFR gave (`…&currentnum=<n>#t<n>`, `R52a`). Any other `Location` is `invalidLocation`, never returned: the reader requests it with the session (LESSONS 37, 43). A redirect without `Location` is `unrecognizedAnswer`.
- **No match**: a page whose `.hop` says "aucune réponse n'a été trouvée" (`R52b`): `.noMatch`.
- **Anything else** goes through LOT-037's classifier: `notLoggedIn` (HFR's logged-out sentence), `rejected` (a refusal, including the plain-text invalid-token answer), `unrecognizedAnswer` otherwise, each with HFR's message when there is one.
- Both flows: one request per step, never retried (the transport never retries POSTs; the flows never resend); a task cancelled before a request leaves sends nothing more (`network(.cancelled)`), in particular a search cancelled during its POST never sends the GET.

## Edge cases

- A banned word inside another word (`penguin`) refuses the search, as in legacy; a near miss (`applejb`) is searched as typed.
- Accented text is sent lower-cased and UTF-8 percent-encoded (`Pâtes à l'ail` → `search=p%C3%A2tes+%C3%A0+l%27ail`), by LOT-041's `FormBody`.
- A waiting page without refresh (`R50c` served to the POST, the LOT-005 oracle's "no redirect" case) is `noResultsPage` and nothing else is requested; so is a POST answered by a redirect, and a refresh to the forum host with port 8443 or user info (probed by rewriting `R50a`'s refresh target).
- `R50a`'s refresh is relative (`/forum1.php?recherches=1&amp;…`); `SearchRedirectParser` resolves it on the forum and refuses any other host or `http` with a port.
- A pager path built for another host, `http://…:80`, port 8443, `forum2.php`, a list without `recherches=1`, or a `javascript:` link is never requested.
- A `Location` on another host, `http`, port 8443, another topic number, another category, `cat=prive`, `forum1.php`, or without a topic is `invalidLocation`.

## Fixtures

Captures (shared corpus, nothing new): `R50a` (waiting page, POST meta with `request_body`), `R50b` (results, 50 rows, next page), `R50c` (no result), `R52a` (302 and its `Location`, meta only), `R52b` (no match). Oracles: LOT-005 `R50a`, `R50c` (`search-redirect`), LOT-002 `R50b`, `R50c` (rows, next page, notice). `W17b`, `W17c` and `R21` are used only to check that nothing but HFR's sentence reads as "no match"; they are not claims about what `transsearch.php` answers.

## Tests

- `GlobalSearchFlowTests`: the `R50a` → `R50b` chain against both oracles (POST body equal to `R50a`'s `request_body`, results URL equal to the LOT-005 `absoluteURL`, sent by GET, the 50 LOT-002 paths and next page, no `Cookie` header); `R50c` empty with the oracle's notice; banned words at the boundaries; accented text; no refresh; a redirect answering the POST; a refresh target with a port or user info; results off the forum; transport failures on each step (one request each); HTTP error; empty text; cancellation between the POST and the GET; next page by GET; refused pager paths; the public flow's transport is `AnonymousTransport`.
- `TopicSearchFlowTests`: `R52a` match (one POST, `doNotFollow`, token and fields), `R52b` no match, refused `Location`s, redirect without `Location`, other pages never "no match", missing token and missing criterion before sending, transport failure without retry, HTTP error, cancellation.

Shown to fail with the behaviour removed (22 mutations, each caught): no banned-word check, check on the raw text, legacy's second POST, no cancellation check (each flow), results off the forum accepted, pager path not checked for forum / path / `recherches`, one retry after a failure, the public flow over a session, legacy's "any answer is no match", any `Location` accepted, topic / path / forum not checked, no token check, redirects followed, logged-out read as a refusal; after the review: the POST following redirects, a 3xx answer parsed as a waiting page, the refresh URL not checked before the GET.

## Pending capture

- `POST /search.php` **without cookies** (`R50a` was sent with user2's session), once with an empty `hash_check` and once with the account's: whether HFR checks the token there.
- A global search with accented characters (what HFR does with UTF-8 percent-encoding; legacy sent the letters raw).
- A results page 2 (`R50b`'s next-page link): `page(atPath:)` reads it like the first page.
- `transsearch.php` answering LOT-041's legacy body (`hash_check, p, post, cat, word, spseudo, filter=1`): `R52a` and `R52b` answered the browser's field set (`config`, `sondage`, `owntopic`, `dep=0`, `firstnum`, no `filter`); the tests use only their status, `Location` and page.
- `transsearch.php` answering a bad token, a logged-out session, and a continued search (`firstnum`/`currentnum`; "Stepping not tested", HFR-PROTOCOL §7).

## Intentional differences from legacy

- **Results by GET** instead of a second POST of the same body (`ObjCForumSearchWorker.m:211-240`): HFR serves them to a cookie-less GET (`R50b`), and a GET is never a second submission. [CHANGELOG-LEGACY](../CHANGELOG-LEGACY.md) row 43.
- **Accented text percent-encoded in UTF-8** (`:194-199` left letters raw); done by LOT-041's builder, recorded here as the issue asks. Row 44.
- **Banned words refuse the search** with a warning instead of searching for a replacement text (`:150-156`, Q-7). Row 45.
- **Intra-topic**: only HFR's "aucune réponse" sentence is "no match"; a refused token, an expired session or an unknown page is reported (legacy: any answer without `Location`, `ObjCTopicSearchWorker.m:46-51`). The `Location` is returned only for a forum page of the searched topic (legacy returned any `Location`). Row 46.

## Learnings

- A flow over a captured exchange can be checked against two oracles at once: the redirect parser's oracle gives the next request byte for byte, the list oracle gives what that request must read.
