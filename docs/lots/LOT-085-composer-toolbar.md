# LOT-085 — Composer formatting toolbar and insertion engine

- **Module:** App (`App/SwiftHFR/Composer/`)
- **Difficulty / model:** medium (Sonnet 5.5 → Opus)
- **Issue:** [#177](https://github.com/ezzz/HFRnow/issues/177) · **Depends on:** LOT-084 (#176)

As a poster, I want buttons for HFR's BBCode tags, so that I format without typing tags by hand.
Absorbs feedback 'BBCode toolbar' (p. 505), 'link paste helper' (p. 497) and cursor jumps (p. 506).

## Legacy counterpart

`BBCodeTag`, `wrapWithBBCode`, `splitQuote` and `insert` exist at `2440d79` (`ReplyComposer.swift:59-139`, GAP-085); `textForEmptySelection`, `wrapSelectionWithURL`, the colours, the toolbar and the clipboard helper are newer: `origin/master` @ 21173e7.

| Legacy | Here |
|---|---|
| `ReplyComposer.swift` `BBCodeTag` (9 tags, labels, symbols) | `BBCodeTag` |
| `ReplyComposer.swift` `ReplyTextInsertionEngine` (`wrapWithBBCode`, `wrapSelectionWithURL`, `splitQuote`, `insert`) | `ReplyTextInsertionEngine` |
| `AnswerView.swift:54-86` `ReplyTextColor` (16 colours) | `ReplyTextColor` |
| `AnswerView.swift:1205-1320` `performFormatting`, clipboard candidates; `:530-565` alert | `ComposerFormattingModel` + alert in `ReplyComposerView` |
| `AnswerView.swift:1060-1135` toolbar and palette | `FormattingToolbar` |

## Behaviour (legacy parity)

- Selection: `[tag]sel[/tag]`, caret after. No selection: empty tags, caret between. Colours write `[<hex>]…[/<hex>]`.
- `url` with a selection and an http(s) clipboard URL: alert "Utiliser le presse-papiers ?" (Oui → `[url=<clip>]sel[/url]`,
  Non → `[url]sel[/url]`). Empty selection and non-blank clipboard text: alert offering to wrap that text. A clipboard
  content already inserted (same `changeCount`) is not offered again; refusing does not mark it used (legacy).
- `splitQuote` (cursor strictly inside a `[quotemsg=…]` block) is ported and tested; no button calls it yet (legacy button
  is part of the quote lot).

## Differences

- Ranges are clamped in the engine (legacy: in the view). The caret is set from the engine's result after every edit
  (`cursorRevision`) through `TextEditor(text:selection:)`: the editor never jumps to the end.
- Buttons show SF Symbols for every tag (legacy: letters "G", "I", "S", "IMG", "CODE") and the colour label is "Couleur <nom>" (legacy adds the hex): a (b) item for M5 if parity is wanted. Buttons are dimmed and disabled while the composer cannot edit. The caret goes to the end after the draft restore (legacy on appear). GAP-084's quote splitting now points here (engine only).
- Toolbar is a bar under the editor, above the keyboard, not the legacy floating capsule: layout only, no behaviour change.
- `insert` (smiley codes) is in the engine and model, not wired to a button here.

## Pending

Hand check on simulator/device (caret after each tag, palette, clipboard alerts, Dynamic Type XL, dark mode).
