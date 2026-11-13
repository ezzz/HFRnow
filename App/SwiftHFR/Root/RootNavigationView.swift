import Foundation
import HFRStorage
import SwiftUI

// Port of HFRswift/Swift/MainWindow.swift (RootTabView.usesSidebarRoot) @ 2440d79. Differences: none in the condition.
/// The root navigation: the legacy bottom tab bar, or the legacy sidebar on a regular-width iPad (`MainWindow.swift:1132-1134` @ 2440d79,
/// `usesSidebarRoot`). A compact-width iPad (Slide Over, Split View) gets the tab bar, as legacy.
struct RootNavigationView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var model: RootModel
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
        .environment(\.rootHasTabBar, !usesSidebarRoot)
        .task { await model.forums.loadIfNeeded() }
        .task {
            // Réglages writes the settings to `UserDefaults`: the badge and the tab bar follow without a relaunch.
            for await _ in NotificationCenter.default.notifications(named: UserDefaults.didChangeNotification) {
                model.reloadSettings()
            }
        }
        .onChange(of: model.selectedDestination, initial: true) { _, destination in lastDestination = destination }
        // A new session rebuilds the root: a filter run of the discarded one would keep reading pages with no control.
        .onDisappear {
            model.categories.filtering.cancel()
            model.favorites.filtering.cancel()
        }
    }

    private var usesSidebarRoot: Bool {
        Self.usesSidebarRoot(idiom: UIDevice.current.userInterfaceIdiom, sizeClass: sizeClass)
    }

    /// Only an iPad at regular width: a Plus or Pro Max iPhone in landscape is regular width and keeps the tab bar.
    static func usesSidebarRoot(idiom: UIUserInterfaceIdiom, sizeClass: UserInterfaceSizeClass?) -> Bool {
        idiom == .pad && sizeClass == .regular
    }
}
