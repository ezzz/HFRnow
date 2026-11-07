# LOT-088 — Edit and delete own messages

- **Module:** App (`App/SwiftHFR/Composer/`, `App/SwiftHFR/Reader/Actions/`), two small additions to `HFRClient` (`PostingFlow`)
- **Difficulty / model:** medium (Opus 5.5 → Fable)
- **Issue:** [#180](https://github.com/ezzz/HFRnow/issues/180) (UXD-14: the first post's delete went to LOT-175, #415, M5)
- **Depends on:** LOT-048 (`PostingFlow`, `PostingForm`), LOT-084 / LOT-089 (`ReplyComposerModel`, drafts, sub-category picker), LOT-087 (message menu, `MessageActionRegistry`, `MessageMenuPolicy`), LOT-063 (`DraftContext.edit`)

As a logged-in member, from the `⋯` menu of my own message, I edit it ("Editer", the first post with its title and sub-category) or
delete it ("Supprimer", any post but the first, after a confirmation).

## Legacy sources

Legacy app: <https://github.com/ezzz/HFRnow> at `2440d79`, read-only.

| Legacy | Replaced by |
|---|---|
| `HFRswift/Swift/MessagesView.swift:251,255` (menu: edit link; delete with the edit link, not on the first message of a page), `:1649-1656`, `:1789-1796` (entries) | `MessageMenuPolicy` (LOT-087), `MessageWriteModel.handlers` |
| `MessagesView.swift:3525-3531` (`openEditComposer`: "Edition", no subject), `:3549-3576` (`prefillComposer`: form fetched first, `composerPersistsDraft = false`, `composerSubmitURL = url`, failure alert with a retry), `:2522-2541` (labels), `:4472` (`ProgressView`), `:4618-4627` (alert) | `MessageWriteModel.openEditor`, `EditPrefill`, `ReaderEditFlow` |
| `Classes/QuoteMessageViewController.m:209-300` (visible `sujet` → `haveTitle`, `subcat` select → `haveCategory`, selected option else the first), `:400-435` (sub-category menu, "Aucune"), `Classes/AddMessageViewController.m:559-564` (`sujet`, `subcat` posted), `Classes/EditMessageViewController.m` (title "Editer") | `ReplyComposerModel` with `ComposerTarget.edit`, `ReplyComposerView`, `PostingFlow.edit(_:subject:subcategory:…)` |
| `MessagesView.swift:3805-3836` (`askDeleteMessageConfirmation`, `confirmDeleteMessage`: HFR's sentence or "Message supprimé", reload of HFR's refresh URL), `:4628-4640` (alerts "Supprimer ce message ?" Non / Oui, "Cette action est définitive."; "Suppression impossible") | `MessageWriteModel.askDelete`, `confirmDelete`, `ReaderEditFlow` |
| `HFRswift/Swift/ReplyService.swift:922-1040` (`ForumMessageDeletionService.deleteMessage`), `Classes/DeleteMessageViewController.m:44` | `LiveReplyPoster.delete`, `PostingFlow.deleteLaterPost` |

## Legacy counterpart (app lots)

| SwiftHFR | Legacy @ `2440d79` |
|---|---|
| `Composer/EditTarget.swift` (`EditTarget`, `EditPrefill`) | `HFRswift/Swift/MessagesView.swift` (`openEditComposer`, `prefillComposer`), `Classes/QuoteMessageViewController.m` (form harvest) |
| `Reader/Actions/MessageWriteModel.swift` | `MessagesView.swift` (`openEditComposer`, `askDeleteMessageConfirmation`, `confirmDeleteMessage`), `ReplyService.swift` (`ForumMessageDeletionService`) |
| `Reader/Actions/ReaderEditFlow.swift` | `MessagesView.swift` (prefill `ProgressView`, alerts, composer cover) |
| `Composer/ReplyComposerView.swift`, `ReplyComposerModel.swift` (edit mode) | `HFRswift/Swift/AnswerView.swift` (`AnswerView`) |

## UX evolutions (app lots)

- GAP-096 (`a`): a draft per message and account (legacy: none). An edit left as the form served it stores no draft.
- GAP-097: the (a) half only (UXD-14, 2026-11-02): "Supprimer" with a confirmation, not on the topic's first post. No new UX; the (b) half is LOT-175.
- First post's title and sub-category (UXD-14): the ObjC composer edited them, the Swift layer at `2440d79` did not (`composerRequiresSubject = false`).
- GAP-100 (`a`): errors say whether anything may have changed, as in every composer.

## Behaviour

**Entry.** `MessageMenuContext` (LOT-087) reads the edit link of the message's toolbar (LOT-031). `EditTarget(link:post:topic:)` is nil unless
the link is `https` on the forum host (default port, no user info) **and** names the topic on screen and that very message (`cat`,
`post`, `numreponse`, shape `R63a`): its form is posted back as served, so a parser slip offers nothing. "Editer" and "Supprimer"
are registered in `TopicReaderView.installMenuActions` with a composer (an account), hidden otherwise.

**Edit.** `MessageWriteModel.openEditor` reads the edit form through the current session while a progress line shows (legacy order: the
composer opens once the form is read); a failure opens nothing and offers "Réessayer" (a read). `EditPrefill` keeps the stored text
(`textareaContent`, LOT-036), the title when `sujet` is visible (`R63b`, `R43a`; hidden on a later post, `R62a`) and the `subcat` select
with its preselection (`R63b`: option marked selected; a private first post has none, `R43a`; a later post a hidden `subcat`, `R62a`, sent as served).
The sheet is the composer of LOT-084, title "Edition". Send needs a text, and a title when the field shows. The form is fetched **again** at send
(fresh `hash_check`, LOT-084 rule; legacy did too) and must be that message's (`numreponse`), else nothing is sent. `PostingFlow.edit` overrides
`content_form`, `sujet` and the `subcat` select; every other control goes back as served (poll fields, boxes), `delete` unchecked.

- `PostingResult` (HFR's sentence): draft discarded, sheet closed, HFR's sentence in the reader's banner, page on screen reloaded at the message.
- Any `PostingError`: text and draft kept, `ComposerMessages` says what happened. Only `unconfirmed` says it may have been changed; "Voir le sujet"
  closes with the draft kept and reloads the page at the message, no sentence. Nothing is resent automatically.
- `unknownSubcategory` at send: the form is read again and the user chooses again (as LOT-089).

**Drafts.** Context `.edit(topic:post:)`, same autosave, close choices and warnings as LOT-084, never the topic's reply draft. A stored draft wins
over the form's text at opening. While the fields equal what the form served nothing is stored and closing asks nothing; typing back to it
removes the draft. The sub-category is not in a draft (LOT-063 has no such field), so closing with only the picker changed asks nothing.

**Delete.** The menu entry only sets `pendingDelete`; the legacy alert asks ("Supprimer ce message ?", Non / Oui, "Cette action est définitive."). Nothing
leaves before "Oui". The form is fetched, then `PostingFlow.deleteLaterPost(_:with:)` refuses, nothing sent: another message's form, a form with a first-post
sign (`deletesWholeTopic`: visible `sujet` or "intégralité", `R63b`, `R43a`), a form without the box (`R44`). Then the stored text goes back with `delete=1`.

- This is the decision LOT-048 left open: `PostingFlow.delete` asks a whole-topic confirmation of **every** public form (fail closed). LOT-088 lifts it for a form
  **without** a first-post sign on a message the page does not call the first post (two independent checks, page and form, both on captures: `R62a`, `R63b`).
- `PostingResult`: HFR's sentence in the banner, page on screen reloaded, scroll position kept.
- `unconfirmed`: alert "Suppression impossible", the message says it may be gone and to check; the page reloads so the user sees; never resent, no retry button.
- Any other error: same alert with the reason, page left alone.

## Edge cases

- First post on page 1: no "Supprimer" (first non-continuation block, LOT-087). A page that hid that fact: refused by the form sign, HFR is not contacted for the POST.
- Last message of a page deleted: the reader asks the same page; past the end HFR redirects to the last page on a public topic (`R24`). See pending capture for a private thread.
- Non-BMP character in a stored message (`R43c`): shown, refused at send like any text (Q-3); delete sends the stored text unchanged.
- Leading line break: HFR serves the edit text without it (`R130b`, §6c "Leading newline"), so the composer holds what HFR serves; an edit sent back unchanged loses it whatever the client.
- Two devices: a draft or an open sheet overwrites a newer version, as on the site; no conflict detection (HFR gives none).
- Session expired: `notLoggedIn` at the form read or at send.
- Account switch while the sheet is open: same as LOT-084.

## Fixtures

No new capture. Forms `R62a` (public later post), `R63b` (public first post), `R43a`, `R43b` (private first and later post), `R44` (no delete box), `R130b` (leading line break);
page `R63a` (own posts, toolbars); answers `W31`, `W34` (edit), `W16a`, `W32` (delete).

## Tests

- `HFRClientTests/PostingEditDeleteTests`: `W34` fields with title and sub-category as served, changed ones in place of the served ones, "Aucune" sent, unknown sub-category, later post's hidden `subcat`,
  `W32` and `W16a` through `deleteLaterPost`, first post refused (public, private) with no POST, another message's form, `R44`.
- `App/SwiftHFRTests/Composer/EditComposerTests.swift`: `EditPrefillTests` (captures, link checks) and `EditComposerTests` (round trip, title and sub-category, unconfirmed never resent, drafts per message, close rules, stale list, texts).
- `App/SwiftHFRTests/Reader/Actions/MessageWriteModelTests.swift`: menu on the real toolbars, form read once, failure and retry, confirmed and unconfirmed edit, delete asks first, confirmed, unconfirmed, refused.

Shown to fail without the change: see the PR.

## Pending capture

Not hand-built (LESSONS 36). None blocks the lot; each is handled conservatively. No HFR write was made for this lot.

1. **First-post edit with a changed `sujet` or `subcat`**: `W34`, `W35` sent them as served, and `W41` its own topic's. Legacy posts them (`AddMessageViewController.m:559-564`) and the form offers them, so the app does; whether HFR applies them, and what its refresh then names, is not captured. The app reports HFR's sentence, nothing more.
2. **First-post edit form of a topic without sub-category** ("Aucune", cited as HFR-091 by #180, not found in the legacy tree): which option HFR marks. The picker takes the marked option, else the first, so "Aucune" stays chosen; only the capture is missing.
3. **Topic page after a delete** (LOT-090 pending too): whether later messages move, and what a private thread serves for a page past its end when the deleted message was alone on the last page (`R24` is public). A failure shows the reader's "Réessayer".
4. **Edit form of a message in a locked topic** (#131): HFR's sentence is shown if it serves none.
5. **First post of a topic with a poll**, edit form as served: its boxes and fields go back as served (`W41` adds one from a form without).

## Intentional differences from legacy

1. The title and sub-category of a first post are editable (ObjC yes, Swift no at `2440d79`).
2. A draft per message (legacy Swift: none), GAP-096.
3. Delete: a first-post form is refused locally; legacy's menu rule was the only guard (and hid the first message of every page, LOT-087 difference 4).
4. Success needs HFR's sentence (legacy accepted "Message supprimé" as a fallback text; `isSuccessfulDelete` was looser, LOT-037).
5. After a write the page on screen is reloaded; legacy loaded HFR's refresh, the same page (`W31`, `W32`: the form's `page`) at its top. An edit opens at the message, a delete keeps the scroll position.
6. An unconfirmed delete has its own message and is never presented as refused.

## Learnings

- `TopicReaderView` installs handlers after the first render: a modifier that branches on them would rebuild the web view, so `ReaderEditFlow` reads an optional through bindings.
- A reload anchored with `ReaderTarget.anchor` draws the flag separator; `AnchorRule.message` scrolls to a message without it.
