import SwiftUI
import UIKit

/// A list whose screen loads it when it appears (`onAppear`), and whose load in flight can be stopped and asked again (#1404).
@MainActor
protocol SceneAwareList: AnyObject {
    /// The list became visible: its own rule for a first load or a refresh.
    func onAppear() async
    /// Stops the load in flight, keeping what is shown, and remembers it (`hasSuspendedLoad`); true when there was one.
    func suspendLoad() -> Bool
    /// A load stopped by `suspendLoad()` that nothing replaced since: `retry()` asks for it again.
    var hasSuspendedLoad: Bool { get }
    /// Asks again for the page the last load asked for.
    func retry() async
}

extension TopicListModel: SceneAwareList {
    func suspendLoad() -> Bool { loader.suspend() }
    var hasSuspendedLoad: Bool { loader.wasSuspended }
}

extension MessageListModel: SceneAwareList {
    func suspendLoad() -> Bool {
        guard loader.isLoading else { return false }
        // As `chooseSegment` stops a segment search: `loadCount` moves first, so the search's loop, seeing a load that applied
        // nothing, does not ask for the page again in the background (r1414 finding 1); `retry()` resumes it on return.
        loadCount += 1
        return loader.suspend()
    }

    var hasSuspendedLoad: Bool { loader.wasSuspended }
}

extension EnvironmentValues {
    /// The window went to the background and is not active again yet (#1404), as `SceneAwayTracking` above the root says.
    @Entry var sceneIsAway = false
}

/// Tells the views under it whether their window is away (`\.sceneIsAway`, #1404): from a move to `.background` until the
/// next `.active`. iOS lays a backgrounded app out again for its app-switcher snapshots (on the iPhone Duo in the other size
/// class), and a request sent then freezes once the phone locks (device pass of #1388).
///
/// Only `.background` starts it: an inactive window (the notification permission prompt at the first launch, Control Center)
/// is on screen and its requests run. It follows the moves, not the phase alone: a view hosted outside a SwiftUI scene reads
/// the default phase, `.background`, all along. Before the first move, a window counts as away when its phase and the app
/// both are in the background (a root first built there), from the first body on, so its lists' first `task` sees it.
struct SceneAwayTracking: ViewModifier {
    /// Whether the app is in the background; the app's state, a fixed answer in tests.
    let appIsInBackground: @MainActor () -> Bool
    @Environment(\.scenePhase) private var scenePhase
    /// The window has moved to `.background` or `.active` since it was built: `movedAway` then says which came last.
    @State private var hasMoved = false
    @State private var movedAway = false

    func body(content: Content) -> some View {
        let isAway = hasMoved ? movedAway : scenePhase == .background && appIsInBackground()
        content
            .environment(\.sceneIsAway, isAway)
            .onChange(of: scenePhase) { _, phase in
                guard phase != .inactive else { return }
                hasMoved = true
                movedAway = phase == .background
            }
    }
}

/// Runs a list's `onAppear` when the view appears or `id` changes, but never while its window is away (#1404).
///
/// An appearance while away (a list rebuilt for a snapshot) loads once the window is active again, and a load in flight when
/// the window goes away is stopped (rows and error kept as they were) and asked again on return, instead of surfacing the
/// `timedOut` (25–56 s on the Duo) of a request iOS froze. The stopped load is remembered by the model, so a screen rebuilt
/// meanwhile (a fold made while away swaps the root on return) asks for it again too.
struct SceneAwareListLoad<ID: Equatable>: ViewModifier {
    let model: any SceneAwareList
    let id: ID
    @Environment(\.sceneIsAway) private var isAway
    /// Bumped on return to make the `task` run again for what waited.
    @State private var wakes = 0
    /// An appearance happened while away: `onAppear` runs on return.
    @State private var appearWaits = false

    private struct Key: Equatable {
        let id: ID
        let wakes: Int
    }

    func body(content: Content) -> some View {
        content
            .task(id: Key(id: id, wakes: wakes)) {
                guard !isAway else {
                    appearWaits = true
                    return
                }
                appearWaits = false
                // The stopped load's page, not `onAppear`'s rule: a forum list shown again would keep the page before it.
                if model.hasSuspendedLoad { await model.retry() } else { await model.onAppear() }
            }
            .onChange(of: isAway) { _, away in
                if away {
                    _ = model.suspendLoad()
                } else if appearWaits || model.hasSuspendedLoad {
                    wakes += 1
                }
            }
    }
}

extension View {
    /// Says under it whether the window is away (`SceneAwayTracking`, #1404); applied above each window's root.
    func tracksSceneAway(
        appIsInBackground: @escaping @MainActor () -> Bool = { UIApplication.shared.applicationState == .background }
    ) -> some View {
        modifier(SceneAwayTracking(appIsInBackground: appIsInBackground))
    }

    /// Loads `model` as its screen appears, deferred while the window is away (`SceneAwareListLoad`, #1404).
    func sceneAwareListLoad<ID: Equatable>(_ model: any SceneAwareList, id: ID) -> some View {
        modifier(SceneAwareListLoad(model: model, id: id))
    }
}
