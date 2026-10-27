# LOT-025 — Small parsers (search redirect, profile edit page, smiley search and wiki)

- **Module:** HFRParsing
- **Difficulty / model:** easy (Sonnet → Opus)
- **Issue:** none (lot tracked in `docs/LOTS.md`)

First parsers tested on **real captured pages** (LOT-001 corpus). The oracle exporters (LOT-002..004) are not merged, so the
expected values come from what the captured HTML shows and from the legacy code (cited `file:line`).

## Legacy sources

Legacy repository <https://github.com/francoisgn/hfrnow> at `2440d79`. Audit: [B8](../audit/B-list-parsing-models.md), [D §3.1](../audit/D-posting.md), D9.

| Legacy | Replaced by |
|---|---|
| `Classes/ObjCForumSearchWorker.m:46-55, 305-321` (`forumSearchRedirectURLFromHTML:`: regex over `<meta … refresh …>`, `&amp;` → `&`, no match = "Aucune page de résultats") | `SearchRedirectParser.redirectURL(in:)` |
| `HFRswift/Swift/LoginService.swift:87-113` (`hash_check` regex, avatar regex on `profilCase3`) | `ProfileEditPageParser.parse(_:)` |
| `HFRswift/Swift/SmileySearchService.swift:62-88` (`<img>` regexes), `Classes/SmileyViewController.m:893-910` | `SmileySearchParser.parse(_:)` |
| `Classes/SmileyViewController.m:902-925` (`keywords0` split on spaces) | `SmileyWikiDetailParser.parse(_:)` |

## Behaviour

All functions are pure, `throws(ParsingError)`, go through `HTMLDocumentLoader` (`SwiftSoup.parseHTML`) and never expose SwiftSoup.

- **`SearchRedirectParser.redirectURL(in:) -> URL`** (capture `R50a`): first `<meta http-equiv="refresh">` (name and value compared
  case-insensitively) whose `content` is `<delay>;url=<target>` (`,` separator and quoted target accepted, as HTML does). The target is
  resolved with `HFRURL.absolute` (`&amp;` decoded, relative to the forum root). It must be **`https` on `forum.hardware.fr`**
  (the URL is requested with the search session): another scheme or host is `invalidValue`; `http://forum.hardware.fr:80/…` (explicit port, not upgraded) is refused, `https://forum.hardware.fr:443/…` accepted. No refresh meta with a target is
  `missingElement` (legacy: "no result page"). Models: returns a `URL`; B8's `Result<…, ListPageFailure>` is not used because the other
  parsers of this module throw `ParsingError` (the caller maps `missingElement` to the "no result page" message).
- **`ProfileEditPageParser.parse(_:) -> ProfileEditPage`** (`R55-p1`, `p3`, `p5`): `hashCheck` = first non-empty value of
  `input[name=hash_check]` (empty on all = `invalidValue`, none = `missingElement`); `avatarURL` = first `<img src>` in the `profilCase3` cell
  of the `tr.profil` whose `profilCase2` label starts with "Avatar", through `HFRURL.absolute`, else nil. Page 1 and 3 need no extra
  fields: they hold the same token, and the posts-per-page setting `topicpp` is LOT-044's.
- **`SmileySearchParser.parse(_:) -> [ForumSmiley]`** (`R53a-c`): every `<img>` whose `alt` is a smiley code (`[:…]`) and an `https`/`http` `src`, in served
  order, duplicates kept. The text "aucune réponse" without a smiley gives `[]`; neither gives `missingElement` (an error page must not look like "no match").
- **`SmileyWikiDetailParser.parse(_:) -> SmileyWikiDetail`** (`R54`): `code` = `input[name=smiley0]`, `keywords` = `input[name=keywords0]` split on
  whitespace and commas, `imageURL` = the `<img>` next to `smiley0`. The contribution history lines (member, date, keywords) are not parsed.

## Edge cases

Redirect: other `<meta http-equiv>` first (Pragma, Cache-Control, Expires), `URL=` in upper case, refresh without target, `javascript:`, `//evil.example`,
`user@host` tricks, `http` upgrade. Avatar: image of another row must not be taken, `javascript:` source. Smileys: raw space/apostrophe in the path,
missing `alt`/`src`, relative `src`. Wiki: extra spaces, empty keywords, missing inputs.

## Fixtures

Shared corpus only, no new file: `R50a`, `R50b`/`R50c` (results pages, no refresh), `R53a` (40-byte text), `R53b` (657 smileys), `R53c` (1010, one repeated), `R54`,
`R55-p1`, `R55-p3`, `R55-p5`, `R55-p5u1` (logged in as user1, **with an avatar**). Test helpers `Support/Fixture.swift` and `Support/Lot005Oracle.swift` (both also added identically by LOT-026).

## Differential tests (ADR 0004)

`Search/SmallParsersOracleTests.swift` compares the full result of each parser with the LOT-005 oracles (`Fixtures/LOT-005`, spec [LOT-005](LOT-005-small-parsers-oracle.md)):
R50a/b/c (redirect found or not, absolute and relative URL, error code), R55-p1/p3/p5/p5u1 (token length, avatar), R53a/b/c (the whole list, code and URL, in order,
against both the live service and the legacy callback) and R54 (keywords against the ObjC step and the Swift copy, code). A guard test fails when
`oracle-map.json` gains a case of these kinds that the tests do not run.

## Not covered / gaps

- **AQ listing and RSS: not captured** (third-party host `aq.super-h.fr`, LOT-001 checklist row P08) and **left out**: no parser, no fixture.
- Smiley search with special characters, standard (non-personal) smileys and charset were not captured; all smileys of `R53b/c` are personal.
- Global search: only the waiting page and the results of a **no-result** search (`R50c`) exist; the POST answer for a search without any result is unknown.

## Intentional differences from legacy

Each is asserted by a test; the oracle agrees with the port everywhere else.

- **Redirect host and scheme**: the target must be `https` on `forum.hardware.fr`; legacy followed any URL. Not exercised by the captures (tests are synthetic).
- **Avatar (LOT-005 quirk Q1)**: legacy took the first `<img>` after any `profilCase3`. The oracle shows it fetched an icon (`aide.gif`) on R55-p1/p3 and a tracking
  pixel on R55-p5, and the real avatar only on R55-p5u1. The port reads the "Avatar" row only: `nil` on p1/p3/p5, the real URL on p5u1.
- **Token**: legacy accepted only a non-empty match; the port also skips an empty first token and takes the next non-empty one, and reports `invalidValue` when all are empty (legacy: `missingHash`).
- **Smiley alt filter**: legacy (live service and ObjC callback) kept every `<img>` with `src` and `alt` (the ObjC callback even crashed on a missing one, Q5); the port keeps only `alt="[:…]"`,
  so a full page served instead of the fragment is an error. Equal on R53a/b/c (every image there is a smiley).
- **Empty answer**: an answer with neither smiley nor the "no result" sentence throws; legacy returned `[]`.
- **Charset**: UTF-8 only (Q4: legacy decoded ISO-8859-1 and would garble non-ASCII codes); no capture has a non-ASCII code.
- **Keywords**: split on whitespace and commas like the shipped Swift copies; the ObjC step kept commas (Q6, comma removal discarded). All attribute entities are decoded (SwiftSoup), as the ObjC step did; the Swift copies decode six. R54 has neither commas nor entities.
- **Query encoding** (Q3) is a request matter (HFREndpoint), not covered here.

## Learnings

- The anonymous and logged-in captures share a `hash_check` value shape (`REDACTED` here); parsers must not validate the token's format.
