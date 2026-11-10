# LOT-101 — Archived drafts (M4)

- **Module:** App (storage in LOT-063's draft store)
- **Difficulty / model:** easy (Sonnet → Opus)
- **Issue:** [#192](https://github.com/ezzz/HFRnow/issues/192) · **Milestone:** M4, backport of legacy evolution (operator, 2026-11-09, [#655](https://github.com/ezzz/HFRnow/issues/655))
- **Depends on:** LOT-063 (#88, drafts), LOT-084 (#176, reply composer)

Stub written with the M4 move of #655. Absent at `2440d79`, added by legacy at `2fe43da3` (`196620d2`, refined in `08a63c8e`), so a port of legacy evolution. LOT-084's "the archived drafts list is not ported" (its intentional difference 2) described the `2440d79` scope; this lot ports it. Completed by the author at `87fe0d1c` (AGENTS.md §5).

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
Reference `87fe0d1c` (AGENTS.md §2; the `AnswerView.swift` lines of the table above are the same at `2fe43da3` unless said). The app pointers: `// Port of HFRswift/Swift/AnswerView.swift (ReplyDraftPickerSheet, :1855-2001) @ 87fe0d1c` on `ArchivedDraftsView`, and the same for `useDraft`, `archiveAndClearCurrentDraft`, `clearTopicDrafts` and `removeDraft` (`:693-760`) on `ReplyComposerModel+ArchivedDrafts`; GAP-093.

| App | Legacy @ `87fe0d1c` |
|---|---|
| `DraftStore.archiveReply`, `archivedReplies`, `discardArchivedReply`, `discardArchivedReplies` (HFRStorage) | `ReplyDraftStore.archive`, `drafts(for:)`, `remove`, `removeAll`, `trimPerTopic` (`AnswerView.swift:137-244`) |
| `ArchivedDraftSource` | `ReplyDraftSource` (`:103-121`) |
| `ReplyComposerModel+ArchivedDrafts` | `reloadTopicDrafts`, `canArchiveCurrentDraft`, `useDraft`, `archiveAndClearCurrentDraft`, `clearTopicDrafts`, `removeDraft` (`:686-760`); the removal of the picked draft after a posted reply (`:1509-1513`) |
| `ArchivedDraftsView` (sheet) | `ReplyDraftPickerSheet` (`:1855-2001`) |
| "Brouillons" button in `ReplyComposerView`'s toolbar | the tray button of the header (`:783-796`), shown only for a reply (`draftContext != nil`) |
| `ArchivedDraftsFormat` | `ReplyDraftSource.title`, `previewText`, `formattedDate` |

## UX evolutions (app lots)
None: same UX as legacy at `87fe0d1c`, with the differences below.

## Behaviour, edge cases, fixtures
Local storage only: no HFR request, so no capture and no fixture (synthetic tests).

**Store** (`HFRStorage`, `DraftStore+ArchivedReplies.swift`). A new `DraftContext.archivedReply(topic:id:source:)`: the archive lives in LOT-063's file, under its account scoping, TTL and size bound, and is removed with the account's other drafts at a logout (`discardAll`). One draft per archived reply, told apart by `id` (the identity); `source` is data.
- `archiveReply(_:topic:source:account:)`: blank text is never archived (nothing written); a text equal to an archived one ignoring surrounding whitespace replaces it (the new copy is the newest, the old one is gone); the newest is first; past **3 per topic and account** the oldest are dropped, in the same write.
- `archivedReplies(topic:account:)`: newest first, expired ones ignored; equal dates keep the later write first.
- `discardArchivedReply(id:topic:account:)`, `discardArchivedReplies(topic:account:)` ("Vider": only that topic and account).
- Topic identity is `TopicID` (category and number), as the reply draft; legacy keyed by the number alone (`post-<n>`, `ReplyDraftTopicContext.topicID`).
- Archived replies and the active draft (`.reply(topic:page: 1)`) never touch each other: archiving leaves the active draft to the composer, and discarding the active draft after a send leaves the archive.

**Composer** (reply only: a new topic, a message, an edit have no archive, legacy `draftContext != nil`).
- "Brouillons" (tray) button in the toolbar, filled when the topic has archived drafts, disabled while the editor is.
- Picker sheet: "Mettre de côté et vider" (only with non-blank text), the list or "Aucun brouillon archivé", each row with its source ("Réponse rapide", "Citation"), its date ("Aujourd’hui HH:mm", "Hier HH:mm", else the short date and time) and a two-line preview ("Brouillon vide" when blank); tap = use; swipe "Supprimer"; "Vider" (disabled with no draft). With nothing to archive and nothing archived the sheet says "Aucun brouillon".
- **Set aside and clear**: the text is archived with the current source, the editor empties, the active draft is removed (blank text stores none), the sheet closes and the editor takes focus. If the archive cannot be written, nothing changes and the draft warning shows.
- **Use**: a different non-blank text in the editor is archived first, then the picked draft is archived again as the newest (legacy `useDraft`, so it is on top of the list); a text equal to it ignoring whitespace archives nothing. The picked text replaces the editor's, becomes the active draft, and the editor's source becomes the draft's. The picked draft **stays in the archive** until the reply is posted: HFR's confirmation removes it (legacy `:1509-1513`), any other outcome keeps it. A failed removal leaves it in the list; the reply is posted either way.
- Typing is refused while one of these writes runs (`isMovingDrafts` in `canEdit`), and a pending autosave is settled first (LOT-084 learning): an autosave never lands after a set-aside and brings the text back.
- The source of the text on screen: "Citation" when the sheet was opened with a quote (LOT-086), "Réponse rapide" otherwise, the draft's own after a pick.

## Intentional differences from legacy
1. **Per account** (LOT-063, LOT-084 difference 2): legacy kept one `UserDefaults` list for every account (`reply_drafts_by_topic_v1`); the archive is per account and goes with the account's drafts at a logout.
2. **Expiry**: archived drafts expire 30 days after they were set aside (the draft store's TTL), and count in its 100-draft bound; legacy kept them until deleted.
3. **No "Répondre forum" source**: legacy's `ReplyDraftSource.forumReply` and `archived` came from template prefills (`prefillComposer`, edit mode) that SwiftHFR's reply composer does not have (it opens empty or on a quote). The enum has the two sources the app can produce.
4. **A quote does not archive**: legacy's `replaceComposerDraft` (`MessagesView.swift:4365-4380`) archived a different non-empty draft before a quote or reply replaced it; SwiftHFR merges the quote into the draft (LOT-086 difference 7), so nothing is replaced and nothing is archived. The user's own text is never lost either way.
5. **No undo of the swap**: legacy pushed the replaced text on its own `undoHistory` (`:707-711`); SwiftHFR's editor is SwiftUI's `TextEditor` without a history of its own, and the text a pick replaces is archived first, so it is one tap away in the picker.
6. **Legacy archives are not imported**: they stay in `UserDefaults` (ADR 0013 Amendment 3, LOT-067); this lot reads nothing from there.
7. **Native sheet**: a navigation stack with "Fermer" and "Vider" instead of the hand-drawn header; medium and large detents (legacy: medium only).
8. A failed write is reported (the composer's draft warning) and changes nothing on screen; legacy ignored `UserDefaults` failures.

## Tests
Engine, `Tests/HFRStorageTests/Drafts/ArchivedRepliesTests.swift` (run on Linux): order and source, the limit of 3 per topic and per account, equal dates, the same text replacing itself, blank text writing nothing, discard one and all, independence from the active draft, restart and expiry, logout, a refused write, the file round trip of the new context.
App, `App/SwiftHFRTests/Composer/ArchivedDraftsTests.swift` (CI on a Mac): the archive read per topic and account, set aside (editor empty, active draft gone), blank text refused, a quote's source, pick with an empty editor, pick over a different text, pick of the same text, the fourth draft dropping the oldest, delete one and "Vider", a confirmed reply removing the picked draft only, a failed one keeping it, a refused write changing nothing, no archive for a message; `ArchivedDraftsFormatTests` (today, yesterday, older, one-line preview, titles).

## Mac checks
The picker on a device: the button's filled state, the sheet's detents with the keyboard, focus back on the editor after a pick, VoiceOver reading of a row (combined element), the date labels in the device's locale.

## Learnings
To copy into AGENTS.md §11 when the lot closes.
- A list of several items per key does not need a second store: one `DraftContext` case per item (its `id` in the key) keeps the file's account scoping, TTL, bound and logout for free; do the multi-step change (replace the same text, trim to the limit) in one `mutate`.
