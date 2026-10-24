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

private struct RootSidebarRevealButton: ViewModifier {
    @Environment(\.rootSidebarToggle) private var sidebar

    func body(content: Content) -> some View {
        content.toolbar {
            if sidebar.isAvailable {
                ToolbarItem(placement: .topBarLeading) {
                    Button(sidebar.isVisible ? "Masquer la barre latérale" : "Afficher la barre latérale", systemImage: "sidebar.leading") {
                        sidebar.toggle()
                    }
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

    /// Regular width: the tab bar is replaced by the sidebar, which covers `leadingInset` points.
    func rootTabContent(usesRootSidebar: Bool, leadingInset: CGFloat) -> some View {
        padding(.leading, leadingInset)
            .toolbar(usesRootSidebar ? .hidden : .automatic, for: .tabBar)
    }
}
