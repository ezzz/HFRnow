# LOT-146 — iPad multi-window (M4)

- **Module:** App
- **Difficulty / model:** medium (Sonnet → Opus)
- **Issue:** [#236](https://github.com/ezzz/HFRnow/issues/236) · **Milestone:** M4, backport of legacy evolution (operator, 2026-11-09, [#655](https://github.com/ezzz/HFRnow/issues/655))
- **Depends on:** LOT-170 (#296, the root view each window shows). No longer LOT-145 (#235, M5): legacy has no per-window state restoration (below).

Stub written with the M4 move of #655. `UIApplicationSupportsMultipleScenes` is false at `2440d79` (`HFRswift/Info.plist:206-207`) and true at `2fe43da3` (`afec5433`, "Enable iPad multi-window support"), so a port of legacy evolution. The author completes the spec before coding (AGENTS.md §5).

## Legacy sources
At `2fe43da3`:

| Legacy @ `2fe43da3` | Behaviour |
|---|---|
| `HFRswift/Info.plist:204-208` | `UIApplicationSceneManifest` → `UIApplicationSupportsMultipleScenes` `true`: the system offers new windows of the app (iPad) |
| `HFRswift/Swift/HFRswiftApp.swift:24-36` | one `WindowGroup { RootTabView() }`: every window starts a fresh root (tab bar or split, by its own size classes); the app delegate and its singletons are shared by every window |
| `git grep -n 'SceneStorage\|NSUserActivity\|openWindow\|handlesExternalEvents' 2fe43da3 -- HFRswift` | no match: no per-window state restoration, no "open in a new window" action, no drag of a topic to a new window |

## Legacy counterpart (app lots)
To write by the author (`// Port of HFRswift/Swift/HFRswiftApp.swift (HFRswiftApp) @ 2fe43da3. Differences: …`, GAP-219).

## UX evolutions (app lots)
None planned: same UX as legacy at `2fe43da3`. "Open in a new window", a dragged topic and per-window restoration are not in legacy: they stay with LOT-145 (M5).

## Behaviour
To write. What every window shares (accounts and the current session, settings, caches, the MP poll) and what each owns (navigation, selection, the reader) is the core of the spec: legacy shares its singletons, check that SwiftHFR's `@MainActor` models do not assume one scene (LOT-081 `AccountsModel`, LOT-140 background check, LOT-170 root).

## Edge cases
To write (two windows on one topic, logging out in one window, an MP notification with two windows open).

## Fixtures
None: no HFR request.

## Intentional differences from legacy
To write.

## Learnings
To copy into AGENTS.md §11 when the lot closes.
