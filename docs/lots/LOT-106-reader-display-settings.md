# LOT-106 — Reader display settings (layout, signatures, swipe pages)

- **Module:** App (`App/SwiftHFR/Reader/`, `App/SwiftHFR/Settings/`); one key added to HFRStorage
- **Difficulty / model:** medium (Sonnet 5.5 → Opus 5.5)
- **Issue:** [#197](https://github.com/ezzz/HFRnow/issues/197)
- **Depends on:** LOT-083 (reader), LOT-060 (settings store), LOT-119 (settings screen)
- **Not here:** text size (one app-wide scale, LOT-169 #295: no second size setting or CSS size rule in the reader)

## Legacy sources
Read-only. `2440d79` unless noted; `master` @21173e7 for what is newer.

| Legacy | Used for |
|---|---|
| `HFRswift/Swift/AppSettingsView.swift:98, 136-139, 402-406` | `theme_style` (default 1 = Moderne), options Classique 0 / Moderne 1 |
| `HFRswift/Swift/AppSettingsView.swift:105, 152-155, 434-438` | `display_sig`, `yes` / `no`, picker "Afficher les signatures" |
| `HFRswift/Swift/MessagesView.swift:1363-1400` | style variables: header background, content padding-top 8 px (classic) / 0 (modern), content width |
| `Classes/ObjCTopicHTMLRenderer.m:83` | header tint alpha 0.15 (classic) / 0.03 (modern) |
| `master` `HFRswift/Swift/Common.swift:235-237`, `AppSettingsView.swift:94, 479` | key `topic_page_swipe_navigation` (default on), row "Swipe changement de page" |
| `master` `HFRswift/Swift/MessagesView.swift:5295-5320` | the swipe: 120 pt, 70 pt impulse, vertical < 0.5 × horizontal; next opens at top, previous at bottom |

**Legacy at `87fe0d1c`** (the reference since 2026-11-10, AGENTS.md §2; `b16eb82d`, beta feedback on #372, `backlog.md:66` HFR-098): a touch that **starts** inside a block that scrolls sideways never changes the page. A `touchstart` script walks up from the target to an element with `scrollWidth > clientWidth + 1` and `overflow-x` `auto` or `scroll` and posts the answer when it changes (`HFRswift/Swift/MessagesView.swift:1102-1142`, handler `horizontalScrollTouch`, `:980, 1265, 1658-1670`); the swipe's `DragGesture` returns early while it is true (`:3196`, `:5347-5349`, guard `:5403`, the swipe itself `:5398-5428`), and a page change resets it (`:3779`, `loadPage`, `5f6c411c`; `:4775`, the filtered-search path, `87fe0d1c`). The block's own scroll position does not matter: no swipe from inside a block, even at its edge. **Measured** ([Mac check of `87fe0d1c` on #372](https://github.com/ezzz/HFRnow/pull/372#issuecomment-6737029007), checks 4a to 4d): covered for `[fixed]`; **not for `[code]`** (check 4a'): HFR renders it as `ol.olcode`, legacy's `style-liste-*.css` gives `overflow: scroll` to `table.code p, table.fixed p` only, so a long `[code]` line is cut, not scrollable, and a fling on it still turns the page. The commit message's "[code]" is not what legacy does. Not in this lot, which shipped before it: [#672](https://github.com/ezzz/HFRnow/issues/672) ports it (`PageSwipe.of` gets the input, GAP-071). In SwiftHFR `table.code td` scrolls sideways too (`App/SwiftHFR/Reader/Resources/reader.css:123`), so the guard covers `[code]` there: an intentional difference for #672 to record.

## Behaviour
- **"Sujets" section** of the settings screen (`TopicsSettingsModel`, `@Observable @MainActor`): "Style des messages" (Classique / Moderne), "Afficher les signatures", "Swipe changement de page". Each reads its legacy key at creation (nothing written) and writes it back, in its legacy shape, on a real change. Other legacy "Sujets" rows stay with LOT-118 (blacklist) and LOT-084 (reply button); the smiley size stays dropped (LOT-119 table). LOT-119 had given "Style des messages" to LOT-121, but this issue's scope and GAP-052 name it here: the row is built here, LOT-121 owns the colours.
- **Layout** is `ReaderRenderOptions.style`: a `style-classic` / `style-modern` class on `<body>`, styled in `reader.css` (header tint 15 % / 3 % of the accent, content padding-top 8 px / 0). Default modern, as legacy and `SettingKey.themeStyle`. UXD-09 (2026-11-02): legacy style is the default, the other is offered as a value.
- **Signatures** (`display_sig`) already reached the document through `ReaderRenderOptions` (LOT-083); the settings row is new.
- **Live apply:** the reader listens to `UserDefaults.didChangeNotification` and calls `TopicReaderModel.applyDisplaySettings()`, which rebuilds the document from the typed page (no request, scroll position kept) only when the options differ from those of the document on screen.
- **Swipe:** `PageSwipe.of(translation:predictedEnd:page:maxPage:)` is the legacy rule as a pure function; the reader's `DragGesture` (simultaneous with the web view's) reads `topic_page_swipe_navigation` at the end of each drag. Next page opens at its top; previous at its last message (`AnchorRule.lastMessage`, the nearest existing form of legacy's "start at bottom").

## Edge cases
- Changing a setting while a page loads: the new options apply to that load (`renderOptions()` is read when the document is built); `applyDisplaySettings()` does nothing while loading or before a page is shown.
- A setting changed during a load that fails or is cancelled is applied when the load ends.
- A swipe while loading, on the first page (previous) or last page (next), does nothing.

## Fixtures
None: HTML structure and tests use the typed `ReaderPage` of the existing reader tests.

## Intentional differences from legacy
- Legacy ignored the swipe during a text selection (`isMessageTextInteractionActive`) and in its post-filter mode: neither exists in this reader (selection hand-check pending, GAP-071).
- Header colours use the accent colour; legacy's me / love header variants (`--color-message-header-me-background`, love colours) are not ported (they need the theme colours of LOT-121 and the own-message detection; GAP-052 follow-up).
- With the swipe setting off no gesture is attached to the web view (legacy `including: .none`).
- A rebuild after a setting change resets the images tapped to load (the web controller clears consent per document) and the scroll offset may drift by the header padding change; accepted for M2, to be refined if the hand check finds it annoying.
- "Bottom" of the previous page is the last message anchor, not the exact scroll end.

## Learnings
- `UserDefaults.didChangeNotification` is the cheap channel between the settings screen and an open reader, as both go through `UserDefaultsSettingsStore`.

## Hand check (host: mac, `mac/m2-lead`)
The drag gesture on the web view, its interplay with vertical scroll, text selection and LOT-137's pushed readers, and the classic / modern look are checked on a device: PR #460 checklist.
