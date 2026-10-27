# LOT-031 — Per-message action links

- **Module:** HFRParsing
- **Difficulty / model:** medium (Opus → Fable)
- **Issue:** none (lot tracked in `docs/LOTS.md`; old [francoisgn/ios-app_SwiftHFR#65](https://github.com/francoisgn/ios-app_SwiftHFR/issues/65); audit item C04 in [C](../audit/C-message-parsing.md))

Chain: LOT-030 (message blocks) → **LOT-031** → LOT-049 (quote engine). Output type: `MessageActions` and `QuoteSelectionToken` of LOT-011.

## Legacy sources

Legacy repository <https://github.com/francoisgn/hfrnow> at `2440d79`.

| Legacy | Replaced by |
|---|---|
| `HFRswift/Wrapped/ParseMessagesOperation.m:371-372` (parent of `alt="answer"`, its `className` → `urlQuote`) | `quoteURL` |
| `:374-375` (parent of `alt="edit"`, `className` → `urlEdit`) | `editURL` |
| `:377-378` (first `href` containing `/user/modo.php` → `urlAlert`) | `alertURL` |
| `:380-381` (parent of `alt="profil"`, `href` → `urlProfil`) | `profileURL` |
| `:383-384` (first `href` containing `addflag` → `addFlagUrl`) | `favoriteURL` |
| `:386-387` (first `onclick` containing `quoter('hardwarefr'` → `quoteJS`) | `quoteSelection` |
| `:389-390` (first `href` containing `/message.php?config=hfr.inc&cat=prive&sond=&p=1&subcat=&dest=` → `MPUrl`) | `privateMessageURL` |
| `Classes/ObjCMessageActionsBuilder.m:31-47, 70-89` (decode the class when longer than 20 characters without `/` or `http`, absolute URL on the forum base) | `ObfuscatedURL.decode(classAttribute:)` then the forum-origin check |
| `HFRswift/Swift/MessagesView.swift:1852-1876` (`quoteJS` arguments: split on commas, quotes stripped; cookie `quotes<a0>-<a1>-<a2>`, id `<a3>`) | `QuoteSelectionToken` (forum, `TopicID`, `numreponse`) |

Not ported here, by design (LOT-011 decision 5, audit C 7.2 C04): `isOwnMessage` (`editURL != nil`), `canDelete` (`editURL` and not the first
post: a delete is the edit form with `delete=1`, HFR-PROTOCOL §3.1, LOT-048), `canAQ`, `canBookmark`, `canBeFavorite`, `isPrivateCategory`,
`permalinkURL` (LOT-020 helpers), `avatarImagePath` (LOT-030 `avatarURL`), `authorName`/`postID`/`topic*` (on `Message` and `TopicPage`).
The topic's own flag state (`delflag.php` header link, `flagn0.gif`) is page-level, not per message, and LOT-033 decision 5 leaves it out.

## Behaviour

### API

| Type | Member | Rules |
|---|---|---|
| `MessageActionsParser` (public) | `actions(in: String) throws(ParsingError) -> [MessageActions]` | One action set per message block, in the order and number of `MessageBlockParser.blocks(in:)` (advertisements skipped); a page without block gives `[]`; block errors are LOT-030's |
| `MessageActionsParser` (internal) | `actions(of: ExtractedMessageBlock) -> MessageActions` | For the `TopicPage` builder working on the same `Document` |

### Fields

Every lookup runs over the elements of the block's `div.toolbar`, in document order, first match wins; a block without toolbar, or whose
first `div.toolbar` sits inside the message content (member markup, not HFR's), gives `MessageActions()`. Every URL goes through the forum-origin check: `HFRURL.forumRelativePath` (an `https` `forum.hardware.fr` URL without
user info nor a port other than 443, or a single-`/` path; `http://forum.hardware.fr/` without port is upgraded), then made absolute on
`https://forum.hardware.fr/`. Anything else gives nil: these links are requested with the account session, and `favoriteURL` is a
state-changing GET (LESSONS 37, 43).

| Field | Rule |
|---|---|
| `quoteURL` | Parent of the first `img` whose whole `alt` is `answer` (not `answer +`); its `class` decoded by `ObfuscatedURL.decode(classAttribute:)`; a class that does not decode but holds a `/` is a link in clear (legacy rule); any other class gives nil; the URL path must be `/message.php` |
| `editURL` | Same with `alt="edit"`, path `/message.php` |
| `alertURL` | First `href` whose URL path is exactly `/user/modo.php` and whose `numreponse` is the block's own |
| `profileURL` | `href` of the parent of the first `img` with `alt="profil"`, kept when its path is `/hfr/profil-<digits>.htm` |
| `privateMessageURL` | First `href` whose URL path is exactly `/message.php`, whose `cat` is `prive` and whose `dest` is non-empty |
| `favoriteURL` | First `href` whose URL path is exactly `/user/addflag.php` and whose `numreponse` is the block's own |
| `quoteSelection` | First `onclick` containing `quoter('hardwarefr'`, read as `quoter(<forum>, <cat>, <post>, <numreponse>[, …])` (the first four of four or more arguments, as legacy), each argument optionally quoted with `'` or `"`; `<forum>` must be `hardwarefr`; `cat` must be a `CategoryID` (`13`, `prive`), `post` and `numreponse` positive integers, and `numreponse` must be the block's own; otherwise nil |

## Edge cases

Checked on the captures (facts in HFR-PROTOCOL §6c "LOT-031"):

- Logged out (`R20`, `R22a`, `R22b`, `R23`, `R24`, `R26`–`R28`, `R31`, `R32a`): quote and profile only.
- Logged in on a public topic (`R21`, `R32b`): quote, multi-quote, profile, MP, favourite, alert on every post (none of them the viewer's).
- Private conversations (`RA1`–`RA4`, `RU1`, `RU2`): edit on the viewer's own posts only, MP on the other account's posts, multi-quote with
  `cat=prive`, no favourite, no alert.
- A post without profile link (`R22a`, 3 posts of one member): quote link only.
- The continuation block of pages 2+ carries the same toolbar as any post (its quote link has `ref=0`).
- The header's `delflag.php` link and the topic-level `modo.php?…&ref=0` link sit outside the blocks and are never taken (`R21`).
- `RA5` (deleted conversation) and `R04` (list page): no block, `[]`.
- Inline tests (no page state involved, attacks and forms no capture shows): links posted in the message body, off-origin links
  (`https://evil.example`, `//host`, `http://forum.hardware.fr:80`, user info, `javascript:`, `/\host`), an obfuscated link decoding off the
  forum, an undecodable payload, a link in clear in the class, a reordered MP query, a `quoter` call for another message or forum,
  parameter values naming another action's path (four one-change derivations of `R21`), wrong paths or `numreponse`,
  and a page derived from `R21` (one change: a block's toolbar moved into its content, labelled derived in the test).

**Pending capture** (implemented from legacy code, positive test on inline blocks only):

- The viewer's own post on a **public** topic: the edit link shape there and which other links (MP, favourite, alert) remain. Every edit
  link of the corpus is in a private conversation.
- A quote or edit link printed in clear instead of `md_noclass_cryptlink`. Legacy, like this parser, reads only the wrapper's `class`, so
  only a path in clear **in the class** is supported (inline test); a wrapper `<a href>` without obfuscated class gives nil in both and
  would need a capture before being read.

## Fixtures

The captures (`Fixtures/captures/`, LOT-001) and the LOT-003 oracles (`Fixtures/LOT-003/`), read in place through `oracle-map.json`;
no new fixture.

### Oracle coverage (ADR 0004)

`MessageActionsOracleTests` compares, for the 20 topic oracles (358 messages, `exception: null` everywhere), message by message:

| Oracle field (`result.actions[]`) | Compared with | Note |
|---|---|---|
| count, `index` | `actions(in:)` count and order | one entry per message |
| `quoteURL`, `editURL`, `alertURL`, `profileURL`, `privateMessageURL`, `favoriteURL` | the same `MessageActions` field, `absoluteString` | equal on every message; absent key ⇔ nil |
| `quoteJS` | `quoteSelection` | both turned into the cookie name and id legacy used (`quotes<a0>-<a1>-<a2>` and `<a3>`, `MessagesView.swift:1852-1876`) |

`corpusCoversEveryAction` checks that every action appears at least once in the oracles, so no comparison is vacuous.
Not compared (policy, LOT-011 decision 5): `isOwnMessage`, `canDelete`, `canAQ`, `canBookmark`, `canBeFavorite`, `isPrivateCategory`,
`permalinkURL`, `avatarImagePath`, `authorName`, `postID`, `topicID`, `topicCategory`, `topicTitle`.

## Intentional differences from legacy

1. **Toolbar only.** Legacy searched the whole message row (`firstChild` of the table, content included); a link posted in a message
   (`addflag.php`, `modo.php`, an image with `alt="edit"`) became an action when the toolbar lacked it, and the app would follow it with
   the session. A `div.toolbar` inside the content is refused for the same reason. Identical on all 358 messages.
2. **Forum origin only.** Legacy made any link absolute, whatever its host. Off-origin links give nil (LESSONS 37, 43).
3. **No URL from a class name.** Legacy turned an undecodable class into `https://forum.hardware.fr/<class>`; it gives nil
   (`ObfuscatedURL` already refuses a prefixed class that fails to decode, LOT-020).
4. **MP link by its parameters**, not by the literal prefix `/message.php?config=hfr.inc&cat=prive&sond=&p=1&subcat=&dest=`: a reordered
   query is still found; the multi-quote `href` of an MP thread (`cat=prive`, no `dest`) is still not.
   More generally, **every action is recognised by its exact path and required parameters**, never by a substring of the whole URL
   (legacy: `href` containing `/user/modo.php`, `addflag`, the MP prefix): a pseudo in `dest=` or any parameter value naming another
   action's path (`dest=x/user/addflag.php…`) would otherwise turn the MP link into the favourite or alert action. Alert and favourite
   links must name the block's own `numreponse` (true on every capture). Tested on one-change derivations of `R21` (labelled derived).
5. **Typed multi-quote token.** `quoteJS` (a JavaScript string the app parsed at tap time) becomes `QuoteSelectionToken`; a call whose
   `numreponse` is not the block's own, or whose first argument is not `hardwarefr`, gives nil, so a token can only select its own
   message. Arguments must be names or digits (legacy kept any text between commas).

## Learnings

To copy into AGENTS.md §11 when the lot closes:

- Every per-message link lives in `div.toolbar`; scoping lookups to it is both the legacy result on the whole corpus and the guard
  against links members post in their messages.
