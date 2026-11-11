# LOT-055 — AQ client

- **Module:** HFRClient
- **Difficulty / model:** easy · Opus → Fable (author → reviewer)
- **Issue:** [#81](https://github.com/ezzz/HFRnow/issues/81). Depends on [LOT-028](LOT-028-aq-parsers.md) (#56, parsers) and
  [LOT-071](LOT-071-third-party-services.md) (#95, rules R1–R6, inventory T1–T3).

Implemented: `AQClient`, `AQConfiguration`, `AQError` (`Sources/HFRClient/AQ/`). **Create is not implemented** (the PR is `Refs #81`);
its answer is captured since (`T50`, `T51`, [#531](https://github.com/ezzz/HFRnow/issues/531)) and left to a follow-up.

## Legacy sources
ezzz/HFRnow @ `2440d79`, `HFRswift/Swift/`:

| Part | Legacy |
|---|---|
| Feed + badge | `AQPlusView.swift:39` (`https://aq.super-h.fr/rss.php`), `:41-50` (`last_check_aq`, default 2010-01-01), `:52-57` (category-25 filter), `:60-92` (`AQBadgeCheckService`: GET, 20 s, cache ignored, `URLSession.shared`, count of `isNew`, stale-check guard `:86`), `:202-204` (`isNew = aqDate >= lastCheck`, unreadable date = now), `:248-322` (list view model, `:278` 20 s, sets `last_check_aq` on display) |
| Launch trigger | `MainWindow.swift:1178-1192` (3 s after the main window, once per process, logged out too) |
| Per-topic check | `MessagesView.swift:325-338` (`isAQAlreadySignaled`, URL `:327`: GET `…/api/getAlertesByTopic.php?topic_id=`, `URLSession.shared`, default timeout, `content.contains(postID)`, nil on error), called at `:2001`, `:3716` |
| Create (not ported) | `MessagesView.swift:340-376` (`createAQ`: POST `…/api/addAlerte.php`, 5 s, form content type, ASCII body (lossless: percent-encoded first), `"1"` = success), `:378-398` (`aqRequestBody`, fixed field order), `:434-437` (`legacyPercentEncode`), `:439-441` (pseudo lower-cased); toasts `:2038-2043` |

## Behaviour
Inputs: `AQConfiguration(baseURL:)` (R2: the app injects it; the legacy value is `https://aq.super-h.fr`, configuration name
`AQBaseURL`, set by the app lots LOT-133/LOT-134), a transport (default `AnonymousTransport`).

| API | Request | Result |
|---|---|---|
| `feed()` | GET `<base>/rss.php` | `[AQFeedItem]` from `AQFeedParser`, document order, **every category** (hiding 25 is app policy, Q-7) |
| `alerts(topicID:)` | GET `<base>/api/getAlertesByTopic.php?topic_id=<n>` | `[AQAlert]` from `AQAlertListParser`, newest first |
| `isReported(postID:topicID:)` | same GET | `AQAlertListParser.isReported` (whole-number match) |
| `AQClient.newCount(in:since:)`, `isNew(_:since:)` | none | "new since" badge: `publishedAt >= lastCheck` |

Rules:
- Every request: GET, no body, timeout 20 s (legacy feed), body capped at 1 MiB (`T01` is 31 KB, `T02` 13 KB),
  `redirectPolicy: .doNotFollow`. A 3xx is `AQError.redirected`, a 4xx/5xx `AQError.http`, a transport failure `AQError.network`,
  a body that is not the expected document `AQError.invalidResponse` (never an empty list: legacy's `nil` meant "unknown").
- **Host**: URLs are built from the configured base only; redirects are never followed, so no request leaves that host.
  `AQConfiguration` accepts `https` (both captures are https) or `http` on loopback (tests), no userinfo, query or fragment, and
  refuses `hardware.fr` and its subdomains: AQ is a third party.
- **No forum cookie (R1)**: the default transport is `AnonymousTransport` (cookie storage off, `Cookie` header dropped); the client never
  sets a `Cookie` header. Tested on the policy itself (default transport type, cookie-less configuration), with no network path (LESSONS 56).
- **"New since"**: the date comes from the caller (the app stores the last check, LOT-133). The app filters a hidden category
  **before** counting, as legacy did. The legacy stale-check guard (`AQPlusView.swift:86`: drop the count if the list was viewed during the
  fetch) is app logic (LOT-133).
- Launch timing (3 s, once per process) and the first-use notice are app logic (LOT-133, LOT-134, LOT-183).

## Edge cases
- Topic number ≤ 0: `invalidTopicID`, no request.
- The listing served on the feed URL (or the reverse): `invalidResponse`.
- A base URL with a path (`https://host/sub/`) keeps it (`/sub/rss.php`).

## Fixtures
`T01` (`rss.php`) and `T02` (`getAlertesByTopic.php?topic_id=8680`) of the LOT-001 corpus (run 10, #133), served by a
`MockTransport` with their captured content types; the newness oracle is `Fixtures/LOT-028/T01.oracle.json` (legacy `isNew`,
last check 2026-10-01, `newCount` 2).

Captured since: the create's success on the live host (`T50`, `T51`, [#531](https://github.com/ezzz/HFRnow/issues/531)) and its refusals on a
local instance (`T52`-`T71`, #574; `T72`-`T90`, #611: values the database refuses, by `sql_mode`); the server's own contract (secondary source, ADR 0015) is in HFR-PROTOCOL §8.

## Create
`AQClient.create(_ report: AQNewReport) async throws(AQCreateError)` (`AQCreateError.swift`, `AQReportEncoder.swift`). Wire facts: POST
`<base>/api/addAlerte.php`, form body (`FormBody`, UTF-8 percent-encoded: accents verified, `T75`) in the legacy order
`alerte_qualitay_id`, `nom`, `topic_id`, `topic_titre`, `pseudo` (lower-cased as legacy, `MessagesView.swift:439-441`), `post_id`, `post_url`,
`commentaire`, then `from=SwiftHFR` (decided, #573); 5 s (legacy); no cookie (anonymous transport); redirect not followed; answer read up to 4 KiB.
An addition (`existingAlertID` set) sends `alerte_qualitay_id`, `pseudo`, `post_id`, `post_url`, `commentaire`, `from` only (the server ignores
`nom` / `topic_*` then, `T84`, `T85`; fewer fields to a third party).
- **Success** only status 200 with the trimmed body `1` (`T50`, `T51`).
- **`unconfirmed`** for everything else: a redirect, a transport failure (the POST may have left; never retried), any other status or body.
  `unrecognizedAnswer` carries the status and a bare numeric body (`-2`, `-3`, `-4`: seen on a local instance only, `T52`-`T61`) so the app
  may word a message, but none is read as a refusal: refusals are not captured on the live host, some of them ban the client, and an empty
  200 or a 403 is "maybe banned" (`T67`, `T68`). The caller checks `alerts(topicID:)` before offering a retry.
- **Validated before sending** (`invalidReport`, no request): required text (`nom`, `topic_titre` for a new AQ; `pseudo`, `post_url`) not blank
  and not `0` (PHP `empty()`); `nom` / `topic_titre` / `post_url` ≤ 512, `pseudo` ≤ 128, `commentaire` ≤ 1024 characters (scalars); no
  character outside the BMP; ids positive and ≤ `int(11)`; `post_url` starts with `https://forum.hardware.fr` (else a 403). Source: HFR-PROTOCOL
  §6c "Values the database refuses" (`T72`-`T90`, #611): the live `sql_mode` is unknown, so a value either mode would refuse or change is refused here.
- A task cancelled before the request is handed to the network is `AQCreateError.cancelled` (nothing sent), not `unconfirmed`.
- The N1 notice before the first create, and one create at a time, are app logic (LOT-134).

## Intentional differences from legacy
- **Create** (`MessagesView.swift:340-376` @ 2440d79): a non-`1` answer was shown to the user as a refusal code; it is now `unconfirmed`
  (refusals are not captured on the live host). Values the database refuses or silently changes (over-long, outside the BMP, ids out of
  range) were sent; they are refused before sending (#611). The body is UTF-8 (legacy: lossy ASCII, accents lost), carries `from=SwiftHFR`
  (#573), and an addition omits `nom` / `topic_*`.
- An item with an unreadable date is **not** new. Legacy dated it "now" (`AQPlusView.swift:203`), so it was new on every check and the
  badge never cleared. No such item in `T01`.
- Redirects are not followed. Legacy used `URLSession.shared`, whose jar holds the `.hardware.fr` cookies: it never sent them to the AQ host
  (cookies are scoped by domain), but an AQ answer redirecting to a forum URL was followed with the session (R1). Requests now go through
  the cookie-less transport and stop at the AQ host.
- A failed check is an error, not `nil` (same meaning, typed); a non-listing body is an error instead of "not reported".
- The check timeout is 20 s (legacy: `URLSession` default, 60 s).

## Tests (create)
`AQCreateTests` (8 tests, 18 cases with `AQClientTests`): `T50`'s answer is a success with the exact request (URL, POST, field order, `from`,
no `Cookie`, `doNotFollow`, 5 s); addition fields; 8 non-confirming answers (empty, `11`, `-1`, `-4`, page, 403, 201, 500) are `unconfirmed`;
numeric code carried only when bare; redirect and timeout unconfirmed with one request; 11 invalid reports refused with no request; the
1024-character boundary and the permalink rule. Mutations checked to fail: any 200 accepted, permalink check removed, BMP check removed.

## Tests
`Tests/HFRClientTests/AQ/AQClientTests.swift` (10 tests): requests (URL, method, no body, no `Cookie`, `doNotFollow`, timeout, cap),
`T01` 25 items with categories, newness against the oracle, inclusive boundary and undated items, `T02` check (whole numbers),
invalid topic before any request, redirects (5 codes), 4xx, offline, HTML and swapped document, base URL rules, default transport.
Mutations checked to fail: follow redirects, undated = new, `>` boundary, 3xx accepted, forum host accepted, topic guard removed,
default transport replaced.

## Learnings
To copy into AGENTS.md §11 when the lot closes.
- A third-party write whose answer is not captured ships as a capture issue, not as code that guesses the confirmation.
