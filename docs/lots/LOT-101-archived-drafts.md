# LOT-101 — Archived drafts (M4)

- **Module:** App (storage in LOT-063's draft store)
- **Difficulty / model:** easy (Sonnet → Opus)
- **Issue:** [#192](https://github.com/ezzz/HFRnow/issues/192) · **Milestone:** M4, backport of legacy evolution (operator, 2026-11-09, [#655](https://github.com/ezzz/HFRnow/issues/655))
- **Depends on:** LOT-063 (#88, drafts), LOT-084 (#176, reply composer)

Stub written with the M4 move of #655. Absent at `2440d79`, added by legacy at `2fe43da3` (`196620d2`, refined in `08a63c8e`), so a port of legacy evolution. LOT-084's "the archived drafts list is not ported" (its intentional difference 2) described the `2440d79` scope; this lot ports it. The author completes the spec before coding (AGENTS.md §5).

## Legacy sources
At `2fe43da3`, `HFRswift/Swift/AnswerView.swift`:

| Legacy @ `2fe43da3` | Behaviour |
|---|---|
| `:103-121` (`ReplyDraftSource`) | an archived draft remembers where it came from: "Réponse rapide", "Citation", "Répondre forum", "Brouillon archivé" |
| `:137-141, 191-244` (`ReplyDraftStore`) | at most 3 archived drafts per topic, newest first; archiving the same text again replaces it; empty text is never archived |
| `:783-796` | a "Brouillons" (tray) button in the composer bar, prominent when the topic has archived drafts |
| `:509-521, 1855-2001` (`ReplyDraftPickerSheet`) | the picker: "Mettre de côté et vider" (archive the current text, clear the composer), the list ("Aucun brouillon archivé" when empty) with source and date ("Aujourd'hui", "Hier", else short date and time), swipe "Supprimer", "Vider" for the topic |
| `:693-725` (`useDraft`) | picking a draft archives the different current text first, then puts the draft in the composer (undoable) |
| `MessagesView.swift:4299-4315` (`replaceComposerDraft`) | a quote or reply that replaces a different non-empty draft archives it first |

Storage at `2fe43da3` is `UserDefaults` (`reply_drafts_by_topic_v1`), one store for every account; SwiftHFR keeps its drafts per account in LOT-063's file store (LOT-084 difference 2).

## Legacy counterpart (app lots)
To write by the author (`// Port of HFRswift/Swift/AnswerView.swift (ReplyDraftPickerSheet) @ 2fe43da3. Differences: …`, GAP-093).

## UX evolutions (app lots)
None planned: same UX as legacy at `2fe43da3`.

## Behaviour, edge cases, fixtures
To write. No HFR request (local storage only), so no capture.

## Intentional differences from legacy
To write (per-account storage, from LOT-063).

## Learnings
To copy into AGENTS.md §11 when the lot closes.
