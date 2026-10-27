# LOT-082 — Adaptive navigation

- **Module:** App (`App/SwiftHFR/Navigation/`)
- **Difficulty / model:** medium (Sonnet 5.5 → Opus 5.5)
- **Issue:** none (tracked in [LOTS.md](../LOTS.md)); old francoisgn/ios-app_SwiftHFR#96
- **Depends on:** LOT-080 (target), LOT-021, 022, 024 (parsers), LOT-045 (fetchers)

## Legacy sources
Read-only: the legacy forum, topic-list and favourites screens (`ObjCForumsLoaderWorker.m:20`, `ObjCForumTopicsLoaderWorker.m:36-89`, `ObjCFavoritesLoaderWorker.m:46-48`); App Review rule Q-7 ([audit](../audit/README.md)). No legacy view is copied: the layout is a new `NavigationSplitView`.

## Behaviour
One three-column `NavigationSplitView` (sidebar forums, content topics, detail messages). It collapses to a stack on compact widths (iPhone, folded devices) by itself.

- **Sidebar:** "Drapeaux" (`owntopic=1`), "Favoris" (`owntopic=3`), then each category as a collapsible section: "Tous les sujets" (the category) then its sub-forums. A category opens by its id (`forum1.php`), a sub-forum from the forum-relative link the home page gives (`/hfr/<cat>/<sub>/liste_sujet-1.htm`, fetched with the session; `ForumCatalogue` has top-level categories only, and `topicListPath` sends an empty `subcat`). Page N of such a forum is `liste_sujet-N.htm` (HFR-PROTOCOL §7b B2); no engine change. Pull to refresh reloads the home page.
- **Apple category (Q-7):** `ForumVisibility` hides category 25 when logged out and for the review account (default `applereview`, configuration, case-insensitive). A logged-in session whose pseudo is unknown counts as logged out. Applied to the forum list only here; the AQ feed is LOT-046/055. Flags and favourites are not filtered (not in Q-7).
- **Topic list:** forum lists are paged with previous / next / first and "Page N". Honest paging (LOTS issue #3): the pager is a window, so only "a next page exists" (`nextPath`) is used, never a total. Flags and favourites are one page, favourites grouped by category in page order.
- **Refresh (LOTS issue #6):** reloads the page on screen, not page 1. Rows stay while it runs and after a failure; a banner offers "Réessayer".
- **Loads (LOTS issue #7, same rule for lists):** `ContentLoader` runs one load at a time; a newer load or `cancel()` supersedes the older, whose result is dropped. The work runs in its own task so a dismissed pull-to-refresh does not strand the screen.
- **Failures are actionable:** `ListLoadError` (offline, timeout, HTTP status, maintenance with HFR's message, unreadable page) has a title, a detail and Retry; the first load shows it full-screen, a reload as a banner. A message page instead of a list (R12) is "Connexion requise" when logged out, HFR's notice when logged in (the parser cannot tell them apart, LOT-024).
- **Detail:** a placeholder naming the chosen topic. It fetches nothing: an authenticated topic GET marks the flags read (E25). The reader is LOT-083.
- **Flags and favourites** reload each time they reappear, rows kept meanwhile; forum pages only on pull-to-refresh.
- **Login state of a list:** the last forum list, else the session (`AppEnvironment.isLoggedIn`), so a notice is not called a login wall before the home page loads. The single `ForumVisibility` (review account name) lives in `AppEnvironment` for LOT-055 to reuse.
- **Identity:** lists use the account session (`PageFetcher` defaults); the session is anonymous until the login lot (LOT-081) supplies `AppEnvironment.session` and `accountName`.
- UI strings are French (development region `fr`).

## Edge cases
- Selecting another source clears the chosen topic; reselecting the same keeps it. Each source keeps its model, so going back keeps rows and page.
- A superseded or cancelled load shows no error.
- Page past the end: the page HFR serves is shown (`navigation.current`).

## Fixtures
None: the models are tested with a scripted `ForumDataSource`; parsers are covered by their lots. Tests: `ForumVisibilityTests`, `ContentLoaderTests`, `TopicListModelTests`, `ForumListModelTests` (with `ListLoadErrorTests`), `NavigationModelTests` in `App/SwiftHFRTests/`.

**Pending capture:** HFR-PROTOCOL §7b B2 (does `forum1.php?…&page=N` reach page N when logged in? logged out it answers 301 to `liste_sujet-N.htm`; the `liste_sujet-N.htm` path used for sub-forums is not captured logged in either). Until settled, category paging relies on the LOT-041 builder and sub-forum paging on the path form.

## Intentional differences from legacy
- Refresh no longer jumps to page 1; no fake page total.
- Favourites are grouped by category, not merged and sorted by last post (`topicsByLastPost` stays available).

## Learnings
- Typed-throws closures need an explicit `() async throws(E) -> T in` signature and `do throws(E)`, or the error type is inferred as `any Error`.
