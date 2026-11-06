# LOT-113 — Search inside a topic

- **Module:** App
- **Difficulty / model:** easy (Sonnet 5.5 → Opus 5.5)
- **Issue:** [#204](https://github.com/ezzz/HFRnow/issues/204)
- **Depends on:** LOT-046 (`TopicSearchFlow`, merged), LOT-083 (reader, merged). Captures: #122 (`R122a`-`R122d`, merged).

## Legacy sources

Legacy app: ezzz/HFRnow at `2440d79`.

| Legacy | What it gives this lot |
|---|---|
| `HFRswift/Swift/TopicSearchSheetView.swift:12-195` | the sheet: "Mot-clé", "Pseudo", submit disabled until one is filled (`:56-60`), trimmed values (`:62-69`), the error shown in the sheet (`:149-155`), "Recherche en cours…" (`:163`) |
| `HFRswift/Swift/TopicSearchService.swift:11-62` | `TopicSearchParams`, `isSubmittable` (`:36-40`), the form (ported by LOT-041 as `TopicSearchQuery`) |
| `TopicSearchService.swift:90-108` | messages: empty query "Renseigne un mot-clé ou un pseudo pour lancer la recherche.", no result "Aucun résultat n'a été trouvé." |
| `TopicSearchService.swift:163-172` | `TopicSearchContext`: results mode of the message list (not ported, see below) |
| `Classes/MessagesSearchTableViewController.m` | empty template, nothing to port |

## Legacy counterpart

| SwiftHFR | Legacy |
|---|---|
| `Reader/Search/TopicSearchModel.swift`, `TopicSearchSheet.swift` | `TopicSearchSheetView.swift` (`TopicSearchSheetView`) |
| `Reader/Search/TopicSearching.swift` | `TopicSearchService.swift` (`ObjCTopicSearchService`) |
| `Reader/Search/ReaderSearchFlow.swift` | the search menu entry of `MessagesView` |

## UX evolutions

- The toolbar button and the sheet are shown only with an account (the POST needs the account's `hash_check`, LOT-046 `missingToken`); a logged-out reader has no button. Legacy showed the sheet to everyone and failed on submit. `b·needed`.
- A refusal, an expired session and an unreadable answer are told apart from "no result" (LOT-046 intentional difference 4). `b·needed`.
- A match on the page shown scrolls in place; legacy always pushed a new `MessagesView` (`handleSearchResult`, `MessagesView.swift:3885-3911`). `b·needed` (GAP-135): no second reader for a message already on screen. Any other match opens a reader above, as legacy.
- Not ported yet: the "Filtrer les messages" and "Depuis le début du sujet" toggles, and the results mode with "next results" (`TopicSearchContext`): see Pending capture.

## Behaviour

- Button "Rechercher dans le sujet" in the reader's secondary menu, like "Filtrer les posts" (legacy: the reader menu, `MessagesView.swift:4710-4716`; needs `ComposerServices.topicSearcher`, set for the current account, and a page that names its topic; never on a private conversation). It opens `TopicSearchSheet` (medium/large detents).
- `TopicSearchModel` (`@Observable @MainActor`): `word`, `author`; `canSubmit` when one is non-blank and no search runs; `submit()` sends one `TopicSearchQuery` (trimmed values, `filterEnabled: false`, no `p`, no continuation) through `TopicSearching` (live: `TopicSearchFlow`), one search at a time.
- `state`: `idle`, `searching`, `failed(message)`; closing the sheet cancels and drops a late answer. Messages (French): no result "Aucun résultat n'a été trouvé." (never an empty screen); logged out or no token "Connecte-toi pour rechercher dans ce sujet."; HFR's own refusal message when it gave one; transport "Impossible de joindre le forum."; unreadable answer, off-topic `Location` or no message number "Réponse inattendue du forum.".
- **Match**: the flow returns a `Location` of the searched topic (`R52a`). Only the message number `n` of its `#t<n>` anchor is read: whether its `page=` follows the match is not captured (`R52a`'s match is on page 1). The target is `ReaderTarget(source: .topic, anchor: n, numreponse: n)`, so HFR picks the page holding `n` (`R25`, issue #106). It goes through `TopicReaderModel.follow`: scrolled to in place when the page shown holds `n`, else a reader opened above this one (legacy pushes a new `MessagesView`, `MessagesView.swift:3885-3911`). The sheet closes first. A `Location` without anchor is an error message, never a guess.
- No new `reader.js` message: nothing is read from the web view. `TopicReaderModel` is untouched (all code is in `Reader/Search/`).

## Edge cases

- Word and author blank or whitespace only: the button stays disabled, nothing is sent.
- Double tap on "Rechercher": the second is ignored while the first runs.
- The sheet closes while the search runs: cancelled, its answer opens nothing.
- A match on the page already shown: scroll, no fetch. Any other match: a reader above, back returns to the page left.

## Fixtures

None new: `R52a` (the `Location`, meta only) and `R52b` (no match) are LOT-046's; `R122c`/`R122d` document the filtered URL. Tests use scripted `TopicSearching` answers.

## Tests

`App/SwiftHFRTests/Reader/Search/TopicSearchModelTests.swift`: target of a match (page left to HFR), no message number, no result, author alone, no criterion, every `TopicSearchError` message, second submit ignored, cancel drops the answer, cancelled search is not a failure, match on the page shown scrolls in place, a match elsewhere opens a reader above at its message. `ReaderTarget(searchMatch:)` is tested directly (`R52a`'s Location, a differing `page=`, a foreign topic, no anchor). Gates use `ReaderGate` signals, no wall-clock waits. Written in the cloud, run by CI; mutation runs are left to the Mac check.

## Pending capture

- **Filter (GAP-135 is parity, so this is a tracked loss):** `R122c`/`R122d` verify that the filtered results are a plain GET of the `R52a` `Location` plus `filter=1`. A filter could therefore be offered without the uncaptured POST (POST without `filter`, then GET `Location` + `filter=1`); it needs a reader source that takes a query, so it is a follow-up issue, not a silent drop.
- `transsearch.php` POST **with `filter=1`**: whether it answers the `R52a` redirect plus `filter=1` (`R122c` is the GET). Until then the sheet has no "Filtrer" toggle and sends no `filter`.
- A continued search (`firstnum`/`currentnum`, "next results"): "Stepping not tested" (HFR-PROTOCOL §7 E28). No results mode in the reader.
- Searching a private conversation (`cat=prive`): `transsearch.php` and its `Location` there are not captured, so no entry is offered.
- **Departure from legacy:** legacy sent the page form's hidden `p` (`TopicSearchService.swift:45-48`; `R52a` sent `p=1`). `ReaderPage` does not expose it, so the sheet omits it: a body neither legacy nor a capture sent. Needs a capture of a `transsearch.php` POST without `p` (`host: mac`) or `ReaderPage` exposing the form's `p`; the Mac check list asks for it.

## Intentional differences from legacy

See UX evolutions. Open at the message through `numreponse` instead of requesting the `Location`.

## Learnings

- Read the message number of a search `Location`, not its `page=`.
