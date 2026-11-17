# LOT-146 — iPad multi-window (M4)

- **Module:** App
- **Difficulty / model:** medium (Sonnet → Opus)
- **Issue:** [#236](https://github.com/ezzz/HFRnow/issues/236) · **Milestone:** M4, backport of legacy evolution (operator, 2026-11-09, [#655](https://github.com/ezzz/HFRnow/issues/655))
- **Depends on:** LOT-170 (#296, the root view each window shows). No longer LOT-145 (#235, M5): legacy has no per-window state restoration (below).

Written with the M4 move of #655. `UIApplicationSupportsMultipleScenes` is false at `2440d79` (`HFRswift/Info.plist:206-207`) and true at `2fe43da3` (`afec5433`, "Enable iPad multi-window support"), so a port of legacy evolution.

## Legacy sources
At `2fe43da3`:

| Legacy @ `2fe43da3` | Behaviour |
|---|---|
| `HFRswift/Info.plist:204-208` | `UIApplicationSceneManifest` → `UIApplicationSupportsMultipleScenes` `true`: the system offers new windows of the app (iPad) |
| `HFRswift/Swift/HFRswiftApp.swift:24-36` | one `WindowGroup { RootTabView() }`: every window starts a fresh root (tab bar or split, by its own size classes); the app delegate and its singletons are shared by every window |
| `HFRswift/Swift/Common.swift:153-157`, `:217-225`, `:494`; `MainWindow.swift:1272-1277`, `:2774` @ `87fe0d1c` | legacy looks up the key window of `connectedScenes` for its alerts and tab bar controller: it picks one window, never "the window of the caller" (not ported, below) |
| `git grep -n 'SceneStorage\|NSUserActivity\|openWindow\|handlesExternalEvents' 2fe43da3 -- HFRswift` | no match: no per-window state restoration, no "open in a new window" action, no drag of a topic to a new window |

## Legacy counterpart (app lots)
- `App/SwiftHFR/SwiftHFRApp.swift` (`SwiftHFRApp`) ports `HFRswift/Swift/HFRswiftApp.swift` (`HFRswiftApp`, `:12-37`) @ `87fe0d1c`; the manifest is `HFRswift/Info.plist:204-208` @ `2fe43da3`.
- `App/SwiftHFR/Root/AppWideState.swift` (`AppWideEvents`, `SharedPrivateMessageCounts`): none @ `87fe0d1c`; legacy runs its launch work once in the app delegate, which is what these two give the SwiftUI scene content back.

## UX evolutions (app lots)
None: same UX as legacy at `2fe43da3` (GAP-219: each window starts a fresh root; no per-window restoration, no "open in a new window" action). "Open in a new window", a dragged topic and per-window restoration are not in legacy: they stay with LOT-145 (M5).

## Behaviour
**Manifest.** Xcode 27.2 writes `UIApplicationSupportsMultipleScenes` = `true` into the generated scene manifest (`INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES`) with nothing set in the project, so SwiftHFR was already a multi-window app on iPad when this lot started. Measured: an `INFOPLIST_KEY_UIApplicationSupportsMultipleScenes = NO` build setting and a `UIApplicationSceneManifest` dictionary with `false` in `Config/Info-Keys.plist` both left the built `Info.plist` at `true`, so neither is a way to pin it. A test reads the built bundle (`MultiWindowTests.theBundleDeclaresMultipleScenes`).

**Windows.** The `WindowGroup` of `SwiftHFRApp` builds `RootView` once per window: each window has its own `RootView` (built environment, `lastDestination`), `RootNavigationView` and `RootModel`, so its tab or sidebar selection, its navigation stacks, its reader and its composer sheet are its own. The root picks the tab bar or the sidebar by the window's own size classes (`RootNavigationView.usesSidebarRoot`), as legacy `RootTabView`.

**Shared by every window**, because it is created once in `SwiftHFRApp` (`@State`) or is a process singleton:

| State | Owner | Notes |
|---|---|---|
| Accounts and the current session | `AccountsModel` (LOT-081) | one session per account; a login, switch or logout bumps `currentSessionGeneration` and every window rebuilds its root |
| Settings | `UserDefaultsSettingsStore`, `GeneralSettingsModel`, `ExperimentalSettings` | a change in one window shows in the others (`UserDefaults.didChangeNotification` reloads each root's badge and tab-bar settings) |
| Theme and typography | `ThemeSettingsModel`, `SeasonalThemeModel`, `appTheme`, `appTypography` | `WindowStyle` sets the appearance and tint on each window by its own anchor view |
| App lock | `AppLockModel` | one lock; `AppLockCover` owns one cover window per scene (LOT-173), so every window is covered |
| Legacy import, account deletion, avatar cache, drafts | `LegacyImportModel`, `AccountDeletionModel`, `AvatarRefresh`, the `DraftStore` of the process | |
| The unread private messages count (Messages badge, app icon) | `SharedPrivateMessageCounts` (new), one `PrivateMessageCount` per session generation | was one per root, so a second window showed a stale badge |
| The background MP check and its ledger | `MPBackgroundScheduler`, `MPBackgroundCheck`, `MPNotificationLedger` | `.backgroundTask(.appRefresh)` belongs to the scene declaration, not to a window |
| Network monitor, offline store, seasonal scroll activity | process singletons | |

**Per window**: the selected destination and tab, every `NavigationModel` (selected forum, topic, reader), the Messages list model and its open conversation, the search form, the filter runs, the MPStorage sync model, the reader's web views, a composer sheet. Two windows may show the same topic: each has its own reader and scroll position.

**What runs once, not once per window.** The content closures of `WindowGroup` run in every window, and the scene phase the `App` reads is the aggregate of all windows, so each window sees each change. `AppWideEvents` (`isNew(_:for:)`, `firstTime(_:)`) lets the first window act: the account-change import, the foreground re-check and the next background check, the app lock and season handler, the offline eviction. `AppIconSeasonModel.checkOnceAtLaunch()` runs the dated-icon check once, so a window opened later does not clear a question another window shows. Already once-only and kept: `LegacyImportModel.runAtLaunch`, `AccountsModel.restore`, `NetworkMonitor.start`, the seasonal arrival alert (`SeasonalThemeModel.alert(for:)`: one scene presents it).

**An MP notification tap.** `MPNotificationRouter` holds the tap until a root takes it. With several windows every root watches it, so the first to see it opened the Messages tab, even one hidden behind the others. A root takes it only while its own scene is `.active` (`RootNavigationView.mayOpenNotification`): the tap waits in the router until then, whether it arrived before the root was built (cold launch) or while the windows were away. Of several windows on screen, the first to see the tap takes it (not verified on a device which one that is).

**Single-scene assumptions checked.** `connectedScenes` loops: `OrientationPolicy.refresh` walks every scene (iPhone only); `AppLockAnchorView` finds its own scene. `UIApplication.shared.open`, `alternateIconName` are application-wide by nature. No `keyWindow` or `UIApplication.shared.windows` in the app. No `UISceneDelegate`: the SwiftUI lifecycle owns the scenes. `@UIApplicationDelegateAdaptor` is one delegate for all scenes: `supportedInterfaceOrientationsFor` takes no window.

## Edge cases
- **Two windows on one topic.** Each has its own reader. A reply composer opened in both shares the topic's draft (one `DraftStore` per process, keyed by topic and account): autosaves overwrite each other, the last one wins, and a reply sent in one window deletes the draft while the other window's open composer can write its text back at its next autosave. Not fixed here (a per-window draft, or a notice, is a product decision); listed in the report of the lot for the operator.
- **Logging out (or switching account) in one window.** The shared `AccountsModel` bumps `currentSessionGeneration`: every window rebuilds its root on the new session (`RootView.buildKey`), keeps its destination, and the Messages count restarts (`SharedPrivateMessageCounts`). A window's open reader goes with the old root.
- **An MP notification with two windows open.** Above: one window, an active one, opens the Messages tab, the conversation or the first page of the list.
- **Theme change.** One `ThemeSettingsModel`: each window re-applies the colours and its own `WindowStyle` anchor sets that window's `overrideUserInterfaceStyle` and tint.
- **A window opened while the app lock is on.** The cover window is created per scene (`AppLockAnchorView`), so the new window is covered too; the lock follows the app's aggregate phase.
- **Closing one window.** Its models are released with it; the shared ones stay.
- **Messages badge and app icon.** One count for all windows, so the icon badge is the same whichever window loaded a list last.
- **Not covered**: per-window restoration after a relaunch (LOT-145, M5); iPhone, which has a single window.

## Fixtures
None: no HFR request.

## Intentional differences from legacy
- The Messages count is one for the process per session, not per window (legacy has one `nb_mp`, `HFRplusAppDelegate.m:704-706`).
- The notification tap is taken by a window on screen. Legacy consumes the pending request from whichever `RootTabView` reads it (`Common.swift`, `MessagesNotificationNavigation.consumePendingOpenMessagesRequest` @ `87fe0d1c`).
- Legacy's alert and tab-bar lookups use the first key window of any scene (`Common.swift:153`, `MainWindow.swift:1272` @ `87fe0d1c`); SwiftHFR presents from the view that asks, so an alert opens in its own window.

## Learnings
To copy into AGENTS.md §11 when the lot closes.
- A handler on the content of a `WindowGroup` runs once per window, and the `App`'s `scenePhase` is the aggregate: anything that must run once goes through `AppWideEvents`.
- `INFOPLIST_KEY_UIApplicationSupportsMultipleScenes` and a manifest in `Info-Keys.plist` do not change the generated scene manifest (Xcode 27.2).
