# LOT-053 — Smileys: search, wiki

- **Module:** HFRClient (`Sources/HFRClient/Smileys/`), plus the wiki request in HFRNetwork (`HFREndpoint.smileyWiki`, `PageFetcher.smileyWiki`)
- **Difficulty / model:** easy (Opus 5.5 author → Fable 5.1 reviewer; the plan routes Sonnet → Opus)
- **Issue:** [#79](https://github.com/ezzz/HFRnow/issues/79) (audit NET-12, `docs/audit/A-network-sessions.md:267`, D9; old issue francoisgn/ios-app_SwiftHFR#81)
- **Builds on:** LOT-025 (`SmileySearchParser`, `SmileyWikiDetailParser`), LOT-041 (`HFREndpoint.smileySearch`), LOT-045 (`PageFetcher`), LOT-042 (`HFRSession`, `AnonymousTransport`), LOT-047 (the probe-session pattern of `MPUnreadPoll`), all done.

## Legacy sources
ezzz/HFRnow at `2440d79` (an ancestor of `origin/master`).

| Legacy | What it gives this lot |
|---|---|
| `HFRswift/Swift/SmileySearchService.swift:17-23` | search URL, at least 3 characters after trimming (`:19`, `[]` otherwise), the value encoded with `urlQueryAllowed` minus `+&=` (`:38-42`) |
| `SmileySearchService.swift:25-35` | `URLSession.shared` (the shared cookie jar, so the account's cookies), answer decoded as Latin-1, then UTF-8 (`:32-34`), non-2xx = `[]` |
| `HFRswift/Swift/AnswerView.swift:1308-1326` | `smileySearchQuery`: words joined by a space, a leading `+` on each when "all keywords" is on (ported by LOT-041) |
| `Classes/SmileyViewController.m:873-879` | ObjC search: the same URL, the text encoded with `!*'();:@&=+$,/?%#[]` escaped |
| `Classes/SmileyAlertView.m:151-155` | wiki: `wikismilies.php?config=hfr.inc&detail=<code>`, the code encoded with `URLPathAllowedCharacterSet` (`:` left raw), redirects not followed, 2 s timeout |
| `SmileyAlertView.m:162-197`, `HFRswift/Swift/MessagesView.swift:3317-3319`, `AnswerView.swift:764` | wiki keywords (parsed by LOT-025), the Swift copies of the wiki URL |

## Behaviour

### `SmileyLookupFlow` (HFRClient)
`init(session:)`: the account's `HFRSession`, only read; `nil` when no account is logged in: the search probe then starts without cookies (a logged-out search is not captured, #360) and the wiki works the same.

- **`search(_:requireAll:) -> [ForumSmiley]`**: refuses a text under 3 characters once trimmed with `queryTooShort`, before anything is built or sent (legacy returned `[]`). Otherwise one GET of `HFREndpoint.smileySearch` (LOT-041), sent in an **ephemeral probe `HFRSession` seeded with the account's cookies** (`MPUnreadPoll`'s pattern; it keeps the account session's host policy, [#365](https://github.com/ezzz/HFRnow/issues/365)): the captures are logged in (`R53a`-`R53c`, user2) and legacy sent its cookies, but whatever the answer sets is written back nowhere. The answer is read by `SmileySearchParser`: smileys in the order served, duplicates kept (`R53c` serves one twice), `[]` for HFR's "no result" sentence (`R53a`, not an error).
- **`requireAll`** only shapes the request (each word sent with a `+`, LOT-041). What HFR does with `+` is not captured: the only two-word capture, `R53c`, was sent as `findsmilies=+chat+noir` (raw `+`, see below) and answered 1010 smileys against 657 for `chat` alone, so the words were OR-ed. The flow never filters the answer, so `requireAll` promises nothing about AND (tested: the `R53c` answer comes back whole).
- **`wiki(code:) -> SmileyWikiDetail`**: drops surrounding white space from the code, refuses a blank one with `invalidCode`, before any request. Otherwise one cookie-less GET (`AnonymousTransport`: `R54` was served logged out) of `HFREndpoint.smileyWiki(code:)`, read by `SmileyWikiDetailParser` (code, image, keywords split on whitespace and commas). An entry whose code is not the one asked for is `page(.invalidValue(field: "smiley0"))`.
- **Errors** (`SmileyLookupError`): `queryTooShort`, `invalidCode`, `network(NetworkError)` (offline, timeout, HTTP error, cancellation: a task cancelled before the request goes out sends nothing, `PageFetcher`; one cancelled during the exchange may already have sent it), `page(ParsingError)` (an answer with neither a smiley nor the "no result" sentence, or not the entry asked for). Nothing is retried.
- **Decoding**: `RawPage` decodes UTF-8 first (`TextDecoding`, Q-2); every capture is `text/html; charset=utf-8`.

### `HFREndpoint.smileyWiki(code:)` (HFRNetwork)
`GET /wikismilies.php?config=hfr.inc&detail=<code>`, the code percent-encoded like every query value (strict unreserved set): `[:user3]` → `%5B%3Auser3%5D`, exactly `R54`'s URL. `PageFetcher.smileyWiki(code:as:)` defaults to `.anonymous`.

## Requests sent and captured
| Call | Request sent | Captured request | Same answer? |
|---|---|---|---|
| `search("chat")` | `findsmilies=chat` | `R53b`: `findsmilies=+chat` | not captured (*pending*) |
| `search("chat noir")` | `findsmilies=chat%20noir` (= legacy live, LOT-005 oracle) | `R53c`: `findsmilies=+chat+noir` | not captured (*pending*) |
| `search("chat noir", requireAll: true)` | `findsmilies=%2Bchat%20%2Bnoir` (= legacy "all keywords") | none | not captured (*pending*) |
| `wiki(code: "[:user3]")` | `detail=%5B%3Auser3%5D` | `R54`: the same URL | yes |

The capture tool sent the search value with raw `+` (the protocol table's `+w1+w2` template); the flow sends LOT-041's encoding, which is legacy's (LOT-005 oracle `live.requests`). The differential test therefore feeds the captured answers to the flow and compares the result with the legacy oracle; the request is compared with the legacy one.

## Edge cases
- Inner spaces count towards the 3 characters (`"a b"` is sent), as legacy (`SmileySearchService.swift:18-19`).
- A full page served instead of the fragment (maintenance, a login wall) holds no `[:…]` image and no "no result" sentence: `page(.missingElement)`, never "no smiley".
- A wiki redirect is followed (cookie-less GET); legacy did not follow it (`SmileyAlertView.m:154`). No redirect is captured (`R54` answers 200 in place).
- **Pending capture** ([#360](https://github.com/ezzz/HFRnow/issues/360); never hand-built, LESSONS 35-36): a search sent as the flow sends it (`chat`, `chat%20noir`, `%2Bchat%20%2Bnoir`), a search with accents or special characters, a search returning standard (non-personal) smileys, a logged-out search, and the wiki page of an unknown code.

## Fixtures
| Fixture | Covers |
|---|---|
| `R53a` + `LOT-005/R53a.oracle.json` | no result: `[]`, the legacy live request `findsmilies=zzqxw` |
| `R53b` + oracle | 657 smileys, code and image URL in order, request `findsmilies=chat` |
| `R53c` + oracle | 1010 smileys, one served twice, request `findsmilies=chat%20noir`; `requireAll` returns it whole |
| `R54` + oracle, `R54.meta.json` | code `[:user3]`, keywords (the Swift copy's), the request equal to the captured URL, no cookie |

## Intentional differences from legacy
1. **Too short is an error** (`queryTooShort`), not `[]`: the app can tell "type more" from "no smiley".
2. **UTF-8 first** (Q-2): legacy decoded Latin-1 first (`:32-34`), which garbles UTF-8 pages; every capture is UTF-8.
3. **Wiki code fully encoded**: `:` is `%3A` as in `R54`; legacy left it raw (`URLPathAllowedCharacterSet`).
4. **No cookie written, no cookie on the wiki**: legacy sent both requests with the shared cookies (`SmileySearchService.swift:25`; the wiki's Swift copies `AnswerView.swift:775` and `MessagesView.swift:3317-3319` use `URLSession.shared`, the ObjC one ASIHTTPRequest's default jar, `SmileyAlertView.m:153`), and the jar stored whatever HFR set. Here the search probe writes nothing back (`R53a`-`R53c` set no cookie anyway: a removed risk, not an observed fault), and the wiki goes cookie-less, a choice that rests on `R54` alone: a logged-in wiki answer is not captured (#360).
5. **HTTP errors are errors**: legacy returned `[]` on a non-2xx search answer (`:26-29`).
6. **Wiki redirects followed, transport timeout**: legacy did not follow redirects and waited 2 s (`SmileyAlertView.m:154-155`); a cookie-less GET may follow one safely.

## Tests
`SmileyLookupFlowTests` (the three searches against the LOT-005 oracles and their live requests, `requireAll` against `R53c`, too-short texts sending nothing, the probe seeded with exactly the account's cookies, a stateful probe whose cookies never reach the account (LOT-047's test), no account, the wiki against `R54` and its captured URL on the cookie-less transport, a padded code, another smiley's entry, a blank code, an unreadable page, network failures, cancellation) and `HFREndpointLookupTests.smileyWiki` (`R54`'s encoding, a folder suffix, a space, an apostrophe, a standard code, blank codes). Eleven mutations, each applied and reverted, each failed named tests: no length check, the wiki through the probe, the search without cookies, no code check, a blank code sent, `requireAll` dropped, duplicates removed, `:` left raw, and after review: the wiki code compared untrimmed, the endpoint sending it untrimmed, the probe seeded with nothing.

## Learnings
- A capture's request can differ from the one the code sends (here raw `+` against `%20`/`%2B`): compare the answer with the oracle and the request with the legacy one, and list the request the code really sends as pending capture.
