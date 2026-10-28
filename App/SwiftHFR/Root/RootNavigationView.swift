import HFRStorage
import SwiftUI

/// The root navigation: the legacy bottom tab bar, or the legacy sidebar on a regular-width iPad (`MainWindow.swift:1353-1355`,
/// `usesSidebarRoot`). A compact-width iPad (Slide Over, Split View) gets the tab bar, as legacy.
struct RootNavigationView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var model: RootModel
    private let reader: ReaderServices

    init(environment: AppEnvironment, store: any SettingsStore = UserDefaultsSettingsStore()) {
        reader = environment.reader
        _model = State(initialValue: RootModel(environment: environment, store: store))
    }

    var body: some View {
        Group {
            if usesSidebarRoot {
                RootSidebarView(model: model, reader: reader)
            } else {
                RootTabsView(model: model, reader: reader)
            }
        }
        .task { await model.forums.loadIfNeeded() }
    }

    private var usesSidebarRoot: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && sizeClass == .regular
    }
}
