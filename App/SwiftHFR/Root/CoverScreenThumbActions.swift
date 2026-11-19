import SwiftUI

// Port of HFRswift/Swift/CoverScreenThumbActions.swift (`refreshToolbarPlacement`, `coverScreenBottomBackButton`, `:1-35`) and
// HFRswift/Swift/MainToolbar.swift (`MainToolbarContent`, the « Actualiser » item, `:46-58`) @ 87fe0d1c. Differences (GAP-713,
// LOT-147): « Actualiser » goes to the bottom on all four lists, where legacy's Catégories and Messages draw it at the top (a
// legacy defect reported on #372, not ported); off the cover screen Catégories and Messages have no top-bar « Actualiser » (pull to
// refresh only, as before), so theirs exists on the cover screen alone.
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
    /// On the iPhone Duo cover screen, adds a « Retour » button at the bottom of the toolbar column of a pushed screen, within
    /// thumb reach (`CoverScreenThumbActions.swift:11-35` @ 87fe0d1c). The system back button and the edge swipe stay.
    func coverScreenBottomBackButton() -> some View {
        modifier(CoverScreenBottomBackButton())
    }
}

private struct CoverScreenBottomBackButton: ViewModifier {
    @Environment(\.phoneDisplayKind) private var phoneDisplayKind
    @Environment(\.isPresented) private var isPresented
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content.toolbar {
            if isPresented && phoneDisplayKind.placesThumbActionsAtBottom {
                ToolbarItem(placement: .bottomBar) {
                    Button("Retour", systemImage: "chevron.backward") { dismiss() }
                }
            }
        }
    }
}
