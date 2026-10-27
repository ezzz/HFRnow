# LOT-047 — MP unread count poll

- **Module:** HFRClient
- **Difficulty / model:** easy (Sonnet 5.5 → Opus 5.5)
- **Issue:** none (lot tracked in `docs/LOTS.md`; audit item NET-13 in [A](../audit/A-network-sessions.md); old issue francoisgn/ios-app_SwiftHFR#75)
- **Depends on:** LOT-023 (`PrivateMessageBadgeParser`), LOT-045 (`PageFetcher`)

## Legacy sources
Legacy app: `master` of ezzz/HFRnow (same lines as francoisgn/hfrnow @ `2440d79`).

| Legacy | Replaced by |
|---|---|
| `HFRswift/Swift/MPBackgroundService.swift:70-107` (background check: GET `https://forum.hardware.fr` with a 5 s timeout, parse, compare with `nb_mp`, notify when higher) | `MPUnreadPoll.unreadCount()` is the GET and the parse; the timeout is the transport's, the comparison, storage, notification and scheduling (`:36-37`, `earliestBeginDate` 60 s) stay in the app |
| `MPBackgroundService.swift:112-136` (`extractMPCount`, `class="cCatTopic red"`, first integer) | `PrivateMessageBadgeParser.unreadCount(in:)` (LOT-023) |
| `Classes/HFRplusAppDelegate.m:236-246` (foreground poll, same page and `cCatTopic red` regex) | same call |

## Behaviour
`MPUnreadPoll(session: HFRSession).unreadCount() async throws(MPUnreadPollError) -> Int?`, in `Packages/HFRKit/Sources/HFRClient/MPPoll/`.

1. One GET of the home page (`HFREndpoint.privateMessageCheck()`, `GET /` with the 5 s background timeout) with the account's cookies in a probe session (see "Session" below). It is the cheapest page
   that carries the entry (the legacy choice): a forum list header also does (P03f, R08-2) but needs a category and a longer page; the MP list has none.
2. `PrivateMessageBadgeParser.unreadCount(in:)` on the decoded text: a number, `0` for an entry without a number (R03), `nil` for no entry (R01).
3. Failures are typed: `MPUnreadPollError.network(NetworkError)` (offline, timeout, HTTP 4xx/5xx, cancellation) and `.page(ListPageFailure)`
   (`.maintenance`, `.malformed`).

**Contract for the app:** `nil` is "no information" (logged out, or a page without the entry), never "no unread": do not store it as 0, do not notify,
do not clear the session on it. To find out whether the session expired, call `SessionRefreshFlow` (LOT-044). A logged-in home whose markup changed also gives `nil`; the app cannot tell that drift from a logged-out page.
The app owns scheduling (`BGAppRefreshTask`, foreground timer), comparing with the last count and notifying (LESSONS 48).

**Session:** a logged-in `GET /` sets `md_user` x2 and `md_passs` x2 (R02, R03 metas), which `HFRSession.perform` would store. The poll
therefore snapshots `account.cookies()` into an ephemeral probe `HFRSession`, sends there, and writes nothing back: a poll that started before a login
(LOT-043) or refresh (LOT-044) cannot overwrite the cookies they installed. The account session is only read. Cookie refresh is LOT-044's job.

**No flag is marked read:** the only request is `GET /` (a home page with no topic). HFR marks flags read on an authenticated topic page (HFR-PROTOCOL §7,
E25), which the poll never requests; the cookie-less transport is not used. The test asserts one request, to `/`, through the probe only.

## Edge cases
- A page of another kind served at `/` (a redirect to a login page, an MP list): `nil`, since the parser answers by `<body id>` (R13a, R20 tested).
- Maintenance page: `.page(.maintenance)`, not `nil`, so a poll cannot read it as logged out.
- A status of 400 or more is thrown by the fetcher before parsing (a 500 page holding a valid body is not read).
- A task cancelled before the call sends nothing (`.network(.cancelled)`).

## Fixtures
None added. Existing captures read in place (`Tests/HFRClientTests/Support/Capture.swift`) and the LOT-002 oracle's `sideEffects.nbMP`:
`R01` (home logged out → nil), `R02` (10), `R03` (0), `R13a` (MP list) and `R20` (topic page) for pages without the entry.

**Oracle coverage:** the poll's result on R01-R03 equals the legacy oracle's `nbMP` (`MPUnreadPollTests.homePages`), so there is no difference from the oracle; D1 below is a difference from `MPBackgroundService`'s regex, which the oracle does not run.

**Pending capture:** the home page served to a logged-in session whose cookies have expired (does HFR serve the logged-out home, or a `.hop` page?);
until captured, the poll says `nil` in both cases (a `.hop` page has no `<body id>` home, so it also reads as `nil`). Added to the capture backlog.

## Intentional differences from legacy
| # | Legacy | Port | Why |
|---|---|---|---|
| D1 | no `cCatTopic red` node (nothing unread) returned nil, same as a failure | `0` for "entry without a number", `nil` for "no entry" (LOT-023 D2) | the caller can tell "none unread" from "not logged in" |
| D2 | network errors printed and swallowed | typed `MPUnreadPollError` | the app counts failures and decides |
| D3 | `URLSession.shared` and the shared cookie jar | a probe seeded from the account's `HFRSession`, never written back | one session per account, no stale write |
| D4 | 5 s timeout (`MPBackgroundService.swift:86`) | kept: `HFREndpoint.privateMessageCheck()` (`RequestTimeout.background`), not the 30 s page default | a background task must not hang |

## Learnings
To copy into AGENTS.md §11 when the lot closes:

- The MP poll is one `GET /` with the account's cookies in a probe session, written back nowhere; its `nil` means "no information", never 0 or "expired" (confirm with `SessionRefreshFlow`).
