//
//  RootSidebarToggle.swift
//  HFRswift
//
//  Show / hide button of the root sidebar, in the navigation bar of the content column.
//

import SwiftUI

struct RootSidebarToggle {
    var isAvailable = false
    var isVisible = false
    var toggle: @MainActor () -> Void = {}
}

private struct RootSidebarToggleKey: EnvironmentKey {
    static let defaultValue = RootSidebarToggle()
}

extension EnvironmentValues {
    var rootSidebarToggle: RootSidebarToggle {
        get { self[RootSidebarToggleKey.self] }
        set { self[RootSidebarToggleKey.self] = newValue }
    }
}

private struct RootTabBarHiddenInRegularWidth: ViewModifier {
    @Environment(\.rootSidebarToggle) private var sidebar

    func body(content: Content) -> some View {
        content.toolbar(sidebar.isAvailable ? .hidden : .automatic, for: .tabBar)
    }
}

private struct RootSidebarRevealButton: ViewModifier {
    @Environment(\.rootSidebarToggle) private var sidebar
    @AppStorage(NatifAppearance.accentKey) private var accentID = 0

    func body(content: Content) -> some View {
        content
            .rootTabBarHiddenInRegularWidth()
            .toolbar {
            if sidebar.isAvailable {
                ToolbarItem(placement: .topBarLeading) {
                    Button(sidebar.isVisible ? "Masquer la barre latérale" : "Afficher la barre latérale", systemImage: "sidebar.leading") {
                        sidebar.toggle()
                    }
                    // Bar items keep the tint they were created with.
                    .id(accentID)
                }
            }
        }
    }
}

extension View {
    /// Adds the show / hide sidebar button to the navigation bar in regular width. The item is
    /// always present there: adding / removing it made the Duo navigation bar drop its items.
    func rootSidebarRevealButton() -> some View {
        modifier(RootSidebarRevealButton())
    }

    /// Regular width: the sidebar covers `leadingInset` points of the tab content.
    func rootTabContent(usesRootSidebar: Bool, leadingInset: CGFloat) -> some View {
        padding(.leading, leadingInset)
    }

    /// Regular width: the tab bar is replaced by the sidebar. Applied on each screen rather than on
    /// the tab content: an outer `.automatic` there overrode the `.hidden` of pushed topic pages
    /// on iPhone, which kept the tab bar over their bottom buttons.
    func rootTabBarHiddenInRegularWidth() -> some View {
        modifier(RootTabBarHiddenInRegularWidth())
    }
}
