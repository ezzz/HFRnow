# LOT-050 — Moderator alert

- **Module:** HFRClient (one layout function in HFRParsing)
- **Difficulty / model:** easy (Opus 5.5 → Fable)
- **Issue:** ezzz/HFRnow#76; audit D5 in [D](../audit/D-posting.md) §2.6
- **Depends on:** LOT-036 (`HopFormParser.parseModerationForm`), LOT-037 (`HopResponseParser`, `.alertPrepare`); uses LOT-031's
  alert link (`MessageActions.alertURL`) and LOT-048's write conventions (`PostingSession`, `PostingBody`, `isForumPage`)

Report a message to the moderators with a reason, through the selected account's session: read HFR's alert page for the
message, which either says the message was already reported or serves the form, then post the form like a browser.
The mailto fallback is the app's (LOT-135, #225).

## Legacy sources

Legacy app: francoisgn/hfrnow @ `2440d79`.

| Legacy | Replaced by |
|---|---|
| `Classes/AlerteModoViewController.m:153-160` (a `.hop` holding `<a>` or `<input>` = already alerted, its text shown) | `ModeratorAlertFlow.prepare` with LOT-037 `.alertPrepare` |
| `AlerteModoViewController.m:164-176` (form whose `action` contains `modo.php`, every input with a name and a value, submit URL `ForumURL/user/<action>`) | LOT-036 `parseModerationForm` (action resolved against the page), `moderationLayout` |
| `AlerteModoViewController.m:197-240` (POST of the inputs plus `raison`, emoji removed `:209`, `\n` → `\r\n` `:210`, the `.hop` text shown as a success "Hooray !" `:229-236`) | `ModeratorAlertFlow.submit` |
| `HFRswift/Swift/ReplyService.swift:1426-1462` (`prepareAlert`: logged-out form check, already alerted with a fixed fallback text "Alerte déjà envoyée.", form by regex, action with `defaultSubmitURL()` as fallback `:1455`) | `prepare`; no fixed text, no default action |
| `ReplyService.swift:1465-1500` (`submitAlert`: blank reason refused `:1468-1471`, any non-empty `.hop` text returned as the success message `:1495-1499`) | `submit`; the text is returned, never called a success |

The LOT-004 oracle of `R46` (`Fixtures/LOT-004/R46.oracle.json`, `result.legacy`) is the legacy reading of the form: its
inputs (`inputData`), its submit URL (`formSubmit`) and the POST it would send (`post.pairs`, with "Alert reason").

## Behaviour

Code in `Sources/HFRClient/Alert/`, tests in `Tests/HFRClientTests/Alert/`.

1. **Link** — `ModeratorAlertTarget` accepts the link only when it is an `https` page of `forum.hardware.fr`, default
   port, no user info (`PostingFlow.isForumPage`, LESSONS 37, 43), whose path is exactly `/user/modo.php`, with
   `config=hfr.inc` and one forum `cat` above 0, one positive `post` and one positive `numreponse` (LOT-031's alert link,
   `R21`). A repeated parameter is refused (the server may read either copy). Anything else is `invalidLink`, nothing
   sent. The topic-level `modo.php?…&ref=0` link of `R21` has no `numreponse` and is refused: its page is not captured.
   A private conversation has no alert link (`RA1`-`RA4`), so `cat=prive` is refused too.
2. **Prepare** — a session without a usable identity (logged out, or its `md_user` expired) is `notLoggedIn` before
   any request: its form would be refused at submit. Otherwise `prepare(link:in:)` GETs the link through the account's session (redirects followed, as
   for LOT-048's form pages). The final URL must still be a forum page (`invalidLink`). Then, in legacy's order:
   - LOT-037 `.alertPrepare`: `alreadyAlerted` gives `ModeratorAlertPage.alreadyAlerted(message:)` with HFR's own sentence,
     never a fixed text (`R88`); `loggedOut` (`W17c`'s sentence, or the alert page's own, `R89`) is `notLoggedIn`;
   - otherwise the page must hold the alert form (LOT-036 `parseModerationForm` and `moderationLayout`) with a `raison`
     textarea, else `formUnavailable(message:)` with the page's `.hop` text if any;
   - the form's action, resolved against the page, must be the alert page of **the same message** (same parsed target as
     the link), else `invalidLink`: the token and cookies are never posted elsewhere;
   - an empty `hash_check` means a logged-out session (`notLoggedIn`); a non-empty one is recorded in the session, unless
     a login was adopted while the page was in flight (#308).
3. **Submit** — `submit(reason:with:)` refuses before sending a reason that is blank after trimming (`emptyReason`) or
   holds characters outside the BMP (`unsupportedCharacters`, distinct, in order; decision Q-3, as for posts). The body
   is the form's controls in document order, as a browser sends them (`hash_check`, `referer_page`, `raison`, `Submit`
   on `R46`), with `raison` = the reason and its line breaks as CRLF (LOT-048's `PostingBody`, generalised to a named
   textarea). Last before sending, the session's identity must still be the one the alert page was requested with:
   after a logout or a login of another account in the same session the form's token is no longer the session's, so
   the submit is `sessionChanged` with nothing sent, as for posts (#342). A re-login of the same account still sends. A
   cancellation before the POST, during that identity lookup included, is `network(.cancelled)`. One POST to the action,
   redirects not followed, 60 s timeout, never retried.
4. **Answer** (#395) — read by LOT-037 `.alertSubmit`. HFR's confirmation, the `.hop` "Un message a été envoyé avec
   succès aux modérateurs" with its back link and no refresh (`W46`), is the only success: `ModeratorAlertAnswer(message:)`.
   HFR's logged-out sentences (`W47`, `W17c`) are `notLoggedIn`. Any other `.hop` with a link or an input (flood `W20a`,
   `W17a`, `R88`'s sentence) and `W17b`'s plain text are `rejected(message:)` with HFR's sentence. Another write's or the
   vote's confirmation (`W10`, `W42`), a redirect, a page without a sentence, or a failed exchange is `unconfirmed`
   (`unrecognizedAnswer`, `transport`); a request the session refuses to send is `network`.
5. **Errors** (`ModeratorAlertError`) — before anything leaves: `invalidLink`, `formUnavailable`, `notLoggedIn`,
   `unsupportedForm` (a control a browser cannot send), `emptyReason`, `unsupportedCharacters`, `sessionChanged`,
   `network`. After the
   POST left: `notLoggedIn`, `rejected`, `unconfirmed`. No case carries the reason, a token or a cookie.

## Edge cases

- `R46` is served at the link itself (no redirect, `R46.meta.json`); its form action reorders the query
  (`modo.php?cat&ref&post&numreponse&page&config`) and is relative to `/user/`.
- The page also holds the `#fastsearch` form with its own `hash_check`: only the form whose action contains `modo.php`
  is read (LOT-036).
- Already alerted: every `.hop` + link/input page reads `alreadyAlerted` at this step (flood `W20a`, `RA5`, `W17a`
  included: LOT-037's rule, which fails safe), so the sentence shown is always HFR's own.

## Intentional differences from legacy

1. **Success only on HFR's confirmation**: legacy showed any `.hop` text as a success (`AlerteModoViewController.m:229-236`,
   `ReplyService.swift:1495-1499`); here only `W46`'s sentence is, refusals are `rejected` and the logged-out page and
   answer (`R89`, `W47`) `notLoggedIn` where legacy read the page as already alerted. CHANGELOG-LEGACY rows 66 and 74.
2. **Emoji refused, not removed**: Objective-C legacy removed them silently (`:209`), the Swift service sent them; the
   reason is refused with the characters listed, as for posts (Q-3). Row 66.
3. **No default action**: legacy Swift posted to `defaultSubmitURL()` when the action could not be read (`:1455`);
   here the action must be the alert page of the same message, on the forum origin. Row 66.
4. **Browser order**: legacy sent its dictionary's order (oracle `bodyOrder`); here the document order. The fields and
   values are the oracle's.
5. **No fixed "already alerted" text**: legacy Swift fell back to "Alerte déjà envoyée."; the sentence here is HFR's or nil.

## Tests

Captures only: `R46` and its LOT-004 oracle (form, POST), `R21` (link); `R88` (already reported), `W17a`, `W20a`, `RA5`
(the same shape), `W17c` and `R89` (logged out), `R20` (no form); `W46` (HFR's confirmation of an alert), `W47` (logged
out), and `R88`, `W10`, `W17a`, `W17b`, `W20a`, `W42`, `W43` for the answer's other shapes. LOT-037's reading of them:
`HopResponseAlertTests`.
Small fragments give the form rules' inputs (empty token, no `raison`, another action).

- `ModeratorAlertPrepareTests`: `R21`'s link of message 2666649 is `R46`'s request; the prepared form equals the oracle
  (inputs, submit URL), one GET, token recorded; a logged-out session refused before any request; already alerted with HFR's sentence (`R88` and three pages of the same
  shape); logged out (`W17c`, `R89`); no form; empty token;
  no `raison`; four actions refused; nine links refused before any request; an off-forum redirect refused for a form and
  for a `.hop` page; the public entry point sends through the account's session.
- `ModeratorAlertSubmitTests`: the POST carries the oracle's pairs, in document order, to the oracle's URL, form content
  type, redirects not followed, 60 s; CRLF; blank and non-BMP reasons refused before sending; `W46` is the success, one
  POST; five captured refusals `rejected` with HFR's sentence; `W10` and `W42` and `W46` served as a redirect
  `unconfirmed`; `W47` and `W17c` after the POST `notLoggedIn`; no sentence or a timeout is `unconfirmed`; a refused request is `network`; a logout or a login of another account after the prepare, or a login of
  another account while the alert page is in flight, is `sessionChanged` with no POST; a re-login of the same account
  still posts; a cancellation during the identity lookup is a plain cancellation, switched or not.
- `HopFormParserTests.moderationLayout`: `R46`'s controls in document order, `raison` between the hidden inputs and
  `Submit`.

Shown to fail with the behaviour removed (each mutation caught): no already-alerted step, an off-forum redirect
accepted, the action of another message accepted, an empty token accepted, LOT-037's refusal read on the answer,
non-BMP characters sent, redirects followed on the POST, any `cat` accepted, no `raison` check, the logged-out page read
as already alerted, line breaks sent as LF, a blank reason sent, no identity check before the POST, no cancellation
check after it, the login generation compared instead of the identity, no identity check before the GET.

## Captured since, read by #395

PR #394 captured the pages this lot was written without; #395 reads them (steps 2 and 4): `R88` already alerted, `W46`
the success, `R89` and `W47` `notLoggedIn` (their sentence, "Vous devez être identifié pour prévenir les modérateurs",
is not `W17c`'s, and is read in the alert contexts only).
