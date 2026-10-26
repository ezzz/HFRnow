# LOT-040 — HFRNetwork transport

- **Module:** HFRNetwork
- **Difficulty / model:** easy (Sonnet 5.5 → Opus 5.5)
- **Issue:** none (claimed in PR #16)

## Legacy sources
Audit [A](../audit/A-network-sessions.md) §3.2–3.5 and lot NET-01 / NET-14; legacy repo <https://github.com/francoisgn/hfrnow>.

| Concern | Legacy |
|---|---|
| Form encoding with `alphanumericCharacterSet` (accent bug) | `ObjCForumSearchWorker.m:176, 194-199` |
| UTF-8 charset on form requests | `LoginService.swift:61`, `Favorites.swift:74`, `ReplyService.swift:177` |
| Response decoding, invalid bytes dropped | `ASIHTTPRequest+Tools.m:19-37` (`safeResponseData`), `ObjCTopicPageWorker.m:89` |
| UTF-8 then Latin-1 / CP1252 fallbacks | `LoginService.swift:136-141`, `AnswerView.swift:786`, `MessagesView.swift:3341`, `UserProfileView.swift:127-130` |
| Redirects followed, final URL read | `ASIHTTPRequest.m:290`, `ObjCTopicPageWorker.m:94` |
| Redirects disabled, `Location` read | `ObjCTopicSearchWorker.m:33, 39-52` |
| Status code ignored | audit A §3.4 (only `SmileySearchService.swift:26-29`, `Favorites.swift:80-82` check it) |
| Timeouts 30 / 60 / 15 / 5 s | `Constants.h:70-72`, `ObjCTopicSearchWorker.m:34`, `ObjCForumSearchWorker.m:8, 131-140`, `MPBackgroundService.swift:86` |

## Behaviour
All in `Packages/HFRKit/Sources/HFRNetwork/Transport/`.

- `HTTPTransport.perform(_:)` returns the raw answer for any status; `send(_:)` (protocol extension, the call sites use this one) additionally throws `NetworkError.httpStatus(code:url:)` for 4xx/5xx. 3xx is returned, so `RedirectPolicy.doNotFollow` works.
- `HTTPRequest` / `HTTPResponse` / `HTTPHeaders` are plain `Sendable` values; headers are case-insensitive and names are trimmed (` Cookie` is `cookie`, LOT-042). `HTTPResponse.url` is the **final** URL after followed redirects; `redirectLocation` resolves a relative `Location` (HFR sends relative ones, HFR-PROTOCOL §6).
- `URLSessionTransport`: wraps an injectable `URLSession` (LOT-042 passes one per account). Default session is ephemeral and cookie-less. No retry of any request (POST replay is dangerous, redface2 E29), no TLS delegate (system trust only).
- Redirects: `.follow` is the default. `.doNotFollow` uses a second session built from the same configuration (same cookie storage) with a session delegate refusing redirects, because swift-corelibs-foundation ignores per-task delegates.
- Timeout: `HTTPRequest.timeout` is a **total** limit enforced by the transport on every platform (corelibs ignores `timeoutInterval`); presets in `RequestTimeout` (30 / 60 / 15 / 5 s).
- `FormBody`: ordered fields; `A-Za-z0-9*-._` literal, space `+`, every other UTF-8 byte `%XX` uppercase; content type `application/x-www-form-urlencoded; charset=utf-8`. Line breaks: `.preserve` (default) or `.crlf` (browser behaviour); whether HFR needs CRLF is open (HFR-PROTOCOL §7, X11), the posting lots choose.
- `TextDecoding.decode`: charset from `Content-Type`, else `<meta charset>` in the first 2 KiB, else UTF-8. Declared ISO-8859-1 / Windows-1252 / ASCII → Windows-1252 (as browsers). UTF-8 failing validation: if the text still holds valid multi-byte sequences keep UTF-8 with U+FFFD for bad bytes (`utf8Lossy`), else treat as Windows-1252. Never throws; `DecodedText.encoding` says what happened.
- `NetworkError`: `invalidRequest`, `httpStatus`, `timedOut`, `offline`, `cancelled`, `invalidResponse`, `transport(code:)`, `unscripted` (mock). Task cancellation surfaces as `NetworkError.cancelled`. Errors never contain bodies, cookies or query strings; nothing is logged.
- `MockTransport` (actor, public, in the module): scripted FIFO replies or a handler closure; records requests. It lives in `HFRNetwork` rather than a test-support target so `HFRClientTests` and previews can use it without a new product or `Package.swift` change; the cost is ~50 lines in the shipped module. It does not simulate redirects: script the final `HTTPResponse.url`.

## Edge cases
- Non-HTTP(S) URL → `invalidRequest`, nothing sent.
- Bad bytes in a UTF-8 page keep the accents of the rest (no whole-page mojibake).
- 3xx without `Location` → `redirectLocation == nil` (intra-topic search: "no result").
- Out of scope: emoji / non-BMP filtering on posted text (Q-3, posting lots), `Set-Cookie` handling (LOT-042), endpoints (LOT-041), `https → http` redirect refusal and the cookie-less image client (LOT-045).

## Fixtures
None. HTTP behaviour is tested against an in-process loopback server (`LoopbackServer`, 127.0.0.1, real sockets) because corelibs `URLProtocol` cannot simulate redirects; no external network.

## Intentional differences from legacy
- HTTP status is checked (legacy fed 4xx/5xx pages to parsers).
- Accents and all non-ASCII are percent-encoded as UTF-8 (legacy sent raw bytes in global search).
- No TLS bypass, no global timeout state (legacy mutated `ASIHTTPRequest` class-level defaults), no global cookie jar by default.
- Cancellation is an error value, not a silently dropped completion.

## Learnings
- swift-corelibs-foundation: `URLProtocol` cannot redirect, per-task delegates passed to `data(for:delegate:)` are ignored for redirects, and `timeoutInterval` is not honoured. Test the real transport against a loopback socket server and enforce deadlines in our code.
