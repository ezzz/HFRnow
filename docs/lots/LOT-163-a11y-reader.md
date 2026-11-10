# LOT-163 — Accessibility pass: reader and composer

- **Module:** App
- **Difficulty / model:** medium (Sonnet 5.5 → Opus 5.5)
- **Issue:** #253

## Legacy sources
Legacy accessibility is thin (GAP-202: "a few toolbar labels; message markup unlabelled"), so this lot is mostly new work (GAP-203):

- `HFRswift/Swift/AnswerView.swift:795,815,998-1195,2189-2225` @ `87fe0d1c`: the labels the composer's bars carried ("Brouillons", "Envoyer", "Vider le texte", "Annuler", "Rétablir", "Smileys", "GIF Giphy", "Insérer image", the tag labels, "Choisir une couleur", "Retour aux styles", the colour swatches). SwiftHFR already has them (`FormattingToolbar`, `BBCodeTag.label`, `ReplyTextColor`); this lot only checks them.
- `HFRswift/Swift/MessagesView.swift:3488,3509-3510,5015` @ `87fe0d1c`: loading label and next-page label (SwiftHFR: `ReaderPageControls`).
- `MessagesView.swift` `MessageBodyTextSizeCSS` (issue body): the reader's text size is already `-apple-system-body` plus `--text-scale` (LOT-083, LOT-169): no work, checked here.

## Legacy counterpart (app lots)
| SwiftHFR | Legacy @ `87fe0d1c` |
|---|---|
| `Reader/TopicHTMLBuilder.swift`, `Reader/Resources/reader.js`, `reader.css` | the message HTML of `ObjCTopicMessageContentBuilder.m` (no labels): none for accessibility |
| `Reader/TopicReaderView.swift`, `Composer/ReaderReplyFlow.swift` | `MessagesView.swift` (no announcements): none |
| `Composer/ReplyComposerView.swift`, `Composer/FormattingToolbar.swift` | `AnswerView.swift` (labels above) |
| `Reader/Viewer/ImageViewerView.swift` | `MessagesView.swift` `FullScreenPhotoViewer` (no labels) |

## UX evolutions (app lots)
GAP-202 / GAP-203 already carry the accessibility pass (class `b`: optional, never visible to sighted users). No new row; nothing visible changes. The page announcement ("Page 3 sur 12") is spoken only while VoiceOver runs.

## Behaviour
Nothing changes for sighted users. What is added, by where it lives (the reader's security is untouched: no page script, CSP `script-src 'none'`; the adapter `reader.js` runs in its own content world and only sets attributes on the DOM):

1. **Message structure (HTML built by `TopicHTMLBuilder`).** Each message stays an `article` labelled "Message de <pseudo>, <date>". The author becomes a level-2 heading (`role="heading" aria-level="2"` on a `span.byline` around the author), so the web rotor's "Titres" steps from message to message. The tappable avatar duplicates the author button, so it is hidden from assistive technologies (`aria-hidden`, `tabindex="-1"`); the author button takes the name "Menu de <pseudo>" and `aria-haspopup="menu"`, the `⋯` button too.
2. **Quotes, code, spoilers (adapter).** The tables HFR draws (`table.citation`, `oldcitation`, `quote`, `code`, `fixed`, `spoiler`) get `role="group"` and a name: the quote's own header ("user4 a écrit :"), "Citation", "Code", "Texte préformaté", "Spoiler". A blocklisted quote that hides its author is named "Citation masquée", never its header (the pseudo is hidden on screen). A spoiler header, and a collapsed blocklisted quote's header, become a `role="button"` with `aria-expanded` kept in step with `.open` and Enter/Space activation (the tap handler is a click, which VoiceOver's double tap already sends; keyboard and switch users need the keys). An opened blocklisted quote's header is a link container again and loses the role.
3. **Pictures (adapter).** A posted picture (`img.hfrplusimg`) with no `alt` gets "Image", so VoiceOver does not read a file name.
4. **Announcements (VoiceOver only).** The reader's feedback toast (`menuFeedback`) is announced by the toast itself, once, whoever set it (before, only some callers announced and the quote errors did not); HFR's reply confirmation banner is announced when it appears; a page change is announced ("Page 3 sur 12") because the web view's content changes under the focus; the composer's error and draft warnings are announced when they appear.
5. **Targets and containers.** The reply confirmation's dismiss button reaches 44 pt; the composer's formatting bar is one labelled container ("Mise en forme"); the image viewer names each picture "Image 2 sur 5".
6. **Keyboard focus.** `:focus-visible` draws an outline in the action colour (the page had none), so Full Keyboard Access shows where it is.
7. **Reduce Motion.** The reader has no animation or transition; a `prefers-reduced-motion` rule disables them for any later one. The Swift side has no `withAnimation` in the reader or the composer.

Checked, no change: Dynamic Type (`html { font: -apple-system-body }`, sizes in `em`, `--text-scale`), contrast (`--secondary` on both surfaces and Increase Contrast measured in #568), page controls and composer labels (already present), actions without gestures (every message action is in the `⋯` menu, the page swipe has buttons, the scrubber's adjustable action moved to M5 with LOT-112).

## Edge cases
- A message hidden behind a blocklisted author: its summary is a native `summary` (focusable, announces expanded state); inside it the byline is the heading.
- A continuation block has the heading too (it repeats the author), as it has the article label.
- Author menus off (setting): the author is a plain `span`, still inside the heading; no avatar button exists to hide.
- The same feedback text twice in a row is announced twice (the serial changes).
- A page change of the same number (refresh) is not announced; the first load is not announced.

## Fixtures
None needed: tests build pages with `TopicHTMLBuilder` and run the real adapter in a `WKWebView` on hand-written markup shaped as HFR's (`Packages/HFRKit/Tests/HFRParsingTests/Fixtures/captures`, spoiler and citation tables, anonymised).

## Intentional differences from legacy
Legacy had no message labelling; every item above is new (GAP-202, GAP-203).

## Mac checks (device)
VoiceOver on iPhone and iPad: heading rotor over a topic page, quote/spoiler/blocklisted-quote activation, `⋯` and author menus, reply sent and error announcements, page change announcement, image viewer; Dynamic Type XL and AX5, Increase Contrast, Reduce Motion; Full Keyboard Access on a spoiler.

## Learnings
To copy into AGENTS.md §11 when the lot closes: a feedback toast announces itself (one place), the callers do not.
