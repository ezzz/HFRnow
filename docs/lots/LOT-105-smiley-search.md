# LOT-105 — Smiley search, history and wiki keywords

- **Module:** App (`App/SwiftHFR/Smileys/`, services in `App/SwiftHFR/Composer/ReplyPosting.swift`)
- **Difficulty / model:** easy (Sonnet 5.5 → Opus)
- **Issue:** [#196](https://github.com/ezzz/HFRnow/issues/196) (legacy parity, GAP-088, no FEAT)
- **Depends on:** LOT-104 (picker, #459), LOT-053 (`SmileyLookupFlow`), LOT-064 (`SmileySearchHistoryStore`), LOT-025 (parsers)

## Legacy counterpart

Legacy `master` of ezzz/HFRnow @ `2440d79`, `HFRswift/Swift/`. Functional reference only.

| Legacy | Replaced by |
|---|---|
| `AnswerView.swift:1230-1262` (search field, "Rechercher", "Tous les mots clés" toggle, `@AppStorage("AnswerView.smileys.search.allKeywords")`) | `SmileyPickerView.searchBar` (same key) |
| `AnswerView.swift:1264-1345` (`performSearch`, `clearSearch`, `search(using:)`, `refreshSuggestions`) | `SmileySearchModel.search`, `clear`, `submit`, `refreshSuggestions` |
| `AnswerView.swift:1088-1093` (`suggestionChips`: 5 chips, recent first, then top not already listed), `:1171-1190` (chip row) | `SmileySearchModel.suggestions`, `SmileyPickerView.suggestionChips` |
| `AnswerView.swift:1103-1106`, `:1200-1206`, `:1262-1290` (results grid, back button, empty state "Aucun smiley trouvé") | `SmileyPickerView.searchResults` |
| `AnswerView.swift:1473-1615` (`FavoriteSmileyDetailView`: "Mots clés" chips, tap → search), `:762-836` (`fetchSmileyKeywords`) | `SmileyDetailView.keywords`, `SmileySearchModel.loadKeywords` over `SmileyLookupFlow.wiki` (LOT-053) |
| `AnswerView.swift:1308-1326` (`smileySearchQuery`), `SmileySearchService.swift:17-42` | `SmileyLookupFlow.search` (LOT-053, unchanged) |
| `SmileySearchService.swift:78-140` (`SmileySearchHistoryStore.record`, `recentSuggestions`, `topSuggestions`) | `SmileySearchHistoryStore` (LOT-064, unchanged) |

## UX evolutions

| GAP | Difference | Class |
|---|---|---|
| GAP-088 | A text under 3 characters shows why ("Saisissez au moins 3 caractères…") under the field, and the search button stays disabled; legacy silently did nothing | b·needed (acceptance criterion of #196) |
| GAP-088 | A search that failed (offline, HFR answer unreadable) says so with a reason and "Retour aux smileys"; legacy showed "Aucun smiley trouvé" (LESSONS 44: not found ≠ could not read) | b·needed |
| GAP-088 | Results are listed once per code (HFR serves one twice, `R53c`); legacy's grid listed it twice | b·needed (the grid identifies cells by code) |
| GAP-088 | While a search is in flight the catalogue and the chips give way to "Recherche…" (legacy kept them and spun the button) | b |
| GAP-088 | Wiki keywords failing to load show the reason; the detail is a sheet (LOT-104), now also resizable to large | b |

## Behaviour

- The picker sheet has a search bar at the bottom (field, "Rechercher", "Tous les mots clés"). Nothing is sent below
  `HFREndpoint.smileySearchMinimumLength` (3, trimmed): the hint explains why, the button is disabled and a submit shows
  "Recherche trop courte". The panel has no search bar when the composer has no account (`ComposerServices.smileyLookups`
  is nil; HFR shows no answer form logged out anyway).
- A search runs `SmileyLookupFlow.search(text, requireAll:)` (LOT-053, network path unchanged; its probe session carries the
  account cookies and writes nothing back). The results area replaces the catalogue: grid of results (tap → the favourite
  detail: insert, add/remove favourite, keywords), "Aucun smiley trouvé" for HFR's "no result", a failure message otherwise,
  a back button that returns to the catalogue. Only the latest request counts: an answer arriving after a newer search, a
  clear or the panel's closing is dropped.
- History (LOT-064, device-wide, 50 entries, minimum length 3 and at least one result: the store's rules): the text is
  recorded after a successful search with results. Chips (recent searches, with the field empty; recent then frequent matches
  when typing; 5 at most, never the same text twice) refresh as the text changes; a tap runs the search.
- Detail: opening it reads the wiki entry (`SmileyLookupFlow.wiki`, cookie-less) and lists the keywords in the order served.
  A tap on a keyword closes the detail and searches it. An entry with no keyword shows no section.
- The search model lives as long as the reply sheet (legacy's session state): closing the panel to insert a smiley and reopening it shows the same text and results. Closing the panel drops a request in flight and returns to the catalogue.
- A history write that the store refuses never hides the results (the history is a convenience; the store reports its own
  failure when read).

## Edge cases

- The chip row is shown in the catalogue state only (as legacy: `displayMode == .library`).
- A keyword shorter than 3 characters ends in "Recherche trop courte" (legacy ignored it).
- The server's duplicate in a result list (`R53c`) is dropped after the first.

## Pending capture (never hand-built, LESSONS 35-36)

Everything of LOT-053's list (#360): a search sent as the flow sends it, accents and special characters, a standard
(non-personal) smileys result, a logged-out search, the wiki page of an unknown code (the detail then shows the failure
reason). What `+` does to the answer ("Tous les mots clés") is not captured: the toggle shapes the request like legacy and
promises nothing about AND (LOT-053).

## Tests

`SmileySearchModelTests` (Swift Testing, `App/SwiftHFRTests/Smileys/`): minimum length and hint, results order and
single listing, request text and `requireAll`, history recorded only after a result, no result, failure not taken for no
result, clear, stale answers of a search and of keywords dropped (explicit gates, no clock), chips (empty field, typed text,
dedup, cap), keywords in order and failure, keyword tap from the picker. Not built locally (cloud): the CI job "App build +
tests" is the check; the hand checks are listed in the PR ("Mac check needed").
