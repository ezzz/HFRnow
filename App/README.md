# App

The iOS app target (SwiftUI, iOS 27), `App/SwiftHFR.xcodeproj` ([ADR 0012](../docs/adr/0012-app-project-file-strategy.md), [LOT-080](../docs/lots/LOT-080-app-target.md)).

| Path | Content |
|---|---|
| `SwiftHFR.xcodeproj` | Project and shared scheme `SwiftHFR`; links the local package `../Packages/HFRKit` |
| `SwiftHFR/` | App sources and assets (folder-synchronized: add files here, the project file does not change) |
| `SwiftHFRTests/` | Unit tests (Swift Testing), hosted by the app |

Build and test on the simulator (unsigned, as CI does):

```sh
xcodebuild build test -project App/SwiftHFR.xcodeproj -scheme SwiftHFR \
  -destination 'platform=iOS Simulator,OS=27.0,name=iPhone 18 Pro' CODE_SIGNING_ALLOWED=NO
```

A dependency change in `HFRKit` re-resolves and commits this project's `Package.resolved` in the same PR (CI never resolves packages):

```sh
xcodebuild -resolvePackageDependencies -project App/SwiftHFR.xcodeproj
```

Signing is automatic with the team `QMG83DG7YP` and bundle id `hfrplus.red.super`; a device build needs that team's account in Xcode. Never commit certificates, profiles or `xcuserdata/`.
