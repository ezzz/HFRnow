# LOT-111 — First-unread landing (and the "Nouveau" banner, moved)

- **Module:** App · **Difficulty / model:** medium, Sonnet → Opus review
- **Issue:** [#202](https://github.com/ezzz/HFRnow/issues/202) · **Feature spec:** [FEAT-007](../features/FEAT-007.md) (proposed by Bybifok, `moust4ki`)
- **Depends on:** LOT-083 (reader), LOT-090 (position store)
- **Scope (UXD-11, 2026-11-02):** the (a) part only. The "Nouveau" banner is LOT-178 (#418, M5).

## Legacy counterpart
| Legacy | Used for |
|---|---|
| `ObjCTopicMessageContentBuilder.m:25-33` @ 2440d79 (GAP-063) | a separator after the flag message; no banner, no layout stability |
| `HFRswift/Swift/MessagesView.swift:796-801, 979-1005` (`WebView.ScrollPosition`, anchor) @ `21173e7` (cited by LOT-090) | the `t<numreponse>` anchor is the position's key |

## Behaviour
- **Anchor kept through redirects (#106)**: unchanged from LOT-083/095: `ReaderTarget(opening:)` reads the flag link's `#t` anchor; with `numreponse=M` the server picks the page and `page=` is never read alone.
- **Stable landing**: `reader.js` `landOnPost` scrolls to the message and re-scrolls on every image `load`/`error` and layout resize until the user touches the page or no image is pending. WebKit has no scroll anchoring.
- **Recording**: after scrolling pauses 500 ms, `reader.js` reports the topmost message (not a continuation block); `TopicReaderModel.recordPosition(post:token:)` records `ReadingPosition(page, messageNumber)` through `ReaderPositionRecording` (LOT-090 `advance`, forward only). Older documents, messages not on the page and logged-out sessions record nothing. The offset is not recorded (nil).
- Restoring a stored position on opening a topic with no flag is not part of this lot (pending: the entry point, no spec row yet).

## Intentional differences from legacy
Layout stability while images load and a persisted position are new (GAP-063: UX change, Bybifok).

## Tests
`ReaderPositionTests` (model: recording, stale document, foreign message, flag landing, no recorder). The pin in `reader.js` is not unit-tested: it needs late-loading images in a real web view; see the Mac check list in the PR.

## Pending capture
None.
