import Foundation
import HFRStorage
import SwiftUI

// Port of HFRswift/Swift/MainWindow.swift (RootTabView.usesSidebarRoot) @ 2440d79, and its tab root on a landscape Pro Max
// (`compactTabRoot`, #431) @ 87fe0d1c. Differences: none in the condition; the foldable inner screen (regular in both
// dimensions) keeps the tab bar (GAP-215).
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
    /// Where the app icon badge goes: the notification center in the app, a recorder in tests.
    private let badges: any MPNotificationDelivering
    /// The app icon badge iOS did not show (no badge permission yet, the first launch's count can come under the permission
    /// prompt, or refused), set again when the window is back on screen (#1060): while refused, one settings read and one
    /// write per foreground.
    @State private var badgeIsPending = false
    /// The last destination, kept by `RootView` across session generations (the root is rebuilt on each).
    @Binding private var lastDestination: SidebarDestination?

    init(
        environment: AppEnvironment, lastDestination: Binding<SidebarDestination?> = .constant(nil),
        store: any SettingsStore = UserDefaultsSettingsStore(), badges: any MPNotificationDelivering = MPNotificationCenter()
    ) {
        self.environment = environment
        self.badges = badges
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
        // EXPERIMENTAL(mpDarkTopic, #1014): the account's model reads the option from here.
        .onAppear { model.mpStorage?.experimental = experimental }
        // The blocklist's MPStorage sync (LOT-131): its changes in order for the session, and its questions.
        .task { await model.blocklistSync?.run() }
        .blocklistSyncQuestions()
        .environment(model.blocklistSync)
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
        .onChange(of: scenePhase) { _, phase in
            takeNotification()
            // Legacy sets the badge again each time the app is back on screen (`MainWindow.swift:2588-2593` @ 87fe0d1c); only a
            // badge iOS did not show is set again here, so a shown badge never rewrites a newer count a background check set
            // (GAP-192, #1060). Limit: a pending badge may rewrite such a count once, when the check ran after badges were turned
            // on; the next page load corrects it.
            if phase == .active, badgeIsPending { setBadge(model.appIconBadge) }
        }
        // The app icon badge follows the Messages badge (legacy `MainWindow.swift:1779-1784`, GAP-192).
        .onChange(of: model.appIconBadge, initial: true) { _, badge in setBadge(badge) }
        // A new session rebuilds the root: a filter run of the discarded one would keep reading pages with no control.
        .onDisappear {
            model.categories.filtering.cancel()
            model.favorites.filtering.cancel()
        }
    }

    /// Hands `badge` to iOS and records whether it was shown; nil (no page gave a count yet) leaves the icon alone.
    private func setBadge(_ badge: Int?) {
        guard let badge else { return }
        Task {
            let shown = await badges.setBadge(badge)
            // Only the answer for the badge the root shows now counts: an earlier write may finish after a later one.
            if badge == model.appIconBadge { badgeIsPending = !shown }
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

    /// The width class the tab bar root's split views are given (UXD-24, #431). A Plus or Pro Max iPhone in landscape is
    /// regular width with a compact height: legacy keeps its tab root there, a stack per tab, so the topic is pushed over the
    /// list, full width, and hides the tab bar (`MainWindow.swift:1380-1388`, `usesSidebarRoot`; `:1792-1847`, `rootContainer`
    /// and `rootTabs`; `Favorites.swift:665`, the tab's `NavigationStack`; `MessagesView.swift:4024` @ 87fe0d1c). A compact
    /// width collapses the split to that stack. An iPad (Slide Over, Split View) and an iPhone regular in both dimensions (a
    /// foldable's inner screen, GAP-215) keep their own width.
    static func tabSplitSizeClass(
        idiom: UIUserInterfaceIdiom, horizontal: UserInterfaceSizeClass?, vertical: UserInterfaceSizeClass?
    ) -> UserInterfaceSizeClass? {
        idiom == .phone && vertical == .compact ? .compact : horizontal
    }
}

extension EnvironmentValues {
    /// The idiom `TabSplitWidth` decides for; nil is the device's. Tests set it to check both rules on one simulator.
    @Entry var tabSplitIdiom: UIUserInterfaceIdiom?
}

/// Gives a tab's split view the width class of `RootNavigationView.tabSplitSizeClass` (#431): on a large iPhone in landscape
/// the split collapses to a stack and the reader takes the full width, as legacy. Applied by each tab's own split view
/// (Catégories, Favoris, Messages); the Plus tab is a stack, whose readers keep the regular width (GAP-008, UXD-02).
struct TabSplitWidth: ViewModifier {
    @Environment(\.tabSplitIdiom) private var idiomOverride
    @Environment(\.horizontalSizeClass) private var horizontal
    @Environment(\.verticalSizeClass) private var vertical

    func body(content: Content) -> some View {
        let idiom = idiomOverride ?? UIDevice.current.userInterfaceIdiom
        return content.environment(
            \.horizontalSizeClass, RootNavigationView.tabSplitSizeClass(idiom: idiom, horizontal: horizontal, vertical: vertical)
        )
    }
}
