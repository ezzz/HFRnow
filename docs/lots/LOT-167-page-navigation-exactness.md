# LOT-167 — PageNavigation exactness flag (honest list paging)

- **Module:** HFRModels (flag) and HFRParsing (`TopicListPager` sets it)
- **Difficulty / model:** easy (Sonnet → Opus)
- **Issue:** [#279](https://github.com/ezzz/HFRnow/issues/279) (implements FEAT-003, [#147](https://github.com/ezzz/HFRnow/issues/147), proposed by Bybifok; related bug #104)

## Legacy sources
None: new behaviour. The legacy app shows the last pager link as the page count; Bybifok reported it as a fake total (#104). LOT-082 ([#100](https://github.com/ezzz/HFRnow/issues/100), done) already shows "Page N" without a total. Legacy pager parsing: `ObjCTopicListParser.m:172-252` (see [LOT-022](LOT-022-topic-list-parser.md)).

## Behaviour
`PageNavigation` (`Packages/HFRKit/Sources/HFRModels/Lists/PageNavigation.swift`) gains `isExact: Bool`: true when `last` is the real page count, false when it is only the last page the pager links to (a lower bound). Source: HFR-PROTOCOL §7b B1, §6c LOT-022 and LOT-167 (captures `R04`, `R05a`, `R05b`, `R08-2`, `R13u1`, `R50b`).

- **Default `false`**: a caller that sets `last` by hand claims nothing. `PageNavigation()` (one page) is a lower bound until a parser says otherwise.
- **Codable**: the key is `isExact`; decoding uses `decodeIfPresent`, so a record written before the flag existed decodes as lower bound instead of throwing `keyNotFound`. Encoding is unchanged otherwise.
- **Parser rule** (`TopicListPager`, shared by forum lists, favourites, search and MP lists): exact when the pager entries are exactly `1, 2, … N` with `N < 10`, or when the page has no pager header (empty or single page list). Any jump (`10 20 30`, `1 10 11 …`), or a pager reaching 10, is a lower bound.
- **Why `N < 10`**: HFR shows pages 1-10 one by one then only tens (`R04`: `1 … 10 20 30 …`), so a pager that stops before 10 cannot hide pages. A pager `1…10` alone is ambiguous (11 to 19 pages would show the same), hence the strict bound. Short pagers are captured (`R08-2`: 1, `R50b`: 1-2, `R13u1`: 1-7); that nothing hides behind them is an inference from the window shape, not a capture of a topic count: listed as *pending capture* below.
- **Hop/message pages** (`.hop` result, maintenance): left at the default (not exact); they carry no list.
- **Topic rows**: the exact page count of a topic stays `TopicSummary.pageCount` (`sujetCase4`, asserted against the legacy oracle by `TopicListDifferentialTests`).

The app disabling "Dernière page" when `isExact` is false is out of this lot (app lists, FEAT-003).

## Edge cases
- Decoding data written before the flag exists: lower bound.
- Pager of a topic *page* (not a list): not `PageNavigation`; the topic page model keeps its own count (LOT-033), unaffected.
- Current page inside a window (`R05a`, page 12): not contiguous from 1, lower bound.
- Entries that are not numbers are ignored by `pageEntries`, so they cannot make a pager look contiguous.

## Fixtures
Existing captures only, no new one: `R04`, `R05a`, `R05b` (lower bound), `R08-2`, `R50b` (exact), `R13u1` (MP, 1-7, exact), `R13c` (no pager, exact). Oracle `R04` `maxTopicPage` for the row count.

## Pending capture
- A forum list whose real page count is 2-9 with the **last page** shown (a small sub-forum): would confirm the "stops before 10 means exact" inference on a list that is known to have no more pages. Search results (`R50b`) and the MP list (`R13u1`) are consistent with it but their true totals are not independently known.
- A list of exactly 10 and of 11-19 pages: would show whether `1…10` could be made exact. Until then `N = 10` is a lower bound.

## Intentional differences from legacy
The legacy app treats the last pager link as the total; this lot does not (CHANGELOG-LEGACY).

## Learnings
- A flag that qualifies a parsed number belongs next to the number and defaults to the honest value (lower bound); only the parser that has evidence turns it on.
