# LOT-086 — Quote and multi-quote into the composer

- **Module:** App (`App/SwiftHFR/Reader/Quote/`, `App/SwiftHFR/Composer/`), one setting key in HFRStorage / HFRModels
- **Difficulty / model:** medium (Opus 5.5 → Fable; coded by a cloud child, `cloud/lot-086`)
- **Issue:** [#178](https://github.com/ezzz/HFRnow/issues/178) (roadmap [#166](https://github.com/ezzz/HFRnow/issues/166))
- **Depends on:** LOT-049 (`QuoteFlow`, `QuoteSelectionFormatter`), LOT-042 (the selection cookie, `HFRSession.toggleQuote`),
  LOT-084 / 085 / 089 / 128 (the composer), LOT-087 (message menu, typed bridge)
- **GAP rows:** GAP-081 (quote), GAP-082 (quote a selection), GAP-083 (multi-quote). **Decision:** UXD-17 (2026-11-02): keep the
  per-message toggle (A); the tray is LOT-153 (M5).

As a poster, I quote one message, several messages or a passage, and the quotes land in my reply.

## Legacy sources

Legacy app: `ezzz/HFRnow`. The reply-button setting and the selection menu are newer than `2440d79`, so those lines cite `master`
at `21173e7` (LESSONS: cite the revision with every line range).

| Legacy | Replaced by |
|---|---|
| `HFRswift/Swift/MessagesView.swift:15-34` @ 21173e7 (`ReplyQuoteDraftMerger`) | `QuoteDraftMerger` |
| `MessagesView.swift:4144-4195`, `:4196-4281` @ 21173e7 (`openQuoteComposer`, `openTextQuoteComposer`, `prefillComposer`, `replaceComposerDraft`) | `TopicReaderModel.quoteMessage`, `quoteSelection`, `requestReply`; `ReplyComposerModel.start()` merges the quote into the restored draft |
| `HFRswift/Swift/ReplyService.swift:767-841` @ 2440d79 (`fetchQuoteTemplate`) | LOT-049's `QuoteFlow.quote` / `multiQuote` through `LiveQuoter` |
| `MessagesView.swift:36-109` @ 2440d79 (`ReplyQuoteSelectionFormatter`) | LOT-049's `QuoteSelectionFormatter` (not reimplemented) |
| `MessagesView.swift:1637-1644`, `:1852-1945` @ 2440d79 (multi-quote toggle, cookie) | `QuoteSelectionHandler`, `LiveQuoter.toggle` over LOT-042's cookie |
| `MessagesView.swift:545-660` @ 21173e7 (`MessageWebView`: "Citer extrait" / "Citer gras", `requestTextQuote`) | `QuoteMenuWebView`, `reader.js` `quoteSelection`, `ReaderBridgeMessage.quote` |
| `Common.swift:243-263` @ 21173e7 (`AppReplyButtonBehavior`: `quick`, `forum`, `hidden`), `AppSettingsView.swift:106, 481-485` | `ReplyButtonBehavior`, `SettingKey.replyButtonBehavior`, "Bouton +" picker, `ReaderReplyFlow` |
| `MessagesView.swift:3180-3200`, `:4535-4560` @ 21173e7 (`shouldHideReplyComposerButton`, `replyButtonSystemImage`, `openReplyComposer`) | `ReaderReplyFlow` toolbar button (`plus` for `quick`, `square.and.pencil` for `forum`, none for `hidden`) |
| `Classes/OnlineMessagesTableViewController.m:523, 544, 1005-1014` (Quotinuum, issue comment of 2026-10-28) | same entries as above; the ObjC rules are LOT-049's |
| `HFRswiftTests/ReplyPostingServiceTests.swift:1330-1368` @ 21173e7 | the four merger cases of `QuoteDraftMergerTests` |

## Legacy counterpart (app lots)

| SwiftHFR | Legacy |
|---|---|
| `QuoteDraftMerger` | `HFRswift/Swift/MessagesView.swift (ReplyQuoteDraftMerger)` @ 21173e7 |
| `TopicReaderModel+Quote.swift` | `MessagesView.swift (openQuoteComposer, openTextQuoteComposer, openReplyComposer, toggleQuoteSelection)` @ 21173e7 |
| `QuoteOpening.swift` (`LiveQuoter`) | `ReplyService.swift (fetchQuoteTemplate)` @ 2440d79, `MessagesView.swift (quoter cookie)` @ 2440d79 |
| `QuoteMenuWebView.swift` | `MessagesView.swift (MessageWebView)` @ 21173e7 |
| `ReaderReplyFlow` ("+" button) | `MessagesView.swift (replyButtonMode)` @ 21173e7 |

## UX evolutions (app lots)

| Change | GAP | Class |
|---|---|---|
| The reply button carries the selected quotes (legacy `quick` ignored the selection; only `forum` fetched it) | GAP-083 | b·needed: the absorbed backlog item "reply '+' carries selected quotes" and user feedback p. 497-505 |
| The selection is released after HFR confirmed the reply (legacy: one hour, so the next composer quoted the same messages again) | GAP-083 | b·needed: leftovers of p. 505 (CHANGELOG-LEGACY 70) |
| A short confirmation after each toggle ("Ajouté aux citations (2)") | GAP-083 | b: legacy toggled silently |
| A selection that starts and ends in different messages is not quoted | GAP-082 | b·needed: legacy quoted the first message with the words of the other |
| Blocks of a multi-quote are put in topic order | GAP-083 | b·needed: acceptance criterion; HFR's order for a cookie toggled out of order is not captured |

The tray with a count stays LOT-153 (M5, UXD-17).

## Behaviour

**"Citer"** (`.quote` handler). `QuoteFlow.quote` fetches the message's quote link in the current account's session; the prefill
(HFR's own `[quotemsg=…]` block) is merged into the topic's draft when the composer opens. A failure opens nothing and says why
(`ComposerMessages.quote`). The selection is never touched.

**"Citer ☐/☑"** (`.quoteSelection` handler). Toggles the message in the topic's selection cookie (LOT-042; an exact-match
selection, one cookie per topic). The session is an actor, so the menu reads the selection again before it opens
(`TopicReaderModel.openMenu`): the title shows the state as it is now, also after a reply released some messages. Nothing is
requested.

**Reply button** (`ReplyButtonBehavior`, key `reply_button_behavior`, legacy values kept for import). `hidden` draws no button.
`quick` and `forum` call `requestReply()`: with no selection the composer opens on the draft as it is; with one,
`QuoteFlow.multiQuote` fetches the topic's reply form with the selection (cookie) and its prefill, blocks in topic order
(`MultiQuoteOrder`), is merged into the draft. If that fails the composer still opens, without the quotes, with the reason in the
feedback banner and the selection kept: a quote never blocks a reply.
The two modes do not differ yet. Legacy's `forum` replaced the draft with what HFR serves (archiving the old draft in a store
SwiftHFR does not have); replacing a draft silently is data loss, so both merge. **Open question for the operator:** keep the two
values as one behaviour, or give `forum` a real difference (for instance "start from an empty draft, keep the old one").

**Quote of a selection.** The reader's selection menu gets "Citer extrait" (the passage alone) and "Citer gras" (the whole message,
the passage in bold) while the reader can quote (an account is current, the page has an answer form). `reader.js`
`hfrReader.quoteSelection(bold)` reads the selection in the reader's own world and posts `{type: "quote", token, post, text, bold}`,
decoded to `ReaderBridgeMessage.quote(post:text:bold:)` (a real boolean, a non-blank text of at most 20 000 characters, a positive
message number; anything else is rejected whole). The model fetches the message's quote and gives it to LOT-049's
`QuoteSelectionFormatter`.

**Merge** (`QuoteDraftMerger`, legacy's rules): the quote goes after the draft with a blank line; an empty draft becomes the quote
as served; a blank quote changes nothing; a quote the draft already holds whole is not added again.

**Release.** The composer keeps the selection a multi-quote reply stands for (`QuoteRelease`: the numbers selected when HFR's
prefill was asked for). Only after HFR's confirmation of the reply (`PostingResult`), the messages that the posted text still
quotes (the first number of each `[quotemsg=n,…]`, LOT-049's rule) are unselected, one by one, each read again; a message selected
after the prefill stays, a message the user unselected meanwhile is not selected again, another topic is untouched. A block the user
deleted leaves its message selected. On every other outcome (`rejected`, `unconfirmed`, a local refusal) the selection is kept. A
single quote never releases. Only a reply takes a quote: an edit or a new message ignores one, so an edit never re-posts a quote.

The composer still posts through a form fetched at send time (LOT-084), not through the `QuoteComposer` fetched when it opened (a
form may be minutes old), so the release is the app's own, with LOT-049's rule; `QuoteFlow.reply` is not used.

## Edge cases

- Logged out: `ComposerServices` is nil, so no quote handler is registered and no selection menu entry is offered.
- A page without an answer form (closed topic, private conversation of the Messages tab): nothing to quote into.
- A second quote while one is being fetched is ignored (legacy `isLoadingQuoteTemplate`).
- A selection reported for a document that is no longer the one shown, or for a continuation copy: dropped.
- Quoting twice the same message with another passage adds a second block; the same block twice adds nothing.
- The merged text is saved like typing (after a pause); closing the sheet on it keeps it in the draft.

## Fixtures

No new capture. Prefills are strings shaped like `R41a` / `R42` (`[quotemsg=<numreponse>,<ref>,<author id>]…[/quotemsg]`, HFR-PROTOCOL §4);
the engine's differential tests on the captures are LOT-049's.
**Pending capture:** what HFR does when the cookie lists messages out of order (`MultiQuoteOrder` makes the order ascending whatever
HFR does; `R42` and `R47c` are ascending already).

## Intentional differences from legacy

1. Exact test for "the draft already holds the quote" (legacy ignored case and diacritics).
2. A selection over two messages is not quoted (legacy used the first message's link).
3. The reply button quotes the selection in `quick` mode too.
4. The selection is released after a confirmed reply.
5. The reply button is not hidden in landscape on iPhone (legacy hid its floating "+" there because it covered the page; a toolbar
   item covers nothing).
6. A short confirmation after each toggle.

## Tests

- `QuoteDraftMergerTests` (merger, `MultiQuoteOrder`), `ReplyComposerQuoteTests` (merge into the restored draft, saved, release
  only after a confirmed reply, kept on every other outcome, single quote, new MP), `TopicReaderQuoteTests` ("Citer", selection
  extract and bold with the engine's formatter, toggle and its menu state, reply button with and without selection, failures,
  one quote at a time, logged out), `LiveQuoterTests` (a real `HFRSession`: toggle order, exact numbers, release rules, another
  topic untouched), `ReaderBridgeMessageTests` / `ReaderBridgeWiringTests` (the `quote` case), `TopicsSettingsModelTests` and
  `ReaderDisplaySettingsTests` (the setting), `ReplyButtonBehaviorKeyTests` (HFRStorage).
- `LiveQuoterTests` and `QuoteDraftMergerTests` also ran on Linux against HFRKit while the lot was written; the rest is built and run by
  the `App build + tests` job.

## Learnings

- `HFRSession` is an actor: its selection reads and toggles are asynchronous, so a synchronous menu keeps a main-actor copy and
  refreshes it just before it opens.
- A seam over the session (`QuoteOpening`) can be compiled and tested on Linux (`swift test`) even when the app target cannot.
