# LOT-114 — Filter posts view

- **Module:** App (`App/SwiftHFR/FilteredPosts/`, entries in `Navigation/`, `Root/`, `Reader/`, `Settings/`); the engine gains public initialisers on the LOT-093 result types
- **Difficulty / model:** medium (Sonnet 5.5 → Opus 5.5)
- **Issue:** [#205](https://github.com/ezzz/HFRnow/issues/205), GAP-036
- **Depends on:** LOT-093 (the flow, merged), LOT-083 (reader, merged), LOT-061 (pseudo lists, merged)

## Legacy sources
Read-only, `2440d79`.

| Legacy | Used for |
|---|---|
| `HFRswift/Swift/Favorites.swift:887-960` | start a run (progress at the row's page), cancel, "Aucun post n'a été trouvé" (3 s), error to an alert |
| `Favorites.swift:1045-1060` | the favourite row's menu entry "Filtrer les posts" |
| `Favorites.swift:1099-1135` | progress banner: spinner, text, "Annuler" / "OK" |
| `HFRswift/Swift/FavoritePostFilterService.swift:10-49` | progress text "N posts \| page X/Y", result subtitle "N posts \| A" or "A à B" |
| `HFRswift/Swift/MessagesView.swift:3946-3995` | next batch from `endPage + 1`; nothing found: finished plus "Aucun autre post trouvé"; failure: alert "Filtre impossible" |
| `MessagesView.swift:4727-4741` | bottom button "Résultats suivants" (arrow.forward), "Filtrage…" while it runs, disabled once finished |
| `Classes/FilterPostsQuotes.m:219-243` | start page = the favourite's current page; messages up to the `#t<id>` of its link are skipped |
| `HFRswift/Swift/AppSettingsView.swift:157-169, 443-452` | section "Filtrer les posts": minimum 3, 4, 5, 7, 10; toggle "Inclure les pseudos whitelistés" (`wl_pseudo` / `pseudo`) |

## Legacy counterpart
`Favorites.swift` (`FavoritePostFilterProgressBanner`, `FavoritePostFilterNavigationTarget`) and `MessagesView.swift` (filter mode) for the screens; `FilteredPostsFlow` (LOT-093) replaces `FilterPostsQuotes` and the ObjC renderer.

## Behaviour
- **`FilteredPostsModel`** (`@Observable @MainActor`, one per `NavigationModel`, so a run survives a change of column) drives everything; `FilteredPostsSource` (protocol, live: `FilteredPostsFlow`) reads the pages, cookie-less (LOT-093: no read flag moves, E25).
- **Entries:** long press on a favourites row (`TopicListView`, source `.favorites` only, as legacy) and the reader's menu (`secondaryAction`, any topic that names a `TopicID`). Both call `start(opening:)`: start page = the row's resume page, `after` = the message of its resume link (`#t<id>`), as legacy. A `numreponse` link names no page (issue #106): the row's `currentPage` is used and its message is `after`.
- **Run:** banner "N posts \| page X/Y" with "Annuler" (bottom inset of the split view). One run at a time. Cancelling shows nothing and no error. Nothing kept: the banner says "Aucun post n'a été trouvé" for 3 s ("OK" dismisses). A failure is an alert "Filtre impossible" with a French sentence per `FilteredPostsError`.
- **Result:** a sheet with the kept posts of the batch in the reader's web view (same document builder, normalizer and image policy, so the settings of LOT-106/107 apply), title = the topic, subtitle "N posts \| A à B". Read-only: no reply, no page bar.
- **"Résultats suivants":** reads from `endPage + 1` and **replaces** the batch (legacy). The button says what it does ("Lit les pages suivantes à partir de la page N et affiche les prochains posts retenus."). While it runs the bar shows "Filtrage des pages suivantes…" with "Annuler"; **cancelling or failing leaves the batch shown** and the button usable. A batch that keeps nothing marks the topic finished ("Aucun autre post trouvé", the button is replaced by "Fin du sujet"). `isFinished` from the engine also ends it.
- **Settings** ("Filtrer les posts" section of Réglages): minimum quotes (legacy choices plus a migrated stored value), "Inclure les pseudos whitelistés". Read when a run starts, so a change applies to the next run. Keys and shapes are legacy's (`filter_posts_min_quotes`, `filter_posts_quotes` `wl_pseudo` / `pseudo`).

## Edge cases
- A private conversation or a row without a `TopicID`: no menu entry on the list; the model answers "Ce sujet ne peut pas être filtré." if started anyway; the engine refuses a non-forum topic before any request.
- A stale run (cancelled, or superseded by `closeResult`) never delivers.
- Closing the sheet stops a running "Résultats suivants".

## Pending
- **Allowlist source:** `PseudoListStore` is not wired in the app yet (LOT-118 owns the lists screen and the store location). Until then `FilteredPostsServices.live(allowlist:)` receives an empty list: the toggle is stored and honoured by the criteria, but no pseudo is allowlisted. LOT-118 passes the store's allowlist minus the blocklist.
- **Links inside the filtered view** open in the in-app or default browser (setting `open_links_in_default_browser`); a forum link does not open a reader from there (no `ReaderTarget` stack in a sheet). Follow-up if the Mac check finds it needed.
- **Dynamic Type XL, light/dark, iPad layouts:** Mac check (see the PR).

## Fixtures
None: the model is tested with a scripted `FilteredPostsSource`; the engine reads are LOT-093's fixtures.

## Intentional differences from legacy
1. The result is a sheet, not a pushed screen; the reader menu entry is new (the issue asks for it; legacy had the favourites menu only).
2. "Résultats suivants" can be cancelled and explains itself (acceptance criteria of #205).
3. Page 1's opening post, long pseudos and `after` by number: LOT-093's differences apply.
