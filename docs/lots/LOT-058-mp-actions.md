# LOT-058 — MP actions: mark unread, MP quote, group members

- **Module:** HFRClient (plus the mark-unread link in HFRParsing's topic page metadata)
- **Difficulty / model:** easy (the plan routes Sonnet → Opus; taken by an Opus contributor, `ext/bybifok-opus-1`, so the self-spawned reviewer is Fable)
- **Issue:** [#84](https://github.com/ezzz/HFRnow/issues/84)
- **Depends on:** LOT-042 (#68): `HFRSession`; LOT-045 (#71); LOT-036 (#63); the conventions of LOT-031 (#58, quote links), LOT-048 (#74, `PostingFlow.loadForm`) and LOT-051 (#77, `TopicFlagFlow`, the session check of #314).
- **Audit:** redface2 E6, E8, E9 (`docs/research/redface2-comparison.md:294, 296, 297`).

## Legacy sources

Legacy app: `francoisgn/hfrnow` at `2440d79` (an ancestor of `origin/master`).

| Legacy | What it gives this lot |
|---|---|
| `HFRswift/Wrapped/MessagesTableViewController.m:1571-1574` | the mark-unread link: the first `href` containing `nonlu` anywhere on the conversation page |
| `MessagesTableViewController.m:1250-1272` (`markUnread`) | a GET of that link; any answer with a body is taken as done (the answer is never read), then the list is reloaded |
| `Classes/ObjCTopicPageWorker.m:158` | `unreadable` set when the page has such a link |
| `HFRswift/Wrapped/ParseMessagesOperation.m:371-372`, `HFRswift/Swift/ReplyService.swift:767-841` | the MP quote is the topic quote path: decoded quote link, then the form's `content_form` |
| none | group MP members (`newdest`): redface2 E8 only |

## Behaviour

### Mark unread

- **Link** (`TopicPageMetadata.markUnreadURL`, LOT-033's parser). The first header link (`a.cHeader`) whose path, made absolute on the forum origin, is exactly `/user/nonlu.php` (`RA1`-`RA4`: `/user/nonlu.php?config=hfr.inc&cat=prive&subcat=0&post=3207033&page=1&p=1&sondage=0&owntopic=0&new=0`). It is read from the page, not built from `W18`'s URL template, because the meaning of its `page` parameter is not captured.
  - A link a member posted in a message (`a.cLink`), one on another host, port or scheme, or another path gives nil.
  - Topic pages (`R20`, `R21`) and a deleted conversation (`RA5`) have none. `isUnreadable` is unchanged.
- **Write** (`TopicFlagFlow.markUnread(link:in:)`, a new `TopicFlagAction.markUnread`). It is LOT-051's link-write path:
  - the link must be an `https` forum page, path exactly `/user/nonlu.php`, `config=hfr.inc`, a single `cat=prive` and a single positive `post` (`FlagLink(…, privateThread: true)`). The flag writes still refuse `cat=prive`, and the unread write refuses a forum category;
  - the session is checked first (LOT-044, #314): HFR's answer to this GET without a session is not captured;
  - then one GET of the link, redirects not followed, never retried. A failure after sending is `unconfirmed(.transport)`.
- **Confirmation**: LOT-037's success **and** the action's own sentence, "Le message a été marqué comme non lu avec succès" (`W18`, refresh to the MP list).
  - Another write's confirmation (`P03a`, `P03d`, `W15`) is `unconfirmed(.unexpectedConfirmation)`.
  - A refusal (`W17b`) is `rejected`, and a logged-out page (`W17c`) is `notLoggedIn`.
  - The MP list read afterwards shows the conversation unread (`R13b`, LOT-023's `isUnread`).

### MP quote

No new code. A conversation's quote links (LOT-031 actions of `RA1`-`RA4`, `cat=prive`) load through LOT-048's `PostingFlow.loadForm` as they are. `R47a`'s prefill `[quotemsg=<cited>,<ref>,<author id>]…` equals the LOT-004 oracle's `content_form`. LOT-049's `QuoteFlow.quote` (#348) wraps the same path for the composer.

### Group MP members

Not done: no group conversation is captured (capture issue [#336](https://github.com/ezzz/HFRnow/issues/336), which needs the operator's approval for a write). The one-to-one composers have no `newdest` (`R47b`, `R47u1`, HFR-PROTOCOL §7 E8). The PR uses `Refs #84` for that reason.

## Edge cases

- Duplicate parameters (`cat=prive&…&cat=13`), `post=0`, no `config`, another path, host, port or scheme: `invalidLink`, nothing sent.
- A session never logged in: `sessionNotConfirmed(.expired(.noIdentityCookie))`, nothing sent (the LOT-051 gate tests now cover the four writes).

## Fixtures

Captures only, nothing new: `RA1`-`RA5`, `R20`, `R21` (link); `W18` (answer), `R13b` (list after it), `P03a`, `P03d`, `W15`, `W17b`, `W17c` (other answers); `R47a` and its LOT-004 oracle (MP quote). The link rule's origin cases are small fragments.

## Tests

- `MarkUnreadLinkTests` (HFRParsing): the link on `RA1`-`RA4`; none on `R20`, `R21` or `RA5`; message links, other origins and other paths refused.
- `MarkUnreadTests`: `RA1`'s link is `W18`'s request, and `W18` confirms it after one GET with redirects not followed; `R13b` shows the conversation unread; other confirmations, a refusal, a logged-out page and a transport failure; eight refused links; the flag writes still refuse private links; the session gate.
- `FlagSessionGateTests`: the gated and confirmed cases now include `markUnread` (answer `W18`).
- `MPQuoteTests`: every quote link of `RA1`-`RA4` passes the loader's check; `RA4`'s link to message 1980875030 is `R47a`'s request, and its prefill equals the oracle; an off-forum link is refused before any request.

Shown to fail with the behaviour removed (9 mutations, each caught): any `nonlu` link taken (legacy), the path matched by prefix, no forum-origin check, `cat=prive` accepted by every write, a forum category accepted by the unread write, a wrong link path, a wrong sentence, no session check, redirects followed.

## Pending capture

- `nonlu.php` answered without a session, and sent twice (capture issue [#137](https://github.com/ezzz/HFRnow/issues/137)); until then the session is checked first.
- A group conversation seen by its owner and by a member (#336).
- A multi-page conversation's mark-unread link (whether its `page` follows the page shown).

## Intentional differences from legacy

1. **The answer is read**: only HFR's own sentence is a success (legacy took any answer with a body, `:1250-1272`). [CHANGELOG-LEGACY](../CHANGELOG-LEGACY.md) row 49.
2. **The link is the header's, on the forum origin** (legacy took the first `href` containing `nonlu`, a member's link included, `:1571-1574`). Row 49.
3. **The session is checked before the write**, as for the flags (#314).

## Learnings

- A "first link containing X" rule picks member content too: read the site's own control (`a.cHeader`), never a substring of any `href`.
