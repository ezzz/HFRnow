# LOT-124 — Favourites options and super favourites

- **Module:** App (`App/SwiftHFR/Navigation/`, `Settings/`, `Root/`); one key added to HFRStorage
- **Difficulty / model:** medium (Sonnet 5.5 → Opus 5.5)
- **Issue:** [#215](https://github.com/ezzz/HFRnow/issues/215)
- **Depends on:** LOT-064 (stores, #345), LOT-082 (navigation), LOT-119 (settings screen). LOT-125 (#216, swipes) and LOT-143 (#233, Home "À suivre") build on it.

## Legacy counterpart

Legacy app `ezzz/HFRnow` at `2440d79`, `HFRswift/Swift/` (the issue's `AppSettingsView.swift:383-390` is a `master` line; the rows are cited at `2440d79` below).

| Legacy | Used for |
|---|---|
| `Favorites.swift:112-137` (`FavoritesSuperFavoriteStore`, `SuperFavoritesIds`) | the super-favourite set; storage is LOT-064, this lot reads and writes it through `SuperFavoritesStore` |
| `Favorites.swift:139-155` (`FavoritesCollapsedSectionsStore`) | folded sections; storage is LOT-064 (`FavoritesLayoutStore`) |
| `Favorites.swift:157-166` (`FavoritesTopicListOrdering`) | flat list: every topic by last post, newest first (`FavoritesPage.topicsByLastPost`) |
| `Favorites.swift:168-200` (`FavoritesListDensity`) | compact row density: **not here**, compact mode is applied app-wide by LOT-169 (#295) |
| `Favorites.swift:293-395` (`FavoriteSectionView`) | section header: forum title, topic count, fold chevron only when the section has a topic |
| `Favorites.swift:402-410` (`@AppStorage` block): `vos_sujets`, `sujets_avec_cat`, `favorites_auto_refresh`, `FavoritesShowCollapsedSections` | the four settings, same keys and defaults (the last one has no registered default: absent is off) |
| `Favorites.swift:446-448, 525-545` | `shouldShowEmptyFavoriteSections` (`showCollapsedSections && vos_sujets == "0"`), `shouldDisplayCategorizedFavorite`, `collapsibleSectionIDs` |
| `Favorites.swift:466-476` (`refreshContentWhenViewAppears`) | forced reload on appear only with `favorites_auto_refresh`, else load once |
| `Favorites.swift:544-607` (all-folded state, `pruneCollapsedSections`, fold/unfold all) | prune folded ids to the sections of a non-empty page; "Tout replier" / "Tout déplier"; the all-folded empty state |
| `AppSettingsView.swift:86-88, 121-124, 341` (`2440d79`; `master` `:383-390`) | "Drapeaux & Favoris" / "Favoris uniquement" and the three rows in "Général" |
| `Favorites.swift:850-858, 1036-1040` | super-favourite toggle in the row **menu** (swipes are LOT-125) |
| `ObjCFavoritesLoaderWorker.m:46-47` | `vos_sujets == 1` → `owntopic=3`, else `owntopic=1` |

GAP rows: GAP-030, GAP-031, GAP-032, GAP-033 (`docs/migration/GAP-LEGACY-VS-SWIFT.md`). No UX decision (`UXD`) applies.

## Behaviour

Code: `FavoritesPresentation` (pure layout rules), `FavoritesOptionsModel` (`@Observable @MainActor`: settings, folded sections, super-favourites), `FavoritesStores` (process-wide file stores under `Application Support/Favorites/`), views in `TopicListView`, `FavoritesSourceMenu` and `SettingsView`. Tests in `App/SwiftHFRTests/Favorites/`.

- **Settings** keep their legacy keys and shapes (`vos_sujets` stored as a string, the others as booleans); creating the model writes nothing. Rows are in Réglages > "Général" (after "Écran de démarrage", legacy order) and in the Favoris tab's "Options" menu, so they are reachable from the screen itself (comment of 2026-10-28 on #215).
- **Mode** (`vos_sujets`): "Drapeaux & Favoris" is the flags list (`owntopic=1`, source `.flagged`), "Favoris uniquement" the favourites list (`owntopic=3`, source `.favorites`). Picking a list in the tab's menu writes the mode, and the tab opens on the list the mode names (default: "Drapeaux & Favoris", as legacy). This is GAP-032's "merged mode back".
- **Sort** (`sujets_avec_cat`, default on): grouped = one section per category in page order with its topic count; flat = one list, last post newest first, undated last.
- **Folding**: a section with at least one topic has a chevron; the folded ids persist per device. A folded section is hidden unless "Afficher les sections repliées" is on, then it shows its header only. "Tout replier" / "Tout déplier" are in the menu. After each successful load, folded ids the page no longer has are forgotten; an empty page forgets nothing (a failed or logged-out load never loses the user's choices).
- **Empty categories** (the fix asked on HFR+ topic p. 507): with "Afficher les sections repliées" on **and** the mode "Drapeaux & Favoris", categories without a topic are listed too (legacy rule). The toggle stays usable in both sorts: flat has no section to show or hide, so it changes nothing there (legacy disabled it in flat mode; here it keeps its state so switching sort back finds it).
- **All folded**: when the page has topics but the options hide every section, the screen says "Toutes les sections sont repliées" with "Afficher les sections repliées" and "Tout déplier".
- **Super favourites**: marked from a row's context menu ("Ajouter aux / Retirer des super favoris"; swipes are LOT-125), local, per account, keyed by category and topic (LOT-064). Grouped: a "Super favoris" section first, each topic only there (a row never appears twice, so the list selection stays unambiguous); flat: no section, the row carries the mark. Rows are tinted orange and carry a "Super favori" icon. Logged out: no entry. Setting `daySuperFavoriteColor` / `nightSuperFavoriteColor` (LOT-121) will replace the fixed orange.
- **Automatic refresh** (`favorites_auto_refresh`, default off): the lists refresh on re-appearance only when on; otherwise pull-to-refresh and the refresh action reload. Forum lists are unchanged.
- **No write**: this lot sends nothing to HFR. Flag writes (remove a favourite, mark read) stay in `TopicFlagFlow` and come with the swipes of LOT-125.
- A store that cannot be read or written (LOT-064 failure guard) leaves the list as it was and sets `storeProblem`; the choices are never overwritten.

## Edge cases

- Same topic number in two categories: only the marked one is a super-favourite (tested).
- A row without `topicID` cannot be marked; no account: nothing can be marked.
- A category whose topics are all super-favourites shows no section of its own (unless empty categories are on) and is not foldable.
- Settings changed in Réglages while the tab is alive are read again by `RootModel.reloadSettings()` (UserDefaults change notification).

## Fixtures

None new: layout rules run on synthetic `FavoritesPage` values; the parser's output for real pages is LOT-022's.

## Pending capture

- **Empty category headers on the real favourites page**: whether HFR serves a category header with no row (the case "show empty categories" relies on). The parser opens a section per header and yields an empty one (`FavoritesParser`), but `R10`/`R11` have no such header. Capture request: #109 (a `forum1f.php?owntopic=1` with a category whose flagged topics were all removed).
- **`Tous · Favoris · Suivis · Lus` across all categories** (community request of 2026-10-28 on #215; legacy filter `MainWindow.swift:660-678` is a per-forum filter on `forum1.php?owntopic=0..3`, GAP-023): the Favoris tab already offers "Suivis" (`owntopic=1`) and "Favoris" (`owntopic=3`) through its list menu. "Tous" and "Lus" need `forum1f.php?owntopic=0` and `owntopic=2`, **not captured** (`HFR-PROTOCOL.md` §6 "Favourites page filters"). Not built; LOT-124 stays the owner once captured.

## Intentional differences from legacy

- Super-favourites per account and per category+topic (LOT-064, CHANGELOG-LEGACY 30 and 41); a legacy `SuperFavoritesIds` import is LOT-067's.
- Folded-section ids are `cat:<id>` / `path:<forum path>` (`FavoriteSection.id`), not legacy's `forum-id:` / `forum-url:` / `forum-title:` strings: LOT-067 maps them or drops them.
- Super-favourites are a section, not only a tint (GAP-033).
- Store failures are shown instead of ignored.
- "Afficher les sections repliées" stays enabled in flat mode.

## Learnings

- A favourites mode and a list source are the same fact (`vos_sujets` 0/1 = flags/favourites): keep one place writing it (the source selection) instead of two pickers.
- Layout rules over a parsed page belong in a pure function: the whole behaviour is tested without a store, a view or a request.
