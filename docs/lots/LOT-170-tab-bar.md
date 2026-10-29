# LOT-170 — Root tab bar Catégories / Favoris / Messages / Plus

- **Module:** App (`App/SwiftHFR/Root/`)
- **Difficulty / model:** medium (Sonnet 5.5 → Opus 5.5)
- **Issue:** [#296](https://github.com/ezzz/HFRnow/issues/296)
- **Depends on:** LOT-080 to 083 (done), LOT-119 (#210, start-screen setting and the tab-bar row)

## Legacy sources
Read-only, `origin/master`: `HFRswift/Swift/Common.swift:25-45` (`RootTabIdentifier`, `AppStartupScreen`), `HFRswift/Swift/MainWindow.swift:1275-1420` (`RootTabView`), `:1353-1355` (`usesSidebarRoot`), `:1698-1725` (tab items and badge), `:2205-2245` (iPad sidebar sections, titles, icons), `HFRswift/Swift/PlusTab.swift:11-60` (Plus menu), `HFRswift/Swift/AppSettingsView.swift:130-138` (favourites tab mode "Drapeaux & Favoris" / "Favoris uniquement", start tab values), `:1365-1376` (`defaultIPadDestination`), `:1305-1311`, `:1744-1755`, `:1876-1891` (iPad Plus entries), `:1509-1512` (app-icon badge).

## Behaviour
- **iPhone, or compact-width iPad (Slide Over):** `TabView` Catégories (`folder.fill`), Favoris (`star.fill`), Messages (`envelope`), Plus (`ellipsis`), in that order. The start tab is the LOT-119 start-screen setting (`HFRswiftStartupScreen`, default Favoris). Each tab owns its navigation (a collapsed `NavigationSplitView` is a stack) and the reader opens inside the tab. `tabbar_minimize_on_scroll` (default on) maps to `tabBarMinimizeBehavior(.onScrollDown / .never)`, refreshed on `UserDefaults.didChangeNotification` (`RootModel.reloadSettings()`), so a change in Réglages shows without a relaunch.
- **Catégories:** the category list only (`ForumListView`, "Drapeaux" and "Favoris" rows removed), then the topic list, then the reader.
- **Favoris:** the favourites list, with a toolbar picker "Favoris / Drapeaux" so the flags stay reachable where legacy lists them (legacy shows "Drapeaux & Favoris" together, mode setting `AppSettingsView.swift:130-131`; the merged mode and the "Favoris uniquement" option belong to LOT-124).
- **Messages:** a placeholder until LOT-126, behind `MessagesRootView(environment:)` (tab, owns its `NavigationStack`) and `MessagesListColumn(environment:)` (iPad content column, the reader in the detail column like Favoris), so LOT-126 (`MessagesTabView(environment:)`) replaces those bodies and adds a `RootModel.messages` if the two layouts share the list. The legacy app-icon badge (`MainWindow.swift:1509-1512`) is out of scope. The tab badge is the unread private-message count of the home page (`ForumListPage.unreadPrivateMessages`, LOT-023), hidden when 0, logged out, or when `mp_badge_enabled` is off (legacy `MainWindow.swift:1349`). The home page is loaded at launch whatever the start tab (`RootNavigationView.task`), so the badge does not wait for a visit to Catégories. Legacy read an `nb_mp` counter in defaults; this port reads the page count and does not poll (refresh = pull to refresh on Catégories).
- **Plus:** seven rows in legacy order: Réglages, Rechercher sur le forum, Bookmarks, Alertes Qualitay, Crédits, Charte du forum, Supprimer mon compte. Réglages opens the LOT-119 screen; the others show a placeholder, never a dead row (owning lots: LOT-115, 132, 133, 120 for Crédits and Charte, 157). The settings gear of the sidebar toolbar (LOT-119) is gone. The account menu sits in the Plus and Catégories toolbars. The Alertes Qualitay badge on Plus waits for LOT-133.
- **Regular-width iPad:** a sidebar root replaces the tab bar (legacy `usesSidebarRoot`): sections [Catégories, Favoris, Messages], [Bookmarks, Alertes Qualitay], [Réglages, Rechercher, Crédits, Charte, Supprimer mon compte]. Catégories shows the category list and pushes the topic list in the same column, the reader keeps the detail column; Favoris shows the favourites in the content column. A Plus entry uses a two-column split with the entry in a `NavigationStack` in the detail column (legacy `MainWindow.swift:1305-1311`, `:1744-1755`, `:1876-1891`). On iPad the Plus tab opens Réglages (`defaultIPadDestination`, `:1365-1376`).

## Edge cases
- Selecting another category clears the chosen topic (`NavigationModel`), per tab.
- Deselecting in the sidebar keeps the current destination.
- One selection feeds both layouts (`RootModel.selectedDestination`; `selectedTab` is derived from it, a Plus entry being the Plus tab), so Slide Over or Split View keeps the user where they were. Re-selecting Plus in the tab bar keeps the sidebar's open entry, and the Plus stack shows it (`RootModel.plusPath`): Back returns to the Plus menu.
- A new session generation rebuilds the whole root (`RootView.id`), so no account keeps another's badge or lists; the selected destination is kept (`RootView` passes it to `RootModel(initial:)`, legacy `MainWindow.swift:1276-1278`, `:1357-1362`) and the start-screen setting applies to the first creation only.

## Fixtures
None: view-model logic only (`RootModelTests`: tab order, titles, icons; start tab per setting and default; badge count, 0, logged out, setting off; minimize setting and `reloadSettings()`; kept destination across rebuilds; Plus entries, symbols and owning lots; iPad sections, symbols and Plus-to-Réglages mapping).

**Pending capture:** none. Checked in the simulator (launch only, no tap automation available): tab bar on iPhone, start tab from the setting, Dynamic Type accessibility XL on Catégories, iPad Pro 11" portrait (sidebar behind the toggle, as a three-column split does in portrait). Not verified: the "sidebar filter never blocks opening a topic" criterion on iPad (a tapped topic sets the reader's selection; check in the Xcode build), and the home-screen quick actions.

## Intentional differences from legacy
- No `nb_mp` counter: the badge is the home page count, refreshed with the home page.
- Flags reachable by a picker in Favoris instead of the merged list (until LOT-124).
- iPad: the columns are all shown at launch and the choice is not persisted (legacy defaults to two columns and persists it, `MainWindow.swift:1351`, `:1434-1505`).
- iPad: Catégories opens topics in a pushed list in the content column (legacy used a forum picker).

## Follow-ups (not in this lot)
- Home-screen quick actions (Catégories, Favoris, Messages; legacy `SuperHFRplus-Info.plist:235-255`, `HFRplusAppDelegate.m:314`): not trivial (needs Info.plist items and a delegate), left for a separate lot.

## Learnings
- `List(selection:)` in a sidebar needs an optional selection on iOS; wrap a non-optional model value in a binding that ignores nil.
