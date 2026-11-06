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
- Not ported yet: the "Filtrer les messages" and "Depuis le début du sujet" toggles, and the results mode with "next results" (`TopicSearchContext`): see Pending capture.

## Behaviour

- Button "Rechercher dans le sujet" in the reader's toolbar (needs `ComposerServices.topicSearcher`, set for the current account, and a page that names its topic). It opens `TopicSearchSheet` (medium/large detents).
- `TopicSearchModel` (`@Observable @MainActor`): `word`, `author`; `canSubmit` when one is non-blank and no search runs; `submit()` sends one `TopicSearchQuery` (trimmed values, `filterEnabled: false`, no `p`, no continuation) through `TopicSearching` (live: `TopicSearchFlow`), one search at a time.
- `state`: `idle`, `searching`, `failed(message)`; closing the sheet cancels and drops a late answer. Messages (French): no result "Aucun résultat n'a été trouvé." (never an empty screen); logged out or no token "Connecte-toi pour rechercher dans ce sujet."; HFR's own refusal message when it gave one; transport "Impossible de joindre le forum."; unreadable answer, off-topic `Location` or no message number "Réponse inattendue du forum.".
- **Match**: the flow returns a `Location` of the searched topic (`R52a`). Its `page=1` is not the page of the match (`R122d`: the same URL without `filter` is a plain page 1), so the reader opens `ReaderTarget(source: .topic, anchor: n, numreponse: n)` with `n` read from the `#t<n>` anchor: HFR picks the page holding `n` (`R25`, issue #106) and the reader scrolls there; when the page shown holds `n` it scrolls in place (`TopicReaderModel.open`). A `Location` without anchor is an error message, never a guess.
- No new `reader.js` message: nothing is read from the web view. `TopicReaderModel.swift` is untouched (all code is in `Reader/Search/`).

## Edge cases

- Word and author blank or whitespace only: the button stays disabled, nothing is sent.
- Double tap on "Rechercher": the second is ignored while the first runs.
- The sheet closes while the search runs: cancelled, its answer opens nothing.
- A match on the page already shown: scroll, no fetch.

## Fixtures

None new: `R52a` (the `Location`, meta only) and `R52b` (no match) are LOT-046's; `R122c`/`R122d` document the filtered URL. Tests use scripted `TopicSearching` answers.

## Tests

`App/SwiftHFRTests/Reader/Search/TopicSearchModelTests.swift`: target of a match (page left to HFR), no message number, no result, author alone, no criterion, every `TopicSearchError` message, second submit ignored, cancel drops the answer, cancelled search is not a failure, match on the page shown scrolls in place. Gates use `ReaderGate` signals, no wall-clock waits. Written in the cloud, run by CI; mutation runs are left to the Mac check.

## Pending capture

- `transsearch.php` POST **with `filter=1`**: whether it answers the `R52a` redirect plus `filter=1` (`R122c` is the GET). Until then the sheet has no "Filtrer" toggle and sends no `filter`.
- A continued search (`firstnum`/`currentnum`, "next results"): "Stepping not tested" (HFR-PROTOCOL §7 E28). No results mode in the reader.
- The `p` value of the topic page's search form is not exposed by `ReaderPage`; `R52a` sent `p=1` and the flow omits it. Whether HFR needs it is not captured (the POST answered with the legacy body is LOT-046's pending capture).

## Intentional differences from legacy

See UX evolutions. Open at the message through `numreponse` instead of the `Location`'s `page=1` URL.

## Learnings

- A search `Location` names `page=1` whatever the page of the match: read the message number, not the page.
