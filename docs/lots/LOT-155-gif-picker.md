# LOT-155 — GIF picker in the composer (Giphy)

- **Module:** App (`App/SwiftHFR/Composer/Gif/`, entry point in `App/SwiftHFR/Composer/`)
- **Difficulty / model:** easy (Sonnet 5.5 → Opus)
- **Issue:** [#245](https://github.com/ezzz/HFRnow/issues/245) (M2, legacy parity, GAP-089)
- **Inputs:** [LOT-098](LOT-098-giphy-client.md) (`GiphyClient`) · [LOT-071](LOT-071-third-party-services.md) (T5, R1, N1) ·
  [ADR 0007](../adr/0007-third-party-api-keys.md) · [LOT-084](LOT-084-reply-composer.md) · [LOT-104](LOT-104-smiley-picker.md) (picker pattern) ·
  [LOT-185](LOT-185-liquid-glass-surfaces.md) (glass rules) · captures `T40`, `T41`

## Legacy sources

Lines of <https://github.com/ezzz/HFRnow> @ `2440d79`.

| Concern | Legacy |
|---|---|
| Toolbar button "GIF Giphy" (`g.circle`) opening the panel | `HFRswift/Swift/AnswerView.swift:525-535` |
| Panel: SDK `GiphyViewController`, rating R, confirmation screen, `.gifs` and `.recents` | `AnswerView.swift:2286-2335` |
| What is inserted | `AnswerView.swift:2333` (`[img]<original gifUrl>[/img]` and a line break) |

## Legacy counterpart (app lots)

| SwiftHFR | Legacy @ 2440d79 |
|---|---|
| `GifPickerView`, `GifConfirmationView` | `AnswerView.swift (GiphyPanel, GiphyViewController)` |
| `GifPickerModel` | `AnswerView.swift (GiphyPanel.Coordinator.didSelectMedia)` |
| `ReplyComposerView` toolbar "GIF" | `AnswerView.swift (ComposerToolbarButton "GIF Giphy")` |

## UX evolutions (GAP-089)

- **b·needed** — Notice N1 before the first request (LOT-071; legacy had none): host and operator named, search terms the only data sent,
  the chosen GIF is published by its address. Accepted once per device (`giphy_notice_accepted`).
- **b·needed** — The button is absent from a build without a Giphy key (ADR 0007).
- **b·needed** — Only `https` GIFs on `giphy.com` or a subdomain are shown or posted (LOT-098 edge case).
- **b** — No "recents" tab (legacy `.recents`); our own grid instead of the SDK's, same flow: tap, confirmation, insert.
- Otherwise the same UX: rating R, `[img]<url>[/img]` and a line break at the caret.

## Behaviour

- "GIF" in the sheet's top toolbar (`g.circle`, next to Smileys and Image), shown only when `GifServices.isAvailable` (key and base URL
  from `Info.plist` keys `GiphyBaseURL` and `GiphyAPIKey`, build settings `GIPHY_BASE_URL` and `GIPHY_API_KEY`, `App/Config/`). Disabled until the draft
  is read. The caret is saved when the button is tapped (the sheet takes focus) and used at insertion; focus returns to the editor.
- **Nothing is contacted before the panel opens, nor before N1 is accepted.** Opening shows the notice; "Continuer" remembers it
  and loads trending, "Annuler" closes the panel. `start`, `submitSearch`, `loadMore` and `retry` stop at the same gate (tests).
- Trending first; the search field (submit) searches; an empty field goes back to trending. Rating `r` (legacy). 25 per page, the next page loads
  when the grid reaches its last five items; repeated ids are dropped; an empty page ends the list. A failed first page shows its reason and "Réessayer";
  a failed next page keeps the list and offers "Réessayer".
- Tapping a GIF opens a confirmation (legacy `showConfirmationScreen`): preview and "Insérer"; the snippet is `[img]<url>[/img]` and a line break, put
  through `ComposerFormattingModel.insert`, so the draft autosave and every composer rule apply.
- **Which URL is posted:** `images.original.url` **as served**, query included (what `T40`/`T41` verify and what the SDK's `gifUrl` gave). The
  query-less form (`originalURLWithoutTracking`) is not captured as serving the GIF, so it is not posted; its `cid` is derived from the key
  (a fingerprint, not the key). **Pending capture**: one fetch of a media URL without its query; if it serves, a later change can post that form.
- **Images** (grid and confirmation) go through `SmileyImageLoader` → `ReaderImageFetcher`: the cookie-less client, policy C, no `Referer`.
  `allowsThirdParty` is true only for these two views (the member opened the panel and accepted N1) and only URLs that pass
  `GifMediaPolicy` reach them.
- LOT-185 rules: the search bar is a `safeAreaBar` at the bottom without fill, no hand-made glass, no `.background(.bar)`.
- Request without `lang`: kept (Giphy documents it as optional); the captures used `lang=en` on search. **Mac check**: results with the real key.
- UI strings in French.

## Edge cases

- No key (or an unexpanded `$(…)` setting, or a non-`https` base URL): no button, no request.
- Notice declined: panel closes, nothing was sent; it asks again next time.
- A response older than the last search is dropped (generation counter).
- `429` says so in French; other statuses and an unreadable answer say the service answered unexpectedly.
- A GIF with a preview off Giphy's CDN shows an empty tile (not loaded); one with an original off it is dropped.

## Fixtures

`T40` (search) and `T41` (trending), read in place from `Packages/HFRKit/Tests/HFRParsingTests/Fixtures/captures/`, answered through `MockTransport` to the real
`GiphyClient`. Keys in tests are fakes (`DUMMYKEY0123`); no real request.

## Tests

`GifPickerModelTests` (gate before N1, accepting loads trending, search and empty field, snippet, off-CDN items dropped, paging, failures) and
`GifServicesTests` (configuration from `Info.plist`, no key, `GifMediaPolicy`), in `App/SwiftHFRTests/Composer/`.

## Mac check needed

Real key in `App/Config/Secrets.xcconfig`: button visible; first open shows N1, "Annuler" sends nothing (proxy or Charles); trending, search,
paging, confirmation, insertion at the caret, animation of previews; light, dark, Dynamic Type XL, iPhone and iPad; build without key: no button.
No post is sent to HFR from the check unless the operator decides.

## Intentional differences from legacy

See "UX evolutions".

## Learnings

- A client that only checks `https` on media URLs leaves the host policy to the app: keep it in one place (`GifMediaPolicy`) and filter before the view.
