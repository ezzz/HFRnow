import SwiftUI

// Port of HFRswift/Swift/CoverScreenThumbActions.swift (`refreshToolbarPlacement`, `coverScreenBottomBackButton`, `:1-35`) and
// HFRswift/Swift/MainToolbar.swift (`MainToolbarContent`, the « Actualiser » item, `:46-58`) @ 87fe0d1c. Differences (GAP-713,
// LOT-147): iOS 27.2 stacks a list's `.bottomBar` items in the cover screen's strip right after the top items, which is legacy's
// measured defect (« Actualiser » at the top of Catégories and Messages, Mac check of `87fe0d1c` on #372, checks 2b, 2e); a flexible
// spacer pushes them down to the tab bar on all four lists (measured on the Duo simulator, #1239). Off the cover screen Catégories
// and Messages have no top-bar « Actualiser » (pull to refresh only, as before), so theirs exists on the cover screen alone.
extension PhoneDisplayKind {
    /// Whether a list's « Actualiser » and a pushed screen's « Retour » go to the bottom of the toolbar column (the cover screen,
    /// thumb reach) instead of the top (`PhoneDisplayPolicy.placesThumbActionsAtBottom`).
    var placesThumbActionsAtBottom: Bool {
        PhoneDisplayPolicy.placesThumbActionsAtBottom(kind: self)
    }
}

/// « Actualiser » of a list, the same button in either placement (legacy `refreshToolbarButton`, `MainWindow.swift:381-393`).
struct RefreshToolbarButton: View {
    let isLoading: Bool
    var isEnabled = true
    let refresh: () async -> Void

    var body: some View {
        Button { Task { await refresh() } } label: {
            Label { Text("Actualiser") } icon: { ToolbarRefreshIcon(isLoading: isLoading) }
        }
        .disabled(!isEnabled)
    }
}

extension View {
    /// On the iPhone Duo cover screen, puts a list's thumb actions at the bottom of the toolbar column, within reach: a flexible
    /// spacer, « Retour » when the list is a pushed screen (`CoverScreenThumbActions.swift:11-35` @ 87fe0d1c; the system back
    /// button and the edge swipe stay), then `refresh` (legacy `MainWindow.swift:848-852`). Nothing elsewhere.
    func coverScreenThumbActions(@ViewBuilder refresh: () -> some View) -> some View {
        modifier(CoverScreenThumbActions(refresh: refresh()))
    }

    /// On the iPhone Duo cover screen, adds « Retour » to the bottom-bar items of a pushed topic, which iOS lays right above its
    /// page controls in the column (legacy Mac check 2c): no spacer, no refresh (the topic keeps its top « Actualiser »).
    func coverScreenThumbActions() -> some View {
        modifier(CoverScreenThumbActions<EmptyView>(refresh: nil))
    }
}

private struct CoverScreenThumbActions<Refresh: View>: ViewModifier {
    let refresh: Refresh?
    @Environment(\.phoneDisplayKind) private var phoneDisplayKind
    @Environment(\.isPresented) private var isPresented
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content.toolbar {
            if phoneDisplayKind.placesThumbActionsAtBottom {
                if refresh != nil { ToolbarSpacer(.flexible, placement: .bottomBar) }
                if isPresented {
                    ToolbarItem(placement: .bottomBar) {
                        Button("Retour", systemImage: "chevron.backward") { dismiss() }
                    }
                }
                if let refresh { ToolbarItem(placement: .bottomBar) { refresh } }
            }
        }
    }
}
