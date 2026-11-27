import SwiftUI
import UIKit

/// A list whose screen loads it when it appears (`onAppear`), and whose load in flight can be stopped and asked again (#1404).
@MainActor
protocol SceneAwareList: AnyObject {
    /// The list became visible: its own rule for a first load or a refresh.
    func onAppear() async
    /// Stops the load in flight, keeping what is shown; true when there was one.
    func suspendLoad() -> Bool
    /// Asks again for the page the last load asked for.
    func retry() async
}

extension TopicListModel: SceneAwareList {
    func suspendLoad() -> Bool {
        guard loader.isLoading else { return false }
        loader.cancel()
        return true
    }
}

extension MessageListModel: SceneAwareList {
    func suspendLoad() -> Bool {
        guard loader.isLoading else { return false }
        loader.cancel()
        return true
    }
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
/// the default phase, `.background`, all along; a root first built in the background counts as away only when the app is.
struct SceneAwayTracking: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @State private var isAway = false

    func body(content: Content) -> some View {
        content
            .environment(\.sceneIsAway, isAway)
            .onAppear { isAway = scenePhase == .background && UIApplication.shared.applicationState == .background }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { isAway = true } else if phase == .active { isAway = false }
            }
    }
}

/// Runs a list's `onAppear` when the view appears or `id` changes, but never while its window is away (#1404).
///
/// An appearance while away (a list rebuilt for a snapshot) loads once the window is active again, and a load in flight when
/// the window goes away is stopped (rows and error kept as they were) and asked again on return, instead of surfacing the
/// `timedOut` (25–56 s on the Duo) of a request iOS froze.
struct SceneAwareListLoad<ID: Equatable>: ViewModifier {
    let model: any SceneAwareList
    let id: ID
    @Environment(\.sceneIsAway) private var isAway
    /// Bumped on return to make the `task` run again for what waited.
    @State private var wakes = 0
    /// An appearance happened while away: `onAppear` runs on return.
    @State private var appearWaits = false
    /// A load was stopped as the window went away: it is asked again on return.
    @State private var loadWasSuspended = false

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
                if loadWasSuspended {
                    // The stopped load's page, not `onAppear`'s rule: a forum list shown again would keep the page before it.
                    loadWasSuspended = false
                    await model.retry()
                } else {
                    await model.onAppear()
                }
            }
            .onChange(of: isAway) { _, away in
                if away {
                    if model.suspendLoad() { loadWasSuspended = true }
                } else if appearWaits || loadWasSuspended {
                    wakes += 1
                }
            }
    }
}

extension View {
    /// Says under it whether the window is away (`SceneAwayTracking`, #1404); applied above each window's root.
    func tracksSceneAway() -> some View {
        modifier(SceneAwayTracking())
    }

    /// Loads `model` as its screen appears, deferred while the window is away (`SceneAwareListLoad`, #1404).
    func sceneAwareListLoad<ID: Equatable>(_ model: any SceneAwareList, id: ID) -> some View {
        modifier(SceneAwareListLoad(model: model, id: id))
    }
}
