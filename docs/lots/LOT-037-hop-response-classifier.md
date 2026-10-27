# LOT-037 — `hop` response classifier

- **Module:** HFRParsing
- **Difficulty / model:** medium (Sonnet → Opus)
- **Issue:** none (lot tracked in `docs/LOTS.md`); old issue francoisgn/ios-app_SwiftHFR#70 (frozen history)

Turns the page HFR answers after a write into a [`HopResponse`](LOT-012-form-write-models.md). The write flows of `HFRClient`
(LOT-048 post/edit/delete, LOT-050 alert, LOT-051 flags, LOT-054 poll vote) read the result; none of them may report success
unless this classifier did.

## Legacy sources
Legacy repository <https://github.com/francoisgn/hfrnow> at `2440d79` (same paths on `origin/master`).

| Legacy | What it gives |
|---|---|
| `Classes/AddMessageViewController.m:586-622` | reply/edit/new topic/MP: `.hop` with `<a>` or `<input>` = refusal (alert shows its text); otherwise success, anchor = fragment of the refresh meta (`<meta http-equiv="Refresh" content="[^#]+([^"]*)" />`), or the `numreponse` of the request URL for a delete |
| `Classes/AlerteModoViewController.m:154-163`, `229-236` | alert: `.hop` with `<a>` or `<input>` before the form = already alerted; submit shows the `.hop` text |
| `HFRswift/Swift/ReplyService.swift:579-625` | `parseHopMessage` (text of the `.hop` block, tags stripped, entities decoded) |
| `ReplyService.swift:627-668` | refresh anchor and URL |
| `ReplyService.swift:718-732` | `isSuccessfulPost`: refresh meta anywhere, or a `.hop` without `<a`/`<input` in the next 2000 characters |
| `ReplyService.swift:1564-1572` | `isAlreadyAlerted` |
| `ReplyService.swift:1707-1730` | `isLoggedOutForm` (login form shape; not used, see Pending capture) |
| `Classes/AddMessageViewController.m` via `SuperHFRplus/Helpers/ASIHTTPRequest+Tools.m:14-48` | response decoding (not here: callers decode bytes) |

Oracle: LOT-004 `response` kind, `Fixtures/LOT-004/W*.oracle.json` (`legacy.classification`, `message`, `anchor`).

## Behaviour
`HopResponseParser.classify(html:context:requestURL:) throws(ParsingError) -> HopResponse`. Pure; reads no status code (a non-2xx
answer is a transport failure, decided before parsing).

| Page | Kind | Rule |
|---|---|---|
| `.hop` (class exactly `hop`) with an `<a>` or `<input>`, text contains "vous devez être enregistré" | `loggedOut` | `W17c` |
| same, `context: .write` | `rejected` | flood (`W11x`, `W13cx`, `W14x`, `W20a/b`), empty body (`W17a`); `message` is the sentence |
| same, `context: .alertPrepare` | `alreadyAlerted` | legacy structural rule, text not captured |
| `.hop` with no link/input, a sentence, **and** a refresh meta to an `https` forum URL, `context: .write` | `success` | `W10`-`W16`, `W18`, `W19`, `P03a/b/d`; `refreshURL` resolved against `requestURL`, `refreshAnchor` = fragment without `#` (nil when none) |
| no `.hop`, body text starts "Une erreur est survenue lors de l'envoi des données" | `rejected` | invalid `hash_check`, `W17b` |
| anything else | `unrecognized` (message kept when a `.hop` exists) | R12, RA5 (read pages), R44 and R46 (forms), empty body, `.hop` without refresh, refresh without `.hop`, refresh off the forum |

`message` is the **own text** of the `.hop` block, whitespace collapsed and trimmed: the sentence without the "Retour à la page
précédente" link or button (a child-element sentence falls back to all the text). `refreshURL` and `refreshAnchor` are set on
`success` only, so a caller never follows the refresh of a refusal.

`context` exists because the same shape (`.hop` with a link) is a refusal after a write and "already alerted" before the alert
form; the page alone cannot say which.

## Edge cases
- Refresh target: `&amp;` decoded, relative resolved, only `https` on `forum.hardware.fr` accepted (same rule as `SearchRedirectParser`, LESSONS 37; `http://forum.hardware.fr:80/…`, other hosts, `//host/…`, `javascript:` are not a confirmation). A refresh without `url=` is ignored. The first valid-looking refresh meta decides.
- A delete's refresh has no fragment (`W16a`, `W19`): `refreshAnchor` is nil. The post to scroll to is the caller's `numreponse`, as in legacy.
- A `.hop` with an empty sentence is never a success.
- `.alertPrepare` never returns `success`: the alert's own success page is not captured.
- Latin-1 pages (`ASIHTTPRequest+Tools` quirk 13) are the caller's decoding concern; this parser takes a `String`.

## Fixtures
Existing captures and LOT-004 oracles, no new file:
`W10 W11 W11x W12 W13b W13c W13cx W14 W14x W15 W16a W16b W17a W17b W17c W19 W20a W20b` (differential), `W18 P03a P03b P03d`
(GET writes), `R12 RA5` (read pages with `.hop`), `R44`, `R46` (forms, `.hop` absent). Small hand-written HTML in the tests only
exercises structural edges (refresh target validation, link next to a refresh, `.alertPrepare` shape); none of it is offered as a
captured state.

## Intentional differences from legacy
1. **Never success without HFR's confirmation.** Legacy: no `.hop` → success; `.hop` without link/input → success even without a refresh. Here a refresh to the forum and a sentence are both required. Consequence: `W17b` (bad `hash_check`, 99-byte plain text, no HTML) is `rejected`, where the oracle says `success` (`hopFound: false`, a known oracle bug: legacy `messagesNode` is nil and the `findChildTag` tests fall through to the success branch). Tests assert both the legacy value and the corrected one.
2. **`loggedOut`** refines the legacy "rejected" for `W17c` (HFR's own "vous devez être enregistré" sentence). `message` is kept.
3. **Delete anchor**: legacy reads `numreponse` from the request URL; the classifier reports only what the page says (nil).
4. **Anchor without `#`** (legacy `"#t1003"`, `""` when none): `HopResponse.refreshAnchor` has no `#` (LOT-012 decision 3).
5. **Message**: legacy `contents` of the node (first text child); live concatenates link text ("… Retour à la page précédente", quirk 12). Here the block's own text, which equals legacy on every capture and drops the link text.
6. **Refresh plus a `.hop` link** is `rejected` (legacy rule; the live Swift service said success, audit B4).
7. `refreshURL` has `&amp;` decoded (live kept it, quirk 6).

## Pending capture
Reported to the orchestrator for the capture backlog in `docs/LOTS.md` (this lot does not edit it). None blocks the lot; until captured, each state is classified conservatively.
- **Alert already sent** (`modo.php` GET on a message the account already reported): the page text and whether the shape is really `.hop` + link/input. `alreadyAlerted` rests on the legacy rule alone.
- **Alert submitted, success**: text and whether a refresh is present. Until captured, the alert write cannot be classified `success` by this parser (a `.hop` without refresh is `unrecognized`).
- **Logged-out variants of other writes** (flag GET, alert, vote): `loggedOut` is detected only by the `W17c` sentence; a login-form page (legacy `isLoggedOutForm`) is not interpreted.
- **Poll vote answer** (LOT-054) and **topic/MP create, edit with a ban or locked topic**: any other refusal sentence is `rejected` by shape, but unverified.

## Learnings
To copy into AGENTS.md §11 when the lot closes.
- A write answer is `success` only with both HFR's refresh and a sentence; the legacy "no `.hop` means success" turned a 99-byte refusal into a success.
