# LOT-174 — Composer formatting toolbar (M4)

- **Module:** App
- **Difficulty / model:** medium (Sonnet → Opus)
- **Issue:** [#414](https://github.com/ezzz/HFRnow/issues/414) · **Milestone:** M4 (moved from M5 by the operator, 2026-11-07, after the beta-test finding [#592](https://github.com/ezzz/HFRnow/issues/592))
- **Split from:** LOT-085 (#177), the (b) half; the (a) half keeps the legacy behaviour.

Stub created on 2026-11-02 with the operator decisions on [#379](https://github.com/ezzz/HFRnow/issues/379): the evolutions of M1–M4 go to M5, never dropped. The author of the lot completes it before coding (AGENTS.md §5).

## Legacy sources
None: this is an evolution, not a port. The legacy behaviour is cited in LOT-085 (composer insertion engine).

**Legacy at `2fe43da3`** (catch-up of #655; the parity reference by the operator decision of 2026-11-08 on #655, which AGENTS.md §2 states once #660 lands): the visible formatting bar is **in the reference**, so "none" above holds for `2440d79` only. `143ea5f0` adds a bar toggled by the composer's `textformat` button ("Afficher les styles" / "Masquer les styles"), shown above the control row (`composerToolbar`, `HFRswift/Swift/AnswerView.swift:942-962`; button `:1040-1053`; bar `formattingBar`, `:1056-1074`, its content `:1075`- @ `2fe43da3`). LOT-085 ported its tags, colours and clipboard helpers from `21173e7`, an ancestor of `2fe43da3`. Related rows of the #655 sweep:
- "Lien" on a selection with a URL in the clipboard (`6c0c23f3`: `performFormatting`, `:1228-1240`; `clipboardURLCandidate`, `:1304`): the `[url]` with a selection path below, parity.
- Caret fixes of legacy's `UITextView` bridge (`7844a011`, `12f6c91b`, `c6e59bec`: the editor scrolls to keep the caret visible after a text or selection change, `scheduleCaretVisibilityUpdate`, `:3208-3218`; caret after an insertion; bottom-bar taps): SwiftHFR sets the caret from the engine's result (LOT-085, `cursorRevision`) in a native `TextEditor`; that the caret stays visible while typing and after an insertion is part of the composer Mac check of [#653](https://github.com/ezzz/HFRnow/issues/653).

## Legacy counterpart (app lots)
None @ 2440d79 (new UX). The code says so in its `// Port of …` header: "none @ 2440d79" (AGENTS.md §4).

## UX evolutions (app lots)
- **UXD-18**, GAP 084, 085, 086 in `docs/migration/GAP-LEGACY-VS-SWIFT.md`: class `b`, optional, never the default: a setting or a separate entry keeps the legacy UX by default ([UX principles](../FEATURES.md#ux-principles-operator)).

## Behaviour
Delivered by #598 (the first slice; the rest of the lot is still to write), on top of the merged LOT-085:
- **Size** (`ComposerBarMetrics`): a cell is 48 pt in regular density and 40 pt in compact, times Dynamic Type (`@ScaledMetric`, LOT-169) and the text scale; the colour swatch is half a cell, the symbol 0.4 of it.
- **`[url]`**: with a selection, today's path (clipboard link → `[url=<clip>]sel[/url]`). With nothing selected and a non-blank clipboard text not already used, the alert offers both legacy forms (`HFRTextView.m:205-262`, `:308-350` @ 2440d79): `[url=<clip>][/url]` with the caret between the tags, or `[url]<clip>[/url]`; "Sans le presse-papiers" writes the empty `[url][/url]` and, as in legacy, does not mark the clipboard used (the choice is offered again until a form is picked); without such a clipboard text, `[url][/url]` is inserted with no choice.
- **Icons**: the top upload button is `photo.badge.plus`; the bottom `[img]` tag keeps `photo`.

## Composer layout and control row ([#653](https://github.com/ezzz/HFRnow/issues/653), M4)

Why here: #653 moves this lot's bar behind **Aa** and brings back legacy's control row around it; the rest is the composer's own
layout. One spec keeps both (AGENTS.md §2: no new document when one has the role); LOT-084 points here.

**Legacy at `87fe0d1c`** (the reference, AGENTS.md §2; the `2440d79` lines #653 cites are re-located):
- Presentation: a full-screen cover (`coverVerticalFullScreen`, `HFRswift/Swift/MessagesView.swift:5429-5443`, helper `:6019-6031`);
  at `2440d79` a `.large` sheet (`MessagesView.swift:4538-4550`). Nothing shows the message being answered.
- Header (`composerHeader`, `AnswerView.swift:768-819`): close `xmark` and, for a reply, a drafts button `tray` ("Brouillons") on the
  left; title in the middle; send `arrow.up` ("Envoyer", spinner while posting) on the right.
- Control row (`composerToolbar`, `:940-962`): the formatting bar above the row when shown; the row is `editionGroup` (`:994-1011`:
  "Vider le texte" `xmark.circle` in red, disabled when the text is empty; "Annuler" `arrow.uturn.backward`; "Rétablir"
  `arrow.uturn.forward`), a spacer, `insertionGroup` (`:1013-1054`: "Smileys" `face.smiling`, "GIF Giphy" `g.circle`, "Insérer
  image" `photo`, **Aa** `textformat`, "Afficher les styles" / "Masquer les styles", tinted while shown). Two rows when one does
  not fit (`ViewThatFits`, `:949-956`). Each group is a glass capsule (`ComposerToolbarGroup`, `:1656-1673`); every control is
  disabled while posting.
- Undo history (`:624-635`): every change of the text pushes the text before it, insertions included; at most 200; a new change
  empties redo. Undo and redo put the caret at the end (`performUndo`, `performRedo`, `:1352-1374`); "Vider le texte" empties the
  text without asking, caret at the start (`clearComposer`, `:1345-1350`), and is one step. The bar starts hidden
  (`isFormattingBarPresented = false`, `:367`); hiding it closes the palette (`:1047-1051`).

**SwiftHFR** (`ComposerControlRow`, `ComposerHistory`, `ComposerHeight`, `ReplyComposerView`):
- Top bar: "Fermer" (`xmark`, the close choice of LOT-084: keep / discard) on the left, the height toggle next to it, the title,
  "Envoyer" (`arrow.up`, spinner "Envoi en cours" while sending) on the right. Smileys, image and GIF leave the top bar for the row.
- Control row above the keyboard, legacy order and labels; the GIF button only when Giphy is configured (LOT-155); the upload
  symbol stays `photo.badge.plus` so it is not mistaken for the bar's `[img]` (`photo`, #598). Cells are `ComposerBarMetrics`
  sized (density, Dynamic Type, text scale); two rows when one does not fit. Clear, undo, redo follow legacy (above); the history
  lives in `ReplyComposerModel` (`update(text:)` is the one path of typing and of every insertion), the text the sheet opens with
  (draft, quote, edit prefill) is no step, and each step is saved like typing (LESSONS 48). Off while sending or closing (`canEdit`).
- **Aa** shows the bar above the row (hidden on each opening, as legacy); the bar keeps #599 (off while the recipient or subject
  has focus, one view across focus changes) and the #602/#605 behaviour.
- **Height (b·operator, GAP-653).** On an iPhone, a reply (topic or MP) and an edit open at partial height: a custom detent of
  a third of the sheet's room (`ComposerHeight.partialHeight`, at least 220 pt). The system lifts a sheet above the keyboard, so
  with the keyboard up the keyboard takes the bottom third, the editor and the row the middle one, and the page being answered
  stays visible in the top third (measured on the iPhone 18 Pro Max simulator, iOS 27.1). Each height is the sheet's only detent:
  a sheet that also offers `.large` is expanded to it as soon as the keyboard comes up (measured there too), which hides the page.
  So the toggle ("Plein écran" / "Réduire") swaps the detent; dragging the sheet does not change its height. A new topic and a
  new MP keep the full height and show no toggle (nothing is answered; their fields need the room); the iPad is unchanged. The
  device decides, not the size class: inside an iPad's form sheet the width is compact too (measured, iPad Pro 13" simulator). The operator asked this layout as the new iPhone default (#653, 2026-11-08), an explicit exception to "defaults keep
  the legacy UX" ([UX principles](../FEATURES.md#ux-principles-operator)).
- Swipe-down keeps LOT-084's rule (blocked while there is text or a send runs); dismissal saving the draft is #429 (UXD-15), not
  changed here.

**Open decisions** (the defaults above are the recommendation, marked as such on #653):
1. Legacy's drafts button (`tray`, archived drafts per topic): not ported; SwiftHFR keeps one draft per target (GAP-092). A
   separate issue if wanted.
2. The page behind the partial sheet is dimmed and not interactive (the system default). Scrolling it while writing would need the
   reader to ignore taps meanwhile (links, quotes, menus).
3. The chosen height is not remembered between openings.

## Edge cases
- The `[url=…]` form is typed, not validated: the clipboard text goes in as is (as legacy). The clipboard is offered once per change count.

## Fixtures
To write (never hand-built in the cloud, LESSONS 36).

## Intentional differences from legacy
The whole lot is one: it is the evolution. Record what the legacy does and what changes.

## Learnings
To copy into AGENTS.md §11 when the lot closes.
