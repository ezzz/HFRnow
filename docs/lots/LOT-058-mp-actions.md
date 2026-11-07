# LOT-058 — MP actions: mark unread, MP quote, group members

- **Module:** HFRClient (plus the mark-unread link in HFRParsing's topic page metadata; the group roster is read from the form LOT-036 parses and changed through LOT-048's reply)
- **Difficulty / model:** easy (the plan routes Sonnet → Opus; written by an Opus contributor, `ext/bybifok-opus-1`, taken over by `ext/francoisgn-opus-1` in #484, continued by `ext/francoisgn-opus-4` in #508 and `mac/lot-058` for the roster change, so the self-spawned reviewer is Fable)
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
  - the session is checked first (LOT-044, #314): HFR answers this GET without a session with the "pas destiné" notice (`W137a`, `W137b`, sent twice, byte-identical, no cookie set), which carries no token and says nothing about the session;
  - then one GET of the link, redirects not followed, never retried. A failure after sending is `unconfirmed(.transport)`.
- **Confirmation**: LOT-037's success **and** the action's own sentence, "Le message a été marqué comme non lu avec succès" (`W18`, refresh to the MP list).
  - Another write's confirmation (`P03a`, `P03d`, `W15`) is `unconfirmed(.unexpectedConfirmation)`.
  - A refusal (`W17b`) is `rejected`, and a logged-out page (`W17c`) is `notLoggedIn`.
  - The MP list read afterwards shows the conversation unread (`R13b`, LOT-023's `isUnread`).

### MP quote

No new code. A conversation's quote links (LOT-031 actions of `RA1`-`RA4`, `cat=prive`) load through LOT-048's `PostingFlow.loadForm` as they are. `R47a`'s prefill `[quotemsg=<cited>,<ref>,<author id>]…` equals the LOT-004 oracle's `content_form`. LOT-049's `QuoteFlow.quote` (#348) wraps the same path for the composer.

### Group MP members

Captures of #336 (PR #480, `R123a`-`R123f`, oracles in `Fixtures/M2-writes/`). The roster is **read**, and **changed** through the owner's reply, from the captures of #507 (`W71`-`W78`, `R124`-`R140`, [HFR-PROTOCOL](../HFR-PROTOCOL.md) §6c "M2 write captures"). The engine offers the change; no screen does yet (LOT-181, #421, M5).

- **Owner** (`PostingForm.groupMembers`): the `newdest` input of the reply composer (`R123c`, "user3, user2"): the members other than the owner, split on the comma and trimmed, blanks dropped (the form joins with ", ", the list row with ","). Nil when the form has no `newdest`: a member who does not own the group (`R123e`), a one-to-one composer (`R47b`, `R47u1`), a two-person thread (`R124`); also nil on a `newdest` served empty, which no capture shows and which names no member, so the form counts as serving none. It lives on `PostingForm` (HFRClient), so the composer that posts the reply is the one that shows the roster, and no `HFRModels` public type changes.
- **Member**: no page but the MP list shows the roster (thread pages `R123b`, `R123d` and the member's composer `R123e` have none): `PrivateMessageThread.interlocutors` of LOT-023, owner first (`R123a`, `R123f`: "user1, user2,user3"). The owner's roster plus the owner names the same members.
- **Reply**: `PostingFlow.reply` from the owner's composer sends `newdest` back as served, at its place in the form (after `pseudo`), as legacy did; the member's composer sends none. The reply's answer is LOT-048's (`Votre réponse a été postée avec succès !`, on a one-to-one thread in `W11` and on a group thread in `W71` and `W72`), read by the same rule.
- **Change** (`GroupRosterFlow.changeMembers(to:text:options:with:in:)`, `GroupRosterError`, `GroupRosterChange`): HFR has no roster request, so a change is the owner's reply with `newdest` edited and **always posts its `text`** (`W74`, `W75`).
  - The list is every member but the owner, the form's `groupMembers` with the change applied. Names are trimmed, blanks and repeats dropped (without regard to case: HFR lower-cases names in the list tooltip, `R123a`, and how it compares them is not captured), then joined with ", " as the captures show. `newdest` goes at its place in the form (after `pseudo`), every other field as served; the body equals `W74`'s. HFR's order rule is not captured, so no order is promised.
  - **Refused before sending, nothing asked of HFR**:
    - `rosterNotOffered`: no `newdest` served on a private thread's reply composer (a member, a one-to-one or two-person thread, an empty `newdest`). A different `newdest` from a non-owner is pending capture and must not be tried;
    - `emptyRoster`: HFR takes an empty `newdest` as "no change" (`W77`), so an empty list cannot mean "remove everyone";
    - `invalidMemberName`: a comma ("a, b" is two members for HFR, "a" and "a," one, which would pass the count), a line break, or a character HFR cuts a text at (`W12`), since a cut `newdest` is another roster;
    - `namesOwner`: the owner in the list would count as a member kept, and HFR's answer is not captured;
    - `tooFewMembers(minimum: 2)`: with one other left the composer stops serving `newdest` and nobody can be added back (`W72`, `R124`);
    - `posting(…)`: the text is any reply's (`checkText`).
  - **Session gate**: after those, LOT-044's check (#314), as the other writes; `sessionNotConfirmed` sends nothing, a check that fails is `posting(.network)`. `PostingFlow.submit` then applies the form's own guards (`sessionChanged`, cancellation). The form must have been loaded through the session passed in.
  - **Answer**: the reply's rule, `W74` and `W75` are `PostingAction.reply`'s sentence. An unknown pseudo is `posting(.rejected(message:))` with HFR's sentence, "Désolé, le pseudo suivant n'existe pas : …" (`W76`, 200, back link, no refresh; nothing posted, roster unchanged). A POST whose exchange fails is `posting(.unconfirmed)`, never retried (LOT-048).
  - **Afterwards**: `GroupRosterChange.members` is read again from the composer's URL, never assumed from what was sent: several members at once and HFR's order are not captured. A failed reload, or a composer with no roster, gives nil: the write stands, the roster is unknown. HFR adds its own "Modération" post after the reply (`R129`, `R133`).
- redface2 E8's "non-owners see the roster as read-only text in `th.repCase1`" does not hold (`R123e`, HFR-PROTOCOL §6c "M2 write captures").

## Edge cases

- Duplicate parameters (`cat=prive&…&cat=13`), `post=0`, no `config`, another path, host, port or scheme: `invalidLink`, nothing sent.
- A session never logged in: `sessionNotConfirmed(.expired(.noIdentityCookie))`, nothing sent (the LOT-051 gate tests now cover the four writes; `GroupRosterSessionTests` the roster change).
- A roster change from a form loaded through another session: `posting(.sessionChanged)`, nothing asked.
- A new roster equal to the served one is sent: HFR treats it as a plain reply (`W71`).

## Fixtures

Captures only, nothing new. Group roster: `R123a`, `R123c`, `R123e`, `R123f` and their legacy oracles (`Fixtures/M2-writes/`, `form` and `mp` kinds, now in the LOT-036 form and LOT-023 list differential tests). Roster change: the composers `R124`, `R127`, `R128`, `R132`, `R136`-`R139` and the answers `W71`-`W78` (`W137a`, `W137b` for `nonlu.php` without a session). Aliases are per file: `R128`'s "user4, user5" are `W74`'s "user3, user4", so a roster is compared across captures by size only. Mark unread and quote: `RA1`-`RA5`, `RU1`, `RU2`, `R20`, `R21` (link); `W18` (answer), `R13b` (list after it), `P03a`, `P03d`, `W15`, `W17b`, `W17c` (other answers); `R47a` and its LOT-004 oracle (MP quote). The link rule's origin cases are small fragments.

## Tests

- `MarkUnreadLinkTests` (HFRParsing): the link on `RA1`-`RA4` and `RU1`-`RU2`; none on `R20`, `R21` or `RA5`; message links, other origins and other paths refused.
- `MarkUnreadTests`: `RA1`'s link is `W18`'s request, and `W18` confirms it after one GET with redirects not followed; `R13b` shows the conversation unread; other confirmations, a refusal, a logged-out page and a transport failure; eight refused links; the flag writes still refuse private links; the session gate.
- `FlagSessionGateTests`: the gated and confirmed cases now include `markUnread` (answer `W18`).
- `GroupMembersTests`: `R123c`'s roster in the form's order; none on `R123e`, `R47b`, `R47u1`, nor on a `newdest` served empty; the roster plus the owner equals `R123a`'s row; separators (", ", ",", blanks) on an edited `R123c`; the size of every composer of the #507 run; a reply from `R123c` sends `newdest` unchanged between `pseudo` and `password` and `W71` confirms it, from `R123e` none.
- `GroupRosterTests` (a scripted session, so no write can reach HFR): `W74`'s body equals ours byte for byte and `R128` gives the roster; `W75` from `R128`, `newdest` between `pseudo` and `password`; names normalized; `W76`'s sentence, no reload; a transport failure is `unconfirmed`, one POST, no reload; `W15`, `W17b`, `W17c`; a failed or roster-less reload keeps the success.
- `GroupRosterGuardTests`: every refusal above, each with no POST and, except the session's own, no session check; `W72`'s roster refused on `R123c` and `R127`; repeats that fall under the minimum; the session gate; another account adopted after the form was loaded; a cancelled task.
- `GroupRosterSessionTests`: the public entry point in a loopback-only `HFRSession`: never logged in, a form of another session, HFR's check refusing and accepting (the write then stops at the loopback policy).
- `HopResponseMPRefusalTests` (HFRParsing): `W76` is `rejected` with HFR's sentence; `W137a` and `W137b` equal `R96c` and are `rejected`. `MarkUnreadTests` runs `W137a` as an answer: `rejected`, the case the gate keeps from leaving.
- `HopFormOracleTests`, `PostingBodyOracleTests` and `PrivateMessageListParserTests` now also run `R123c`, `R123e`, `R123k` and the #507 composers (forms) and `R123a`, `R123f` (lists) against their oracles, `HopResponseParserTests` `W71`, `W72`, `W74`-`W78` against their `response` oracles; `HopFormParserTests.groupComposers` and `PrivateMessageListParserTests.groupThreadRoster` read the raw facts.
- `MPQuoteTests`: every quote link of `RA1`-`RA4` passes the loader's check; `RA4`'s link to message 1980875030 is `R47a`'s request, and its prefill equals the oracle; an off-forum link is refused before any request.

Group roster, shown to fail with the behaviour removed (3 mutations, each caught): no roster read, a split on ", " only, `newdest` left out of the body.

Roster change, shown to fail with the behaviour removed (18 mutations, each caught): joined with ",", no minimum, a minimum of one, empty allowed, no `newdest` check, no session gate, no dedupe, a case-sensitive dedupe, comma, line break or non-BMP accepted, the owner accepted, `newdest` left out of the POST, no reload, a form of another session accepted, the text unchecked, a served-empty `newdest` giving `[]`, a `.hop` with a link not read as a refusal (`W76`).

Mark unread, shown to fail with the behaviour removed (9 mutations, each caught): any `nonlu` link taken (legacy), the path matched by prefix, no forum-origin check, `cat=prive` accepted by every write, a forum category accepted by the unread write, a wrong link path, a wrong sentence, no session check, redirects followed.

## Pending capture

- Group roster: several members changed in one POST, the owner naming itself, an unknown pseudo at creation, the roster order rule, a different `newdest` sent by a non-owner.
- `nonlu.php`: sent twice while logged in (#137). Without a session it is captured (`W137a`, `W137b`): the "pas destiné" refusal, `rejected` by `HopResponseParser`, and the gate keeps the write from leaving.
- A multi-page conversation's mark-unread link (whether its `page` follows the page shown).

## Intentional differences from legacy

1. **The answer is read**: only HFR's own sentence is a success (legacy took any answer with a body, `:1250-1272`). [CHANGELOG-LEGACY](../CHANGELOG-LEGACY.md) row 68.
2. **The link is the header's, on the forum origin** (legacy took the first `href` containing `nonlu`, a member's link included, `:1571-1574`). Row 68.
3. **The session is checked before the write**, as for the flags (#314).
4. **The group roster is shown** to its owner and **can be changed** (legacy never read `newdest`, it only sent it back); a new feature, not a legacy fix: no CHANGELOG-LEGACY row. A plain reply still sends `newdest` as served, as legacy did.

## Learnings

- A "first link containing X" rule picks member content too: read the site's own control (`a.cHeader`), never a substring of any `href`.
