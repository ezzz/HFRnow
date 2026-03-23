# GAP Analysis - HFRswift vs SuperHFRplus

## Decision updates (latest)
1. `OfflineMessagesTableViewController` is deprecated and must not be ported to SwiftUI.
2. `MessagesView` must use file-based WebView rendering (no inline HTML mode) to preserve local CSS/resource loading.
3. `OfflineStorage` must not be used for deprecated offline-topic flows; outside message rendering it remains opt-in and temporary.
4. Testing priority is a minimal safety baseline on ObjC wrappers and critical opening/navigation policies (feature-first).
5. When possible, each SwiftUI screen should have `#Preview` with mock data (normal, loading, empty, error states).
6. Settings must remove dependency to legacy COTS (`InAppSettingsKit`) and move to modern native SwiftUI APIs.
7. iPad parity is lower priority for now; first step is necessity/impact study.
8. End-state target: all UI is SwiftUI; Objective-C is retained only for non-UI processing layers when needed for safety.
9. XIB/NIB usage must be removed from migrated `HFRswift` flows; no new XIB/NIB-based UI should be introduced.
10. Current implementation focus is shifted to `Répondre` parity and message-level contextual actions; settings modernization is deferred in priority (not removed).
11. Current contextual-action sprint scope is limited to quote/profile and related hardening; other per-post actions are explicitly deferred.
12. G19 is closed: quote/profile contextual actions include a UIKit fallback path and are validated on real posts; optional per-post actions remain deferred by scope.
13. For G04, category/topic reordering is explicitly de-scoped (cost > benefit) and replaced by section fold/unfold behavior in Favorites.
14. G06 has moved from action-porting to hardening: the Swift popup menu now covers the full legacy action surface for most posts, including native PM compose and SwiftUI AQ/Bookmark prompts; remaining gaps are now edge-case behavior validation and bridge hardening.

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
| SwiftUI tabs | Catégories/Favoris/Messages/Plus are active; Catégories is currently via wrapper. | `HFRswift/Swift/MainWindow.swift:16`, `HFRswift/Swift/MainWindow.swift:32`, `HFRswift/Swift/MainWindow.swift:42` |
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

### Reply and contextual-action evidence
| Area | Finding | Evidence |
|---|---|---|
| Swift reply UI current state | `AnswerView` now has smileys (common/favoris), insertion image, and a table-cell picker with GIF rendering aligned to legacy behavior. | `HFRswift/Swift/AnswerView.swift:1`, `HFRswift/Swift/ReplySmileyCatalog.swift:1` |
| Swift reply backend | Existing posting pipeline is already robust and reusable. | `HFRswift/Swift/ReplyService.swift:52`, `HFRswift/Swift/ReplyService.swift:83` |
| Legacy reply capabilities | ObjC composer handles smileys/favorites/GIF/rehost and text insertion. | `Classes/AddMessageViewController.m:789`, `Classes/AddMessageViewController.m:951`, `Classes/AddMessageViewController.m:960`, `Classes/AddMessageViewController.m:761` |
| Smiley non-UI cache/service | Smiley defaults/favorites caches are centralized in `SmileyCache`. | `Classes/SmileyCache.h:63`, `Classes/SmileyCache.h:73`, `Classes/SmileyCache.m:106` |
| Message popup trigger in HTML | Message HTML still emits popup schemes for per-post action menu. | `HFRswift/Wrapped/MessagesTableViewController.m:1940`, `HFRswift/Wrapped/MessagesTableViewController.m:2250` |
| Swift popup routing status | Popup schemes are now routed to Swift contextual actions (`showPopupMenu`) and no longer ignored. | `HFRswift/Swift/Common.swift:348`, `HFRswift/Swift/Common.swift:398`, `HFRswiftTests/MessageWebActionHandlerTests.swift:75` |
| Legacy menu actions | ObjC still defines quote/profile actions from popup menu. | `HFRswift/Wrapped/MessagesTableViewController.m:2377`, `HFRswift/Wrapped/MessagesTableViewController.m:2472`, `HFRswift/Wrapped/MessagesTableViewController.m:2618`, `HFRswift/Wrapped/MessagesTableViewController.m:3127` |
| Swift bridge status | Per-post action metadata map is now exposed to Swift and consumed by `MessagesView` for quote/profile menu actions. | `HFRswift/Wrapped/MessagesTableViewController.h:249`, `HFRswift/Wrapped/MessagesTableViewController.m:3556`, `HFRswift/Swift/MessagesView.swift:419` |

## Feature gap matrix

Required fields per feature:
1) user description, 2) ObjC implementation, 3) SwiftUI present/absent, 4) ObjC non-UI dependencies,
5) risks, 6) effort (S/M/L), 7) priority (P0/P1/P2).

| ID | (1) User description | (2) ObjC implementation | (3) SwiftUI status | (4) ObjC non-UI dependencies | (5) Risks | (6) Effort | (7) Priority | Concrete references |
|---|---|---|---|---|---|---|---|---|
| G01 | Browse categories/forums from main tab. | `TabBarController`, `ForumsTableViewController`, XIB wiring. | Completed for current scope: Categories tab now uses native SwiftUI (`CategoriesListView` + `ForumTopicsListView`) with ObjC loaders kept as non-UI backends only. | `Forum`, `k`. | Residual risk reduced to backend parity/regression checks (covered by wrapper + view-model tests). | M | P0 | `HFRswift/Swift/MainWindow.swift:100`, `HFRswift/Swift/MainWindow.swift:223`, `HFRswift/Swift/MainWindow.swift:570`, `HFRswift/Swift/Common.swift:119`, `HFRswift/Swift/Common.swift:144` |
| G02 | Forum quick filters Favoris/Suivis/Lus/Tous. | Long-press actions in `ForumsTableViewController`. | Missing in active SwiftUI flow. | `k` forum URL logic. | Missing power-user behavior. | M | P1 | `Classes/ForumsTableViewController.m:1090`, `Classes/ForumsTableViewController.m:1100` |
| G03 | Topic quick actions (first/last/page/copy link). | `TopicsTableViewController` actions. | Completed for current scope: SwiftUI topic rows now match legacy context behavior (forum: first/last/last-reply/page/copy, favorites: last/last-reply/page/copy, MP: first/last/page/copy), with legacy last-reply URL priority and absolute copied links. | Topic URL pagination model. | Residual risk limited to live/on-device edge cases not reproducible in unit tests. | M | P0 | `Classes/TopicsTableViewController.m:614`, `Classes/HFRMPViewController.m:272`, `Classes/FavoritesTableViewController.m:1423`, `HFRswift/Swift/Common.swift:687`, `HFRswift/Swift/MPListView.swift:246`, `HFRswiftTests/ObjCWrapperLoaderBehaviorTests.swift:356` |
| G04 | Favorites advanced features (filter/super favorite/swipe + section fold/unfold). | `FavoritesTableViewController`. | Partial but substantially advanced: super favorites, swipe actions, compact topic rows, colored states, and section fold/unfold are in SwiftUI; reordering stays explicitly de-scoped. | `FilterPostsQuotes` and favorites data. | Residual risk is now concentrated on heavy-user edge cases rather than missing primary features. | M | P0 | `Classes/FavoritesTableViewController.m:143`, `Classes/FavoritesTableViewController.m:821`, `HFRswift/Swift/Favorites.swift:79` |
| G05 | MP advanced actions (first/last/page/copy link). | `HFRMPViewController` action menu. | Completed for current scope: SwiftUI MP rows expose first page, last page, page picker, and copy-link via the shared topic-row quick-action policy, aligned with legacy. | `MPStorage`. | Residual risk limited to on-device UX validation rather than missing functionality. | M | P0 | `Classes/HFRMPViewController.m:282`, `Classes/HFRMPViewController.m:285`, `HFRswift/Swift/MPListView.swift:246`, `HFRswift/Swift/Common.swift:1061`, `HFRswiftTests/ObjCWrapperLoaderBehaviorTests.swift:488` |
| G06 | Topic web interaction parity (custom schemes/popup/internal links). | `MessagesTableViewController` `WKNavigationDelegate`. | In progress but now very close to parity: routing is covered, popup schemes are handled in Swift, and the popup menu exposes quote, multi-quote, edit, delete, profile, native PM compose, blacklist/whitelist, favorites, link share, alert, AQ, and bookmark, with SwiftUI-native prompts where relevant. Remaining deltas are behavioral edge cases and bridge hardening. | `ParseMessagesOperation`, `BlackList`, `SmileyCache`, `MPStorage`; avoid `OfflineStorage` unless mandatory temporary workaround. | Residual risk is now mainly parity drift in edge behaviors and regressions across mixed Swift/ObjC action bridges. | M | P0 | `HFRswift/Wrapped/MessagesTableViewController.m:2377`, `HFRswift/Wrapped/MessagesTableViewController.m:3005`, `HFRswift/Wrapped/MessagesTableViewController.m:3556`, `HFRswift/Swift/MessagesView.swift:120`, `HFRswift/Swift/MessagesView.swift:2671`, `HFRswiftTests/MessagePopupMenuPolicyTests.swift:1` |
| G07 | Reliable reply flow (auth/hash/cookies/form post/errors). | Legacy composer + posting flow. | Partial (`AnswerView` custom; ObjC composer wrapper commented). | `MultisManager`, `HFRplusAppDelegate.hash_check`. | Posting/session regressions. | L | P0 | `HFRswift/Swift/AnswerView.swift:105`, `HFRswift/Swift/AnswerView.swift:114`, `HFRswift/Swift/ObjCMessageComposerView.swift:7` |
| G08 | Plus routes parity (account/search/bookmarks/AQ/settings/credits/charter/delete). | `PlusTableViewController` routing. | Present via UIKit wrapper; not native SwiftUI yet. | Account/session + AQ backing services. | Route loss if wrapper removed too early. | M | P1 | `Classes/PlusTableViewController.m:82`, `Classes/PlusTableViewController.m:150`, `HFRswift/Swift/PlusTab.swift:10` |
| G09 | Stable multi-account session switching. | `MultisManager` methods for account/cookies/main pseudo. | Partial and tightly coupled from Swift. | `MultisManager`. | Session state drift and threading issues. | M | P0 | `Classes/MultisManager.h:18`, `Classes/MultisManager.h:26`, `HFRswift/Swift/AccountsStore.swift:69` |
| G10 | Lifecycle parity for startup/background tasks. | `HFRplusAppDelegate didFinishLaunchingWithOptions`. | Partial/non-validated. | `MultisManager`, `MPStorage`, `BlackList`, `SmileyCache` (avoid new `OfflineStorage` usage unless mandatory). | Startup/background side effects can diverge. | M | P1 | `Classes/HFRplusAppDelegate.m:65`, `Classes/HFRplusAppDelegate.m:126`, `Classes/HFRplusAppDelegate.m:132`, `Classes/HFRplusAppDelegate.m:144` |
| G11 | iPad split/master-detail parity. | `MainWindow-iPad.xib`, iPad branch in app delegate. | Not implemented in SwiftUI target. | N/A | Potential iPad UX gap. Lower current priority. | M | P2 | `SuperHFRplus/XIB/MainWindow-iPad.xib:22`, `Classes/HFRplusAppDelegate.m:106` |
| G12 | Interop boundary hardening (expose only ObjC non-UI pieces needed). | Shared broad bridging header. | Structural gap present. | `MultisManager`, `MPStorage`, `k`; keep `OfflineStorage` opt-in only. | Build fragility and migration slowdown. | M | P0 | `SuperHFRplus/SuperHFRplus-Bridging-Header.h:8`, `SuperHFRplus/SuperHFRplus-Bridging-Header.h:17` |
| G13 | Minimal high-value test baseline on wrappers/policies. | Wrapped classes in `HFRswift/Wrapped` + ObjC controllers called by Swift. | In progress with a now-usable baseline: wrapper extraction tests and popup/action policy tests exist, but bridge-heavy action execution paths still need selective reinforcement. | Wrapped service/controller dependencies. | Regressions remain possible in action bridges (`AQ`, bookmark, favorite, BL/WL, PM routing) if coverage stops at policy-only checks. | S | P0 | `HFRswift/Wrapped/MessagesTableViewController.h:31`, `HFRswift/Wrapped/ParseMessagesOperation.h:13`, `HFRswiftTests/ObjCWrapperLoaderBehaviorTests.swift:167`, `HFRswiftTests/MessagePopupMenuPolicyTests.swift:1`, `HFRswiftTests/MessageWebActionHandlerTests.swift:1` |
| G14 | Settings migration: remove legacy COTS and use modern native SwiftUI settings. | `PlusSettingsViewController` uses `InAppSettingsKit`. | Not migrated in SwiftUI. | Preference storage and theme/account services. | COTS lock-in and modernization blocker. | M | P1 | `Classes/PlusSettingsViewController.h:9`, `Classes/PlusSettingsViewController.m:16`, `Classes/PlusSettingsViewController.m:39` |
| G15 | SwiftUI previews with mock data for migrated screens. | N/A legacy concern. | Partial/inconsistent. | Mock services and fixtures. | Slower UI iteration and less design/test safety. | S | P1 | `HFRswift/Swift/HFRswiftApp.swift:10`, `HFRswift/Swift/MessagesView.swift:129` |
| G16 | Deprecated offline topic cache navigation must not be ported. | `OfflineMessagesTableViewController`. | Explicitly out of scope for migration. | None (de-scope item). | Wasted effort and added complexity if reintroduced. | S | P0 | `Classes/OfflineMessagesTableViewController.m:38`, `Classes/OfflineMessagesTableViewController.m:1785` |
| G17 | Remove XIB/NIB-backed UI from migrated flows and avoid new NIB UI. | Legacy UIKit controllers and XIB files across app shell and flows. | Structural gap; wrappers still depend on legacy UIKit/XIB paths. | N/A (UI concern; keep ObjC for processing only). | Maintenance cost and UI divergence from SwiftUI target. | L | P1 | `SuperHFRplus/XIB/MainWindow.xib:1`, `SuperHFRplus/XIB/MainWindow-iPad.xib:1`, `Classes/TabBarController.m:57` |
| G18 | Reply composer parity in SwiftUI (default smileys, favorite smileys, image insertion, quote-prefill behavior). | `AddMessageViewController`, `SmileyViewController`, `RehostImageViewController`, `QuoteMessageViewController`. | Completed for current scope: SwiftUI composer covers smileys common/favoris (incl. dynamic forum favorites), image insertion/rehost (incl. 400px), GIF rendering, quote template loading/merge/retry, undo/redo, haptic post feedback, and cleaned server error messages. | `ReplyService`, `AccountSessionService`, `SmileyCache`, `RehostImage`. | Residual risk moved to ongoing reply reliability automation (G07). | L | P0 | `HFRswift/Swift/AnswerView.swift:1`, `HFRswift/Swift/ReplyComposer.swift:1`, `HFRswift/Swift/ReplySmileyCatalog.swift:1`, `HFRswift/Swift/ReplyService.swift:1`, `HFRswift/Swift/MessagesView.swift:1`, `HFRswiftTests/ReplyPostingServiceTests.swift:1`, `Classes/AddMessageViewController.m:789`, `Classes/SmileyViewController.m:1020`, `Classes/RehostImageViewController.m:264` |
| G19 | Message-level contextual actions in `MessagesView` (quote a specific post, open profile from post header/avatar menu). | Popup schemes + `showMenuCon` in `MessagesTableViewController`. | Completed for current scope: popup schemes are handled in Swift, quote/profile contextual menu is wired, and a UIKit fallback path is in place when `UIEditMenuInteraction` is unavailable. Optional actions remain deferred by decision. | Parsed message model fields (`urlQuote`, `urlProfil`, `MPUrl`) exposed by wrapped ObjC controller internals. | Residual risk limited to deferred optional actions outside current scope. | M | P0 | `HFRswift/Swift/Common.swift:398`, `HFRswift/Swift/MessagesView.swift:419`, `HFRswift/Wrapped/MessagesTableViewController.m:3556` |

## Progress tracker
| ID | Status | Exit criteria | Target phase |
|---|---|---|---|
| G01 | Done | Categories/forums navigation is active in native SwiftUI and validated with baseline tests. | S1 |
| G02 | NotStarted | Forum filter actions available in SwiftUI flow. | S1 |
| G03 | Done | Topic quick actions parity validated for forum/favorites/MP contexts and covered by policy tests. | S1 |
| G04 | InProgress | Favorites advanced parity checklist passes. | S2 |
| G05 | Done | MP advanced parity checklist passes. | S2 |
| G06 | InProgress | Full WebView contextual menu parity validated (routing + legacy per-message actions). | S1-S2 |
| G07 | Done | Reply reliability tests pass. | S1-S2 |
| G08 | NotStarted | Plus migrated without route regressions. | S3 |
| G09 | NotStarted | Session/account service stable with tests. | S1 |
| G10 | NotStarted | Startup/background behavior parity validated. | S3 |
| G11 | NotStarted | iPad necessity study completed; implementation only if justified. | S4 |
| G12 | NotStarted | Bridging boundary reduced and documented. | S0-S1 |
| G13 | InProgress | Minimal wrapper/policy regression tests in place and run before push; bridge-heavy popup actions still need targeted coverage. | S0-S2 |
| G14 | NotStarted | Settings no longer depends on InAppSettingsKit. | S2-S3 |
| G15 | NotStarted | Previews with mock data added for migrated SwiftUI screens. | Continuous |
| G16 | LockedOut | OfflineMessages flow marked non-portable and blocked in plan. | S0 |
| G17 | NotStarted | No XIB/NIB execution path remains for migrated `HFRswift` flows. | S2-S4 |
| G18 | Done | Répondre parity validated on device for current scope (quote/smileys/images/undo-redo/haptics/errors). | S1-R |
| G19 | Done | Current-scope contextual popup actions (quote/profile + fallback) validated; optional contextual actions remain deferred by scope. | S1-R |

## Top 10 gaps to close
1. G09 - Account/session adapter hardening.
2. G06 - Topic WebView edge-case validation and bridge hardening.
3. G13 - Minimal wrapper/policy regression baseline.
4. G04 - Favorites advanced parity edge-case validation.
5. G12 - Bridging boundary cleanup.
6. G02 - Forum quick filter actions parity.
7. G08 - Plus routes native SwiftUI migration.
8. G14 - Settings migration away from legacy COTS.
9. G10 - Lifecycle parity for startup/background behavior.
10. G15 - SwiftUI previews with mock data for migrated screens.

## Technical prerequisites
1. Add guardrail: do not port `OfflineMessagesTableViewController`.
2. Add guardrail: no new `OfflineStorage` usage unless mandatory and explicitly documented.
3. Define Swift adapters around wrapped ObjC classes and non-UI services.
4. Build a minimal test floor first: wrapper smoke tests + `TopicOpenPolicy` + known lifecycle regressions.
5. Add preview policy: each migrated SwiftUI screen gets mock-data previews when possible.
6. Replace settings COTS (`InAppSettingsKit`) with native SwiftUI settings stack (`Form`, `AppStorage`, modern APIs).
7. Keep iPad work behind a dedicated necessity study and lower priority.
8. Maintain CI matrix for `HFRswift` on iPhone first; extend to iPad only if study confirms scope.
9. Keep `SuperHFRplus` behavior as oracle for parity decisions.
10. Track temporary workaround debt in docs and remove after stabilization.
11. Define and enforce a reusable SwiftUI Topic list-row pattern (as in Favorites/MP) to avoid per-screen UI drift.
12. Harden and validate the Swift bridge contract for per-post contextual actions (`messageIndex` -> `urlQuote`, `urlProfil`) before closing G19.
