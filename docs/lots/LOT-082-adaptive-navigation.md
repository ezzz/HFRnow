# LOT-082 — Adaptive navigation

- **Module:** App (`App/SwiftHFR/Navigation/`)
- **Difficulty / model:** medium (Sonnet 5.5 → Opus 5.5)
- **Issue:** [#100](https://github.com/ezzz/HFRnow/issues/100); old francoisgn/ios-app_SwiftHFR#96
- **Depends on:** LOT-080 (target), LOT-021, 022, 024 (parsers), LOT-045 (fetchers)

## Legacy sources
Read-only: the legacy forum, topic-list and favourites screens (`ObjCForumsLoaderWorker.m:20`, `ObjCForumTopicsLoaderWorker.m:36-89`, `ObjCFavoritesLoaderWorker.m:46-48`); App Review rule Q-7 ([audit](../audit/README.md)). No legacy view is copied: the layout is a new `NavigationSplitView`.

## Behaviour
Updated by LOT-170: the root is the legacy tab bar (iPhone) or sidebar (regular-width iPad), see [LOT-170](LOT-170-tab-bar.md). Each tab hosts a `NavigationSplitView` (forums, topics, reader) that collapses to a stack on compact widths by itself.

- **Catégories list:** (LOT-170: no "Drapeaux"/"Favoris" rows on top; they have the Favoris tab, `owntopic=1` and `owntopic=3`) each category as a collapsible section: "Tous les sujets" (the category) then its sub-forums. A category opens by its id (`forum1.php`), a sub-forum from the forum-relative link the home page gives (`/hfr/<cat>/<sub>/liste_sujet-1.htm`, fetched with the session; `ForumCatalogue` has top-level categories only, and `topicListPath` sends an empty `subcat`). Page N of such a forum is `liste_sujet-N.htm` (HFR-PROTOCOL §7b B2); no engine change. Pull to refresh reloads the home page.
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
- **Reverted on purpose (operator, 2026-10-28):** the split-view-only navigation of this lot (no bottom tab bar, Drapeaux/Favoris at the top of the sidebar) is not kept. The legacy root tabs Catégories / Favoris / Messages / Plus come back with [LOT-170 (#296)](https://github.com/ezzz/HFRnow/issues/296): a tab bar on iPhone, the legacy sidebar on a regular-width iPad (legacy `HFRswift/Swift/MainWindow.swift:1353-1355`, `:1698-1725`, `:2205-2245`). See the UX principles in [FEATURES.md](../FEATURES.md#ux-principles-operator).

## UX evolutions (H.1)
Classification of directive H.1 (2026-11-01): the `H.1` column of [GAP-LEGACY-VS-SWIFT.md](../migration/GAP-LEGACY-VS-SWIFT.md#convergence-classification-h1). The decision of each UXD row (2026-11-02) is in [the decisions table](../migration/GAP-LEGACY-VS-SWIFT.md#ux-decisions-of-2026-11-02). The code names its legacy counterparts in `// Port of …` comments (AGENTS.md §4), added by [#378](https://github.com/ezzz/HFRnow/pull/378).
- GAP-020, 021, 022 Catégories as collapsible sections with sub-forum rows, no icons, no sub-forum picker: `b`, shipped, pending **UXD-05** (recommendation: A, restore the legacy list).
- GAP-023 no Tous / Favoris / Suivis / Lus filter: not planned, pending **UXD-06**.
- GAP-026, 027 topic row "author · replies · date", no "⚑ cur / max", capsule or tint: `b`, shipped, pending **UXD-07** (inside LOT-169).
- GAP-212, 214 detail column on every regular width: `b`, pending **UXD-24**.
- GAP-024 "Page N" without a fake total: `b·needed` (HFR gives no reliable total, LOT-167). GAP-025, 038: `a`.

### Decisions of 2026-11-02 (UXD)

Operator decisions on [#379](https://github.com/ezzz/HFRnow/issues/379): every UXD row takes its recommendation. M4 is the validated legacy parity, M5 the evolutions.
- **UXD-05, UXD-06: A.** The legacy Catégories list (flat, icons, "N sous-forums", sub-forum picker in the topic list) and the persisted Tous / Favoris / Suivis / Lus filter come back in a restore lot ([#427](https://github.com/ezzz/HFRnow/issues/427), M2).
- **UXD-07: A.** The topic row is the legacy one (title, unread capsule, "⚑ cur / max", flag tint), inside LOT-169.
- **UXD-24:** B on iPad (detail column next to the list on every regular width, shipped); A on a large iPhone in landscape, the reader full width ([#431](https://github.com/ezzz/HFRnow/issues/431), M2).

## Learnings
- Typed-throws closures need an explicit `() async throws(E) -> T in` signature and `do throws(E)`, or the error type is inferred as `any Error`.
