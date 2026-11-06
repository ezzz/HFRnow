# LOT-058 — MP actions: mark unread, MP quote, group members

- **Module:** HFRClient (plus the mark-unread link in HFRParsing's topic page metadata; the group roster is read from the form LOT-036 parses)
- **Difficulty / model:** easy (the plan routes Sonnet → Opus; written by an Opus contributor, `ext/bybifok-opus-1`, and taken over by `ext/francoisgn-opus-1` in #484, so the self-spawned reviewer is Fable)
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
| none | group MP members: legacy has no roster; its composer sends every input it finds, so a reply from the owner's form sent `newdest` as served (LOT-004 rules, `R123c` oracle `post.pairs`) |

## Behaviour

### Mark unread

- **Link** (`TopicPageMetadata.markUnreadURL`, LOT-033's parser). The first header link (`a.cHeader`) whose path, made absolute on the forum origin, is exactly `/user/nonlu.php` (`RA1`-`RA4`: `/user/nonlu.php?config=hfr.inc&cat=prive&subcat=0&post=3207033&page=1&p=1&sondage=0&owntopic=0&new=0`). It is read from the page, not built from `W18`'s URL template, because the meaning of its `page` parameter is not captured.
  - A link a member posted in a message (`a.cLink`), one on another host, port or scheme, or another path gives nil.
  - The recipient's view carries the same link (`RU1`, `RU2`). Topic pages (`R20`, `R21`) and a deleted conversation (`RA5`) have none.
  - `isUnreadable` is unchanged: legacy's rule (any `href` containing `nonlu`, a member's posted link included), kept for the LOT-003 oracles. The app keys the action on `markUnreadURL` only.
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

Captures of #336 (PR #480, `R123a`-`R123f`, oracles in `Fixtures/M2-writes/`). The roster is **read**; the edits of the owner's reply are captured (#507, `W71`-`W78`, `R124`-`R140`, [HFR-PROTOCOL](../HFR-PROTOCOL.md) §6c "M2 write captures"), so changing it is no longer pending capture: the app does not offer it yet.

- **Owner** (`PostingForm.groupMembers`): the `newdest` input of the reply composer (`R123c`, "user3, user2"): the members other than the owner, split on the comma and trimmed, blanks dropped (the form joins with ", ", the list row with ","). Nil when the form has no `newdest`: a member who does not own the group (`R123e`), a one-to-one composer (`R47b`, `R47u1`). It lives on `PostingForm` (HFRClient), so the composer that posts the reply is the one that shows the roster, and no `HFRModels` public type changes.
- **Member**: no page but the MP list shows the roster (thread pages `R123b`, `R123d` and the member's composer `R123e` have none): `PrivateMessageThread.interlocutors` of LOT-023, owner first (`R123a`, `R123f`: "user1, user2,user3"). The owner's roster plus the owner names the same members.
- **Reply**: `PostingFlow.reply` from the owner's composer sends `newdest` back as served, at its place in the form (after `pseudo`), as legacy did; the member's composer sends none. The reply's answer is LOT-048's (`Votre réponse a été postée avec succès !` on a one-to-one thread, `W11`); a group reply's answer is not captured, so it is read by the same rule and nothing more is claimed.
- **Not offered yet** (captured, #507): HFR's behaviour is now known and a follow-up can offer it. An edited `newdest` in the owner's reply adds or removes the members (ordinary success answer, a "Modération" system post "a été ajouté / retiré de la conversation" after the reply: `W74`, `W75`, `R129`, `R133`); an unknown pseudo is refused and posts nothing (`W76`); an empty `newdest` is accepted as "no change" (`W77`); a non-owner's `newdest` is ignored (`W78`). The edit must not leave one other member: the composer then has no `newdest` and nobody can be added back (`W72`, `R124`). No API takes a new roster yet; `PostingFlow` has no override for `newdest`.
- redface2 E8's "non-owners see the roster as read-only text in `th.repCase1`" does not hold (`R123e`, HFR-PROTOCOL §6c "M2 write captures").

## Edge cases

- Duplicate parameters (`cat=prive&…&cat=13`), `post=0`, no `config`, another path, host, port or scheme: `invalidLink`, nothing sent.
- A session never logged in: `sessionNotConfirmed(.expired(.noIdentityCookie))`, nothing sent (the LOT-051 gate tests now cover the four writes).

## Fixtures

Captures only, nothing new. Group roster: `R123a`, `R123c`, `R123e`, `R123f` and their legacy oracles (`Fixtures/M2-writes/`, `form` and `mp` kinds, now in the LOT-036 form and LOT-023 list differential tests). Mark unread and quote: `RA1`-`RA5`, `RU1`, `RU2`, `R20`, `R21` (link); `W18` (answer), `R13b` (list after it), `P03a`, `P03d`, `W15`, `W17b`, `W17c` (other answers); `R47a` and its LOT-004 oracle (MP quote). The link rule's origin cases are small fragments.

## Tests

- `MarkUnreadLinkTests` (HFRParsing): the link on `RA1`-`RA4` and `RU1`-`RU2`; none on `R20`, `R21` or `RA5`; message links, other origins and other paths refused.
- `MarkUnreadTests`: `RA1`'s link is `W18`'s request, and `W18` confirms it after one GET with redirects not followed; `R13b` shows the conversation unread; other confirmations, a refusal, a logged-out page and a transport failure; eight refused links; the flag writes still refuse private links; the session gate.
- `FlagSessionGateTests`: the gated and confirmed cases now include `markUnread` (answer `W18`).
- `GroupMembersTests`: `R123c`'s roster in the form's order; none on `R123e`, `R47b`, `R47u1`; the roster plus the owner equals `R123a`'s row; separators (", ", ",", blanks) on an edited `R123c`; a reply from `R123c` sends `newdest` unchanged between `pseudo` and `password`, from `R123e` none (no answer scripted: only the body is checked).
- `HopFormOracleTests`, `PostingBodyOracleTests` and `PrivateMessageListParserTests` now also run `R123c`, `R123e`, `R123k` (forms) and `R123a`, `R123f` (lists) against their oracles; `HopFormParserTests.groupComposers` and `PrivateMessageListParserTests.groupThreadRoster` read the raw facts.
- `MPQuoteTests`: every quote link of `RA1`-`RA4` passes the loader's check; `RA4`'s link to message 1980875030 is `R47a`'s request, and its prefill equals the oracle; an off-forum link is refused before any request.

Group roster, shown to fail with the behaviour removed (3 mutations, each caught): no roster read, a split on ", " only, `newdest` left out of the body.

Mark unread, shown to fail with the behaviour removed (9 mutations, each caught): any `nonlu` link taken (legacy), the path matched by prefix, no forum-origin check, `cat=prive` accepted by every write, a forum category accepted by the unread write, a wrong link path, a wrong sentence, no session check, redirects followed.

## Pending capture

- `nonlu.php` answered without a session, and sent twice (capture issue [#137](https://github.com/ezzz/HFRnow/issues/137)); until then the session is checked first.
- Changing a group's members (#507): captured, see above. Still pending: several members changed in one POST, an unknown pseudo at creation, the roster order rule.
- A multi-page conversation's mark-unread link (whether its `page` follows the page shown).

## Intentional differences from legacy

1. **The answer is read**: only HFR's own sentence is a success (legacy took any answer with a body, `:1250-1272`). [CHANGELOG-LEGACY](../CHANGELOG-LEGACY.md) row 68.
2. **The link is the header's, on the forum origin** (legacy took the first `href` containing `nonlu`, a member's link included, `:1571-1574`). Row 68.
3. **The session is checked before the write**, as for the flags (#314).
4. **The group roster is shown** to its owner (legacy never read `newdest`, it only sent it back); not a legacy fix, no CHANGELOG-LEGACY row.

## Learnings

- A "first link containing X" rule picks member content too: read the site's own control (`a.cHeader`), never a substring of any `href`.
