import Foundation
import HFRStorage
import SwiftUI

// Port of HFRswift/Swift/MainWindow.swift (RootTabView.usesSidebarRoot) @ 2440d79. Differences: none in the condition.
/// The root navigation: the legacy bottom tab bar, or the legacy sidebar on a regular-width iPad (`MainWindow.swift:1132-1134` @ 2440d79,
/// `usesSidebarRoot`). A compact-width iPad (Slide Over, Split View) gets the tab bar, as legacy.
struct RootNavigationView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// This window's phase (read inside the scene, not in the `App`): only a window on screen opens a notification's target.
    @Environment(\.scenePhase) private var scenePhase
    @Environment(ExperimentalSettings.self) private var experimental: ExperimentalSettings?
    @State private var model: RootModel
    /// Taps on MP notifications, taken once the root is built (LOT-140).
    @State private var notificationRouter = MPNotificationRouter.shared
    private let environment: AppEnvironment
    /// The last destination, kept by `RootView` across session generations (the root is rebuilt on each).
    @Binding private var lastDestination: SidebarDestination?

    init(
        environment: AppEnvironment, lastDestination: Binding<SidebarDestination?> = .constant(nil),
        store: any SettingsStore = UserDefaultsSettingsStore()
    ) {
        self.environment = environment
        _lastDestination = lastDestination
        _model = State(initialValue: RootModel(environment: environment, store: store, initial: lastDestination.wrappedValue))
    }

    var body: some View {
        Group {
            if usesSidebarRoot {
                RootSidebarView(model: model, environment: environment)
            } else {
                RootTabsView(model: model, environment: environment)
            }
        }
        .environment(\.rootHasTabBar, Self.rootHasTabBar(idiom: UIDevice.current.userInterfaceIdiom, sizeClass: sizeClass))
        .task { await model.forums.loadIfNeeded() }
        // EXPERIMENTAL(mpStorageSwitches, #859): the account's model reads the option from here.
        .onAppear { model.mpStorage?.experimental = experimental }
        .task {
            // Réglages writes the settings to `UserDefaults`: the badge and the tab bar follow without a relaunch.
            for await _ in NotificationCenter.default.notifications(named: UserDefaults.didChangeNotification) {
                model.reloadSettings()
            }
        }
        .onChange(of: model.selectedDestination, initial: true) { _, destination in lastDestination = destination }
        // A tap on an MP notification, including the one that launched the app (LOT-140, GAP-011).
        // With several windows (LOT-146) only one takes it, and not one in the background: the tap waits in the router until a
        // window is active, whether it arrived before the root was built or while the window was away.
        .onChange(of: notificationRouter.pending, initial: true) { takeNotification() }
        .onChange(of: scenePhase) { takeNotification() }
        // The app icon badge follows the Messages badge (legacy `MainWindow.swift:1779-1784`, GAP-192).
        .onChange(of: model.appIconBadge, initial: true) { _, badge in
            guard let badge else { return }
            Task { await MPNotificationCenter().setBadge(badge) }
        }
        // A new session rebuilds the root: a filter run of the discarded one would keep reading pages with no control.
        .onDisappear {
            model.categories.filtering.cancel()
            model.favorites.filtering.cancel()
        }
    }

    private func takeNotification() {
        guard let destination = Self.takeNotification(phase: scenePhase, from: notificationRouter) else { return }
        Task { await model.open(destination) }
    }

    /// Whether a window in `phase` opens the target of an MP notification: every window's root watches the one router, and
    /// the first to see a tap used to take it, even one hidden behind the others. Only a window that is on screen does.
    static func mayOpenNotification(phase: ScenePhase) -> Bool {
        phase == .active
    }

    /// The target of the pending tap when a window in `phase` may open it; the tap stays in `router` otherwise.
    static func takeNotification(phase: ScenePhase, from router: MPNotificationRouter) -> MPNotificationDestination? {
        mayOpenNotification(phase: phase) ? router.consume() : nil
    }

    private var usesSidebarRoot: Bool {
        Self.usesSidebarRoot(idiom: UIDevice.current.userInterfaceIdiom, sizeClass: sizeClass)
    }

    /// What the lists read (`\.rootHasTabBar`, #565): the one decision between the sidebar and the tab bar root, so the pager's
    /// placement can never disagree with the root that was built.
    static func rootHasTabBar(idiom: UIUserInterfaceIdiom, sizeClass: UserInterfaceSizeClass?) -> Bool {
        !usesSidebarRoot(idiom: idiom, sizeClass: sizeClass)
    }

    /// Only an iPad at regular width: a Plus or Pro Max iPhone in landscape is regular width and keeps the tab bar.
    static func usesSidebarRoot(idiom: UIUserInterfaceIdiom, sizeClass: UserInterfaceSizeClass?) -> Bool {
        idiom == .pad && sizeClass == .regular
    }
}
