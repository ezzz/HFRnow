# LOT-125 — List swipes and topic actions

- **Module:** App (`App/SwiftHFR/Navigation/`, `Reader/Actions/`, `Root/`)
- **Difficulty / model:** medium (Opus 5.5 → Fable 5.1)
- **Issue:** [#216](https://github.com/ezzz/HFRnow/issues/216) · **Feature:** [FEAT-008](../features/FEAT-008.md) (#152), the M2 half (UXD-08); the uniform swipe set is [LOT-177](LOT-177-uniform-swipes.md)
- **Depends on:** LOT-051 (flag writes), LOT-064, LOT-082, LOT-124, LOT-087 (message menu)

The behaviour, states and edge cases are in [FEAT-008](../features/FEAT-008.md); this file holds what is specific to the port.

## Legacy sources
`ezzz/HFRnow` @ `2440d79`, `HFRswift/Swift/`:

| Legacy | Used for |
|---|---|
| `Favorites.swift:31-93` (`ForumFavoritesTopicActionService.removeFavoriteFlag`) | the list POST, now LOT-051's `removeFavoriteFromList` |
| `Favorites.swift:841-886` (`markTopicAsRead`, `removeFavoriteFlag`) | "Lu" local only; removal then `removeTopic` |
| `Favorites.swift:1029-1097` (`TopicRowView` menu and swipes) | leading "Lu" (full swipe), trailing "Supprimer" ("Suppression..." while in flight), menu order |
| `MainWindow.swift:536-590, 649-693` (`markTopicAsRead`, `removeFlag`, `extraContextMenu`) | the same on a forum row with a flag; a removed flag keeps the row in the "all" list |
| `Common.swift:2261-2366` (`TopicQuickActionsConfiguration`, `TopicQuickActionPolicy`) | the five quick actions, all on; `lastReplyURL` per context; `copyLink` |
| `Common.swift:2875-2893, 2984-3093, 3175-3181` (`TopicListRowView`) | targets and scroll of each quick action; quick actions, divider, then the list's entries |
| `MessagesView.swift:1718-1730, 1945-1961` (`.favorite`, `performFavoriteAction`) | "Favoris" in the message menu |

## Legacy counterpart (app lots)
- `TopicListModel+RowActions.swift`: `Favorites.swift (markTopicAsRead, removeFavoriteFlag)` and `MainWindow.swift (markTopicAsRead, removeFlag)`.
- `TopicQuickActions.swift`: `Common.swift (TopicListRowView quick actions, TopicQuickActionPolicy)`.
- `TopicFlagActions.swift`: `Favorites.swift (ForumFavoritesTopicActionService)` and `MessagesView.swift (performFavoriteAction)`.
- `FavoriteActionHandler.swift`: `MessagesView.swift (the .favorite entry)`.
- `TopicListView.swift` (swipes, menu, alerts) and `TopicRowView.swift` (read mark, flag icon): already ported by LOT-082 / LOT-124.

## UX evolutions (app lots)
None: same UX as legacy (GAP-028, 029, 034 and 035 keep their legacy half here; their (b) half is LOT-177). Messages are in French and failures say why (GAP-035 "confirmed flag writes").

## Behaviour
- `TopicFlagActions` (environment, nil when logged out) wraps `TopicFlagFlow` in the current account's session behind `TopicFlagWriting`; it turns each `TopicFlagError` into a French reason saying whether anything left. The lists use `removeFavorite`, the message menu `addFavorite` (`FavoriteActionHandler`, registered in the reader with "Link" and the quotes; not in the offline reader).
- `TopicListModel` keeps the local state until the next successful load: `markedRead`, `removedFlags`, `removingFlags`, `actionFailure`. A failed load keeps them.
- `TopicQuickActions` builds a `TopicOpening` (target + "at the last message"); `NavigationModel.open(_:at:)` builds a new reader at it, even for the topic on screen (`readerGeneration` in the detail column's identity).
- Quick action targets: Première page = page 1; Dernière page = the row's last-page link without its anchor; Dernière réponse = the last post's link at the page's last message, the flags list ("Drapeaux & Favoris", legacy context `.favorites`) the last page at its last message; Page numéro… = 1 to the row's page count, proposed at its read page; Copier le lien = the first page as an absolute forum link.

## Edge cases
See FEAT-008. Also: a quick action on a row without a topic number reads the row's link; a link that is not a forum page offers nothing.

## Fixtures
None new: the models run on synthetic `TopicSummary` values and a scripted writer; LOT-051's tests cover the writes against `P03*`.

## Pending capture
None for this lot. The removal sentence that HFR picks for the browser or the legacy body is LOT-051's open point (both are accepted).

## Intentional differences from legacy
- "Supprimer" checks the session first and succeeds only on HFR's own sentence; legacy treated any 2xx answer as done, whatever its body (`Favorites.swift:43-93`). An answer that may have reached HFR is reported, never resent.
- "Favoris" shows HFR's sentence or why it failed; legacy showed "Favori mis à jour" for any answer.
- The page prompt lists the accepted pages ("Entre 1 et N"); legacy's sheet ignored an out-of-range page silently.
- "Lu" lasts until the next load of the list; legacy kept the opened URL in the view's state, so a mark could outlive a reload while the row's link was the same.

## Learnings
- A row action whose state lives in the list model must survive a failed reload and give way to a successful one: HFR's page is the truth.
