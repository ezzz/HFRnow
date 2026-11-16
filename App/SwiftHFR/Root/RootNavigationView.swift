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
        .environment(\.rootHasTabBar, Self.rootHasTabBar(idiom: UIDevice.current.userInterfaceIdiom, sizeClass: sizeClass))
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
