# LOT-026 — Poll parser (voting form and results)

- **Module:** HFRParsing (+ one optional field in HFRModels `Poll`)
- **Difficulty / model:** medium (Sonnet → Opus)
- **Issue:** none (lot tracked in `docs/LOTS.md`)

Scope decided by the orchestrator: only states **proven by a capture** are handled — the voting form (`R32a` logged out, `R32b` logged in, not voted) and
the results (`R33a` closed poll, `R33b` already voted with the multi-pseudo notice). No hand-built page. Vote responses (N05) belong to LOT-054.

## Legacy sources

Legacy repository <https://github.com/francoisgn/hfrnow> at `2440d79`. Audit: [B9](../audit/B-list-parsing-models.md), [C07](../audit/C-message-parsing.md), [D §2.9](../audit/D-posting.md). Oracles: [LOT-005](LOT-005-small-parsers-oracle.md) kind `poll`.

| Legacy | Replaced by |
|---|---|
| `Classes/ObjCTopicPageWorker.m:159-162` (first element with class exactly `sondage`, raw HTML handed to Swift) | `PollParser.poll(in:)` finds `div.sondage` itself, in a full page or a fragment |
| `HFRswift/Swift/PollData.swift:104-250` (`PollHTMLParser`: question, options, hidden fields), `253-355` (`extractResults`) | same, on the DOM instead of regexes |

## Behaviour

`PollParser.poll(in: String) throws(ParsingError) -> Poll?`:

- nil when the page has no element with class token `sondage` (`R20`, `R23`, `R31`).
- `question`: text of the `s2` element, `&nbsp;` as space, whitespace collapsed.
- **Mode rule** (from the captures): `li` rows holding an input make a voting form; otherwise `div.sondageLeft` bars make results; neither is `missingElement`.
  (Legacy: any `<input` means voting, `PollData.swift:115-141`.)
- **Voting form** (`R32a/b`): `options` one per `li` with a radio, `id` = 1-based position and the radio `value` must be that integer
  (else `invalidValue(field: "poll answer value")`, since the server receives the `value`; captured values are 1...10), `fieldName` = input `name` (`reponse`);
  a non-radio input is `invalidValue(field: "poll answer input type")`, an `li` without input is `missingElement("input in poll answer")` (no answer is silently dropped). `hiddenFields` = every `input[type=hidden]` **inside** the block (`cat, p, page, sondage, owntopic, subcat, numeropost, hash_check`;
  `hash_check` is `""` logged out; the form also prints one before the block, same value). `footer`, `notice` nil.
- **Results** (`R33a/b`): the block holds, per answer, `div.sondageLeft` (a `div.barre` whose width is not the percentage, then two `div.sondageTop`: `65.2&nbsp;%` and `&nbsp;116 votes`),
  then `div.sondageRight` (`1.&nbsp; Hugo Lloris`) and a `div.spacer`; a `<div><b>Total : 194 votes</b>&nbsp;(16 votes blancs)</div>` closes the block.
  `PollResult`: `id` = position, `label` without the printed rank, `percentage` (decimal point **or comma**, 0...100), `voteCount` (first integer).
  `footer` = the Total line ("Total : 194 votes (16 votes blancs)", blank votes are not in the answers). `notice` = text HFR adds: the text directly inside the block
  (R33b: "(Multipseudo detecté, vous ne pourrez pas voter à ce sondage avec vos autres pseudos)") or else the `b.s1Ext` right after the block
  (R33a: "Ce sondage est clos, vous ne pouvez plus voter"). A bar not followed by its `sondageRight`, an unlabelled bar, an unreadable number or a percentage outside 0...100 is `invalidValue(field: "poll results")`.
- `maxChoices` is 1 (no capture shows a multi-choice hint).

**Model change (HFRModels, justified by R33a/R33b):** `Poll.notice: String?` (default nil, optional in stored data). Both results captures print a status line the reader needs to understand why
the poll cannot be voted; neither fits `footer`. Closed and already-voted polls look the same (`Poll.Kind.results`); the notice tells them apart for display.

Facts for LOT-054 (vote POST), asserted on the captures: the voting block sits in `<form method="post" action="/user/vote.php?config=hfr.inc">`;
the form has two submit buttons with the **same name** `sondage_submit` ("Voter", "Voir les résultats"); legacy sent neither (`PollData.swift:44-100`), so whether the server needs `sondage_submit=Voter` is **unverified**; no `verifrequet`.
A results page has no form and no input at all.

## Callers

A topic page parser (LOT-030/033) must treat a thrown `PollParser` error as "poll unavailable" and still render the page: never fail the whole page
because of a poll shape that is still pending.

## Edge cases

Fragment instead of page; `sondageLeft` is not the `sondage` block; labels with `&amp;`, `&nbsp;`, double spaces; empty token logged out; token not printed by `Poll`'s description;
decimal comma; bar without label; percentage out of range; radio value not equal to its position.

## Fixtures

`R32a`, `R32b` (voting form, poll `98162`, ten answers), `R33a` (closed, three answers), `R33b` (already voted, user1, three answers); `R20`, `R23`, `R31` for "no poll". No synthetic file.
`R32a` does **not** show results for an anonymous visitor (the checklist expected it to): it shows the voting form with an empty token.

## Differential tests (ADR 0004)

`Topic/PollOracleTests.swift` compares the whole parsed poll (question, mode, `maxChoices`, every option or result line, hidden fields) with the LOT-005 `poll` oracles of R32a, R32b, R33a, R33b, plus a guard test
that fails if `oracle-map.json` gains a `poll` case the suite does not run. `Topic/PollParserTests.swift` holds the unit tests on the same captures.

## Pending (not captured, left out)

- **A plain "already voted" page without the multi-pseudo notice** (poll voted from the account itself): searched on the Mac, not found (`MANIFEST.md`). It is probably the R33b markup without the notice; not assumed.
- **Multi-choice polls**: the hint text between the question and the answers (`extractMaxChoices`, `PollData.swift:185-206`), checkbox inputs and their field names (`reponse<N>`, E11), vote value `"1"` per field. Refused with `invalidValue(field: "poll answer input type")`.
- **`div.sondageFooter`** (legacy footer, `PollData.swift:164-181`; ObjC takes the last child of the block): no capture has it, so it is not read.
- Vote response parsing (N05, `PollData.swift:79-98`): LOT-054.

## Intentional differences from legacy

All asserted in the differential tests.

- **Entities in texts (quirk Q7)**: legacy left `&amp;` in answer texts (`E85 entre 25 &amp; 40 % + SP`); the port decodes (`&`).
- **Result labels (quirk Q9)**: legacy kept the printed rank and a non-breaking space (`"1.\u{00A0} Hugo Lloris"`); the port strips the rank (the `id` carries it).
- **Footer**: legacy returned `""` on all four captures (no `sondageFooter`); the port returns the Total line on results.
- **Notice**: new field; legacy ignored the multi-pseudo and closed sentences.
- **Decimal comma** accepted (legacy read only the point, `PollData.swift:330`); not exercised by a capture (unit test).
- Strictness: legacy paired bars and labels by index and cut the longer list, and returned nil for an unreadable block; the port throws a typed error. Hidden inputs without a `value` give `""`.

## Learnings

- A checklist expectation ("results as anon") can be wrong: read the capture before designing the state machine.
- A status sentence can sit outside the block it qualifies (`b.s1Ext` after `div.sondage`): look at siblings, not only descendants.
