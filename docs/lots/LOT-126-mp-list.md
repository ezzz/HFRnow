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
| `MPListView.swift` toolbar (refresh, account menu, delete and "marquer non lu" context menu) | refresh by pull and on appear; the account menu is LOT-170's; delete and mark unread are LOT-127 |

## Behaviour
Entry point: `MessagesRootView(model:environment:)`, the Messages tab of the LOT-170 root (#303): a `NavigationSplitView` of the list and the reader (collapses to a stack on iPhone). On the regular-width iPad sidebar the same `RootModel.messages` model feeds `MessagesListColumn` (content column) and `MessageReaderColumn` (detail column, like Favoris), so a size-class change keeps the page and the open conversation. The reader gets the reply composer (LOT-084, `environment.composer`); the tab badge stays LOT-170's (home page count).

| Piece | Rule |
|---|---|
| `PrivateMessageSource` / `LivePrivateMessageSource` | `PageFetcher.privateMessages(page:)` with the account session, then `PrivateMessageListParser.parse`; transport and parser failures become `ListLoadError`. No thread page is fetched, so nothing is marked read by listing |
| `MessageListModel` | `@Observable @MainActor`; `ContentLoader` rules shared with the topic lists (one load at a time, rows kept while reloading and after a failure, a superseded load is dropped); `onAppear` loads page 1 the first time, then reloads the page on screen (reading elsewhere changes the unread state); next / previous / first page; `retry` asks for the last page asked for |
| Logged out | `isLoggedIn` false: **no request**, content is the empty list with `.signInRequired(nil)`, shown as "Connexion requise". The MP list logged out was never captured (#121), so nothing is inferred from what HFR would answer |
| Rows | `PrivateMessageThread` as parsed: `isGroup` and per-row unread state stay available, so LOT-171 splits and counts without refetching |
| Unread | HFR's own state (icon) until the reader has fetched the thread's page; then `markOpened` shows it read, a failed or abandoned load leaves it unread; leaving the conversation drops its reader, so opening it again refetches; a load brings HFR's state back (opening in the reader is what marks it read on HFR) |
| Opening | `model.reader(for:)` builds a `TopicReaderModel` from `ReaderTarget(opening: thread.summary)` (a `cat=prive` topic link), once per selection |
| Avatar | a read of `AvatarCache` by the interlocutor pseudo; generic icon when absent, group icon for a group. Nothing downloads an avatar here: the list rows carry no avatar link (pending capture below) |
| Badge | the unread count of the Messages tab is the home page count (`ForumListPage.unreadPrivateMessages`, LOT-023 `PrivateMessageBadgeParser`), wired by LOT-170; this list's own `unreadCount` is page-bounded |

## Edge cases
- Empty mailbox: "Aucun message privé" (R13c).
- A row whose link names no thread opens nothing (`reader(for:)` nil, "Choisissez une conversation").
- Failure with rows on screen: banner, rows kept; without rows: full-screen failure with "Réessayer".
- A page past the last one: not captured (#114); the pager only offers "next" when a next link exists.

## Fixtures
Existing captures only; none added. `LivePrivateMessageSourceTests` runs `LivePrivateMessageSource` over `R13u1` (group rows, unread rows, every row openable) and `R04` (a list of another category is `.unreadable`, never shown as messages); the parser itself is oracle-tested in LOT-023.

**Pending capture** (none hand-built): #114 page past the last page; #115 interlocutor deleted or banned; MP list logged out (#121); #117 header badge N > 1; #118 ignore icon `ignore1.gif`; #119 pseudos with a comma; the interlocutor's avatar link for a list row (none in the list page: avatars come from thread pages or profiles); an MP thread of another member and a group thread opened in the reader (only the owner's `RA1`/`RA2` exist).

## Intentional differences from legacy
| # | Legacy | Port | Why |
|---|---|---|---|
| D1 | page 1 only (`ObjCMPTopicsLoaderWorker.m:9-21`) | paged | R13u1 has 7 pages |
| D2 | unread = `[non lu]` prefix or icon | the member's icon state only | the marker is the other party's state (LOT-023 D3) |
| D3 | group detected by the text "multiples" | `PrivateMessageThread.isGroup` | LOT-023 D4 |
| D4 | no "login required" state | "Connexion requise" without a request | acceptance criterion of #217 |

## Learnings
- A screen over a parser that can say "not logged in" should not depend on HFR's answer to a page that was never captured: check the session first.
