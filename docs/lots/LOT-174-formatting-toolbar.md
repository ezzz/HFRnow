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

**Operator reference (2026-11-10, #653): legacy's buttons in the Claude app's layout.** Legacy's placement at `87fe0d1c` (above),
in a card docked on the keyboard: the page being answered visible and scrollable above it, the card growing with the text up to a
cap and the editor scrolling inside past it, the full-screen control expanding it, an inserted image as a thumbnail with an ✕
inside the card above the text, the two pills just under the editor so they move with the keyboard, send ↑ at the top right
(operator, 2026-11-10: not in the card).

**SwiftHFR** (`ComposerHeader`, `ComposerEditorCard`, `ComposerImageChips`, `ComposerControlRow`, `ComposerHistory`,
`ComposerHeight`, `ReplyComposerView`):
- Top bar (`ComposerHeader`, legacy `composerHeader` `:768-819` and its button styles `:1704-1745`): "Fermer" (`xmark`, glass circle,
  the close choice of LOT-084: keep / discard) and, where LOT-101 archives drafts (a topic's reply), "Brouillons" (`tray`,
  prominent when drafts are archived) on the left; the title in the middle; "Envoyer" (`arrow.up`, prominent glass when there is
  something to send, plain glass and disabled while the text is empty; spinner "Envoi en cours" while sending) on the right. Legacy's
  own header, not a navigation bar: the same buttons, order and groups on every device. VoiceOver labels as legacy ("Fermer",
  "Brouillons", "Envoyer"; the row's "Vider le texte", "Annuler", "Rétablir").
- The editor in a rounded glass card (legacy `composerEditorStyle`, `:1748-1760`), the full-screen toggle ("Plein écran" /
  "Réduire") in its top corner where the composer offers it: legacy's top bar has no such button, so the bar stays legacy's.
- Control row just under the card, legacy order and labels; the GIF button only when Giphy is configured (LOT-155); the upload
  symbol stays `photo.badge.plus` so it is not mistaken for the bar's `[img]` (`photo`, #598). Cells are `ComposerBarMetrics`
  sized (density, Dynamic Type, text scale); two rows when one does not fit. Clear, undo, redo follow legacy (above); the history
  lives in `ReplyComposerModel` (`update(text:)` is the one path of typing and of every insertion), the text the sheet opens with
  (draft, quote, edit prefill) is no step, and each step is saved like typing (LESSONS 48). Off while sending or closing (`canEdit`).
- **Aa** shows the bar above the row (hidden on each opening, as legacy); the bar keeps #599 (off while the recipient or subject
  has focus, one view across focus changes) and the #602/#605 behaviour.
- **Height (b·operator, GAP-653).** On an iPhone every composer opens at partial height: a reply (topic or MP) and an edit
  (operator, 2026-11-08), a new topic and a new MP too (operator, 2026-11-10). At partial height the sheet is the docked card: its
  detent is the card's measured height (`ComposerCardLayout`: header, banners, fields, image chips, the editor, the row), and the
  editor is as tall as its text, from 2 lines up to 6 lines of the body font (Dynamic Type included), past which it scrolls inside
  the card. Six lines keep about the third of the screen #653 first gave the text and the row on a 6.9" iPhone, so the page keeps
  the top of the screen with the keyboard up; the cap is the author's choice within the reference ("up to a maximum height"). The
  system lifts the sheet over the keyboard, so the card sits on it (measured on the iPhone 18 Pro Max simulator, iOS 27.2). Each
  height is the sheet's only detent:
  a sheet that also offers `.large` is expanded to it as soon as the keyboard comes up (measured there too), which hides the page.
  So the toggle ("Plein écran" / "Réduire") swaps the detent; dragging the sheet does not change its height. The height is not
  remembered: every opening starts at partial height (operator, 2026-11-10), except at an accessibility text size (AX), where it
  starts full with the toggle still offered: there the control row takes two tall rows and a partial card leaves no line for the
  text (measured at AX XL with a new MP on the iPhone 18 Pro Max simulator, iOS 27.2). Operator decision, confirmed 2026-11-11.
  In compact height (an iPhone in landscape) the system shows a sheet at full height whatever its detents (measured, see #749), so there is no toggle there and the sheet is the full one;
  back in portrait the choice made before the rotation holds. On the iPad the presentation is unchanged (a `.large` form sheet, no toggle); its top bar is legacy's too. The device decides, not the size class: inside
  an iPad's form sheet the width is compact too (measured, iPad Pro 13" simulator). The operator asked this layout as the new iPhone default (#653, 2026-11-08), an explicit exception to "defaults keep
  the legacy UX" ([UX principles](../FEATURES.md#ux-principles-operator)).
- **The page behind the partial composer (operator, 2026-11-10; #853, 2026-11-13).** It is not dimmed and it scrolls, so the
  message being answered can be read again. In the reader on an iPhone the composer is not a sheet but a bar docked at the
  bottom of the page, on the keyboard (`ReaderComposerPresenter`, `ComposerPlacement`): a sheet with
  `presentationBackgroundInteraction` left the page inert with the keyboard up, because iOS moves a sheet to its largest detent
  when the keyboard rises (device, 2026-11-13). The page's bottom inset counts the bar and the keyboard, dragging the page down
  pulls the keyboard down with the finger (`keyboardDismissMode = .interactive`) while the bar stays, the bottom bar is hidden
  while writing, and "Plein écran" fills the reader with the same composer (navigation bar hidden). Its taps and actions are ignored while the composer is open. The reader keeps a set of open composers (reply, edit, the
  author menu's MP: `TopicReaderModel.composer(_:isOpen:)`, reported by each presenter from its sheet's state); while one is open
  (`suspendsPageInteractions`) a link, a message menu, a video, a picture, a third-party image placeholder, a selection quote, the
  reply button, a page change, a swipe, "Actualiser" and "Réessayer" (both disabled), "Sondage" (hidden; its sheet could not show
  over the composer's) and "Marquer comme non lu" (no `W18` write) do nothing, the "…" overflow has no entry, the back button is
  hidden (going back would drop the sheet), and the web view drops those taps itself (`ReaderWebController.ignoresPageTaps`: a
  long-pressed link gets an empty menu of ours, never WebKit's previewing one). Scrolling and the reading position go on; the web
  view is neither reloaded nor stopped. A new topic (from a forum's list) and a new MP (from the Messages list) are partial too,
  but their list stays dimmed and inert (the system default; operator decision, confirmed 2026-11-11): nothing is answered there, and a list has no such suspension yet
  (`.disabled` on a `List` also stops its scrolling, measured on the iPhone 18 Pro Max simulator, iOS 27.2; a tap on a row would
  open a topic under the sheet). The author menu's MP is opened over the reader, so its page scrolls. "Fermer" (×) stays at the
  top left, as legacy's header.
  Every toolbar entry on the reader and its gate (swept for round 3 of #749): top bar "Actualiser" (disabled), "Sondage"
  (`offersPoll`); "…" overflow "Filtrer les posts", "Rechercher dans le sujet", the offline save entries, "Marquer comme non lu"
  (`offersMarkUnread`) and the page items (all hidden); bottom bar ‹ ›, "N / M", "Répondre" (disabled); the failure banner's
  "Réessayer" (disabled). The model's own actions refuse too (`pollModel`, `markUnread`, `refresh`, `retry`, …).
- **Image chips.** An image the panel uploaded and inserted shows as a 56 pt thumbnail (the host's mini rendition, as the panel's
  history) at the top of the card, with an ✕ ("Retirer l'image"). The snippet stays in the text where legacy puts it (at the caret,
  `AnswerView.swift:646-676` @ 2440d79), so what is posted and the draft do not change; the chip shows while its snippet is in the
  text (typing it away, "Vider le texte" or an undo hides it, a redo shows it again), and the ✕ takes the snippet out as one undoable
  step. A link typed by hand in the panel gets no chip (nothing is loaded from an unknown host). Chips last as long as the composer:
  a draft reopened later shows its snippets as text only. Whether the operator wants the snippet hidden from the text (an attachment,
  as the Claude app) is open (#749).
- Swipe-down keeps LOT-084's rule (blocked while there is text or a send runs); dismissal saving the draft is #429 (UXD-15), not
  changed here.

**Decisions** (operator, 2026-11-10 and 2026-11-11, on #653 and #749):
1. Legacy's drafts button (`tray`, archived drafts per topic) belongs to LOT-101
   ([#192](https://github.com/ezzz/HFRnow/issues/192)), merged since: the top bar shows it where LOT-101 offers it, after "Fermer".
2. The page behind the partial sheet scrolls; its taps are ignored while the composer is open (above).
3. The chosen height is not remembered: every opening starts at a third of the screen.
4. "Fermer" (×) stays at the top left, as in legacy.
5. A new topic and a new MP open at partial height too, with the toggle.
6. Legacy's button placement in the Claude app's layout (reference of 2026-11-10, above); send stays at the top right.
7. Accessibility text sizes open at full height, with "Réduire"; the lists behind a new topic / new MP stay dimmed and inert
   (the author's two choices of round 2, confirmed by the operator on 2026-11-11).

## Edge cases
- The `[url=…]` form is typed, not validated: the clipboard text goes in as is (as legacy). The clipboard is offered once per change count.

## Fixtures
To write (never hand-built in the cloud, LESSONS 36).

## Intentional differences from legacy
The whole lot is one: it is the evolution. Record what the legacy does and what changes.

## Learnings
To copy into AGENTS.md §11 when the lot closes.
