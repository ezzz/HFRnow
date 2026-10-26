# LOT-045 — Page fetchers

- **Module:** HFRNetwork
- **Difficulty / model:** easy (Sonnet 5.5 → Opus 5.5)
- **Issue:** none (claimed in `docs/LOTS.md`)
- **Depends on:** LOT-041 (`HFREndpoint`), LOT-042 (`HFRSession`, `AnonymousTransport`)

## Legacy sources
Audit [A](../audit/A-network-sessions.md) lots NET-08 and NET-09; protocol [R1–R5, R7, R9, §7 E25](../HFR-PROTOCOL.md); legacy repo <https://github.com/francoisgn/hfrnow>.

| Concern | Legacy |
|---|---|
| Home, topic list, favourites, MP list workers (network side) | `ObjCForumsLoaderWorker.m:20`, `ObjCForumTopicsLoaderWorker.m:36-89`, `ObjCFavoritesLoaderWorker.m:46-48`, `ObjCMPTopicsLoaderWorker.m:9` |
| Topic page: GET, redirects followed, final URL read | `ObjCTopicPageWorker.m:14-43, 86-94` |
| Smiley search, profile | `SmileySearchService.swift:12-42`, `UserProfileView.swift:113-430` |

## Behaviour
All in `Packages/HFRKit/Sources/HFRNetwork/Fetchers/`. No parsing, no flow, no persistence.

- **`PageFetcher`** (struct, `Sendable`): built from the account's `HTTPTransport` (an `HFRSession`) and a cookie-less one (default `AnonymousTransport()`). Functions: `home`, `topicList(category:filter:page:)`, `favorites(filter:)`, `privateMessages(page:)`, `profile(memberID:)`, `smileySearch(_:requireAll:)` return a `RawPage`; `topicPage(topic:page:)` returns a `FetchedTopicPage`. Requests come from `HFREndpoint` (LOT-041); an invalid input throws `NetworkError.invalidRequest` before anything is sent. The `hash_check` and the `vos_sujets` choice (`filter`) are the caller's.
- **`RawPage`**: `text` (decoded by `TextDecoding`), `encoding`, `declaredCharset` (`Content-Type`, else `<meta>`, lowercased, nil if undeclared), `finalURL` (after followed redirects), `statusCode`. 4xx/5xx are thrown (`NetworkError.httpStatus`, via `send`), so a parser never receives an error page.
- **Identity** (`FetchIdentity`): `.authenticated` (default for every list, home, profile and smiley search: flags and personal content need the account) or `.anonymous` (default for topic pages). An authenticated GET marks the flags read (HFR-PROTOCOL §7, E25), so prefetch stays anonymous and the caller asks for `.authenticated` only when the user is reading. Every function takes `as:` to override. The images policy (E26) lives in `AnonymousTransport`; no image fetcher here.
- **Topic page**: `forum2.php` redirects to the canonical URL; `FetchedTopicPage.location` (`TopicPageLocation`) reads `sujet_<post>_<page>.htm` from the final URL (`R5`), nil when the final URL has another shape. `requestedPage` is kept so a caller sees when HFR changed the page. The sub-category segment is never needed.
- **Cancellation**: Swift task cancellation. A task cancelled before the call sends nothing; in flight, the transport throws `NetworkError.cancelled`.

## Edge cases
- Final URL not canonical (no redirect): `location == nil`, text still returned.
- Page below 1, private category in a forum list, short smiley text: `invalidRequest`, nothing sent.
- The `#t<numreponse>` anchor is a fragment and is not sent; use `HFREndpoint.topicPage(post:page:)` plus the returned page if a caller needs it.

## Fixtures
None. `MockTransport` for requests and identity choice; a loopback server (`LoopbackServer`) behind a host-rewriting test transport for the 301 redirect, charset and cancellation.

## Intentional differences from legacy
- Topic pages are fetched without the account cookie by default (legacy used the shared jar and marked flags read on every prefetch).
- Status is checked; the "prepare session" step is explicit session injection.

## Learnings
- A loopback test of a forum URL needs a transport that rewrites the host: keep path and query, swap scheme/host/port.
