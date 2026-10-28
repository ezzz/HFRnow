# LOT-023 — MP list specifics and unread badge

- **Module:** HFRParsing (two small HFRModels types)
- **Difficulty / model:** easy (Sonnet → Opus)
- **Issue:** [#51](https://github.com/ezzz/HFRnow/issues/51) (audit items B6 in [B](../audit/B-list-parsing-models.md) and NET-13 in [A](../audit/A-network-sessions.md); old issue francoisgn/ios-app_SwiftHFR#63)

## Legacy sources
Legacy repository <https://github.com/francoisgn/hfrnow>, commit `2440d79`.

| Legacy | Replaced by |
|---|---|
| `Classes/ObjCMPTopicsLoaderWorker.m:9-21` (fixed URL `/forum1.php?config=hfr.inc&cat=prive&page=1`, nav fields reset: page 1 only) | `PrivateMessageListParser` (the URL is `HFRClient`'s, LOT-045; the pager is kept) |
| `Classes/ObjCTopicListParser.m:59-470` (the MP list is the topic list on `cat=prive`) | `TopicListParser.parseRows` (LOT-022), reused |
| `HFRswift/Swift/MPListView.swift:12-36` (`MPTopicReadState.isUnread` = `[non lu]` title prefix **or** `!isViewed`); group = "multiples" at `:377`, `:773`, `:894` | `PrivateMessageThread.isUnread`, `.unreadBy`, `.isGroup` |
| `Classes/ObjCForumsParser.m:516-525` (home `cat=prive` row, replace-all regex) | `PrivateMessageBadgeParser.countOnHomePage` |
| `Classes/HFRplusAppDelegate.m:242` (a fourth reader: `findChildOfClass:@"cCatTopic red"`, same regex) | `PrivateMessageBadgeParser.unreadCount(in:)` |
| `Classes/ObjCTopicListParser.m:83-92` (header `.none` block with 3 `td`) | `PrivateMessageBadgeParser.countInListHeader` |
| `HFRswift/Swift/MPBackgroundService.swift:115-139` (`class="cCatTopic red"`, first integer) | `PrivateMessageBadgeParser.unreadCount(in:)`, which LOT-047 calls |

## Behaviour
### `PrivateMessageListParser.parse(_:pageURL:) throws(ListPageFailure) -> PrivateMessageListPage`
Pure. One page of the MP list: the rows are `TopicListParser`'s (title path, replies, pages, last post, `topicID` with `.privateMessages`), the pager and
the new-message link too; this adds the MP-only facts.

| Output | Rule |
|---|---|
| `threads[].summary` | the `TopicSummary` of the row with the `[non lu]` marker removed from `title` (the marker is `span.red` in `sujetCase3`; the text after it, trimmed) |
| `isUnread` | the member's own state: `summary.readState == .unread`, i.e. `sujetCase1` icon `closedbp.gif`, `alt="On"` ("Nouveau message"); `closedp.gif` `alt="Off"` is read (R13a, R13b, R13u1) |
| `isUnreadByOthers`, `unreadBy` | `[non lu]` is the **other party** not having read (HFR-PROTOCOL §6b, B8): `span.red` present; `unreadBy` = pseudos after the colon of its `title` ("Ce message n'a pas été lu par : a, b"), split on `,`, trimmed |
| `isGroup`, `interlocutors` | `sujetCase6` with a profile link: one interlocutor (its text); without one, a `span` **with a `title`** ("Interlocuteurs multiples") is a group and its `title` lists the others; a span without `title` is not (the starter text is the one interlocutor) (split like `unreadBy`). Pseudos are as served (U+200B kept) |
| `unreadThreadCount` (page) | threads of **this page** with `isUnread`; not the mailbox total (use the badge) |
| `navigation`, `newMessagePath` | `TopicListPage.navigation` / `.newTopicPath` (R13u1: 7 pages; R13c, R13a: one) |

Failures: `.notAuthenticated(message)` for a `.hop` message page, whatever the URL (an empty mailbox keeps the list body, R13c, so a message page can
only be the login wall); `.maintenance` and `.malformed` as `TopicListParser`; `.malformed` when the page is a list whose category is not `prive`.
**For LOT-038/047 (walking the pager):** a thread deleted mid-walk may leave `page=N` past the last page, and HFR's answer there was never captured; if it is a `.hop` page, the parser reports `.notAuthenticated` for a logged-in member. A `.notAuthenticated` on a page after the first must be confirmed (re-read page 1) before the session is cleared.

### `PrivateMessageBadgeParser.unreadCount(in:) throws(ListPageFailure) -> Int?`
The one reader of the three legacy variants. The page kind comes from `<body id>`:

| Page | Rule | Result |
|---|---|---|
| home (`unique__home__listing_category`) | `a.cCatTopic` whose `href` has `cat=prive`: first integer of its text | R02 "Vous avez 10 nouveaux messages privés" → 10; R03 "Envoyer / lire des messages privés" → 0; R01 (logged out, no row) → nil |
| logged-in forum list (`…__topics_listing__…`) | first `table.none` with exactly 3 `td` (one of another shape is skipped, unlike legacy, which stopped at the first `.none`): first integer of the middle cell | P03f "Vous avez 1 nouveau message privé" → 1; R08-2 "Messages privés" → 0; anonymous lists, the MP list, search results → nil |
| anything else (message page, topic page) | none | nil |

`nil` = the page shows no private messages entry (logged out, or not a page that has one); `0` = it shows the entry without a number. A poll (LOT-047)
treats nil as "no information", never as 0. A maintenance page throws `.maintenance`, an unreadable document `.malformed`. `ForumListParser` and
`TopicListParser` now call the same helpers (`count(inText:)`, `countInListHeader`), so the rule lives once.

## Edge cases
- Own unread and the others' `[non lu]` are independent: R13u1 has rows read by the member but marked `[non lu]` and the reverse.
- Marking a thread unread (W18, R13b) flips `isUnread`, not the marker.
- A `span` without `title` in `sujetCase6` is not a group (a deleted or banned interlocutor may print one; unverified, pending). Tested on a capture row with its tooltip removed, a derived variation, not a capture.
- `isUnreadByOthers` is computed from the marker and `unreadBy`, so it cannot disagree with them.
- The count is of conversations (R02: 10 = the 10 `closedbp` rows, but page-bounded; the badge is the total).
- Whether a pseudo can hold a comma is **unknown** (no source for HFR's pseudo rules); if it can, `unreadBy`/`interlocutors` split it (HFR joins with `, ` or `,`; no captured pseudo has one).

## Fixtures
Existing captures and LOT-002 oracles (`Fixtures/captures`, `Fixtures/LOT-002`); none added.

| Capture | Covers |
|---|---|
| R13a, R13b | one-to-one thread, `[non lu]` tooltip, read then unread after "mark unread" |
| R13c | empty mailbox |
| R13u1, R13u1b | 50 rows, group threads (34 pseudos in the tooltip), read/unread combinations, 7-page pager; R13u1b after the owner deleted the thread |
| R02, R03, R01 | home with 10 unread, with none, logged out |
| P03f, R08-2, R04, R50b, R08-1, R20 | header badge 1, 0, none (anonymous, search, message page, topic page) |

**Oracle coverage:** the 5 MP oracles are compared row by row (`PrivateMessageListParserTests.matchesOracle`); the badge is compared with
`sideEffects.nbMP` (R01-R03) and, on the 18 list cases, with `needToUpdateMP`/`sNewMPNumber` (`PrivateMessageBadgeParserTests`). Tooltip names are
checked against regexes over the raw rows, independent of SwiftSoup (LESSONS 33).

**Pending capture:** the MP list page past the last page (after a deletion mid-walk); a one-to-one thread whose interlocutor was deleted or banned (the `sujetCase6` shape); the MP list logged out (the `.notAuthenticated` rule is checked on another list's `.hop` page); the header badge with N > 1 ("Vous avez N
nouveaux messages privés" in `table.none`; the plural is captured on the home page only, so the digit rule is what is tested); a mailbox whose rows hold a
closed-for-the-member thread or the ignore icon in another state (`ignore1.gif`); pseudos containing a comma; the badge on a page of another section (a topic
page logged in: R20 is anonymous). None is hand-built.

## Intentional differences from legacy
| # | Legacy | Port | Why |
|---|---|---|---|
| D1 | the `[non lu]` marker stays in `aTitle` | removed from `summary.title`, kept as `isUnreadByOthers`/`unreadBy` | typed fact; `MPListView` stripped it by prefix |
| D2 | `MPBackgroundService` found no `cCatTopic red` when nothing is unread and returned nil, same as a failure; the home reader wrote 0 | `0` for "entry without a number", `nil` for "no entry" | audit A §9 Q7: a poll must tell "none unread" from "not logged in" |
| D3 | `isUnread` = `[non lu]` prefix **or** `!isViewed` (`MPListView.swift:12-22`) | two facts: own (`isUnread`, icon) and others' (`unreadBy`) | R13u1 shows they differ (read rows marked `[non lu]`); the prefix means the *other* party (§6b) |
| D4 | group = `aAuthorOrInter` contains "multiples" | no profile link and a `span`; names from its tooltip | no display string test; the names are on the page |
| D5 | MP list = page 1 only, navigation reset | the pager is parsed | R13u1 has 7 pages; LOT-038/047 scan them |
| D6 | three readers (`ObjCForumsParser`, `ObjCTopicListParser`, `MPBackgroundService`), regexes needing text on both sides | one rule: first integer, 0 without | audit B §3.3.6 |
| D7 | a `.hop` page on the MP list was swallowed by the generic loader (audit B finding 12) | `.notAuthenticated` | typed failure |

## Learnings
To copy into AGENTS.md §11 when the lot closes:

- HFR's `[non lu]` on the MP list means the others have not read; the member's own unread state is the icon. Legacy `MPListView` mixed both.
- The unread count is one rule on two pages (home row, forum-list header): keep nil for "no entry" and 0 for "entry without a number" so a poll cannot read a logged-out page as an empty mailbox.
