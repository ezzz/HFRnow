# LOT-168 — Forum list completeness

- **Module:** HFRClient (`Sources/HFRClient/REST/ForumListCompletion.swift`, `RESTBrowsingClient.completingSubforums(of:)`), data fix in HFRParsing (`SubforumInjection`)
- **Difficulty / model:** easy (Sonnet 5.5 author → Opus 5.5 reviewer)
- **Issue:** [#286](https://github.com/ezzz/HFRnow/issues/286); builds on LOT-057 (`subcategories(in:)`, `R285a`-`R285c`) and LOT-021 (`ForumListParser`, `SubforumInjection`), both done.

## Legacy sources
`ObjCForumsParser.m` @ `87fe0d1c` (same lines as `2440d79`, LOT-021): `:84-109` page links, `:88-96` category entry, `:111-503` the injections. Legacy never called the REST API (LOT-057), so legacy has the same gap: the home page lists only some sub-forums.

## Behaviour
**Home page first, REST completes it.** `RESTBrowsingClient.completingSubforums(of: [ForumCategory])` takes the categories the caller read from the home page and, for each one with a `cat` id, makes one REST GET (`subcategories(in:)`'s request, `R285a`-`R285c`, no cookie) and merges (`ForumListCompletion.complete`):
- the page's links stay as they are (path, title, **order**, injected entries in their legacy place);
- a REST row whose title no page link has is added as the REST link (`subcat` path, LOT-057 "Sub-categories"), right after the entry of the REST row before it, first when it has none: REST order only decides where the added ones go;
- rows are matched by title (the page names a list by slug path, REST by number): trimmed, case- and accent-insensitive (« ADA » / « Ada »); a title repeated in REST needs as many page links, each page link matches once;
- the category's own row, "Tous les sujets" (`ForumListModel.swift`) and the dedupe by path are the app's and unchanged: the merged list has no repeated title, and the added paths cannot equal a page path.

**Failures.** A category whose REST exchange fails (unreadable JSON, HFR's error answer, an HTTP error) keeps the page's list: no HTML fallback, the home page is what the caller holds. Cancellation, offline and timeout throw `.network` (as every REST call): the caller keeps its own list. A category without a `cat` id is left as it is, with no request.

**Injection table checked against the captures.** `SubforumInjection` was legacy's, kept as data (LOT-021). Against `R285a`-`R285c` (categories 1, 2, 10) and `R929a`-`R929d` (categories 14, 4, 12, 6, captured 2026-11-18, #929): the table's 23 entries are all in REST by title (Programmation 14, Bench, Divers of Overclocking, and the 7 of Photo numérique, Windows & Software, Graphisme and Achats & Ventes, with their ids in MANIFEST). « PDA » and « Biblio Links » are not in REST: HFR no longer has them (LOT-021's table says « PDA gone from the forum », HFR-PROTOCOL §6b), so both are removed from the table. The four later categories' counts (10, 12, 10, 11) equal the page's list plus the REST rows it lacks, and the page keeps every injected entry in its place.

**Limits.** A page link with no REST row is always kept (the page is authoritative): an injected entry that HFR dropped, in REST later, would stay, and one spelled differently in REST would show twice (slug path and `subcat` path), so such a list can exceed the REST count. Every category that holds an injection is captured now (`R285a`-`R285c`, `R929a`-`R929d`), so the table is checked today; a later HFR change is not. When REST and page orders disagree (C# before C++ in REST), page entries between the two (« Delphi/Pascal », « Flash/ActionScript ») end up between them: the page's order is kept, REST only places the added rows.

## Fixtures
`R01` (home, `ForumListParser`), `R285a`-`R285c` and `R929a`-`R929d` (REST sub-categories), `R57i` (error answer): no new capture.

## Tests
`ForumListCompletionTests`: each captured category ends with its REST count (15, 7, 27, 10, 12, 10, 11), the page's links and order kept; Programmation 13 page entries + 14 REST ones; the 23 injections of the seven captured categories all in REST by title, none of PDA / Biblio Links; matching by spelling and by multiplicity; placement; the client's captured requests (no cookie, no redirect), a category without id, a failed or refused category kept, cancellation / offline / timeout ending the call. Two mutations, each applied and reverted, each failed a named test: the placement anchor (`anchor += 1`), the once-only match (`!matched`). `ForumListParserTests`: the oracle comparison undoes the table change as a named deviation.

## Pending capture
None for the table: #929 is captured (`R929a`-`R929d`). The other categories (3, 5, 7, 8, 9, 11, 13...) have no injection, so their REST lists are not needed to check it.

## Intentional differences from legacy
1. « PDA » and « Biblio Links » are no longer injected (not in `R285c`).
2. The list can hold REST links (`subcat` paths) next to the page's slug links.
3. No app wiring here: `ForumListModel` calling `completingSubforums` is an app lot's.

## Learnings
- A table kept "as data" from legacy needs a check against the first complete source as soon as one exists; two of its entries had gone from the forum.
