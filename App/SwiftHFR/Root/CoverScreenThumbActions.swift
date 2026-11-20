import SwiftUI

// Port of HFRswift/Swift/CoverScreenThumbActions.swift (`refreshToolbarPlacement`, `coverScreenBottomBackButton`, `:1-35`) and
// HFRswift/Swift/MainToolbar.swift (`MainToolbarContent`, the « Actualiser » item, `:46-58`) @ 87fe0d1c. Differences (GAP-713,
// LOT-147): no list has an « Actualiser » button in SwiftHFR, on the cover screen either: a pull refreshes it (operator, #1206 for
// the topic lists, #1239 for Catégories and Messages, following #1206), so `refreshToolbarPlacement` has nothing to move and only
// « Retour » is added. iOS 27.2 lays a list's `.bottomBar` items in the cover screen's strip right after the top items, which is
// legacy's measured defect (« Actualiser » at the top of Catégories and Messages, Mac check of `87fe0d1c` on #372, checks 2b, 2e);
// a flexible spacer, honoured once the trailing slot holds an item (`AccountMenuButton.placement(on:)`), pushes « Retour » down to
// the tab bar (measured on the Duo simulator, #1239).
extension PhoneDisplayKind {
    /// Whether a pushed screen's « Retour » goes to the bottom of the toolbar column (the cover screen, thumb reach) instead of
    /// the top (`PhoneDisplayPolicy.placesThumbActionsAtBottom`).
    var placesThumbActionsAtBottom: Bool {
        PhoneDisplayPolicy.placesThumbActionsAtBottom(kind: self)
    }
}

extension View {
    /// On the iPhone Duo cover screen, puts a list's thumb action at the bottom of the toolbar column, within reach: a flexible
    /// spacer, then « Retour » when the list is a pushed screen (`CoverScreenThumbActions.swift:11-35` @ 87fe0d1c; the system back
    /// button and the edge swipe stay). Nothing on a root list, nothing elsewhere.
    func coverScreenListActions() -> some View {
        modifier(CoverScreenThumbActions(isList: true))
    }

    /// On the iPhone Duo cover screen, adds « Retour » to the bottom-bar items of a pushed topic, which iOS lays right above its
    /// page controls in the column (legacy Mac check 2c): no spacer (the topic keeps its top « Actualiser »).
    func coverScreenTopicActions() -> some View {
        modifier(CoverScreenThumbActions(isList: false))
    }
}

private struct CoverScreenThumbActions: ViewModifier {
    /// A list's « Retour » follows a flexible spacer down to the tab bar; a topic's stays above the page controls.
    let isList: Bool
    @Environment(\.phoneDisplayKind) private var phoneDisplayKind
    @Environment(\.isPresented) private var isPresented
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content.toolbar {
            if phoneDisplayKind.placesThumbActionsAtBottom, isPresented {
                if isList { ToolbarSpacer(.flexible, placement: .bottomBar) }
                ToolbarItem(placement: .bottomBar) {
                    Button("Retour", systemImage: "chevron.backward") { dismiss() }
                }
            }
        }
    }
}
