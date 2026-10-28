# LOT-080 — iOS app target

- **Module:** App (Xcode target `SwiftHFR`)
- **Difficulty / model:** medium · Opus 5.5 → Fable 5.1
- **Issue:** none yet (tracked in [LOTS.md](../LOTS.md)); old francoisgn/ios-app_SwiftHFR#94

## Legacy sources
Read-only reference on ezzz/HFRnow `master`:
- `SuperHFRplus.xcodeproj/project.pbxproj` — the SwiftUI target `HFRswift`: bundle id `hfrplus.red.super`, display name `HFR` (`INFOPLIST_KEY_CFBundleDisplayName = HFR`), development region `fr`, `MARKETING_VERSION = 4.0.3`.
- `HFRswift/Info.plist` — `CFBundleDisplayName` `HFR`.

## Behaviour
- `App/SwiftHFR.xcodeproj`: plain project with folder-synchronized groups ([ADR 0012](../adr/0012-app-project-file-strategy.md)). Targets:
  - `SwiftHFR` (iOS app, iOS 27.0 minimum, iPhone and iPad), links the five `HFRKit` products from the local package `../Packages/HFRKit`.
  - `SwiftHFRTests` (unit-test bundle hosted by the app), Swift Testing.
- Shared scheme `SwiftHFR`; configurations Debug and Release.
- Swift 6 language mode, strict concurrency `complete`, warnings as errors. No default `MainActor` isolation: types that need the main actor say so (AGENTS.md §4).
- Generated Info.plist: display name `HFR` (as legacy), generated launch screen, scene manifest; empty `AppIcon` and `AccentColor` placeholders.
- Signing: automatic, team `QMG83DG7YP`, bundle id `hfrplus.red.super` (audit Q-1). Tests bundle id `hfrplus.red.super.tests`.
- Placeholder UI: `RootView` lists the linked engine modules (`EngineInfo.linkedModules`, read from each module's `moduleName`). LOT-081/082 replace it.
- CI job `App build + tests (iOS 27 simulator)` on `xcode-27`: picks an iPhone simulator on the iOS 27.0 runtime (falls back to any iOS 27 runtime), runs `xcodebuild build test` unsigned, then a Release build for `generic/platform=iOS` unsigned. Package resolution is frozen to the committed `Package.resolved`.

## Edge cases
- Device signing needs the operator's Apple account: the local signed build fails with "No profiles for 'hfrplus.red.super'" until a development profile exists for the team (Xcode → Settings → Accounts, or `-allowProvisioningUpdates` run by the operator). CI never signs.
- `MARKETING_VERSION = 5.0` is a placeholder above the legacy 4.0.3: the release version is set by the release lot.

## Fixtures
None: no HFR page is read.

## Tests
`App/SwiftHFRTests/EngineInfoTests.swift`:
- `linksEveryHFRKitModule` — the app sees all five engine modules, in dependency order.
- `engineRunsInsideTheAppHost` — calls `HFRParsing.documentTitle` (SwiftSoup) from the app-hosted test bundle, so the package is linked and runs on iOS, not only compiled.

## Intentional differences from legacy
- Project name `SwiftHFR` and a new project file (ADR 0012) instead of the legacy `SuperHFRplus.xcodeproj` (ADR 0004).
- No Carthage, no Objective-C, no extensions yet.

## Learnings
- A folder-synchronized Xcode project can be written by hand (object version 77) and builds with `xcodebuild` on Xcode 27.1 with no generator.
- A test bundle hosted by the app can `import` an HFRKit module the app links without linking it again.
