# LOT-109 — Image viewer and HD gallery

Spec: [FEAT-014](../features/FEAT-014.md). Issue [#200](https://github.com/ezzz/HFRnow/issues/200), feature [#158](https://github.com/ezzz/HFRnow/issues/158). Found by Bybifok (moust4ki), credit kept.

## Legacy counterpart
Repository <https://github.com/ezzz/HFRnow> at `2440d79`.

| Legacy | Replaced by |
|---|---|
| `HFRswift/Swift/MessagesView.swift:5643-5746` (`FullScreenPhotoViewer`: black, close button, drag to dismiss) | `ImageViewerView` (`App/SwiftHFR/Reader/Viewer/`) |
| `:5790-…` (`ZoomableRemoteAnimatedImageView`, max zoom 7.5) | `ZoomableImage` / `ZoomScrollView` |
| `Classes/SimplePhotoViewController.m` (older ObjC viewer: zoom to 4, double tap) | same |
| `:2430-2490` (`MessageImagePhotoLibrarySaver`, add-only Photos access) | `PhotoLibrarySaver` |
| `:1240-1275` (context menu: open, "Save to Photos", "Copier le lien") | the viewer's menu |
| `:3298-3312`, `:2202-2215` (`normalizeImageViewerURL`) | `ImageHostTable.fullSizeURL` (LOT-056) via `ImageGallery` |
| `:5748-5762` (`PhotoViewerNetworkRequestFactory`, `Referer` for `reho.st`) | `ReaderImageFetcher.image(at:allowsThirdParty:hostTable:)` |

## Behaviour
- `reader.js` posts `image` (`urls`: the original `src` of the loaded `img.hfrplusimg`, `index`) on a tap; `ReaderBridgeMessage.image` decodes it whole or not at all (entry that is not a string, index outside the list, more than 5 000 entries: rejected).
- `ReaderWebController.openViewer` builds the gallery with `ImageGallery.build`: policy C and the consent set decide, not the page. `TopicReaderView` presents `ImageViewerView` full screen.
- `ImageViewerModel` (`@Observable @MainActor`) holds the states, downloads the selected image and its neighbours, falls back to the thumbnail, and runs save / copy / retry through `ImageViewerServices` (stubbed in tests).
- Save needs `NSPhotoLibraryAddUsageDescription` (already in the build settings); share is a `ShareLink` on the downloaded bytes (never the URL, which the system would fetch outside policy C). `FilteredPostsView` wires the same viewer.

## Intentional differences from legacy
1. Swipe between the pictures of the page (legacy: one picture).
2. Downloads go through the cookie-less client with redirect-by-redirect policy (legacy: `URLSession.shared`, default cookies and redirects).
3. A visible **Fermer** button, always shown, and no drag-to-dismiss (a full-screen cover has none; the legacy toggled the button on tap and dismissed by dragging).
4. Share (bytes) added; "Enregistrer dans Photos" in French.
5. Animated images are still in this lot (pending Mac check).

## Scope note
`docs/LOTS.md` listed the swipe gallery as LOT-176 (M5); issue #200 (the single description of this lot) includes it, so it is here. LOT-176 (#416) is to be closed or reduced by the orchestrator.

## Decoding
The viewer decodes in the app, not in WebKit's process: `ViewerImageCheck` refuses bytes that are not an image or that claim more than 100 million pixels, and the bitmap is sampled to 4096 px on its longest side.

## Tests (`App/SwiftHFRTests/Reader/`)
`ImageViewerCheckTests`, a real-`WKWebView` test of the `reader.js` tap, `ImageGalleryTests`, `ImageViewerModelTests`, `ReaderImageViewerBridgeTests` (decoder, controller filtering by consent, `Referer` per host and per hop).

## Pending capture / Mac check
Capture #134 is reviewed (#328): a real `reho.st` image answers 403 without `Referer` and 200 `image/jpeg` with `Referer: https://forum.hardware.fr/` (`T30`-`T33`, `https` and `http`, no redirect). The viewer's full-resolution fetch now sends that value (legacy sent no trailing slash, seen working only on a path naming no file, `T24`); `ReaderImageFetcherTests.theViewerFetchSendsTheRefererTheCaptureRequires` runs on the metas and fails with the no-slash value. Not observed: `https://reho.st/self/<hash>.jpg` (the app upgrades `http` to `https`; `https` was captured on `/preview/self/` only). Device look and behaviour: see the PR's "Mac check needed".
