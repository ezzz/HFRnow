# LOT-048 — Post-form engine

- **Module:** HFRClient (plus the form layout reader in HFRParsing)
- **Difficulty / model:** difficult (Opus 5.5 → Fable)
- **Issue:** none (claimed by the orchestrator in `docs/LOTS.md`, claim PR #34); old francoisgn/ios-app_SwiftHFR#76 (frozen history); audit D3 in [D](../audit/D-posting.md)
- **Depends on:** LOT-036 (`HopFormParser`), LOT-037 (`HopResponseParser`), LOT-042 (`HFRSession`)

Reply, quote reply, edit, delete (first post included, which deletes the thread), new topic, new private message and MP
reply: fetch the composer's `hop` form with the **selected** account's session, fill it, submit it like a browser, and
report success only when HFR confirmed this very write. Quote prefill building (LOT-049), the alert (LOT-050), flags
(LOT-051), polls (LOT-054), MPStorage (LOT-052) and the multi-quote cookie clean-up after a quoting reply (LOT-049) are out.

## Legacy sources

Legacy app: `master` of ezzz/HFRnow (same lines as francoisgn/hfrnow @ `2440d79`).

| Legacy | Replaced by |
|---|---|
| `Classes/AddMessageViewController.m:513-636` (`done`): POST of the harvested map; `allowvisitor`, `have_sondage`, `sticky`, `sticky_everywhere` only when `"1"`; `delete=1` only in delete mode; `pseudo` and `hash_check` from the selected account (stored hash, else the global one); text `removeEmoji`, `\n` → `\r\n`; overrides `sujet`, `subcat`, `dest`; cookies of the selected account | `PostingFlow` + `PostingBody` |
| `AddMessageViewController.m:586-622`: `.hop` with `<a>`/`<input>` = refusal, otherwise success | LOT-037 classifier **and** the per-write sentence |
| `AddMessageViewController.m:631`: "Votre message a peut être été posté malgré tout" on an exception | `PostingError.unconfirmed` |
| `Classes/QuoteMessageViewController.m:209-290` (form harvest, checkbox `"1"`/`"0"`, `MsgIcon` when checked) | `HopFormParser` (LOT-036) + `HopFormParser.layout` + browser semantics |
| `Classes/DeleteMessageViewController.m:44` (`isDeleteMode` YES: edit with `delete=1` and the unchanged text) | `PostingFlow.delete` |
| `HFRswift/Swift/ReplyService.swift:144-185` (`postReply`: query items of the fetch URL merged into the POST, `pseudo` and `hash_check` of the **main** account, default action `/bddpost.php`) | not ported, see "Intentional differences" |
| `ReplyService.swift:332` (`removeInactiveTopicOptionFlags`), `:991-1040` (`deleteMessage`, `delete=1`) | browser semantics (an unchecked box is not sent), `PostingFlow.delete` |
| `HFRswift/Swift/AccountSessionService.swift:77-105` (`makeReplySessionContext`: main account's cookies, stored hash) | the form's own `hash_check` and `pseudo`, fetched and posted through the selected session |

## Behaviour

All in `Packages/HFRKit/Sources/HFRClient/Posting/`, plus `HFRParsing/Forms/HopFormLayout.swift`.

1. **Load** — `PostingFlow.loadForm(at:in:)` takes the composer URL (answer link, quote link, decoded edit link, new-topic
   link, new-MP link) and an `HFRSession`. The URL must be `https` on `forum.hardware.fr`, default port, no user info
   (`invalidFormURL`, nothing requested). GET through the session (followed redirects stay on the forum, LOT-042). The page
   is parsed twice from the same string: `HopFormParser.parse` (LOT-036) for the fields, `HopFormParser.layout` for the
   document order. No form: the page's `.hop` is classified (LOT-037); the logged-out sentence gives `notLoggedIn`,
   anything else `formUnavailable(message:)` (`RA5`). An empty `hash_check` or `pseudo` (anonymous composer `R40b`) gives
   `notLoggedIn`. The form's token is recorded in the session (`updateHashCheck`). The returned `PostingForm` keeps the
   session it came from, so it can only be posted through it (Q-8).
2. **Shape** (`PostingForm.Shape`) — a non-empty `numreponse` is an edit form (`R43a`-`R44`); else a visible `sujet` with a
   `dest` field is a new MP (`R45b`), without one a new topic (`R45a`); else a reply composer (`R40a`, `R41a`, `R41b`, `R42`,
   `R47a`-`R47u1`). Each write requires its shape (`formMismatch`): `reply` ↔ reply, `newTopic` ↔ new topic,
   `newPrivateMessage` ↔ new MP, `edit` and `delete` ↔ edit.
3. **Local checks** (nothing sent): text, subject and recipient must not be blank (`emptyInput`); a character with a scalar
   above U+FFFF in any of them is refused (`unsupportedCharacters(input, characters)`, Q-3: HFR cuts the text there and
   answers success, `W12`); a sub-category must be one of the select's option values; a subject on an edit only when the
   form shows it (`R43a`); options (`[PostOption: Bool]`: boxes `signature`, `smiley`, `emaill`) only when the form has that box; delete
   needs the `delete` box (`R44` has none) and, on a first post, `confirmingWholeTopic: true`.
4. **First post** — `PostingForm.deletesWholeTopic` is true when the edit form shows the subject **or** its `delete` label
   says "intégralité" ("Effacer l'intégralité du sujet", `R43a`; a later post: hidden subject and "Effacer ce message",
   `R43b`). Either sign is enough, so a page showing only one still asks for confirmation.
5. **Body** (`PostingBody.make`, browser form submission): walk the controls in document order; send text, hidden and
   password inputs with their value (or an override: `sujet`, `dest`), a checkbox or radio only when checked (with
   the options and the flow's own `delete` value applied to checkboxes only), the first submit input only, a select's
   override or effective value (none when it has no option), `content_form` with the text; skip disabled controls, empty
   names and buttons. Refused (`unsupportedForm`): an input of an unknown type, another textarea, no enabled
   `content_form`, no `verifrequet` (copied from the form, never added: every write carries `1100`, HFR-PROTOCOL §7 X4),
   or a layout that does not list the parsed fields and selects in order. Encoding: `FormBody` with CRLF line breaks.
   `pseudo` and `hash_check` are the form's (the selected account's); nothing from the fetch URL is merged.
6. **Writes** — `reply`, `newTopic(subject:subcategory:text:)` (nil sub-category: the form's selected option, else the
   first, "Aucune" on `R45a`), `newPrivateMessage(to:subject:text:)`, `edit(_:subject:)` (sends `delete` unchecked even if
   the page served it checked), `delete(with:confirmingWholeTopic:)` (stored text sent back, `delete=1`).
7. **POST** — to the form's `action` (forum-origin path from LOT-036; nil or off-origin → `missingAction`, no default),
   `application/x-www-form-urlencoded; charset=utf-8`, 60 s (legacy writes had URLSession's default), redirects **not
   followed** (a 3xx is classified, never re-sent elsewhere). Sent once; cancellation is checked right before. A session
   refusal before sending (`invalidRequest`) is `network`; any other failure of the exchange (timeout, offline, lost
   connection, cancellation, HTTP 4xx/5xx) is `unconfirmed(.transport)`.
8. **Confirmation** — `HopResponseParser.classify(context: .write)`: `success` **and** the `.hop` sentence equal to this
   write's (`PostingAction.confirmation`): reply "Votre réponse a été postée avec succès !", new topic and new MP "Votre
   message a été posté avec succès !", edit "Votre message a été édité avec succès !", delete "Message effacé avec succès !".
   Another confirmation is `unconfirmed(.unexpectedConfirmation)`; `rejected` is `rejected(message:)`; `loggedOut` is
   `notLoggedIn`; anything else (or an unreadable page) `unconfirmed(.unrecognizedAnswer)`. Success returns
   `PostingResult` (sentence, refresh URL and anchor, `numreponse` of an edited or deleted message).

Errors carry no user text, token or cookie; `rejected` and `formUnavailable` carry HFR's sentence, `unsupportedCharacters`
the refused characters. Every case except `unconfirmed` means nothing was posted.

## Edge cases

- Double post: a POST is never resent by the engine; `unconfirmed` tells the app to let the user check the topic.
- A redirect answering the POST is not followed (a 307/308 would re-POST): `unconfirmed`.
- A form fetched with account A cannot be posted with account B: the form carries its session.
- An edit form served with `delete` checked never deletes through `edit`.
- Several submit inputs: only the first is sent, as if clicked (captured forms have one, `submit`). A `<button name>` is
  never sent. A checkbox without a `value` attribute would be sent with an empty value (a browser sends `on`); every
  captured box has `value="1"`.
- Repeated names are all sent, in order.
- Characters inside the BMP (é, ☺, ❤) are sent; whether HFR keeps every BMP emoji is HFR-PROTOCOL §7b B13.

## Fixtures

Shared corpus only, no new file. Forms `R40a`, `R40b`, `R41a`, `R41b`, `R42`, `R43a`-`R43c`, `R44`, `R45a`, `R45b`, `R47a`-`R47u1`;
answers `W10`-`W20b` and their metas (`request_body`, `request_fields`, `url`); `RA5`, `W01`, `W18`, `R08-1` as other pages;
LOT-004 `form` oracles (`legacy.post.pairs`, `legacy.postedContent`). A few tests edit one attribute of a captured page
(remove the action, check `delete`, hide the subject, rename a box) to reach a structural edge; none stands for a captured
state.

## Tests

- `PostingCaptureTests` (differential, captured requests): `W10` (new MP from `R45b`), `W11` (reply, LF sent as CRLF), `W13b`
  (byte-identical body), `W13c` (signature option, `R47u1`), `W14` (multi-quote prefill), `W15` (edit, no `delete`), `W16a`
  (delete), `W19` (whole thread, confirmed); the body equals the captured `request_body` once legacy's `"0"` boxes are
  dropped and line breaks written CRLF; URL, content type, timeout, no-redirect policy, recorded token, result sentence,
  anchor and `numreponse`. New topic from `R45a`: field order with the select in place.
- `PostingBodyOracleTests` (differential, LOT-004): on the 14 logged-in composers, the fields and values equal legacy's
  `post.pairs` except the unchecked boxes and the token.
- `PostingRefusalTests`: captured refusals (`W17b`, `W20a`, `W20b`, `W14x`, `W13cx`, `W11x`), `W17c` logged out, another write's
  confirmation (`W15`, `W18`), unknown pages, transport failures and HTTP 500 after the POST (unconfirmed, one POST), a 302
  answer, a session refusal, `R40b`, an empty token, `RA5` and `W17c` as form pages, form request failure, off-forum form
  URLs, absent and off-origin actions.
- `PostingInputTests`: non-BMP in text, subject, recipient (`W12`'s emoji), blank inputs (`W17a`), shapes of every captured
  composer, form mismatches, `R44` delete, unconfirmed whole-thread delete and both first-post signs, edit with `delete`
  served checked, subject on a later post, unknown sub-category, option not offered.
- `PostingBodyTests`: browser rules on small models (disabled, unnamed, second submit, button, repeated names, radio vs
  checkbox overrides, select overrides and empty selects, unsupported forms).
- `HopFormLayoutTests` (HFRParsing): indices match `parse` on all 15 composers, `content_form` and `subcat` positions, delete
  labels, disabled controls and buttons, missing form.

Shown to fail without the change: legacy `"0"` boxes, no per-write sentence check, no non-BMP check, no whole-thread
guard, edit without the forced `delete` off, followed redirects, transport failures as `network`, the subject-only
first-post sign, the textarea missing from the layout, no token check, no blank check, no form URL check, newlines
preserved, no shape distinction, no `invalidRequest` mapping, no `verifrequet` check, no option check.

## Intentional differences from legacy

1. **Browser checkbox semantics**: an unchecked box is not sent (legacy `"0"`); HFR reads values, both work (`W11`, `W13b`),
   and an edit can never carry `delete`.
2. **Document order** of the page (legacy: dictionary order).
3. **The form's `pseudo` and `hash_check`**, through the session that served the form; legacy ObjC used the selected
   account's stored hash with a global fallback, legacy Swift the main account's (Q-8 decided: selected account). An empty
   token stops the write (`notLoggedIn`) instead of posting with a stored one.
4. **Success needs HFR's confirmation and this write's sentence** (legacy: no link in `.hop`; `W17b` was a "success").
5. **No default action** (legacy `/bddpost.php`), and no fetch-URL query items merged (legacy Swift).
6. **Non-BMP characters refused**, not stripped (legacy ObjC `removeEmoji` stripped some ranges and kept others, legacy Swift
   sent them and lost the end of the text).
7. **Blank text refused locally** (legacy ObjC sent it; HFR refuses an empty one, `W17a`).
8. **Deleting a first post is offered**, behind an explicit confirmation (legacy UI never offered it).
9. **Unknown outcome is its own error**; the engine never resends.

## Pending capture

Not hand-built (LESSONS 36). None blocks the lot; until captured, each state is handled conservatively.
- **Public-topic answers**: a reply, a new topic, an edit and a delete in a forum topic (`cat=<forum>`). Only private-message
  writes are captured; public writes expect the same sentences, and another sentence is reported `unconfirmed`, never success.
- **Public edit form** of an own message, first post and later post: the `action` (HFR-PROTOCOL §3.1), the subject field and
  the `delete` label that tell a first post (until then both signs ask for confirmation).
- **Delete of a public topic's first post**: what HFR answers, and whether the whole topic goes (rf2 X1).
- **New-topic answer** in a forum category: sentence and refresh target (E14).
- **Reply form of a locked topic or of a topic the account may not post in** (already listed for LOT-036/037): reported as
  `formUnavailable` with the page's sentence.

## Learnings

- `ForumForm` loses where the textarea and the selects sit among the inputs; HFR's captured bodies follow document order,
  so the poster needs the layout, read from the same page.
- A success-shaped page is not enough for a write: check the sentence of the write you sent (`W18` is a success too).
