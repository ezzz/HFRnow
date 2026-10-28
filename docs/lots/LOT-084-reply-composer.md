# LOT-084 — Reply composer (send, drafts, errors)

- **Module:** App (`App/SwiftHFR/Composer/`, entry point in `App/SwiftHFR/Reader/`)
- **Difficulty / model:** medium (Opus 5.5 → Fable)
- **Issue:** [#176](https://github.com/ezzz/HFRnow/issues/176) (MVP, roadmap [#166](https://github.com/ezzz/HFRnow/issues/166))
- **Depends on:** LOT-048 (`PostingFlow`, `PostingError`, `PostingResult`), LOT-063 (`DraftStore`, `DraftContext`), LOT-081
  (current account and its session, `AppEnvironment`), LOT-083 (reader, `TopicReaderModel`), LOT-033 (`answerFormURL`)

As a logged-in member reading a topic, I write and send a reply from the reader. Quote, multi-quote, edit, new topic,
private messages, smileys, formatting, images and polls are other lots.

## Legacy sources

Legacy app: `master` of ezzz/HFRnow (read-only), SwiftUI layer `HFRswift/`. Functional reference only; no view is copied.

| Legacy | Replaced by |
|---|---|
| `HFRswift/Swift/MessagesView.swift:4557-4569` (`openQuickReplyComposer`: draft text, `composerSubmitURL = topicAnswerURL`), `:5481-5494` (menu "Répondre" only when `topicAnswerURL != nil`), `:3744` (`topicAnswerURL` read from the page) | `TopicReaderModel.replyTarget` (the page's `answerURL`), "Répondre" toolbar button |
| `HFRswift/Swift/MessagesView.swift:5324-5338` (`AnswerView` in a full-screen cover) | `ReplyComposerView` (sheet) + `ReplyComposerModel` |
| `HFRswift/Swift/AnswerView.swift:1462-1526` (`postMessage`: success toast, text cleared, draft cleared, dismiss; any error → toast, text kept) | `ReplyComposerModel.send()`, `ComposerMessages` |
| `HFRswift/Swift/ReplyService.swift:144-185` (`postReply`: form fetched from the answer URL at send time) | `LiveReplyPoster` over `PostingFlow.loadForm` + `reply` (LOT-048) |
| `HFRswift/Swift/AnswerView.swift:137-190` (`ReplyDraftStore`: one active draft per topic in `UserDefaults`), `:277-285` (`ComposerDraftPersistence`), `:603-620` (saved on `onDisappear` only), `:1501-1510` (cleared after a successful post) | `DraftStore` (LOT-063), context `.reply(topic:page: 1)`, debounced autosave |
| `HFRswift/Swift/MessagesView.swift:5019-5049` (`reloadAfterPostedReply`: reload only when on the last page) | `TopicReaderModel.composerDidClose` / `showLatestPost` |
| `HFRswift/Swift/AnswerView.swift:3143-3175` (`ReplyTextEditor`, a `UITextView` rewritten from SwiftUI state); legacy backlog HFR-001 (third-party keyboards; backlog p. 501, back in 4.0.1 p. 502-505, [user feedback](../research/user-feedback-p450-510.md)) | SwiftUI `TextEditor`, default keyboard type |

## Behaviour

**Entry.** `ReaderPage.answerURL` is LOT-033's `answerFormURL` (the first link of `#repondre_form`, `https` on the forum
host). `TopicReaderModel.replyTarget` is non-nil when the page on screen has that link **and** names its topic
(the draft key); `ReaderReplyFlow` shows a "Répondre" toolbar button only then and only with a current account
(`AppEnvironment.composer`, nil when logged out), and presents the sheet. The link is absent logged out (`R20`, `R31`) and present logged in
(`R21`, `R61d`). A locked topic seen by a member is pending capture (#131): the button follows the page (legacy rule), and
if HFR serves no form, the composer shows HFR's own sentence (`PostingError.formUnavailable(message:)`).

**Sending** (`ReplyComposerModel.send`). Refused locally, nothing requested: blank text (Send disabled) and characters
with a scalar above U+FFFF (Q-3: HFR cuts the message at the first one and answers success, `W12`), listed in the
message. Then the exact text is written to the draft, and `ReplyPosting.reply(_:formURL:)` runs: `LiveReplyPoster` fetches
the composer at `formURL` through the **current account's** session (`AppEnvironment.session`, decision Q-8) and posts
with LOT-048's `reply`. One send at a time; the editor, Cancel and swipe-to-dismiss are disabled while it runs.

- `PostingResult` (HFR confirmed this reply, LOT-048 §8): the draft is discarded, the sheet closes with `.sent`, and
  `TopicReaderModel.composerDidClose` shows HFR's sentence ("Votre réponse a été postée avec succès !") in a banner for 4 s and opens the topic's latest
  post (below).
- Any `PostingError`: the text stays, the draft keeps it, `ComposerMessages` says what happened. HFR's own sentence is shown
  for `rejected` (flood, empty body `W33`, bad token) and `formUnavailable`; `notLoggedIn` sends to the Comptes menu;
  transport failures say nothing was sent. Only `unconfirmed` says the reply may have been posted; it offers "Voir le
  sujet", which closes with the draft kept (`.checkTopic`) and opens the latest post, so the user checks before sending
  again. Nothing is ever resent automatically.

**Latest post** (`TopicReaderModel.showLatestPost`). HFR's refresh after a reply names page 1 (`W30`:
`…sujet_6510_1.htm#bas`) while the reply landed at the end of the last page (`R61d`), so it is not followed: the reader
asks for page `maxPage + 1` of the topic shown (the reply may have opened a page; past the end HFR redirects to the last
page, `R24`, on `forum2.php` and on the canonical path) and opens it at its last message (never the continuation block).

**Drafts** (LOT-063). Context `.reply(topic:page: 1)`: one reply draft per topic and account, whatever the page (legacy: one
per topic). The account is the current one (`md_user` key). `ComposerServices.liveDrafts` is the app's single store,
`Application Support/Drafts/drafts.json`.

- Restored when the sheet opens; the editor is disabled until it is read, and nothing is written before, so a stored
  draft is never overwritten unseen.
- Saved while typing, 1 s after the last keystroke (one write per pause, LOT-063 asks to debounce), through the same
  `persist` as every other save (LESSONS 48); written at once when the app leaves the foreground and when the sheet goes
  away without a choice (account switch rebuilds the screens).
- Cancel with text asks "Garder le brouillon" / "Supprimer le brouillon" / "Continuer la saisie"; with no text it removes
  the draft. Swiping the sheet down is blocked while there is text (user feedback p. 498-506: "sheet swipe-down destroys
  the draft").
- Discarded only after a confirmed send or on request. A pending autosave is cancelled and a running one awaited before
  any discard, so it never brings the draft back.
- A draft file that cannot be read or written shows a warning; the text on screen stays and can be sent.

**Editor.** SwiftUI `TextEditor`, `.body` (Dynamic Type), default keyboard (no `asciiCapable`, third-party keyboards work),
focused on open. The sheet's keyboard safe area keeps the caret above the keyboard; the editor never rewrites its text
(legacy cursor jumps came from re-applying state to a `UITextView`).

## Edge cases

- Account switch while the sheet is open: `RootView` rebuilds the navigation; the sheet goes away and its text is saved as
  the previous account's draft. The poster keeps the session it was built with, so a send already running stays that
  account's (Q-8).
- Several pages of new posts between the last load and the reply: `maxPage + 1` may not be the last page; the reader shows
  the page served and its number.
- Another member posts between the reply and the reload: the last message is theirs, the reply just above.
- The draft cannot be deleted after a confirmed send (disk error): the reply is still reported as sent; the stale draft
  comes back at the next reply in that topic, where the user can discard it.
- An `unconfirmed` reply that was in fact posted, sent again by the user: a double post. The message says to check first.
- The page names no topic (a canonical path whose page has no form fields): no "Répondre" (no draft key).

## Fixtures

No new capture. `R61d` (logged in, answer link, own post last), `R20` and `R31` (no answer form) feed
`ReplyEntryTests` through `LiveTopicPageSource.parse`. Sentences of `W30`, `W33` and HFR-PROTOCOL §7 E15 are used as
scripted outcomes; the posting itself is LOT-048's, tested on `R61b`, `W30`–`W33` there.

## Tests

`App/SwiftHFRTests/Composer/`:
- `ReplyComposerSendTests`: a confirmed reply is sent once through the topic's form and clears the draft; every other
  outcome (13 cases) keeps text and draft with its message, `mayHavePosted` only for `unconfirmed`; non-BMP refused
  before any request (BMP characters sent); blank text; one send at a time, typing and Cancel ignored meanwhile; the
  draft holds the exact text before the request leaves; a pending autosave never brings the draft back; "Voir le sujet"
  only after `unconfirmed`; typing clears the failure message.
- `ReplyComposerDraftTests`: restore per topic and account; one write per typing pause; restore after a kill (new store
  on the same file); background flush; nothing written before the restore; Cancel asks and keeps, or discards, or
  removes an emptied draft without asking; write and read failures reported.
- `ReplyEntryTests`: the reply is offered only with an answer form and a topic; after a confirmed reply the reader asks
  for `maxPage + 1`, opens at the last message (not the continuation block) and shows HFR's sentence, on `forum2.php` and
  canonical paths; after an unconfirmed one the same page without sentence, after a plain close nothing; `R61d`
  gives its answer link, `R20` and `R31` none; the live poster refuses an off-forum link without a request; HFR's
  sentence is shown on refusals; only `unconfirmed` says "peut-être".

Shown to fail without the change (each mutation run locally makes its test fail): no discard after a confirmed send, no
local non-BMP check, no debounce, no wait for a running autosave before a discard, no save before sending, closing before
the restore, `maxPage` instead of `maxPage + 1`, the continuation block as last message, no `answerURL` from the page, a
reply offered without answer link, `mayHavePosted` on every failure, no latest post after a confirmed or an unconfirmed
reply.

## Pending capture

- Reply form of a locked topic, and of a topic where the account may not post (#131): the button follows the page's
  answer link; HFR's sentence is shown if it serves no form.
- Edit or quote form whose stored text starts with a newline (#130): not used by the reply composer (empty composer).

## Intentional differences from legacy

1. Success only on LOT-048's confirmation of this reply (legacy: no link in `.hop`, `W17b` was a "success"); legacy's
   "Hooray" toast becomes HFR's own sentence.
2. Drafts per topic and account in LOT-063's file store, saved while typing (legacy: `UserDefaults`, saved on dismiss
   only, one store for every account); the archived drafts list (legacy `ReplyDraftPickerSheet`, 3 per topic) is not
   ported.
3. Cancel asks keep / discard; swipe-down is blocked while there is text (legacy: swipe kept or lost the text depending
   on the path, user feedback p. 498-506).
4. Non-BMP characters refused before sending, with the list (legacy Swift sent them and HFR cut the message).
5. After a reply the reader opens the topic's latest post wherever the user was reading (legacy reloaded only when the
   last page was on screen).
6. Every failure message says whether something may have been posted (legacy: `localizedDescription` or "Ooops").

## Learnings

- HFR's refresh after a reply points to page 1 (`#bas`), not to the page that holds the reply: never follow it to show the
  new post; ask past the last page instead (`R24` redirects to the last one).
- A debounced save and a discard race: cancel the pending save and await a running one before discarding, or the draft
  comes back after a confirmed send.
