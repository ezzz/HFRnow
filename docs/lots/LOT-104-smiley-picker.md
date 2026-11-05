# LOT-104 — Smiley picker (catalogue, favourites, insert)

- **Module:** App (`App/SwiftHFR/Smileys/`, entry point in `App/SwiftHFR/Composer/`)
- **Difficulty / model:** medium (Sonnet 5.5 → Opus)
- **Issue:** [#195](https://github.com/ezzz/HFRnow/issues/195) (M2, legacy parity, no FEAT)
- **Depends on:** LOT-084 (reply composer), LOT-064 (`AppSmileyFavoritesStore`), LOT-012 (`CommonSmileyCatalog`), LOT-071 (policy C images)

## Legacy counterpart

Legacy app `master` of ezzz/HFRnow @ `2440d79`, `HFRswift/Swift/`. Functional reference only.

| Legacy | Replaced by |
|---|---|
| `AnswerView.swift:289-303` (`smileyPickerPanel`, large detent), `:517-535` (`insertSmileyCode` → `insertSnippet(" \(code) ")`) | `SmileyPickerView` (sheet from the composer), `SmileyInsertion` |
| `ReplyComposer.swift:176-196` (`ReplyTextInsertionEngine.insert`: replaces the selection, appends at the end without one) | `SmileyInsertion.insert` (UTF-16 caret, SwiftUI `TextSelection`) |
| `ReplySmileyCatalog.swift` (`BundleReplySmileyCatalogLoader.loadDefaultSmileys`: entries with `editor == true`, catalogue order) | `SmileyPickerModel.basic` over `CommonSmileyCatalog.bundled()` |
| `AnswerView.swift:1051-1470` (`CombinedSmileyPickerView`: collapsible sections, `@AppStorage` keys `AnswerView.smileys.basic.expanded`, `…appFavorites.expanded`; basic = insert on tap, favourites = detail) | `SmileyPickerView` (same keys, same tap behaviours) |
| `AnswerView.swift:1473-1632` (`FavoriteSmileyDetailView`: preview, code, insert, add/remove) | `SmileyDetailView` |
| `AnswerView.swift:737-760` (`updateFavoriteSmiley`: "Smiley ajouté aux favoris", "Smiley retiré des favoris", "Erreur :/") | `SmileyPickerModel.setFavorite` (LOT-064 store, legacy `SmileyCache` semantics) |
| `AnswerView.swift:1634-1760` (`SmileyGridCell`, `SmileyThumbnailView`: animated GIF, caches, ImageIO fallback) | `SmileyThumbnailView`, `SmileyImageLoader` |

## Behaviour

- Button "Smileys" in the keyboard toolbar of the reply sheet opens the picker (large sheet). Choosing a smiley inserts
  ` code ` (the code between two spaces, as legacy) over the editor's selection, at the end when there is none, puts the
  caret after it and gives the editor focus back. The insertion goes through `ReplyComposerModel.update`, so the draft
  autosave and every composer rule apply; nothing is inserted before the draft was read.
- "Smileys basiques": catalogue entries with `isEditorSmiley`, catalogue order; a tap inserts and closes.
- "Favoris de l'app": the account's LOT-064 favourites, oldest first; a tap opens the detail (preview, code, "Insérer",
  "Retirer des favoris"). A removal closes the detail. Notices (2.5 s) use legacy's texts.
- Images: `ReaderImageFetcher` (cookie-less client, policy C, forum hosts only), decoded with ImageIO, animated GIFs as
  `UIImage` animations, cached in an `NSCache` (400 entries). A cell whose URL did not change does no work (LESSONS 49).
- UI strings in French.

## Differences from legacy (intentional)

- Smileys are downloaded, not bundled: the app ships no GIF files (the catalogue's URLs are on the forum image host).
  Legacy's remote path used `URLSession.shared`; ours is the cookie-less policy-C fetcher.
- The detail is a medium sheet, not an overlay card.

## Not in this lot (pending, no capture invented)

- "Smileys du forum" section (profile favourites, LOT-027's `UserProfileSmiley`) and the search with keywords and history
  (LOT-053, `SmileySearchHistoryStore`): own lots. Legacy only adds a favourite from those two entry points (a basic
  smiley has no detail), so **adding** a favourite is wired in the detail view and the model (`setFavorite`, tested) but
  not reachable until they land; reading and removing are.
- Importing the legacy favourites file is LOT-067; iCloud mirroring is LOT-172.

## Tests

`SmileyInsertionTests`, `SmileyPickerModelTests`, `ReplyComposerSmileyTests` (Swift Testing, `App/SwiftHFRTests/`).
