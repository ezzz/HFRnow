# LOT-042 — Per-account session

- **Module:** HFRNetwork
- **Difficulty / model:** medium (Opus 5.5 → Fable)
- **Issue:** none (claimed by the orchestrator in `docs/LOTS.md`)
- **Depends on:** LOT-040 (transport, `URLSessionTransport(session:)`), LOT-013 (`StoredCookie`, HFRModels)

## Legacy sources
Audit [A](../audit/A-network-sessions.md) §4 and lot NET-03; audit [D](../audit/D-posting.md) §2.2; legacy repo <https://github.com/francoisgn/hfrnow>.

| Concern | Legacy |
|---|---|
| One process-wide jar (`HTTPCookieStorage.shared`) for every account | audit A §4.1; `AccountSessionService.swift:108`, `LoginService.swift:131-134` |
| Jar wiped and refilled on account switch and before every list load, `quotes*` cookies saved and restored around it | `MultisManager.m:155-165`, `AccountSessionService.swift:77-110`, `Common.swift:1402-1406` |
| `md_user` = identity, value `deleted` = logged out | `MultisManager.m:55, 231, 248, 261`, `AccountSessionService.swift:130`, `LoginService.swift:118` |
| Account cookies = jar cookies whose domain contains `hardware.fr` | `LoginService.swift:115-117` |
| `hash_check` stored per account, global fallback `appDelegate.hash_check` | `AccountSessionService.swift:93-104`, `MultisManager.m:63, 219` |
| Multi-quote cookie: name from `quoter()` arguments, `\|<numreponse>` markers, `.hardware.fr`, `/`, +1 h, deleted when empty, **substring** match | `MessagesView.swift:1852-1945` |
| Global search uses a cookie-less session | `ObjCForumSearchWorker.m:125-139` |

## Behaviour
All in `Packages/HFRKit/Sources/HFRNetwork/Session/`.

- **`HFRSession`** (actor, conforms to `HTTPTransport`): one per account. Owns a `URLSession` built from a fresh `URLSessionConfiguration.ephemeral`, whose private in-memory `HTTPCookieStorage` is the account's jar (accept policy `.always`, `httpShouldSetCookies`; no URL cache, no credential store). Requests go through `URLSessionTransport(session:)` (LOT-040), so they carry the jar's cookies and store the answer's `Set-Cookie`, including on the no-redirect path (same configuration, same jar). Two sessions never share a cookie; nothing touches `HTTPCookieStorage.shared`.
- **Hosts** (`SessionHostPolicy`): an `HFRSession` only sends to `http`/`https` URLs on `hardware.fr` or a subdomain; any other host is refused with `NetworkError.invalidRequest`, nothing sent. Chosen over filtering `cookies()`: with every request on the forum, the `.always` accept policy can only store cookies the forum sets (Foundation already rejects a `Set-Cookie` for another domain), and account cookies cannot be sent elsewhere by a caller mistake. Cookies the app imports are exported as given. A session-level redirect delegate refuses a redirect that leaves the forum or goes from HTTPS to HTTP: the 3xx answer is returned (`redirectLocation` set) and the caller decides, for example fetching an external target through `AnonymousTransport`.
- **Import / export** (no persistence here, LOT-065): `init(cookies:hashCheck:now:)`, `mergeCookies(_:now:)` (add or replace by `StoredCookie.jarKey`; an already-expired cookie deletes its match; returns how many were installed), `replaceCookies(with:now:)` (for LOT-043: called only after a login is validated), `removeAllCookies()`, `cookies(now:)` (every non-expired cookie, sorted by `jarKey`; session cookies included, as legacy archived them).
- **`StoredCookie` ↔ `HTTPCookie`**: `StoredCookie(_ cookie: HTTPCookie)` and `makeHTTPCookie()`. Name, value, domain (leading dot kept), path (empty → `/`), expiry (nil = session cookie; rounded to the second on the way back, because Darwin returns it with sub-second float noise), `Secure`, `HttpOnly` survive the round trip; `SameSite`, port, comment and version are dropped (HFR does not use them, audit A §4.1). Empty name or domain → nil.
- **Identity**: `userKey(now:)` = value of `md_user`; nil when absent, empty, expired or `deleted`. `isLoggedIn(now:)`. When the jar holds several `md_user` (different domain or path), a `deleted` one wins: it is the server's explicit logout.
- **`hash_check`**: `hashCheck` (read-only) and `updateHashCheck(_:)`; nil, empty or blank values are ignored and the previous token kept (a page without the hidden input must not erase it). Per session: no global fallback. `HFRClient` refreshes it from parse results (HFR-PROTOCOL §5).
- **Multi-quote**: `MultiQuoteCookie` (pure value) and, on the session, `multiQuote(for:now:)`, `isQuoteSelected(_:now:)`, `toggleQuote(_:now:)`, `clearQuotes(for:)`, all keyed by `QuoteSelectionToken` (LOT-011). Name `quotes<forum>-<cat>-<post>` (`cat` as its query value, `prive` for MP); value `|<numreponse>` repeated in selection order; domain `.hardware.fr`, path `/`, expiry one hour after each write; the cookie is deleted when the selection becomes empty. Markers compare **exactly**. An expired cookie reads as an empty selection.
- **Anonymous transport**: `AnonymousTransport` (wraps `URLSessionTransport`): ephemeral, no cookie storage, `httpShouldSetCookies = false`, accept policy `.never`, no cache or credential store, and an explicit `Cookie` header on the request is dropped, whatever its case or surrounding whitespace (`HTTPHeaders` trims names). For prefetch (an authenticated topic GET marks flags read, HFR-PROTOCOL §7 E25) and images (E26).
- Logging: none. `StoredCookie` descriptions hide the value (LOT-013); errors are the transport's `NetworkError`.

## Edge cases
- Cross-host redirect (Fable review of #27): swift-corelibs-foundation copies the request's `Cookie` header, injected from the jar, onto a followed redirect whatever its host, so following `forum.hardware.fr` → another host would leak the account cookies there (domain matching is not reapplied). Hence the redirect policy above; tested with a loopback redirect `127.0.0.1` → `localhost`, which without the policy is followed. The HTTPS → HTTP rule covers the corelibs behaviour of returning `Secure` cookies for `http` URLs.
- `.hardware.fr` and `hardware.fr` are one `jarKey` but two Foundation cookies: merging removes every match before setting, so one key never holds two values.
- An imported cookie with an empty path is treated as path `/` (what Foundation stores), so it replaces or deletes the `/` cookie of the same name and domain.
- A malformed import (empty name or domain) is skipped without deleting the existing cookie of the same key.
- Duplicated markers in a cookie written elsewhere (`|5|6|5`): unselecting removes every copy. Non-numeric markers are kept as written and ignored by `selectedNumbers`.
- Linux (swift-corelibs-foundation): `HTTPCookieStorage` has no public initializer, so the jar comes from `URLSessionConfiguration.ephemeral` (distinct per configuration, verified on Linux; the isolation test also runs on the macOS CI job); an `HTTPCookie` without `expires` reports `isSessionOnly == false`, so expiry is read from `expiresDate` only; a `Secure` cookie is also returned for `http` URLs (HFR is HTTPS-only, not relied on).

## Fixtures
None. Cookie handling is tested against the loopback server of LOT-040 (`LoopbackServer`, 127.0.0.1): two sessions receiving different `Set-Cookie` concurrently, imported cookies, `md_user=deleted` from the server, and the anonymous transport (with an authenticated session as positive control). Cookie values in tests are fake.

## Intentional differences from legacy
- One isolated jar per account instead of the global jar wiped on every switch (races with in-flight requests, audit A §4.4); `quotes*` cookies no longer need saving and restoring.
- Multi-quote ids match exactly: legacy `contains("|1")` saw `|12` as selecting 1, and `replacingOccurrences(of: "|1", with: "")` turned `|12|1` into `2`.
- `hash_check` has no global fallback that could belong to another account (`AccountSessionService.swift:93-98`).
- Exported cookies are not filtered by `domain.contains("hardware.fr")` (which would also match `evilhardware.fr`): the jar only ever talks to the forum, so it is exported whole.

## Learnings
- swift-corelibs-foundation has no public `HTTPCookieStorage()` initializer: an isolated jar comes from `URLSessionConfiguration.ephemeral.httpCookieStorage`.
- Darwin `HTTPCookie` does not return a far-future expiry (2031, 2033) as given; a one-day expiry comes back intact. The macOS CI job shows a 2033 expiry shortened but still more than 399 days ahead, consistent with the RFC 6265bis 400-day cap (`farFutureExpiryIsNeverExtended`). The app therefore gets back at most 400 days of lifetime for an imported cookie. Test cookie dates one day ahead, to the second. corelibs ignores `Max-Age`.
- Foundation keeps `.hardware.fr` and `hardware.fr` as distinct cookies while `StoredCookie.jarKey` merges them: de-duplicate by key before every write.
