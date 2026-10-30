import Foundation
import HFRStorage
import SwiftUI

/// The root navigation: the legacy bottom tab bar, or the legacy sidebar on a regular-width iPad (`MainWindow.swift:1353-1355`,
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
        .task { await model.forums.loadIfNeeded() }
        .task {
            // Réglages writes the settings to `UserDefaults`: the badge and the tab bar follow without a relaunch.
            for await _ in NotificationCenter.default.notifications(named: UserDefaults.didChangeNotification) {
                model.reloadSettings()
            }
        }
        .onChange(of: model.selectedDestination, initial: true) { _, destination in lastDestination = destination }
    }

    private var usesSidebarRoot: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && sizeClass == .regular
    }
}
