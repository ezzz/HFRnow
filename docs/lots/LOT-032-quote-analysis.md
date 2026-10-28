# LOT-032 — Quote analysis (authors, nesting, cited messages)

- **Module:** HFRParsing
- **Difficulty / model:** medium (Sonnet → Opus)
- **Issue:** [#59](https://github.com/ezzz/HFRnow/issues/59) (old, frozen: francoisgn/ios-app_SwiftHFR#66; audit item C05)

Chain: LOT-003 (oracle) → LOT-030 (blocks) → LOT-034 (content) → **LOT-032**. Feeds `Message.quotes` (the `TopicPage` orchestration),
the quote engine (LOT-049) and "posts quoting me" (app-side, C10/C11).

## Legacy sources
Legacy repository <https://github.com/francoisgn/hfrnow> at `2440d79`.

| Legacy | Replaced by |
|---|---|
| `ParseMessagesOperation.m:191-194` (`oldcitation` → `citation`) | `table.oldcitation` and `table.citation` are the same kind of quote; the class is **not** rewritten (ADR 0006, LOT-034 difference 10) |
| `:196-203` (`.citation` blocks, header = first `class="Topic"` descendant, author = its text minus the last 10 characters when longer than 10) | `MessageQuote.author`: header text minus the `a écrit :` suffix, pseudo normalized |
| `:205-224` (own pseudo → `citation_me_quoted`, whitelist/blacklist classes, hidden block, `quoteIndex`) | **not ported**: policy, app-side (audit C 7.1, C10); the app compares `author` with `HFRText.pseudoComparisonKey` |
| (never computed) | `citedNumreponse` (the `#t<n>` of the header link), `depth`, anonymous quotes (`table.quote`) |

## Behaviour

### API

| Type | Members | Rules |
|---|---|---|
| `MessageQuoteAnalyzer` (public) | `quotes(inContentHTML: String) throws(ParsingError) -> [MessageQuote]` | Input: `MessageBlock.contentHTML` (raw) **or** `MessageContent.html` (LOT-034): both keep the quote classes, `a.Topic` and its link. Only a backend failure throws (`malformedDocument`); a message without quote gives `[]` |
| `MessageQuoteAnalyzer` (internal) | `quotes(in: Element) -> [MessageQuote]` | Same from `ExtractedMessageBlock.content`, for the `TopicPage` orchestration; the tree is read, never mutated |

The output is `MessageQuote` (LOT-011, unchanged): `author: String?`, `depth: Int`, `citedNumreponse: Int?`.

### Rules

| Item | Rule |
|---|---|
| Quote | A `table` with the class token `citation`, `oldcitation` (authored) or `quote` (anonymous). Tokens are matched whole (`citation_blacklist`, `quoted` are not quotes). `table.spoiler`, `table.code` and `table.fixed` are not quotes and do not add depth |
| Order | Document order: an outer quote comes before the quotes it contains |
| `depth` | 1 for a quote that has no quote ancestor, +1 per quote ancestor (anonymous ones count) |
| Header | Authored quotes only: the first `a` whose **whole** class attribute is `Topic` (legacy `allowPartial:NO`) that is inside the quote and whose closest quote ancestor is that quote. A nested quote's header is never lent to the outer one |
| `author` | Text of the header, U+00A0 read as a space, suffix `\s*a\s+écrit\s*:\s*$` removed, then `HFRText.normalizedPseudo` (U+200B removed, trimmed). `nil` when the header is missing, does not end with the suffix, or leaves an empty name (no guess: legacy cut 10 characters blindly) |
| `citedNumreponse` | The text after the **last** `#` of the header's `href` must be exactly `t<digits>` and fit an `Int`; anything else gives `nil` (`#bas`, `#t12x`, `#t-1`, no fragment, no `href`). The URL is never followed or resolved: only the number is read |
| Anonymous quote | `author` and `citedNumreponse` are `nil` (header `<b class="s1">Citation :</b>` has no link) |

The walk is iterative with an explicit stack: SwiftSoup's `select` and `parents()` are recursive and a first version using `parents()`
crashed the test thread at 500 nested tables; the version shipped is checked at 2 000.

## Edge cases

Checked on the captures, facts in HFR-PROTOCOL §6c "LOT-032":

- Corpus (20 oracles, 358 messages): 135 quotes = 126 `table.citation` + 9 `table.quote`; 132 at depth 1, 3 at depth 2. The only nested ones are an
  anonymous quote inside a citation, in message 27 of `R28`, `R32a` and `R32b`.
- Every authored header of the corpus is `<a href="/hfr/<cat>/<slug>-sujet_<topic>_<page>.htm#t<n>" class="Topic"><pseudo> a écrit :</a>`.
- `oldcitation` (`R33b`, not an oracle case): `<table class="oldcitation"><tr class="none"><td><b class="s1"><a href="/forum2.php?…&numreponse=0&quote_only=0&new=0&nojs=0#t<n>" class="Topic">`,
  `<hr size="1" />` after the header; 11 on the page, all read like `citation`.
- A spoiler inside a quote (`R27` message 10) is not a quote and adds no depth.
- Synthetic inline snippets (marked as such in the tests, **not** page states): depth 3, a header without suffix, an empty author, rejected
  fragments, class substrings, a header without `href`, 2 000 nested tables.

**Pending capture** (never hand-built; the orchestrator opens the capture issues):

- A **nested authored quote** (citation inside a citation): the corpus has depth 2 only as anonymous-in-authored. Depth ≥ 3 and the
  "own header" rule are covered by synthetic snippets only.
- A quote of a **deleted or unknown account**, whose header might not read `<pseudo> a écrit :` (audit C quirk 14, "unverified"), and a header
  link whose fragment is not `t<n>`.
- `oldcitation` on a **topic page of the public oracle** corpus (only `R33b`, a poll page, has it, with no legacy oracle output: the test checks
  count, author and cited number, not legacy equality).

## Fixtures

| Case | Covers here |
|---|---|
| All 20 topic oracles (`R20`–`R32b`, `RA1`–`RA5`, `RU1`, `RU2`) | 126 authored + 9 anonymous quotes, depth 1 and 2 |
| `R28`, `R32a`, `R32b` (message 27) | anonymous quote nested in an authored one |
| `R33b` | `oldcitation` markup |

### Oracle coverage (ADR 0004)

The LOT-003 oracle has **no per-quote field**, and legacy computed no cited number, depth or anonymous quote. Decision of the orchestrator
(2026-10-28, issue #59): the oracle for the legacy-derivable subset is `result.messages[].dicoHTML`, the legacy content after
`ParseMessagesOperation.m:191-226`; the new facts are checked against the captures. `MessageQuoteOracleTests`:

| Check | Compared with |
|---|---|
| Authors in order | for each `table[class=citation]` of `dicoHTML` with a `class=Topic` descendant: text minus its last 10 characters when longer than 10 (the legacy rule applied to the oracle HTML), compared with `pseudoComparisonKey` |
| Anonymous count | number of `table[class=quote]` of `dicoHTML` |
| Cited numbers | **new fact**: a regex over the capture's `contentHTML` (`#t<n>" class="Topic">`, no DOM), same order |
| Quote count | **new fact**: regex count of `<table class="citation">` or `quote` in `contentHTML` |
| Corpus total | 135 (LOT-034 figures: 126 / 9) |
| Nested case | **new fact**: `R28`, `R32a`, `R32b` message 27 pinned to `[authored depth 1 + cited number, anonymous depth 2]` |

## Intentional differences from legacy

1. **Author by suffix, not by length.** Legacy cut the last 10 characters of any header; here the suffix `a écrit :` must be there (U+00A0 and
   runs of spaces allowed), else the quote has no author. Identical on the corpus (checked by the differential test).
2. **Anonymous quotes are listed** (`table.quote`); legacy ignored them (class `citation` only).
3. **New facts**: `citedNumreponse`, `depth`.
4. **No policy and no rewriting**: no `citation_me_quoted`, `citation_whitelist`, `citation_blacklist`, no hidden block or `quoteIndex`.
5. **Nested headers are scoped**: legacy's `findChild` took the first `Topic` descendant, which for a header-less outer quote would be a nested
   quote's; here each quote reads only its own.

## Learnings

To copy into AGENTS.md §11 when the lot closes:

- SwiftSoup's `parents()` and `select` recurse per nesting level: a message with a few hundred nested tables crashes a 512 KB cooperative
  thread. Walk the tree with an explicit stack (the walk shipped is checked at 2 000 nested tables, 2 s, the cost being SwiftSoup's own parse).
- Proposed LESSONS row: a lot that adds facts legacy never computed differential-tests the legacy-derivable subset from the existing oracle
  output and checks the new facts against captures; it does not wait for a new exporter.
