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
- Layout (#600, operator decisions of 2026-11-07), top to bottom: the system search field (`.searchable`, always shown in the
  navigation bar; it was a bottom bar nobody saw), then the sections "Smileys de base", "Smileys du forum", "Favoris de l’app"
  (a section of the account's own created smileys comes after the forum one once #601 is captured).
- "Smileys du forum" (GAP-087): the `<img src alt>` of `#dynamic_smilies` in the composer's own form (the page the composer
  fetches at send time), read by `HopFormParser` into `ForumForm.dynamicSmileys` (LOT-036, differential test on `R47u1`); the picker
  fetches the form when it opens (`ReplyPosting.forumSmileys`). A tap opens the detail like an app favourite. Loading, "no
  favourite on your account" and "could not be read" are three distinct states; a failed read is never shown as an empty list.
  *Pending capture*: the public-topic reply, new-topic and edit forms of an account **with** favourites (only the MP reply form
  `R47u1` is captured with some); legacy read them on every form fetch (`ReplyService.swift:249-252` @ 2440d79).
- Any smiley (basic, forum, favourite, search result) has a context menu "Ajouter aux favoris" / "Retirer des favoris"; the
  empty "Favoris de l’app" explains it.
- "Smileys de base": catalogue entries with `isEditorSmiley`, catalogue order; a tap inserts and closes.
- "Favoris de l’app": the account's LOT-064 favourites, oldest first; a tap opens the detail (preview, code, "Insérer",
  "Retirer des favoris"). A removal closes the detail. Notices (2.5 s) use legacy's texts.
- Images: `ReaderImageFetcher` (cookie-less client, policy C, forum hosts only), decoded with ImageIO, animated GIFs as
  `UIImage` animations, cached in an `NSCache` (400 entries). A cell whose URL did not change does no work (LESSONS 49).
- UI strings in French.

## Differences from legacy (intentional)

- Smileys are downloaded, not bundled: the app ships no GIF files (the catalogue's URLs are on the forum image host).
  Legacy's remote path used `URLSession.shared`; ours is the cookie-less policy-C fetcher.
- The detail is a medium sheet, not an overlay card.

## Not in this lot (pending, no capture invented)

- Search, keywords and history (GAP-088): LOT-105 ([#196](https://github.com/ezzz/HFRnow/issues/196), spec `LOT-105-smiley-search.md`). Legacy only adds a
  favourite from search results and from the forum section (a basic smiley has no detail), so **adding** a favourite is
  in the detail view and the model (`setFavorite`, tested) and reachable from the search results since LOT-105; reading and removing were already.
- "Mes smileys" (the member's own created smileys, "Smilies persos"): not captured, so not parsed (capture [#601](https://github.com/ezzz/HFRnow/issues/601), *pending capture*). #600 stays open (`Refs`) for it.
- Importing the legacy favourites file is LOT-067; iCloud mirroring is LOT-172.

## Offline and failures

Smileys are downloaded and cached in memory only: offline, each tile shows its code until the image arrives (never a
blank tile); an empty catalogue shows "Catalogue de smileys indisponible.". Bundling the GIFs is an option for M5.

## Entry point

"Smileys" in the sheet's top toolbar (always visible, also with a hardware keyboard). The editor's selection is saved
when the picker opens (the sheet takes focus) and used at insertion; hand check on iPhone and iPad.

## Tests

`SmileyInsertionTests`, `SmileyPickerModelTests`, `ReplyComposerSmileyTests` (Swift Testing, `App/SwiftHFRTests/`).
