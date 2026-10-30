# LOT-126 — MP list screen

- **Module:** App
- **Difficulty / model:** medium (Sonnet → Opus)
- **Issue:** [#217](https://github.com/ezzz/HFRnow/issues/217)

## Legacy sources
Legacy repository <https://github.com/francoisgn/hfrnow> at `2440d79`, and `master` of ezzz/HFRnow for the Swift files.

| Legacy | Replaced by |
|---|---|
| `HFRswift/Swift/MPListView.swift:12-36` (`MPTopicReadState`: unread = `[non lu]` prefix or `!isViewed`) | `MessageListModel.isUnread(_:)` over `PrivateMessageThread.isUnread` (LOT-023, D3) |
| `MPListView.swift:777-800` (`MPRowView`: title without the marker, interlocutor or "Interlocuteurs multiples", "author - date") | `MessageRowView` |
| `MPListView.swift:853-940` (`MPAvatarView`, `MPAvatarImageStore`: cached avatar by pseudo, default and group images) | `MessageAvatarView` (LOT-066 `AvatarCache`) |
| `Classes/ObjCMPTopicsLoaderWorker.m:9-21` (page 1 only) | `MessageListModel` paging over `PageFetcher.privateMessages(page:)` (LOT-045) |
| `Classes/HFRMPViewController.m:225-265` (`didSelectRowAtIndexPath`, line 254-255: a tap opens `aURLOfLastPost`, the `sujetCase9` link, `…&page=<last>…#bas`; the long-press menu offers "Dernière page" `:323-330` and "Première page" `:333-340`) | `MessageListModel.reader(for:)` opens `lastPost.path`, else the row's own link (LOT-023 `lastPost` is that `sujetCase9` link) |
| `Classes/ObjCTopicListParser.m:337,417-418,453-461` (MP rows: `sujetCase5` flag link, `aURLOfLastPost` = `sujetCase9` href, `aURLOfLastPage` = `sujetCase4` href) | LOT-023 `TopicSummary.flagPath` / `lastPost` / `lastPagePath` |
| `MPListView.swift` toolbar (refresh, account menu, delete and "marquer non lu" context menu) | refresh by pull and on appear; the account menu is LOT-170's; delete and mark unread are LOT-127 |

## Behaviour
Entry point: `MessagesRootView(model:environment:)`, the Messages tab of the LOT-170 root (#303): a `NavigationSplitView` of the list and the reader (collapses to a stack on iPhone). On the regular-width iPad sidebar the same `RootModel.messages` model feeds `MessagesListColumn` (content column) and `MessageReaderColumn` (detail column, like Favoris), so a size-class change keeps the page and the open conversation. The reader gets **no reply composer** (`composer: nil` at both call sites, no "Répondre"): an MP reply is a state-changing flow, out of scope here and LOT-128's (`RA1`-`RA5` carry a `message.php?cat=prive` answer link, but the refresh after posting on a `cat=prive` thread is not captured). The view layer has no seam a unit test can read, so this is reviewed in the diff, not tested. The tab badge stays LOT-170's (home page count).

| Piece | Rule |
|---|---|
| `PrivateMessageSource` / `LivePrivateMessageSource` | `PageFetcher.privateMessages(page:)` with the account session, then `PrivateMessageListParser.parse`; transport and parser failures become `ListLoadError`. No thread page is fetched, so nothing is marked read by listing |
| `MessageListModel` | `@Observable @MainActor`; `ContentLoader` rules shared with the topic lists (one load at a time, rows kept while reloading and after a failure, a superseded load is dropped); `onAppear` loads page 1 the first time, then reloads the page on screen (reading elsewhere changes the unread state); next / previous / first page; `retry` asks for the last page asked for |
| Logged out | `isLoggedIn` false: **no request**, content is the empty list with `.signInRequired(nil)`, shown as "Connexion requise". The MP list logged out was never captured (#121), so nothing is inferred from what HFR would answer |
| Rows | `PrivateMessageThread` as parsed: `isGroup` and per-row unread state stay available, so LOT-171 splits and counts without refetching |
| Unread | HFR's own state (icon) until the reader has fetched the thread's **last** page: `markOpened(_:page:of:)` shows the row read only when `page >= pageCount`, so opening or paging through an earlier page of a long unread thread leaves it unread. A failed or abandoned load leaves it unread. It is a local display state: a load brings HFR's own state back, but only for threads opened **before** that load started (each opened thread keeps the number of the newest load at its opening), so a thread opened while a reload runs is not shown unread again when the older answer lands. A failed or superseded load changes nothing. Leaving the conversation drops its reader, so opening it again refetches |
| Opening | `model.reader(for:)` builds a `TopicReaderModel` once per selection from the row's latest-message link (`lastPost.path`, page = the thread's last page, as legacy `HFRMPViewController.m:255`), else from `ReaderTarget(opening:)` (a `cat=prive` topic link, page 1). MP rows have no flag link (`sujetCase5` is `&nbsp;` on every `R13u1` row), so there is no resume position: the last page is the only way to reach new messages (`R13u1` has threads of 457, 164, 58, 6 and 2 pages). Legacy's group-thread resume through `MPStorage` (`:231-250`, setting `mpstorage_active`) is out of scope: no capture, no port |
| Session refused | `.notAuthenticated` from HFR while the cookie is still there closes the open conversation (`selected = nil`) like an expired session; the rows stay |
| Avatar | a read of `AvatarCache` by the interlocutor pseudo; generic icon when absent, group icon for a group. Nothing downloads an avatar here: the list rows carry no avatar link (pending capture below) |
| Badge | the unread count of the Messages tab is the home page count (`ForumListPage.unreadPrivateMessages`, LOT-023 `PrivateMessageBadgeParser`), wired by LOT-170; `MessageListContent.unreadCount` is page-bounded, kept as the per-row state LOT-171 (mailbox counts) can reuse and covered by `rowsKeepGroupFlagAndUnreadStateForTheNextLot`; the model has no count of its own (the rows read `isUnread(_:)`) |

## Edge cases
- Empty mailbox: "Aucun message privé" (R13c).
- A one-page thread: the latest-message link names page 1, so the row is read as soon as that page is shown.
- A row without a latest-message link opens its title link (page 1).
- A row whose link names no thread opens nothing (`reader(for:)` nil, "Choisissez une conversation").
- Failure with rows on screen: banner, rows kept; without rows: full-screen failure with "Réessayer".
- A page past the last one: not captured (#114); the pager only offers "next" when a next link exists.

## Fixtures
Existing captures only; none added. `LivePrivateMessageSourceTests` runs `LivePrivateMessageSource` over `R13u1` (group rows, unread rows, every row openable) and `R04` (a list of another category is `.unreadable`, never shown as messages); the parser itself is oracle-tested in LOT-023.

**Pending capture** (none hand-built): #114 page past the last page; #115 interlocutor deleted or banned; MP list logged out (#121); #117 header badge N > 1; #118 ignore icon `ignore1.gif`; #119 pseudos with a comma; the interlocutor's avatar link for a list row (none in the list page: avatars come from thread pages or profiles); an MP thread of another member and a group thread opened in the reader (`RA1`-`RA5` exist, all of the owner's own account or its own threads); **what HFR does to a thread's unread state when its page is fetched** (whether the fetch marks it read, and from which page): no capture compares an MP list before and after a thread page was opened, so the row is shown read only locally (last page loaded) and HFR's own state is read back from the next list. `RA1` (an MP thread page) does render through `LiveTopicPageSource.parse` (`anMPThreadPageRendersThroughTheReaderParser`).

## Intentional differences from legacy
| # | Legacy | Port | Why |
|---|---|---|---|
| D1 | page 1 only (`ObjCMPTopicsLoaderWorker.m:9-21`) | paged | R13u1 has 7 pages |
| D2 | unread = `[non lu]` prefix or icon | the member's icon state only | the marker is the other party's state (LOT-023 D3) |
| D3 | group detected by the text "multiples" | `PrivateMessageThread.isGroup` | LOT-023 D4 |
| D4 | no "login required" state | "Connexion requise" without a request | acceptance criterion of #217 |

## Learnings
- A screen over a parser that can say "not logged in" should not depend on HFR's answer to a page that was never captured: check the session first.
