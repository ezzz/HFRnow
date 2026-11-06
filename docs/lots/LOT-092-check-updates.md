# LOT-092 — Check-updates flow (MPs and flags)

- **Module:** HFRClient
- **Difficulty / model:** medium (Sonnet 5.5 → Opus 5.5)
- **Issue:** [#184](https://github.com/ezzz/HFRnow/issues/184); features FEAT-005 ([#149](https://github.com/ezzz/HFRnow/issues/149)) and FEAT-001 ([#145](https://github.com/ezzz/HFRnow/issues/145)), both proposed by Bybifok (credit in the PR and CREDITS.md)
- **Depends on:** LOT-047 (`MPUnreadPoll`), LOT-024 (`FavoritesParser`), LOT-037, LOT-045 (`PageFetcher`), and #383 (`StaleSessionAnswer`, merged in #506)

## Legacy sources
Legacy app: `master` of ezzz/HFRnow, citations at commit `2440d79`.

| Legacy | Replaced by |
|---|---|
| `HFRswift/Swift/MPBackgroundService.swift:70-136` (background GET `/`, 5 s timeout, MP count, notify when higher) | `MPUnreadPoll` (LOT-047), called as is |
| `Classes/ObjCFavoritesLoaderWorker.m:42-52` (GET `/forum1f.php?owntopic={1,3}`, `3` when `vos_sujets == 1`) and `:74-139` (parse) | `FlaggedTopicsPoll`: the same page with `owntopic=1` (the flags page), parsed by `FavoritesParser` (LOT-024) |

Legacy has no "check what is new" call: the MP poll and the favourites loader are separate, and neither classifies an expired session.

## Behaviour
`CheckUpdatesFlow(session: HFRSession).check() async throws(CheckUpdatesCancelled) -> UpdateSummary`, in `Packages/HFRKit/Sources/HFRClient/Updates/`.
Nothing is added to `HFRModels`: `UpdateSummary`, `UpdateOutcome` and `UpdateFailure` are HFRClient types.

1. `MPUnreadPoll.unreadCount()`: one `GET /` (LOT-047, with #383's `.sessionExpired`).
2. Unless step 1 threw `.sessionExpired`, `FlaggedTopicsPoll.flaggedTopics()`: one `GET /forum1f.php?owntopic=1` (`HFREndpoint.favorites(filter: .flagged)`), parsed by `FavoritesParser`. Both pages are requested in a probe `HFRSession` seeded with a snapshot of the account's cookies and written back nowhere (LOT-044, LESSONS 55, 56); the probe keeps the account's host policy (#365).
3. Each source has its own outcome, so one failure never hides the other:

| Outcome | Meaning |
|---|---|
| `.value(Int)` / `.value([TopicSummary])` | HFR's page answered. `0` only when the page said 0; `[]` only for a list page with no row (`R123g`) |
| `.noInformation` | MP: no entry in the home page (`R01`). Flags: a `.hop` page that is not the stale-session page (`R12`, the logged-out answer). Never zero, never proof of an expiry (LOT-047 rule) |
| `.failed(.network)` | offline, timeout, HTTP 4xx/5xx |
| `.failed(.page)` | maintenance, unreadable page, or (flags) an answer that is not the page served in place (a redirect, another URL) |
| `.failed(.sessionExpired(reason))` | only HFR's stale-session page (`R70a` home, `R70b` flags), answered to the account's *current* cookies (#383); the flags source takes the home's verdict without a request |

**Flagged topics.** The topics are `FavoritesPage.topicsByLastPost`: every row of every section, most recent last post first. `UpdateSummary.flaggedTopics(postedAfter:)` keeps those whose last post is later than a date the **caller** keeps (the LOT-091 ledger), plus those whose last post has no date; it returns `nil`, not `[]`, when the flags did not answer.
The flow does not decide on its own that a topic "has news": the flags page does not say what the member has read. The flag cell links to the last read position (`…&page=<n>#t<numreponse>`), the last-post link ends in `#bas` with no message number, and a flag link's `page=` can be stale (`R123g`'s run, HFR-PROTOCOL §6c), so comparing pages would invent an answer (LESSONS 17). A page-based "pages behind" signal waits for a capture that shows a flag position and the last message number of the same topic.

**Never marks anything read.** HFR moves a flag on an authenticated *topic* page (E25, `R21`). The flow requests `/` and `/forum1f.php` only. Evidence for the flags page: `R10` and `R73a` are two GETs of user2's `owntopic=1` list two seconds apart (23:34:55 and 23:34:57) with the same two flags at the same positions (`p101#t9810000001`, `p102#t9810000002`); the legacy app reloads this page on every refresh. Also, the flags request is sent with `redirectPolicy = .doNotFollow`, so a redirect cannot lead the account's cookies to a topic page; a 3xx answer is `.failed(.page(.malformed))`.

**Cancellation.** Checked before the first request, between the two, and after the second; a `.network(.cancelled)` of either poll is the same. The flow then throws `CheckUpdatesCancelled` and returns nothing, not even the source that had answered.

**Politeness.** At most two requests, never more, never a retry. How often to call, the minimum interval, the notification and the "already notified" state are the app's and LOT-091's (LESSONS 48).

## Edge cases
- A logged-out account sends the same two requests without `md_user`: `noInformation` on both (`R01`, `R12`). The flow does not special-case an empty jar (that is `SessionRefreshFlow`'s rule, LOT-044).
- A login adopted while a stale answer is in flight: no verdict, the source is `noInformation` (#383's rule through `confirmStaleSession`).
- An empty `owntopic=1` list is a list body (`R123g`), told from the logged-out `.hop` (`R12`) by the parser's `notice`; a `.hop` with a link is `noInformation`.
- A page of another kind served at the flags URL (a topic page, `R20`): `.failed(.page(.malformed))`.

## Fixtures
None added. Captures read in place: `R01`, `R02`, `R03` (home), `R70a` (stale home), `R10`, `R73a` (flags, two rows), `R123g` (empty flags), `R12` (flags, logged out), `R70b` (stale flags), `R20` (a topic page, as the wrong page). `R70b` was captured at `forum1f.php?config=hfr.inc&owntopic=1`; its bytes equal `R70a`'s, and the test serves it at the URL the flow requests (`?owntopic=1`, as `R10`), so the stale check's same-URL rule applies to the real request.

**Pending capture:** none required. Not captured, hence not claimed: a flags page whose flag position and last post can be compared (see above); the flags page of an account whose jar HFR half-accepts (neither stale nor valid).

## Intentional differences from legacy
| # | Legacy | Port | Why |
|---|---|---|---|
| D1 | two unrelated loaders, no shared session handling | one flow, one probe per request, nothing written to the account | LOT-044, LESSONS 55-56 |
| D2 | `owntopic=3` when `vos_sujets == 1` | always `owntopic=1` (the flags page, which also lists favourites, `R73b`) | the check is about flags (#184); the setting is a screen choice of the app |
| D3 | errors swallowed, an unreadable list lost | typed `UpdateFailure` per source | the app counts failures |
| D4 | a stale session read as a failure to count | `sessionExpired` (#383) | HFR's own word that the cookies are refused |

## Learnings
To copy into AGENTS.md §11 when the lot closes:

- The check-updates flow is two GETs (`/`, `/forum1f.php?owntopic=1`) in probe sessions, never a topic page; each source has an outcome, `noInformation` is never zero news, and "news" is relative to a date the caller keeps because the flags page does not say what was read.
