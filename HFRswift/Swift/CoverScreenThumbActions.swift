import SwiftUI

extension PhoneDisplayKind {
    /// Where a screen's « Actualiser » button goes: at the bottom of the toolbar column on the
    /// iPhone Duo cover screen (thumb reach, beta feedback on #372), top trailing elsewhere.
    var refreshToolbarPlacement: ToolbarItemPlacement {
        PhoneDisplayPolicy.placesThumbActionsAtBottom(kind: self) ? .bottomBar : .topBarTrailing
    }
}

extension View {
    /// On the iPhone Duo cover screen, adds a « Retour » button at the bottom of the toolbar
    /// column of a pushed view, within thumb reach. The system back button and the edge swipe stay.
    func coverScreenBottomBackButton() -> some View {
        modifier(CoverScreenBottomBackButton())
    }
}

private struct CoverScreenBottomBackButton: ViewModifier {
    @Environment(\.hfrPhoneDisplayKind) private var phoneDisplayKind
    @Environment(\.isPresented) private var isPresented
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content.toolbar {
            if isPresented && PhoneDisplayPolicy.placesThumbActionsAtBottom(kind: phoneDisplayKind) {
                ToolbarItem(placement: .bottomBar) {
                    Button("Retour", systemImage: "chevron.backward") {
                        dismiss()
                    }
                }
            }
        }
    }
}
