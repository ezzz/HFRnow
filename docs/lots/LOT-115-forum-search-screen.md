# LOT-115 — Forum search screen

- **Module:** App (`App/SwiftHFR/Search/`), no engine change
- **Difficulty / model:** medium (Sonnet → Opus)
- **Issue:** [#206](https://github.com/ezzz/HFRnow/issues/206)
- **Depends on:** LOT-046 (`GlobalSearchFlow`, results as a `TopicListPage`), LOT-082 (list loading rules, `ContentLoader`)

## Legacy counterpart

Legacy citations name `2440d79` of <https://github.com/ezzz/HFRnow>.

| Legacy | Ported as |
|---|---|
| `HFRswift/Swift/ForumSearchView.swift` `ForumSearchViewModel` (`search`, `fetchPage`, `cancel`, request-id guard) | `ForumSearchModel` (`ContentLoader` gives the one-load-at-a-time and superseded-load rules) |
| `ForumSearchView.swift` `ForumSearchView` (form, results, status banner, pagination bar) | `ForumSearchView` (GAP-131, GAP-134) |
| `ForumSearchService.swift:10-127` `ForumSearchParams` (`SearchType`, `SearchScope`, `DateRange`, `legacyDictionary`) | `GlobalSearchQuery` (LOT-041) built by `ForumSearchModel.dateRange()` (GAP-132) |
| `ObjCForumSearchWorker.m:150-156` banned words | refused before any request (GAP-133, Q-7) |
| `PlusTab.swift:26-28` entry "Rechercher sur le forum" | `PlusEntry.search` opens the screen (GAP-130) |
| `recherche_categorie` | `SettingKey.searchCategory`, written on every change of the picker |

## Behaviour

- **Entry:** Plus tab and iPad sidebar (`PlusEntryView`). The model lives in `RootModel.search`, so a change of layout keeps the form and the results.
- **Form:** words, forum, "Mots" (tous / au moins un / avancé), "Dans" (titre et contenu / titre / contenu), "Période" (début / 5 ans / 1 an). The period is a start date from today (`since(day:month:year:)`, calendar injected). Forums come from the home page list, so the Apple category is already filtered (Q-7, `ForumVisibility`); the choice falls back to Discussions (13) when it is no longer offered.
- **Submit:** blank text sends nothing. A text holding a banned word (`GlobalSearchFlow.bannedWords`, same test as the engine) shows a warning and sends nothing; the previous results stay. Accented text is passed as typed: the engine lower-cases and percent-encodes it in UTF-8 (LOT-046).
- **Help for short words:** a word under 4 letters shows a hint (they "peuvent être ignorés"); it never blocks the search. HFR's behaviour is *unsettled* (HFR-PROTOCOL §7b B3), hence the hedge.
- **Results:** the page's rows with the excerpt (`SearchHit.snippet`), the page number, HFR's sentence when nothing matched (`R50c`). First / previous / next pagination follows the pager paths of `TopicListPage.navigation` (`GlobalSearchFlow.page(atPath:)`); like the forum lists, only "there is a next page" is shown, never a total.
- **Open a result:** pushed in the Plus stack; the reader opens at the matching message (`SearchHit.postPath` through `ReaderTarget(link:)`), else as a topic row does.
- **Failures:** `ListLoadError` (offline, timeout, maintenance, unreadable) with "Réessayer"; the rows stay on screen after a failed page. The waiting page without results link (`noResultsPage`) reads as "page illisible".
- "Annuler" stops the search in flight. Leaving the screen does not cancel it (a covered list must not drop its load, LOT-137 learning), so the reader pushed over a result and a layout change keep the load.
- The category sent is the stored one only once the forum list vouches for it (Q-7), else Discussions.

## Edge cases

Blank text; banned word inside another word (`penguin`, as legacy and LOT-046); search while one runs (ignored); a new search drops the open result; a failed new query clears the old rows, a failed page then retry asks for the same page again; empty result keeps HFR's sentence.

## Pending capture / Mac check

- Pages after the first of a search are not captured (LOT-046): the pager is read as the first page.
- Whether HFR ignores words under 4 letters (B3).
- Whether `SearchHit.postPath` opens the matching message in the reader on a device; the row shape of the rare results (#121).
- Light, dark and Dynamic Type XL; iPhone and iPad layouts.

## Intentional differences from legacy

- Banned words refuse the search with a warning (Q-7, CHANGELOG-LEGACY row 45).
- A new query clears the previous rows and pager at once (legacy cleared them only on failure, `ForumSearchView.swift:95-98`); "Annuler" and "Dernière page" are kept (row and bar, not toolbar/banner).
- A failed page keeps its rows (`ContentLoader`); legacy cleared them on any failure.
- No haptic. The glass buttons are not ported here: the operator reversed that on 2026-11-07 ([#545](https://github.com/ezzz/HFRnow/issues/545), GAP-226), and LOT-185 ([#548](https://github.com/ezzz/HFRnow/issues/548)) brings them to the floating controls. The status banner is a "Recherche en cours" row.
- The reviewer-account rule hides the Apple *category* only; hiding the entry point itself (research note P450-510 #3) is not in the issue's scope and stays open.

## Tests

`App/SwiftHFRTests/Search/ForumSearchModelTests.swift`: banned word (sends nothing, inside a word, warning cleared), accents, blank text, form to query, period dates, short-word hint, paging, failed page and retry, no result, failed search retry, categories, Apple category hidden (logged out, review account), private-messages id fallback, stored category, result target, new search drops the selection.

## Learnings

None yet.
