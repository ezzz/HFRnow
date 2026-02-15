# S0 Foundations - Execution Board

## Objectives
1. Lock migration guardrails before feature expansion.
2. Introduce wrapper-friendly service seams in SwiftUI layer.
3. Prepare test and preview conventions for the migration.
4. Establish reusable SwiftUI UI primitives for list-based migrated flows.

## Guardrails (Locked)
- Do not port `OfflineMessagesTableViewController`.
- `OfflineStorage` must not be used for deprecated offline-topic flows.
- For `MessagesView` WebView rendering, local file loading is the default/required path (no inline HTML mode).
- Keep a minimal test baseline around wrapped ObjC classes and critical policy/lifecycle regressions.
- Add SwiftUI previews with mock data whenever feasible.
- Remove settings dependency to legacy COTS (`InAppSettingsKit`) in upcoming phases.
- Keep iPad as lower priority, with decision gate first.
- End-state target: full SwiftUI UI; ObjC kept only for non-UI processing when necessary.
- For migrated `HFRswift` flows, avoid new XIB/NIB-based UI.

## Delivered in this S0 start
- [x] Added adapter/service seams in `HFRswift/Swift/Common.swift`:
  - `FavoritesLoading`, `MPTopicsLoading`, `TopicPageLoading`, `TopicPageRendering`
  - ObjC-backed defaults (`ObjCFavoritesLoader`, `ObjCMPTopicsLoader`, `ObjCTopicPageLoader`)
- [x] Refactored callers to injection-friendly design:
  - `HFRswift/Swift/Favorites.swift`
  - `HFRswift/Swift/MPListView.swift`
  - `HFRswift/Swift/MessagesView.swift`
- [x] Added preview-friendly initializers + first mock previews:
  - `TopicRowView` preview in `HFRswift/Swift/Favorites.swift`
  - `MPRowView` preview in `HFRswift/Swift/MPListView.swift`
- [x] Added list-level preview variants (happy/loading/empty/error):
  - `FavoritesListView` previews in `HFRswift/Swift/Favorites.swift`
  - `MPListView` previews in `HFRswift/Swift/MPListView.swift`
- [x] Mutualized Topic list-row base view used by Favorites and MP:
  - `TopicListRowView` in `HFRswift/Swift/Common.swift`
  - consumed by `TopicRowView` and `MPRowView`
- [x] Switched message rendering to file-based loading only (`loadFileURL` path).
- [x] Removed inline HTML fallback path from `MessagesView` to preserve local CSS/resource loading.
- [x] Added native SwiftUI settings scaffold:
  - `HFRswift/Swift/AppSettingsView.swift`
  - linked from Plus tab via settings button (`HFRswift/Swift/MainWindow.swift`)
- [x] Added initial wrapper-test scaffolding files:
  - `HFRswiftTests/TopicPageRenderingTests.swift`
  - `HFRswiftTests/ObjCWrappedClassesSmokeTests.swift`
- [x] Added first wrapped ObjC behavior test batch:
  - `HFRswiftTests/ObjCWrapperLoaderBehaviorTests.swift`
  - covers `ObjCFavoritesLoader`, `ObjCMPTopicsLoader`, `ObjCTopicPageLoader` success/failure/mapping behavior
- [x] Expanded wrapper/service behavior tests:
  - `HFRswiftTests/ObjCWrapperLoaderBehaviorTests.swift` now also covers `ObjCForumsLoader` and `ObjCForumTopicsLoader` forwarding/mapping
  - `HFRswiftTests/MessageWebActionHandlerTests.swift` extended for paging edges (`begin`/`end`), `file://` internal routing, and navigation-type gating
  - `HFRswiftTests/ObjCAccountSessionServiceTests.swift` added for `ObjCAccountSessionService` mapping and side effects (main account, delete index, cookies/hash context, add-account flow)
- [x] Local test-build validation completed for wrappers/services:
  - `xcodebuild ... build-for-testing` on `generic/platform=iOS` succeeded with `HFRswiftTests` included
- [x] CI wrapper gate added:
  - `.github/workflows/wrapper-tests.yml`
  - runs `xcodebuild ... build-for-testing` for `HFRswift`/`HFRswiftTests` on PR/push

## Remaining S0 tasks
- [x] Add an XCTest target for wrapper tests in Xcode project.
- [x] Keep test scaffolding on XCTest only (removed default Swift Testing placeholder file).
- [x] Execute wrapper-focused tests in CI once test target is created.
- [x] Expand wrapped ObjC behavior tests further (web action routing, reply/session side effects, plus-path wrappers).

## Deferred (tracked, non-blocking S0)
- [ ] `SDWebImage` removal/replacement plan:
  - Keep current ObjC/UIKit usage for now.
  - Prefer native SwiftUI image loading (`AsyncImage`/equivalent) for new SwiftUI views.
  - Remove `SDWebImage` only after remaining ObjC call sites are migrated.
  - Target phase for active cleanup: S2+ (not blocking S0 completion).
- [ ] Re-enable full simulator `xcodebuild test` execution in CI after `SDWebImage` simulator compatibility is restored.

## Acceptance for S0 completion
1. Minimal wrapper/policy tests run before push (CI wrapper gate remains optional/bonus).
2. No new direct SwiftUI instantiation of wrapped ObjC controllers.
3. Offline legacy flow remains de-scoped.
4. Preview policy adopted in migrated SwiftUI screens.
