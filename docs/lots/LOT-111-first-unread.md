# LOT-111 — First-unread landing and legacy separator (the "Nouveau" banner moved to LOT-178)

- **Module:** App · **Difficulty / model:** medium, Sonnet → Opus review
- **Issue:** [#202](https://github.com/ezzz/HFRnow/issues/202) · **Feature spec:** [FEAT-007](../features/FEAT-007.md) (proposed by Bybifok, `moust4ki`)
- **Depends on:** LOT-083 (reader), LOT-090 (position store)
- **Scope (UXD-11, 2026-11-02):** the (a) part only. The "Nouveau" banner is LOT-178 (#418, M5).

## Legacy counterpart
| Legacy | Used for |
|---|---|
| `ObjCTopicMessageContentBuilder.m:25-33` @ 2440d79 (GAP-063) | a separator after the flag message; no banner, no layout stability |
| `HFRswift/Swift/MessagesView.swift:646-656` (`WebView.ScrollPosition`, `InitialScroll`) @ 2440d79; anchors `21173e7:796-801, 979-1005` (cited by LOT-090) | the `t<numreponse>` anchor is the position's key |
| `ObjCTopicPageWorker.m:85` (`separatorRequested = anchor.length > 0`) @ 2440d79 | the separator is drawn when the link has an anchor |

## Behaviour
- **Anchor kept through redirects (#106)**: unchanged from LOT-083/095: `ReaderTarget(opening:)` reads the flag link's `#t` anchor; with `numreponse=M` the server picks the page and `page=` is never read alone.
- **Stable landing**: `reader.js` `landOnPost` scrolls to the message and re-scrolls on every image `load`/`error` and layout resize until the user touches the page or no image is pending. WebKit has no scroll anchoring.
- **Recording**: after scrolling pauses 500 ms, `reader.js` reports the topmost message (not a continuation block); `TopicReaderModel.recordPosition(post:token:)` records `ReadingPosition(page, messageNumber)` through `ReaderPositionRecording` (LOT-090 `advance`, forward only). Older documents, messages not on the page and logged-out sessions record nothing. The offset is not recorded (nil).
- **Legacy separator** (LOTS.md keeps it in this lot): `TopicHTMLBuilder.document(separatorAfter:)` adds `<div class="separator1">` after the message the anchor names, unless it is the last message of the page (`ObjCTopicMessageContentBuilder.m:25-33`); style `.separator1` dashed top border (`style-liste.css:124-126`). Legacy matches only an equal number: a flag message deleted from the page gets none.
- **Landing on a deleted flag message**: the first message after it opens (legacy `closePostID`, `ObjCTopicMessageContentBuilder.m:34-46`); no separator then. Legacy's last-message fallback is not ported: a link whose message is past the page's end opens at the top, as LOT-083 does.
- Separator colour: the app's `--separator`, not legacy's pseudo colour at 50% (`MessagesView.swift:2406`), and dashed as in `style-liste.css:124-126` (the light sheet's 2 px solid is not ported). Optional (b) item, UX of the themes lot.
- Releasing the pin: touch, wheel, key, any `scrollToPost`, or a scroll that moves `scrollY` more than 4 px away from where the pin last put it (VoiceOver, status-bar tap); releasing schedules a position report. Unverified, for the Mac check: that a VoiceOver scroll and a status-bar tap really move `scrollY` outside the pin's own scrolls, and that the 4 px tolerance neither releases on a pin's own scroll nor misses a short accessibility scroll.
- Account removal (`ReadingPositionStore.removeAccount`) is not wired by this lot: left open on #202.
- Restoring a stored position on opening a topic with no flag is not part of this lot (pending: the entry point, no spec row yet).

## Intentional differences from legacy
Layout stability while images load and a persisted position are new (GAP-063: UX change, Bybifok).

## Tests
`ReaderPositionTests` (model: recording, stale document, foreign message, continuation, forward-only live recorder, logged out), `TopicHTMLBuilderTests` and `TopicReaderModelTests` (separator), `ReaderLandingWebTests` (real web view: lands on the anchor, reports the topmost message). The pin against images that load late is not simulated (no held image response in `MockTransport`): Mac check list in the PR.

## Pending capture
None.
