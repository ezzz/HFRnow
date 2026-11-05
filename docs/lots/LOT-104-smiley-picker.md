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

- Button "Smileys" in the toolbar of the reply sheet opens the picker (large sheet). Choosing a smiley inserts
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

- Search, keywords and history (GAP-088): LOT-105 ([#196](https://github.com/ezzz/HFRnow/issues/196)). Legacy only adds a
  favourite from search results and from the forum section (a basic smiley has no detail), so **adding** a favourite is
  in the detail view and the model (`setFavorite`, tested) but not reachable until LOT-105 lands; reading and removing are.
- "Smileys du forum" section (GAP-087, profile favourites, `UserProfileSmiley`): no lot owned it; it has its own issue
  (see the PR), so #195 stays open (`Refs`) until it is done or the operator cuts its scope.
- Importing the legacy favourites file is LOT-067; iCloud mirroring is LOT-172.

## Offline and failures

Smileys are downloaded and cached in memory only: offline, each tile shows its code until the image arrives (never a
blank tile); an empty catalogue shows "Catalogue de smileys indisponible.". Bundling the GIFs is an option for M5.

## Entry point

"Smileys" in the sheet's top toolbar (always visible, also with a hardware keyboard). The editor's selection is saved
when the picker opens (the sheet takes focus) and used at insertion; hand check on iPhone and iPad.

## Tests

`SmileyInsertionTests`, `SmileyPickerModelTests`, `ReplyComposerSmileyTests` (Swift Testing, `App/SwiftHFRTests/`).
