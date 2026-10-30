# LOT-049 — Quote engine

- **Module:** HFRClient
- **Difficulty / model:** medium (Opus 5.5 → Fable; taken by an Opus contributor, `ext/bybifok-opus-1`)
- **Issue:** [#75](https://github.com/ezzz/HFRnow/issues/75)
- **Depends on:** LOT-048 (#74): `PostingFlow.loadForm`, `reply`, `PostingForm`; LOT-031 (#58): `MessageActions.quoteURL`, `quoteSelection`; LOT-042 (#68): the session's multi-quote cookie (`MultiQuoteCookie`, `multiQuote(for:)`, `toggleQuote`). Also reads LOT-033's `TopicPage.answerFormURL` (the multi-quote composer).
- **Audit:** D4 (`docs/audit/D-posting.md` §2.2).

## Legacy sources

Legacy app: `francoisgn/hfrnow` at `2440d79` (an ancestor of `origin/master`).

| Legacy | What it gives this lot |
|---|---|
| `HFRswift/Swift/ReplyService.swift:767-841` (`fetchQuoteTemplate`, `extractContentForm`) | GET the quote link, read `content_form` from the `hop` form, line breaks to `\n` |
| `ReplyService.swift:902-915` (`decodeHTMLEntities`) | eleven entities decoded by hand (LOT-036's parser decodes them all) |
| `HFRswift/Swift/MessagesView.swift:36-109` (`ReplyQuoteSelectionFormatter`) | the selection formatter ported here |
| `MessagesView.swift:1852-1945` | multi-quote cookie (name from `quoter()`, `\|<numreponse>` markers, `.hardware.fr`, 1 h, deleted when empty): LOT-042 |
| `Classes/QuoteMessageViewController.m:459-525` | ObjC selection quote: the same rules, tag rebuilt through `int`, bold on every case-sensitive occurrence |
| `HFRswift/Swift/AccountSessionService.swift:107-115` | `quotes*` cookies saved across the global jar reset; not needed with LOT-042's per-account jars |
| `HFRswiftTests/ReplyPostingServiceTests.swift:1101-1132` | the three formatter cases ported in `QuoteSelectionFormatterTests` |

No legacy code clears the multi-quote cookie after a post (none at `2440d79`): it expired after one hour, and the next composer of the topic quoted the same messages again.

## Behaviour

Code in `Sources/HFRClient/Quote/`, tests in `Tests/HFRClientTests/Quote/`.

### `QuoteFlow`

- `quote(_:in:)`: the composer of one message, from its LOT-031 `quoteURL` (`noQuoteLink` when there is none, before any request), loaded by LOT-048's `PostingFlow.loadForm` through the given account session (forum URL check, token recorded, `notLoggedIn`, `formUnavailable`…: `QuoteError.form`). Returns a `QuoteComposer`.
- `multiQuote(_:answerFormURL:in:)`: the topic's reply composer (`TopicPage.answerFormURL`, `R42`/`R47c`'s URL, no `numrep`) loaded while the session holds the topic's `quotes…` cookie. The session sends it with the GET like a browser, together with the cookies of other topics; HFR prefills one block per selected message. `token` is any `quoteSelection` of the topic: it names the cookie (`MultiQuoteCookie.name(for:)`).
  - The selected messages are read from the session first; none selected is `emptySelection`, before any request.
  - The served form must name the token's topic in its hidden `cat` and `post` (`R42`: `13`, `28563`; `R47c`: `prive`, `3207033`), else `otherTopic`: the selection the composer would unselect after posting is the posted topic's, never another one.
- **Prefill**: `QuoteComposer.prefill` is the form's `content_form` as LOT-036 reads it (`ForumForm.textareaContent`): entities decoded, line breaks `\n`. The `[quotemsg=…]` blocks are HFR's, never rebuilt (HFR-PROTOCOL §4). A form that is not a reply composer (edit, new topic, new MP) or whose textarea is empty is `noQuote`.
- `reply(_:options:with:)`: LOT-048's `reply` through the composer's form, so its session, checks, single POST and confirmation rules. Then:
  - **after HFR's confirmation** (`success` with the reply sentence), the messages the multi-quote composer's request carried are unselected, in one actor turn (`QuotingSession.unselect`, LESSONS 55). A message selected after the composer was loaded stays selected; a message the user unselected meanwhile is not selected again; the cookie is deleted when nothing is left (LOT-042). Other topics' selections are untouched.
  - **on any error** (`rejected`, `notLoggedIn`, `unconfirmed`, a local refusal, `network`), the selection is kept: nothing was posted, or the user has to check the topic, and a retry needs the same quotes.
  - a **single quote** never touches the selection, whatever the outcome.

### `QuoteSelectionFormatter`

`format(_:selection:bold:)` narrows a prefill to the text the user selected in the message, or bolds it (port of `ReplyQuoteSelectionFormatter`):
- The selection is trimmed of whitespace and newlines; empty, it changes nothing. A prefill without a well-formed `[quotemsg=a,b,c]…[/quotemsg]` block (case-insensitive tags) is returned unchanged.
- **One block**: without `bold`, its text becomes the selection (not looked for: the selection is read on the rendered message, whose text is not the BBCode); with `bold`, the first case-insensitive occurrence is wrapped in `[b]…[/b]` as it is written, the rest of the prefill kept, a final `\n` added if missing; no occurrence leaves the prefill unchanged.
- **Several blocks** (multi-quote): the first block whose **text** holds the selection (case-insensitive) is returned alone, narrowed or bolded, followed by `\n`; when none does (a selection over two messages), the prefill is unchanged.
- The selection is looked for in the blocks' text, never in their tags, and the tags are kept as served.

## Edge cases

- A message without quote link (`MessageActions()`), an off-forum quote link (`https://forum.hardware.fr:8443/…`): nothing is requested.
- An anonymous composer (`R40b`) is LOT-048's `notLoggedIn`.
- The answer link served without the prefill (`R47b` standing for a composer whose cookie HFR did not use): `noQuote`, selection kept.
- Another topic's token with `R47c`'s form: another conversation number, the same number in a forum category, another forum topic: `otherTopic`, nothing unselected.
- A quote of a post that itself quotes (`R41b`): HFR's prefill holds only that post's own text, so nested quotes never reach the formatter.
- Selecting a digit or an author number that only a tag holds (`900002` in `R47c`'s tags) bolds nothing (legacy matched the tag).
- Large message numbers stay as served (legacy ObjC rebuilt the tag with `%d`).

## Fixtures

Captures only, nothing new: composers `R41a`, `R41b`, `R42`, `R47a`, `R47c`, answer `W14`; `R40a`, `R40b`, `R43a`, `R45a`, `R45b`, `R47b` as other composers; `W14x`, `W15`, `W17b`, `W17c`, `W20a` as other answers. Oracles: LOT-004 `contentForm` and `contentFormRaw` of `R41a`, `R41b`, `R42`, `R47a`, `R47c`. The formatter's multi-block cases use `R47c`'s prefill, checked against its oracle; its other inputs are prefill strings, not page states.

## Tests

- `QuoteCaptureTests` (differential): for `R41a`, `R41b`, `R47a` (quote link) and `R42`, `R47c` (answer link with the topic's two blocks selected), the prefill equals the oracle's `contentForm` and its `contentFormRaw` once line breaks are `\n`; one GET of the captured URL; the multi-quote GET carried exactly the topic's cookie (`quoteshardwarefr-13-28563=|2666649|2666682`). `W14`: the `R47c` composer posted as served gives the captured body (browser semantics), the conversation's selection is gone and another topic's stays.
- `QuoteFlowTests`: `noQuoteLink`, `emptySelection` (no request), `noQuote` on five other composers, `noQuote` for a multi-quote without prefill (selection kept), `otherTopic` for three other topics, LOT-048 errors; after the reply: later selections stay and an unselected message is not selected again, the selection kept on `W17b`, `W20a`, `W14x`, `W17c`, `W15`, a timeout and HTTP 500, kept on a local refusal, untouched by a single quote whose message is selected; on a real `HFRSession` (no request): the topic's cookie is one the jar sends to the answer link, `unselect` removes only the given messages and deletes the cookie once empty, another topic's cookie stays.
- `QuoteSelectionFormatterTests`: legacy's three cases; empty and untrimmed selections; case; selection not found (one block narrowed anyway, bold unchanged, several blocks unchanged); a selection over two blocks; a selection over two lines of `R47c`'s first block; tags never searched; tags kept as served (upper case, large numbers); surroundings kept when bolding; first occurrence only; prefills without a well-formed block.

Shown to fail with the behaviour removed (each mutation caught): no unselect after success, unselect before posting, the whole selection cleared, toggles without re-reading, a single quote unselecting its message, no empty-selection check, no topic check, topic check on `post` only and on `cat` only, no shape check, an empty prefill accepted, a missing quote link replaced by a URL; formatter: tags searched, tags rebuilt, selection not trimmed, case-sensitive matching, several blocks bolded in place, one block narrowed only when found, no final `\n`, every occurrence bolded, greedy blocks, bold-not-found narrowing.

## Pending capture

- **Whether HFR clears the selection itself** after a post (#334): `W14`'s answer sets a cookie named `quoteshardwarefr-prive-<post>` (its meta), value and expiry not recorded. The client unselects the posted messages either way; if HFR deletes the cookie, a message selected while the reply was in flight is lost by HFR's doing.
- A **quote link loaded while the topic has a selection**: whether HFR adds the selected blocks to the single prefill. Until captured, a single quote leaves the selection alone.
- The **order of the blocks** of a multi-quote prefill: both captures list them by ascending message number, and the selection order was not recorded (`|a|b` in the metas).
- The **cookie-less multi-quote route** (one quote form per message, prefills concatenated, HFR-PROTOCOL §7 X10): not used.

## Intentional differences from legacy

1. **The posted messages are unselected** once HFR confirmed the reply (legacy left the cookie for its hour, and the next composer quoted them again). Only those: later selections and other topics stay; on any error nothing changes. [CHANGELOG-LEGACY](../CHANGELOG-LEGACY.md) row 43.
2. **Selection looked for in the quoted text only, tags kept as served** (legacy Swift searched and rebuilt the tags, ObjC through `int`; a selection matching a tag could bold inside it). Row 44.
3. **Line breaks**: the prefill keeps LOT-036's `\n`, as legacy did (`ReplyService.swift:788-790`); HFR serves CRLF inside the quoted text and bare LF after the blocks (oracle `contentFormRaw`), and the reply is posted with CRLF either way (`W14`'s body). The issue asked for CRLF kept as served: the differential test compares both oracle fields, and the selection formatter needs `\n` to match a selection over several lines.
4. **The selected account's session** loads the composer and posts the reply (legacy Swift used the main account's cookies, `AccountSessionService.swift:77-105`): LOT-048's decision Q-8.

## Learnings

- A cookie a flow writes back after a request belongs to the same compare-and-set rule as a token (LESSONS 55): unselect what the request carried, not the whole selection.
