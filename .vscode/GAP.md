# GAP Analysis - HFRswift vs SuperHFRplus

## Decision updates (latest)
1. `OfflineMessagesTableViewController` is deprecated and must not be ported to SwiftUI.
2. `MessagesView` must use file-based WebView rendering (no inline HTML mode) to preserve local CSS/resource loading.
3. `OfflineStorage` must not be used for deprecated offline-topic flows; outside message rendering it remains opt-in and temporary.
4. Testing priority is coverage of ObjC classes wrapped by Swift/SwiftUI.
5. When possible, each SwiftUI screen should have `#Preview` with mock data (normal, loading, empty, error states).
6. Settings must remove dependency to legacy COTS (`InAppSettingsKit`) and move to modern native SwiftUI APIs.
7. iPad parity is lower priority for now; first step is necessity/impact study.

## Scope and method
This GAP is based on concrete code signals:
- targets/schemes in Xcode project metadata
- app entrypoints and wiring
- real call sites (who calls what)
- ObjC non-UI service dependencies
- bridging header exposure

## Baseline signals

### Targets and entrypoints
| Area | Finding | Evidence |
|---|---|---|
| Targets | `HFRswift` and `SuperHFRplus` exist in same project. | `SuperHFRplus.xcodeproj/project.pbxproj:4307`, `SuperHFRplus.xcodeproj/project.pbxproj:4330` |
| Swift entry | `HFRswift` starts from SwiftUI `@main` and `RootTabView`. | `HFRswift/Swift/HFRswiftApp.swift:10`, `HFRswift/Swift/HFRswiftApp.swift:17` |
| ObjC lifecycle retained | SwiftUI app still injects `HFRplusAppDelegate`. | `HFRswift/Swift/HFRswiftApp.swift:13` |

### Navigation
| Area | Finding | Evidence |
|---|---|---|
| Legacy tabs | Catégories/Favoris/Messages/Plus in ObjC tab bar. | `Classes/TabBarController.m:57`, `Classes/TabBarController.m:60` |
| SwiftUI tabs | Catégories tab is commented; only Favoris/Messages/Plus active. | `HFRswift/Swift/MainWindow.swift:32`, `HFRswift/Swift/MainWindow.swift:43`, `HFRswift/Swift/MainWindow.swift:50` |
| Plus still wrapped | SwiftUI uses `PlusTableViewWrapper`. | `HFRswift/Swift/PlusTab.swift:10` |

### Real Swift -> ObjC usage
| Swift caller | ObjC target | Evidence |
|---|---|---|
| `FavoritesViewModel` | `FavoritesTableViewController.fetchContent` | `HFRswift/Swift/Favorites.swift:25`, `HFRswift/Swift/Favorites.swift:28` |
| `MPListViewModel` | `HFRMPViewController.fetchContent` | `HFRswift/Swift/MPListView.swift:15`, `HFRswift/Swift/MPListView.swift:24` |
| `MessagesView` | `MessagesTableViewController.fetchContentForTopicURL` | `HFRswift/Swift/MessagesView.swift:188`, `HFRswift/Wrapped/MessagesTableViewController.h:249` |
| `MessagesView` | `OfflineStorage` (current HTML cache workaround) | `HFRswift/Swift/MessagesView.swift:194`, `HFRswift/Swift/MessagesView.swift:195` |
| `AccountsStore` | `MultisManager` | `HFRswift/Swift/AccountsStore.swift:33`, `HFRswift/Swift/AccountsStore.swift:69` |

### Deprecated/offline evidence
| Area | Finding | Evidence |
|---|---|---|
| Deprecated offline controller | Offline topic-page controller exists in legacy code and should not be ported. | `Classes/OfflineMessagesTableViewController.m:38` |
| Offline service scope | `OfflineStorage` includes offline-topic storage methods. | `Classes/OfflineStorage.h:20`, `Classes/OfflineStorage.h:23`, `Classes/OfflineStorage.h:32` |
| Legacy startup usage | AppDelegate currently copies offline resources at startup. | `Classes/HFRplusAppDelegate.m:72` |

### Settings COTS dependency evidence
| Area | Finding | Evidence |
|---|---|---|
| Legacy COTS import | Settings depends on `InAppSettingsKit`. | `Classes/PlusSettingsViewController.h:9`, `Classes/PlusSettingsViewController.m:16` |
| Legacy COTS usage | `IASKAppSettingsViewController` used directly. | `Classes/PlusSettingsViewController.m:39`, `Classes/PlusSettingsViewController.m:51` |

## Feature gap matrix

Required fields per feature:
1) user description, 2) ObjC implementation, 3) SwiftUI present/absent, 4) ObjC non-UI dependencies,
5) risks, 6) effort (S/M/L), 7) priority (P0/P1/P2).

| ID | (1) User description | (2) ObjC implementation | (3) SwiftUI status | (4) ObjC non-UI dependencies | (5) Risks | (6) Effort | (7) Priority | Concrete references |
|---|---|---|---|---|---|---|---|---|
| G01 | Browse categories/forums from main tab. | `TabBarController`, `ForumsTableViewController`, XIB wiring. | Absent (tab disabled). | `Forum`, `k`. | Primary navigation regression. | M | P0 | `Classes/TabBarController.m:57`, `HFRswift/Swift/MainWindow.swift:32` |
| G02 | Forum quick filters Favoris/Suivis/Lus/Tous. | Long-press actions in `ForumsTableViewController`. | Missing in active SwiftUI flow. | `k` forum URL logic. | Missing power-user behavior. | M | P1 | `Classes/ForumsTableViewController.m:1090`, `Classes/ForumsTableViewController.m:1100` |
| G03 | Topic quick actions (first/last/page/copy link). | `TopicsTableViewController` actions. | Not fully available end-to-end. | Topic URL pagination model. | Loss of critical navigation actions. | M | P0 | `Classes/TopicsTableViewController.m:614`, `Classes/TopicsTableViewController.m:618` |
| G04 | Favorites advanced features (edit/reorder/filter/super favorite/swipe). | `FavoritesTableViewController`. | Partial; advanced menu still TODO/commented. | `FilterPostsQuotes` and favorites data. | High regression for heavy users. | L | P0 | `Classes/FavoritesTableViewController.m:143`, `Classes/FavoritesTableViewController.m:821`, `HFRswift/Swift/Favorites.swift:79` |
| G05 | MP advanced actions (first/last/page/copy link). | `HFRMPViewController` action menu. | Partial; list works but advanced actions not exposed. | `MPStorage`. | MP navigation regression. | M | P0 | `Classes/HFRMPViewController.m:282`, `Classes/HFRMPViewController.m:285`, `HFRswift/Swift/MPListView.swift:24` |
| G06 | Topic web interaction parity (custom schemes/popup/internal links). | `MessagesTableViewController` `WKNavigationDelegate`. | Critical partial in Swift side. | `ParseMessagesOperation`, `BlackList`, `SmileyCache`; avoid `OfflineStorage` unless mandatory temporary workaround. | Major behavior mismatch risk. | L | P0 | `HFRswift/Wrapped/MessagesTableViewController.m:2137`, `HFRswift/Wrapped/MessagesTableViewController.m:2235`, `HFRswift/Swift/MessagesView.swift:60` |
| G07 | Reliable reply flow (auth/hash/cookies/form post/errors). | Legacy composer + posting flow. | Partial (`AnswerView` custom; ObjC composer wrapper commented). | `MultisManager`, `HFRplusAppDelegate.hash_check`. | Posting/session regressions. | L | P0 | `HFRswift/Swift/AnswerView.swift:105`, `HFRswift/Swift/AnswerView.swift:114`, `HFRswift/Swift/ObjCMessageComposerView.swift:7` |
| G08 | Plus routes parity (account/search/bookmarks/AQ/settings/credits/charter/delete). | `PlusTableViewController` routing. | Present via UIKit wrapper; not native SwiftUI yet. | Account/session + AQ backing services. | Route loss if wrapper removed too early. | M | P1 | `Classes/PlusTableViewController.m:82`, `Classes/PlusTableViewController.m:150`, `HFRswift/Swift/PlusTab.swift:10` |
| G09 | Stable multi-account session switching. | `MultisManager` methods for account/cookies/main pseudo. | Partial and tightly coupled from Swift. | `MultisManager`. | Session state drift and threading issues. | M | P0 | `Classes/MultisManager.h:18`, `Classes/MultisManager.h:26`, `HFRswift/Swift/AccountsStore.swift:69` |
| G10 | Lifecycle parity for startup/background tasks. | `HFRplusAppDelegate didFinishLaunchingWithOptions`. | Partial/non-validated. | `MultisManager`, `MPStorage`, `BlackList`, `SmileyCache` (avoid new `OfflineStorage` usage unless mandatory). | Startup/background side effects can diverge. | M | P1 | `Classes/HFRplusAppDelegate.m:65`, `Classes/HFRplusAppDelegate.m:126`, `Classes/HFRplusAppDelegate.m:132`, `Classes/HFRplusAppDelegate.m:144` |
| G11 | iPad split/master-detail parity. | `MainWindow-iPad.xib`, iPad branch in app delegate. | Not implemented in SwiftUI target. | N/A | Potential iPad UX gap. Lower current priority. | M | P2 | `SuperHFRplus/XIB/MainWindow-iPad.xib:22`, `Classes/HFRplusAppDelegate.m:106` |
| G12 | Interop boundary hardening (expose only ObjC non-UI pieces needed). | Shared broad bridging header. | Structural gap present. | `MultisManager`, `MPStorage`, `k`; keep `OfflineStorage` opt-in only. | Build fragility and migration slowdown. | M | P0 | `SuperHFRplus/SuperHFRplus-Bridging-Header.h:8`, `SuperHFRplus/SuperHFRplus-Bridging-Header.h:17` |
| G13 | Test strategy focused on wrapped ObjC classes. | Wrapped classes in `HFRswift/Wrapped` + ObjC controllers called by Swift. | Missing dedicated test coverage currently. | Wrapped service/controller dependencies. | Regressions hidden behind wrappers. | M | P0 | `HFRswift/Wrapped/MessagesTableViewController.h:31`, `HFRswift/Wrapped/ParseMessagesOperation.h:13`, `HFRswift/Swift/Favorites.swift:25`, `HFRswift/Swift/MPListView.swift:15` |
| G14 | Settings migration: remove legacy COTS and use modern native SwiftUI settings. | `PlusSettingsViewController` uses `InAppSettingsKit`. | Not migrated in SwiftUI. | Preference storage and theme/account services. | COTS lock-in and modernization blocker. | M | P1 | `Classes/PlusSettingsViewController.h:9`, `Classes/PlusSettingsViewController.m:16`, `Classes/PlusSettingsViewController.m:39` |
| G15 | SwiftUI previews with mock data for migrated screens. | N/A legacy concern. | Partial/inconsistent. | Mock services and fixtures. | Slower UI iteration and less design/test safety. | S | P1 | `HFRswift/Swift/HFRswiftApp.swift:10`, `HFRswift/Swift/MessagesView.swift:129` |
| G16 | Deprecated offline topic cache navigation must not be ported. | `OfflineMessagesTableViewController`. | Explicitly out of scope for migration. | None (de-scope item). | Wasted effort and added complexity if reintroduced. | S | P0 | `Classes/OfflineMessagesTableViewController.m:38`, `Classes/OfflineMessagesTableViewController.m:1785` |

## Progress tracker
| ID | Status | Exit criteria | Target phase |
|---|---|---|---|
| G01 | NotStarted | Categories flow active and stable. | S1 |
| G02 | NotStarted | Forum filter actions available in SwiftUI flow. | S1 |
| G03 | NotStarted | Topic quick actions parity validated. | S1 |
| G04 | NotStarted | Favorites advanced parity checklist passes. | S2 |
| G05 | NotStarted | MP advanced parity checklist passes. | S2 |
| G06 | NotStarted | Web action routing parity validated. | S1-S2 |
| G07 | NotStarted | Reply reliability tests pass. | S1-S2 |
| G08 | NotStarted | Plus migrated without route regressions. | S3 |
| G09 | NotStarted | Session/account service stable with tests. | S1 |
| G10 | NotStarted | Startup/background behavior parity validated. | S3 |
| G11 | NotStarted | iPad necessity study completed; implementation only if justified. | S4 |
| G12 | NotStarted | Bridging boundary reduced and documented. | S0-S1 |
| G13 | NotStarted | Wrapped ObjC class tests in CI. | S0-S2 |
| G14 | NotStarted | Settings no longer depends on InAppSettingsKit. | S2-S3 |
| G15 | NotStarted | Previews with mock data added for migrated SwiftUI screens. | Continuous |
| G16 | LockedOut | OfflineMessages flow marked non-portable and blocked in plan. | S0 |

## Top 10 gaps to close
1. G06 - Topic WebView action routing parity.
2. G07 - Reply reliability and session correctness.
3. G01 - Categories flow reactivation.
4. G03 - Topic quick actions parity.
5. G09 - Account/session adapter hardening.
6. G13 - Wrapped ObjC test coverage.
7. G04 - Favorites advanced parity.
8. G12 - Bridging boundary cleanup.
9. G14 - Settings COTS removal to native SwiftUI.
10. G05 - MP advanced parity.

## Technical prerequisites
1. Add guardrail: do not port `OfflineMessagesTableViewController`.
2. Add guardrail: no new `OfflineStorage` usage unless mandatory and explicitly documented.
3. Define Swift adapters around wrapped ObjC classes and non-UI services.
4. Build tests first for wrapped ObjC classes (`MessagesTableViewController`, `ParseMessagesOperation`, and ObjC controllers currently called from Swift wrappers).
5. Add preview policy: each migrated SwiftUI screen gets mock-data previews when possible.
6. Replace settings COTS (`InAppSettingsKit`) with native SwiftUI settings stack (`Form`, `AppStorage`, modern APIs).
7. Keep iPad work behind a dedicated necessity study and lower priority.
8. Maintain CI matrix for `HFRswift` on iPhone first; extend to iPad only if study confirms scope.
9. Keep `SuperHFRplus` behavior as oracle for parity decisions.
10. Track temporary workaround debt in docs and remove after stabilization.
