# LOT-033 — Topic page metadata

- **Module:** HFRParsing
- **Difficulty / model:** medium (Sonnet → Opus)
- **Issue:** none (lot tracked in `docs/LOTS.md`; audit item C06 in [C](../audit/C-message-parsing.md))

Reads the page-level data of a topic page or private conversation. The messages are LOT-030 (and following), the poll is
[LOT-026](LOT-026-poll-parser.md); this lot reads neither. The caller (LOT-034/`HFRClient`) assembles `TopicPage` (LOT-011)
from this value, the messages and the poll.

## Legacy sources
Legacy repository <https://github.com/francoisgn/hfrnow> at `2440d79`. Oracle: [LOT-003](LOT-003-topic-oracle.md), `result.page` and `result.parser`.

| Legacy | Replaced by |
|---|---|
| `Classes/ObjCTopicPageWorker.m:148-164` (`parseMetadataFromBody:parser:`: `hop` hidden inputs, `repondre_form` link, `nonlu`, `.sondage` presence) | `TopicPageMetadataParser` |
| `Classes/ObjCTopicPageWorker.m:166-179` (`searchInputDataFromBody:`, form `/transsearch.php`) | `searchFormFields` |
| `HFRswift/Wrapped/ParseMessagesOperation.m:488-507` (title `h3` of `fondForum2Title`, last child of `.left` in `fondForum2PagesHaut`) | `title`, `maxPage` |
| `Classes/ObjCTopicPageWorker.m:14-43,119-121,139-146` (page from the effective URL, `MAX(…, 1)`, answer URL made absolute) | `currentPage` (via `HFRURL.page(in:)`), `maxPage`, `answerFormURL` |
| `Common.swift:1814-1819` (Swift trims the title) | `title` |

## Behaviour

`TopicPageMetadataParser.parse(html:pageURL:) throws(ParsingError) -> TopicPageMetadata`: a pure function. `pageURL` is the URL the
page was finally served from (after redirects; the page fetchers return it as `finalURL`, LOT-045).

| Field | Rule |
|---|---|
| `title` | text of the first `h3` inside the first element whose `class` contains `fondForum2Title`, trimmed; `""` when absent |
| `currentPage` | `HFRURL.page(in: pageURL)`, else 1. From the URL only, never from the page, and **not clamped** to `maxPage` (legacy Q18) |
| `maxPage` | highest integer among the child elements of the first `class="left"` inside the first `fondForum2PagesHaut` element; 1 when the block is absent (single page) |
| `answerFormURL` | `href` of the first `a` inside `id="repondre_form"`, absolute; nil when absent, or when it is not `https://forum.hardware.fr` (the URL is requested with the session, LESSONS 37) |
| `answerFormFields` | for the first element named `hop`, every descendant whose `type` contains `hidden` and that has both `name` and `value` (an empty value counts); a repeated name keeps the last value; `[:]` without the form. Contains `hash_check` |
| `isUnreadable` | any element with an `href` containing `nonlu` |
| `hasPoll` | an element with `class="sondage"` (the whole attribute) exists. A poll shape is read by `PollParser`; a thrown `PollParser` error means "poll unavailable" for the caller, never a failed page (LOT-026 "Callers") |
| `searchFormFields` | for the first element whose `action` is `/transsearch.php`: its `input`s named `hash_check, p, post, cat, firstnum, currentnum, word, spseudo, filter` that have a `value`; a checkbox only when `checked`; nil without the form |
| `topicID` | `cat` + `post` of `answerFormFields`, else of `searchFormFields`, else of the `pageURL` query (`cat=`, `post=`); nil if none has both |

`TopicPageMetadata` is `Sendable`/`Hashable`, deliberately not `Codable`; `description`, `debugDescription` and `customMirror` print
counts, never values (`hash_check`), like `TopicPage`.

Errors: only `malformedDocument` (backend failure). Missing pieces are absent values: a conversation deleted by its owner (`RA5`) is a
valid page with nothing in it, and a page that is not a topic at all (login page, error) gives an empty value; deciding that this is
a failure is the job of the layer that also sees the messages (LOT-030: no `messagetable`).

## Edge cases
- Logged out and locked look the same: neither has `repondre_form` or `hop` (R20 vs R31). `answerFormURL == nil` means "cannot answer
  here"; the reason comes from the session, not from this page.
- A conversation whose owner deleted it (recipient view, `RU2`) has no reply form but still has the search form: `topicID` comes from
  there and from the URL, not from `hop` (LOT-003 RC3.4: legacy `isPrivateCategory`/`canAQ` were wrong on this page).
- Anonymous pages have no `hop`; their search form carries an empty `hash_check` and gives `cat` and `post`.
- A page beyond the last one is redirected by HFR to the last page (R24); with the final URL `currentPage == maxPage`.
  A client that keeps the requested URL gets `currentPage > maxPage`; callers clamp if they need to.

## Fixtures
Captures (`Fixtures/captures/`) with their oracles (`Fixtures/LOT-003/`), all 20, compared field by field in
`TopicPageMetadataOracleTests` (the first test fails when `oracle-map.json` gains a case that is not in the list):

| Ids | Covers |
|---|---|
| R20, R22a, R22b, R24, R26, R27, R28 | anonymous: first, middle, last and redirected pages, pager with ellipsis, long titles with brackets and quotes |
| R21, R32b | logged in (`user2`): answer form, 17 hidden fields, search form |
| R23, R27b | single page topics (no pager block) |
| R31 | locked topic (visitor view) |
| R32a, R32b | poll presence |
| RA1–RA4, RU1 | private conversation: `nonlu`, `cat=prive` |
| RU2 | recipient view after the owner's delete: no reply form |
| RA5 | conversation deleted by its owner: no title, no forms |

`TopicPageMetadataParserTests` adds expectations written from reading the captures (not from the oracle) and a few small inline
pages for parser rules that no capture exercises (foreign answer link, trailing text in the pager, duplicated hidden names, checked
checkbox). Those inline pages state our parsing rules, not facts about HFR.

Pending capture (no fixture, nothing hand-built): a topic page with a **checked** `filter` box in the search form (search result page
of `transsearch.php`; R52a is a 302 without body), a **locked topic seen by a logged-in account** (does it keep `hop`?), a
**favourite/flagged** topic as seen logged in (`delflag` links), a pager whose current page sits between two ellipses with a trailing
text node, a poll **results** page (R33, LOT-026).

## Intentional differences from legacy
1. **`maxPage` is the highest number of the pager, not the number in its last child.** Same value on all 20 oracles; a trailing node that
   is not a number (legacy: `intValue` of text = 0, so `maxPage` 1) no longer resets the pager.
2. **Title whitespace** is HTML-normalised (`Element.text()` collapses runs of spaces and newlines); legacy used the raw text content.
   Identical on the 20 captures.
3. **The answer URL is restricted to `https://forum.hardware.fr`.** Legacy prefixed any value not starting with `http` with the forum URL
   and accepted any `http…` link, including another host and clear `http`.
4. **A checked checkbox is any `checked` attribute and the `type` is case-insensitive** (HTML semantics); legacy compared both as exact text.
5. **No topic flag state** (`delflag`, red flag): legacy does not read it in the live path either (C §1.2); `isUnreadable` stays the
   only flag-related field, and it is not a "cannot be favourite" rule (LOT-003 RC3.3): that is app policy.
6. **`topicID` is new**: legacy had the category from `hop` only (RC3.4); here the search form and the page URL are fallbacks.
7. **`hasPoll` only.** Legacy's `isNewVote` (a poll `input` exists) is a poll-parser concern; `PollParser` returns the votable or results kind.
8. Typed values instead of `NSDictionary`; `[:]` and nil are distinct for the search form (legacy: always a dictionary).

## Learnings
To copy into AGENTS.md §11 when the lot closes.

- A table row (`<tr>`) written outside a `<table>` in a test page is dropped by the HTML parser, as in browsers: wrap inline test pages.
- Differential tests that read the oracle's page object need only `Fixtures/LOT-003` and the capture; the case list in the test is
  checked against `oracle-map.json` so a new oracle cannot be forgotten.
