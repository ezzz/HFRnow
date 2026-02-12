# S0 Wrapper Test Matrix

## Scope
Primary target: Objective-C classes wrapped and consumed by SwiftUI.

## Priority P0
1. `MessagesTableViewController` (wrapped via `TopicPageLoading`)
- fetch success returns non-empty HTML and optional answer URL mapping
- fetch error propagates correctly to Swift caller
- anchor parameter forwarding

2. `ParseMessagesOperation` (indirectly through message loading stack)
- parsing lifecycle callbacks fire (`didStartParsing`, `didFinishParsing`)
- first/last page metadata extraction remains stable

3. `FavoritesTableViewController` (wrapped via `FavoritesLoading`)
- completion mapping from ObjC to Swift types
- error propagation

4. `HFRMPViewController` (wrapped via `MPTopicsLoading`)
- completion mapping from ObjC to Swift types
- error propagation

## Priority P1
1. `PlusTableViewController` routes remain callable from wrapper while migration is in progress.
2. Account/session wrappers around `MultisManager` (when adapter is introduced).

## Test style guidance
- Prefer adapter-level unit tests first (deterministic and fast).
- Add integration tests around wrapped ObjC classes once XCTest target is available.
- Keep fixtures deterministic and avoid network in unit tests.

## CI gate (target state)
- Wrapper tests mandatory on pull requests touching:
  - `HFRswift/Wrapped/*`
  - `HFRswift/Swift/*` wrappers/adapters
  - ObjC controllers directly called from Swift

## Current S0 status
- Initial XCTest files were added under `HFRswiftTests/`.
- `HFRswiftTests` target is now present and points to the synchronized `HFRswiftTests/` folder.
- Local automation via `xcodeproj` remains incompatible with ISA `PBXFileSystemSynchronizedRootGroup`, so target maintenance should be done directly in Xcode for now.
