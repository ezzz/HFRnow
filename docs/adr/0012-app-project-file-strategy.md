# 0012 — App project file: a plain Xcode project with folder-synchronized groups

**Status:** Accepted — 2026-10-27 (LOT-080)

## Context
The iOS app target (`App/`, iOS 27) needs a project file that several agents and contributors edit in parallel, that CI builds with `xcodebuild` on the `xcode-27` runners, and that links the local `Packages/HFRKit` engine.
Classic Xcode projects list every source file in `project.pbxproj`: each new file is a project-file change, and parallel branches conflict there on almost every merge.
AGENTS.md ground rule 3 forbids a new dependency or tool without an ADR and the maintainer's approval.

## Decision
- `App/SwiftHFR.xcodeproj` is a **plain, checked-in Xcode project** (object version 77) whose source folders `App/SwiftHFR/` and `App/SwiftHFRTests/` are **folder-synchronized groups** (`PBXFileSystemSynchronizedRootGroup`): Xcode compiles whatever the folder holds, so adding, moving or deleting a Swift file never touches `project.pbxproj`.
- `HFRKit` is linked as a **local package reference** (`../Packages/HFRKit`); the app links all five products. SwiftSoup stays pinned by HFRKit (`exact: 2.14.3`); the app's `Package.resolved` is committed and CI builds with `-disableAutomaticPackageResolution`, so the app never resolves another version.
- One **shared scheme** `SwiftHFR` (build, test, run, archive) is committed; per-user state (`xcuserdata/`, `*.xcuserstate`) is git-ignored.
- Build settings live in the project file, not in `.xcconfig` files, until a setting must differ per machine. The untracked key configuration of [ADR 0007](0007-third-party-api-keys.md) is added as an `.xcconfig` when the first key-using feature lands.
- Signing: **automatic**, team `QMG83DG7YP`, bundle id `hfrplus.red.super` ([audit Q-1](../audit/README.md)). No certificate, profile or account data is committed. CI builds **unsigned** (`CODE_SIGNING_ALLOWED=NO`) for the simulator and for a generic device.

## Alternatives rejected
| Option | Why not |
|---|---|
| Classic groups (every file listed in `project.pbxproj`) | Conflicts on every parallel lot that adds files; the reason this ADR exists |
| Generated project: XcodeGen, Tuist | A new tool on every machine and in CI (rule 3); the generated project is either committed (two sources of truth) or not (every session must generate first). Synchronized groups give the main benefit, small merges, without it |
| App as an SPM executable / `Package.swift` only | SwiftPM cannot produce a signed, App Store-ready iOS app bundle (Info.plist keys, asset catalogs, entitlements, extensions) |
| Re-using the legacy `SuperHFRplus.xcodeproj` | ADR 0004: the legacy app is an oracle, not a base; its project carries Carthage and Objective-C targets SwiftHFR does not port |

## Consequences
- Lots add files under `App/SwiftHFR/` without editing the project file; a project-file change (new target, setting, package) is rare and reviewed on its own.
- New targets (widgets, share extension) are added in Xcode and follow the same pattern: one synchronized folder per target.
- The app job in CI (`App build + tests (iOS 27 simulator)`) is not yet a required check: adding it to the [`dev-swift` ruleset](../../.github/rulesets/dev-swift.json) is the repository owner's action.
- CodeQL still analyzes only `HFRKit`: its Swift job runs on `macos-26` (Xcode 26), which cannot build an iOS 27 app target.
