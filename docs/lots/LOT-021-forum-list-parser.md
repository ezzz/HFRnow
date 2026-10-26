# LOT-021 — Forum list (home page) parser

- **Module:** HFRParsing
- **Difficulty / model:** medium (Sonnet → Opus)
- **Issue:** none (lot tracked in `docs/LOTS.md`)

First list parser tested against **both** inputs ADR 0004 asks for: the captured pages (LOT-001) and the legacy oracle (LOT-002).

## Legacy sources

Legacy repository <https://github.com/francoisgn/hfrnow> at `2440d79`. Audit: [B §3.1](../audit/B-list-parsing-models.md), proposal B4.

| Legacy | Replaced by |
|---|---|
| `Classes/ObjCForumsParser.m:13-529` (`parseForumsFromData:`), called from `ObjCForumsLoaderWorker.m:28` | `ForumListParser.parse(_:)` |
| `ObjCForumsParser.m:111-503` (hard-coded sub-forum additions) | `SubforumInjection.all` (data) |
| `ObjCForumsParser.m:516-525`, `HFRplusAppDelegate.m:700-712` (badge) | `ForumListPage.unreadPrivateMessages` |
| `ObjCForumsParser.m:36-43` (`hash_check` into the app delegate) | `ForumListPage.hashCheck`, `isLoggedIn` |

## Behaviour

`ForumListParser.parse(_ html: String) throws(ListPageFailure) -> ForumListPage` — pure, SwiftSoup stays inside the module (ADR 0002), HTML read with `parseHTML` (LESSONS 26).

1. **Maintenance:** the first non-blank node of `<body>` is a `<p>` → `.maintenance(<trimmed text>)` (`:20-31`). Legacy posted a notification and returned `[]`.
2. **Session:** the first element named `hash_check` with a non-empty `value` → `isLoggedIn`, `hashCheck` (`:36-43`). Anonymous pages carry the field with an empty value (R01).
3. **Rows:** every `tr` whose `class` contains `cat` (substring, case-sensitive, as legacy `:18, 48-52`), in document order. The category cell is the second direct `td` (`:54-61`).
4. **Title:** first `<b>` of the cell, text content (entities decoded), trimmed (`:62`).
5. **Path:** every `href` goes through `HFRURL.forumRelativePath` (LESSONS 37; refuses other hosts, `//host`, `https://forum.hardware.fr//host`, `http` with a port, control characters); absolute forum links are reduced to their path. The link is the `href` of the first descendant whose class contains `cCatTopic` (`:67`); `/hfr/AchatsVentes/Hardware/liste_sujet-1.htm` is corrected to `/hfr/AchatsVentes/liste_sujet-1.htm` (`:69-71`). The home page links "Achats & Ventes" to its Hardware sub-forum on R01, R02 and R03.
6. **Sub-forums:** descendants of the cell whose class is exactly `Tableau` (`:84`), title trimmed, `href` as served. Then `SubforumInjection` completes the list (below).
7. **Private messages:** a row whose link contains `cat=prive` is not a category. Its link text gives `unreadPrivateMessages`: the first integer, `0` when the text has none (`:516-525`; R03 "Envoyer / lire des messages privés"). Without such a row (anonymous) the value is `nil`.
8. **Category id:** `categoryID` is read from the row id `cat<N>` (new, see below), falling back to `ForumCatalogue.categoryID(forPath:)` (the legacy id table, LOT-014) when the id is absent or not numeric.
9. **Unreadable rows are skipped:** a `tr.cat` without category cell, `cCatTopic` link (or a forum-relative `href`) or title is ignored, a sub-forum link without a forum-relative `href` is dropped. No forum row at all → `.malformed("no forum row (tr class*=cat)")`; rows but none readable → `.malformed("<n> forum rows, none readable")` (legacy returned `[]`).

### Sub-forum injection

The home page lists only part of the sub-forums of some categories. Legacy completed them from a table keyed on the URL of a *listed* sub-forum, placing the added ones right after it (before it for `API-Win32`). The 15 rules are `SubforumInjection.all`, copied from `ObjCForumsParser.m:111-503` (the audit table B §3.1 matches).

- **Verified, not guessed:** against the REST category counts of `R57a` (`number_of_subcategories`) the injected forums are real. Hardware (15), Photo numérique (10), Windows & Software (12), Graphisme (10) and Achats & Ventes (11) reach the REST count exactly with the table (page links + injected); Overclocking (REST 7) stays at 6 because its trigger (`Mod-elec`) is no longer on the page; Programmation (REST 27) reaches 14 (6 page links + 8 injected). The table is therefore **incomplete**, not wrong; the full list is REST (`R57a`/LOT-057), which is out of scope here.
- **Dedupe (new):** an injected forum is skipped when its path is already a link of the cell or was already injected (legacy would show it twice if HFR starts listing it).
- Triggers are matched on the exact `href`, as legacy.

## Edge cases

- Page of another kind (topic list `R04`, favourites `R12`): no `tr.cat` → `.malformed`.
- Row without second cell, without `<b>`, without `cCatTopic` link or `href`: skipped (legacy raised `NSException` and lost the page). Tested on R01 with an extra empty `tr.cat` and with every `cCatTopic` renamed.
- `hash_check` field with no `value` attribute: treated as empty (legacy: logged in with a nil token).
- Trailing/leading whitespace and `&nbsp;` around titles is trimmed with `whitespacesAndNewlines`, like legacy.
- Text is read from all text nodes under the element (legacy `allContents`); the unread count therefore also works if HFR puts the number in an inline tag (legacy `contents` read only the first text node).

## Fixtures

Shared corpus only, no new capture (`Fixtures/captures/`), oracles `Fixtures/LOT-002/R01|R02|R03.oracle.json` and `oracle-map.json` (`forums` entries). Test helper `Tests/HFRParsingTests/Support/Fixture.swift` (also added identically by LOT-025/026).

| Capture | Covers |
|---|---|
| `R01` home anon | no token, no MP row, Apple present (20 rows), Achats & Ventes link, injection |
| `R02` home user, 10 unread MP | token, `a.cCatTopic.red` "Vous avez 10 nouveaux messages privés" |
| `R03` home user, no unread MP | token, MP row without number → 0 |
| `R07` small forum list | `select[name=cat]`: the 20 (id, title) pairs, cross-check of the row ids |
| `R04`, `R12` | pages of other kinds → `.malformed` |
| `R57a` (read in this spec, not by the tests) | REST subcategory counts used to confirm the injections |

### Oracle coverage (ADR 0004)

`ForumListParserTests.matchesOracle` decodes the full oracle JSON (`ForumListOracle`) for **R01, R02, R03** and compares, for each, the whole forum array (title, path, every sub-forum including the injected ones, in order), plus `hashCheck`, `isLoggedIn` (= legacy "hash_check has a value") and `unreadPrivateMessages` (= `nbMP`). It also checks `exception == nil`, `input.file` and `input.bytes` against the capture. `oracle-map.json` is checked to list the three as `forums`. R07 is not a `forums` oracle: it is used for the cross-check of the category ids.

## Intentional differences from legacy

| # | Legacy | Here | Why |
|---|---|---|---|
| 1 | Anonymous page: the `Apple` row is skipped (`:77-80`) | All categories are returned (R01: 20, oracle 19) | Hiding is app policy for App Review (Q-7), not parsing. The test undoes the legacy rule to compare |
| 2 | `subCats[0]` repeats the parent ("all" entry, `:88-96`); `subCats` is `[]` without sub-forums | `subforums` holds the sub-forums only; the parent is the category itself | The model says "empty when none"; the UI can build the picker (parent + subs) without a duplicated entry |
| 3 | `aID` never set | `categoryID` set from the row id `cat<N>` (catalogue fallback) | The rows carry the `cat` id (R01-R03, all 20 agree with `ForumCatalogue` and with R07's selector); answers audit B open question 2 |
| 4 | Maintenance page: notification + `[]` (`:20-31`) | `throws .maintenance(message)` | Typed errors instead of side effects (B §5) |
| 5 | `hash_check` and `nb_mp` written to global state | Returned in `ForumListPage` | No side effects in parsers (B §5, AGENTS §4) |
| 6 | MP count 0 when the row has no number (`updateMPBadge` on the text) | `unreadPrivateMessages == 0`, `nil` without MP row | Same values as the oracle (`nbMP` 0 / null), made explicit |
| 7 | Missing cell / `<b>` / link raises `NSException` for the whole page | The row is skipped; sub-forum link without `href` dropped | One unexpected row must not break the home page |
| 8 | No row → `[]` | `.malformed` (no row, or none readable) | A home page with no readable forum is a broken page, not an empty forum list |
| 11 | Any `href` kept as served | Only forum-relative paths (`forumRelativePath`); hostile category row skipped, sub-forum link dropped | Paths are requested with the session later |
| 9 | Injections without dedupe; a sub-forum repeated by the page is kept twice | Dedupe by path (first occurrence wins) | See above; no capture repeats a link, so the oracle is unaffected |
| 10 | `contents` (first text node) for the MP count | Whole text content | Same on all captures; robust to inline markup |

## Pending capture

- **Maintenance home page:** none captured. The `.maintenance` path rests on the legacy rule and on a synthetic inline snippet in the tests (not a fixture, behaviour on the live site unverified).
- **Home page with a row lacking `id="cat<N>"` or a new category** (e.g. a forum added after the catalogue): not captured; the fallback is tested with a synthetic row only.
- **Complete sub-forum lists:** the home page omits sub-forums that REST lists (Programmation 14 of 27, Overclocking 6 of 7). Not a capture gap: needs the REST `subcategories` listing (not captured; LOT-057).

## Learnings

To copy into AGENTS.md §11 when the lot closes:

- The home page rows carry the category id (`tr#cat<N>`): the id table is only a fallback. Hidden sub-forums on the home page are real forums; REST counts are the reference.
- A differential test needs the legacy quirks undone explicitly (Apple, parent copy): write them as named deviations in the test, not as filtered expectations.
