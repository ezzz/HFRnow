# LOT-128 — New MP and MP reply composer

- **Module:** App (`App/SwiftHFR/Composer/`, `App/SwiftHFR/Messages/`, latest post in `App/SwiftHFR/Reader/`)
- **Difficulty / model:** medium (Opus 5.5 → Fable)
- **Issue:** [#219](https://github.com/ezzz/HFRnow/issues/219)
- **Depends on:** LOT-048 (`PostingFlow.newPrivateMessage`, `reply`), LOT-084 (reply composer, drafts, `ComposerServices`),
  LOT-126 (Messages list and conversation reader), LOT-063 (`DraftContext.privateMessage`), LOT-023 (`newMessagePath`)

As a member, I write a new private message (recipient, subject, text) and reply in a conversation, as the current account.
The profile entry is LOT-116's and the per-message "MP" action LOT-087's: both open this composer through
`NewMessageTarget(link:)` with the link HFR prints (`dest=<pseudo>`), and neither lot is merged yet.

## Legacy sources

Legacy app: `master` of ezzz/HFRnow at `21173e77` (read-only). Functional reference only; no view is copied.

| Legacy | Replaced by |
|---|---|
| `Classes/HFRMPViewController.m:511,537` (compose button on the MP list), `Classes/TopicsTableViewController.m:222-245` (`newTopic`: opens `forumNewTopicUrl`), `Classes/ObjCTopicListParser.m:133-135` (`md_btn_new_topic`) | "Nouveau message" in the Messages toolbar, `MessageListModel.newMessageTarget` (LOT-023 `newMessagePath`) |
| `Classes/QuoteMessageViewController.m:254-256` (`haveTo` when the form has `dest`), `:306-330` (editable "À :" field filled with the form's `dest`); `Classes/AddMessageViewController.m:557-568` (`sujet` and `dest` posted as typed) | `ReplyComposerView.messageFields`, `ReplyComposerModel.recipient` / `subject`, LOT-048 `newPrivateMessage` |
| `HFRswift/Swift/MessagesView.swift:4208-4224` (`openPrivateMessageComposer`: subject required, recipient = the author, trimmed, no draft), `HFRswift/Swift/AnswerView.swift:826-831` (recipient shown read-only), `:1472-1479` (`sujet` trimmed, `dest` overrides) | `NewMessageTarget(link:)`, `ComposerTarget.newPrivateMessage` |
| `HFRswift/Swift/UserProfileView.swift:702-705` (quick action "MP") | LOT-116 calls `NewMessageTarget(link:)` (not wired here) |
| `HFRswift/Swift/MessagesView.swift:5481-5494` ("Répondre" when the page has an answer link), MP threads read like topics | `MessageReaderColumn(composer:)`: the LOT-084 "Répondre" on a conversation |

## Behaviour

**MP reply.** A conversation is a topic of category `prive`; its page carries the answer link of the MP reply composer
(`RA1`: `/message.php?config=hfr.inc&cat=prive&post=<id>&page=1&p=1&subcat=0&sondage=0&owntopic=0&new=0`, the page `R47b`
serves). `MessageReaderColumn` now gets the current account's composer, so LOT-084's flow applies unchanged: "Répondre"
only with an answer link naming the conversation, draft `.reply(topic:page: 1)` per conversation and account, LOT-048
`reply`, HFR's sentence ("Votre réponse a été postée avec succès !", `W11`) in the banner. The only difference is the
**latest post** (`TopicReaderModel.showLatestPost`): a public topic asks `maxPage + 1`, which HFR redirects to the last page
(`R24`); what HFR serves past the end of a `cat=prive` thread is not captured, so a conversation asks its last known page,
and when that page's pager names a later one (the reply opened it) asks that page next, both opened at the last message.
A failed or superseded load asks nothing more.

**New MP.** `NewMessageTarget(link:)` takes a new-MP composer link: `https` on the forum host, default port, no user info,
`cat=prive`; its `dest` value is the starting recipient (`R45b`: `dest=user1` gives `value="user1"`; the list's
`md_btn_new_topic` has `dest=` empty, `R13a`). Entries:
- the Messages list toolbar, "Nouveau message" (`square.and.pencil`), shown when an account is current and the page on
  screen has the link (`MessageListContent.newMessageURL`); logged out nothing is loaded (LOT-126), so no button;
- LOT-087 (message "MP" action) and LOT-116 (profile) once merged, with the link they read.

The sheet is LOT-084's `ReplyComposerView` with two one-line fields above the editor: "Destinataire" (no autocorrection,
no capitalisation) and "Sujet", focused on the first empty one. `ReplyComposerModel(composing: .newPrivateMessage(_))`:
- **Send** is offered with a non-blank recipient, subject and text (HFR refuses an empty text, `W17a` on an MP reply; a blank
  recipient or subject is refused locally, HFR's answer to one is not captured). Characters above
  U+FFFF in any of the three are refused before any request, listed (Q-3, `W12`). Recipient and subject are sent trimmed,
  as legacy Swift did; the text as typed. `LiveReplyPoster.newPrivateMessage` fetches the form at send time through the
  current account's session and posts LOT-048 `newPrivateMessage(to:subject:text:)`, which checks again (blank, line
  break, `maxlength` 70 on `sujet`, shape `newPrivateMessage`) before sending.
- **Several recipients**: the field is sent as typed, as HFR's own form takes it ("Pseudo des destinataires", hint "Entrez
  le pseudo du destinataire.", `R45b`). The app adds no separator rule: how HFR splits several pseudos is pending capture.
- **Outcomes** follow LOT-084 with texts about a message: `rejected` and `formUnavailable` show HFR's sentence; `emptyInput`,
  `lineBreak` and `tooLong` name the field ("Le sujet dépasse 70 caractères"); only `unconfirmed` says it may have been sent,
  and offers "Voir les messages" (`.checkTopic`). Nothing is resent automatically.
- **After a confirmed MP** (`W10`: "Votre message a été posté avec succès !", refresh to the list, no thread named):
  `MessageListModel.newMessageDidClose` shows HFR's sentence above the list for 4 s, reloads page 1 and opens the thread
  when **exactly one** row of it bears the subject sent (trimmed). `R13a`, the sender's list right after `W10`, lists the
  thread under that subject (`fixture-test-1`). No row or several: the list stays, nothing is guessed. After an
  unconfirmed send, page 1 is reloaded without opening anything.
- **Draft**: `DraftContext.privateMessage(recipient:)` keyed by the link's recipient (empty for the list button), per
  account; the text **and the subject** are kept (LOT-063 `Draft.subject`), restored on open, autosaved like a reply,
  discarded after a confirmed send. A recipient typed in the sheet is not stored: a draft has no recipient field.
  Closing asks keep / discard when the text or the subject holds something.

## Edge cases

- Account switch while the sheet is open: as LOT-084, the sheet goes away and keeps the draft under the previous account.
- The list page changes while the sheet is open: the sheet keeps the target it was opened with.
- Two threads with the subject sent on page 1 (an older one and the new one): none is opened.
- The list reload after a confirmed MP fails: the sentence is shown above the failure banner, nothing opens.
- A thread opened by the model (after a new MP) shows the conversation on an iPhone too: `MessagesRootView` moves the
  compact column to the detail when `selected` is set, as a tap does. Not run with a logged-in account (an agent sends no
  real MP): the operator checks it on the first real new MP.
- A conversation whose last page grew while reading (another member answered): the pager of the page asked names the new
  last page, which is asked next, like a page the reply opened.

## Fixtures

No new capture. `R13a` (list after `W10`, new-MP button, the thread under its subject), `R45b` (new-MP form, URL and `dest`
value), `RA1` (conversation with the `R47b` answer link) feed the tests through `PrivateMessageListParser` and
`LiveTopicPageSource.parse`; `W10`, `W11` sentences are scripted outcomes. The posting itself is LOT-048's (`W10` from `R45b`
is its differential test).

## Tests

`App/SwiftHFRTests/`:
- `Composer/NewMessageComposerTests`: the link names the recipient, the list button nobody; off-forum, non-default port,
  `http` and public links are no target; a confirmed MP sends recipient, subject (trimmed) and text once and clears the
  draft; Send needs the three fields; a non-BMP character in the recipient or the subject is refused before any request;
  an unconfirmed MP says to check the private messages and closes as `.checkTopic`; refusals name the field; subject and
  text are kept per recipient and restored, the typed recipient is not; a subject-only draft is kept; a reply has no subject nor recipient; the live
  poster refuses an off-forum link without a request.
- `Messages/MessageComposerEntryTests`: `R13a` gives the new-MP link; the button follows the loaded page and is absent
  logged out; a confirmed MP reloads page 1 and opens the one thread with its subject (also on `R13a` with `W10`'s subject);
  none opens with no match or two; an unconfirmed one reloads, closing does nothing; `RA1` carries the `R47b` answer link
  naming the conversation; after an MP reply the reader asks the last known page, never past it, then the page the reply
  opened; a failed load asks nothing more.

Shown to fail without the change (each mutation run on the simulator makes its tests fail): `maxPage + 1` on a
conversation, no follow-up page, a follow-up after a failed load, the first of several matching rows opened, no thread
opened, no new-MP link kept from the page, no reload after an unconfirmed MP, Send without recipient or subject, the
non-BMP check on the text only, the subject not saved, not restored, not counted for the close choice, the recipient not
trimmed, the reply's "unconfirmed" text on an MP; after the Fable round: a subject-only draft dropped.

## Pending capture

- What HFR serves for a page past the last one of a `cat=prive` thread (`R24` is a public topic): the reader never asks it.
- Several recipients in `dest`: the separator HFR accepts, and its answer to an unknown pseudo (the sentence is shown
  through `rejected` or `unconfirmed` either way); a pseudo with a space or a `+` in a `dest=` link (`HFRURL.queryValue`
  keeps `+`).
- HFR's answer to a new MP with a blank recipient or subject (the app never sends one).
- The answer to a new MP from an account that may not send one, and a flood refusal on MP creation (`W11x` is a second
  new thread in a row, refused: its sentence is shown).
- The sender's list when several threads share a subject: the app opens none.

## Intentional differences from legacy

| # | Legacy | Port | Why |
|---|---|---|---|
| D1 | Swift: recipient read-only, the message's author (`AnswerView.swift:826-831`) | editable, prefilled from the link (ObjC "À :" field) | ObjC parity; the list button names nobody |
| D2 | Swift: no draft for a new MP (`composerPersistsDraft = false`, `MessagesView.swift:4220`) | draft per recipient and account, subject included (LOT-063) | no lost text (GAP-092 rule of LOT-084) |
| D3 | success = no link in `.hop`; "Hooray" toast | LOT-048's confirmation of this write; HFR's sentence | LOT-084 D1 |
| D4 | after a new MP: dismiss only | list reloaded, the thread opened when its subject names one row | acceptance criterion of #219 |
| D5 | after an MP reply: reload when on the last page (`MessagesView.swift:5019-5049`) | the conversation's last page, never past it | LOT-084 D5; past-the-end not captured for `prive` |
| D6 | non-BMP characters sent (Swift) or stripped (ObjC) | refused in every field before sending | Q-3 (`W12`) |

## UX evolutions (H.1)

Rows of [GAP-LEGACY-VS-SWIFT.md](../migration/GAP-LEGACY-VS-SWIFT.md#convergence-classification-h1); open choices in
[UX-DECISIONS-PENDING.md](../migration/UX-DECISIONS-PENDING.md).
- GAP-115 MP reply: `a`, the LOT-084 composer on a conversation.
- GAP-114 new MP: pending **UXD-20**, whose recommendation keeps one recipient from a message and moves the list and
  profile entries to M5 (split `128b` in `docs/LOTS.md`). The list button is ObjC parity (`HFRMPViewController.m:511,537`,
  table above), not a new entry; several recipients are not a feature here, the field is HFR's own one-line `dest`. The
  operator decides on #219 whether the list button stays in this lot.

## Learnings

- HFR names no thread after a new MP (`W10` refreshes to the list): find it on the list by its subject, and only when one
  row matches.
- A behaviour verified on public topics (`R24`, past the last page) is not a fact for `cat=prive` threads: ask a page
  that exists and read its pager.
