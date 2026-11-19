import SwiftUI

/// The guard of a sheet holding typed text (#1169; HIG › Sheets: "If people have unsaved changes in the sheet when they begin
/// swiping to dismiss it, use an action sheet to let them confirm"; › Modality): while `hasChanges`, the swipe-down is blocked
/// and « Annuler » asks first, as the composer does (#429, UXD-15). With nothing typed, « Annuler » closes at once.
enum DiscardConfirmation {
    static let discardTitle = "Abandonner"
    static let keepTitle = "Continuer la saisie"
}

extension View {
    /// Blocks the swipe-down while `hasChanges` (the sheet's only `interactiveDismissDisabled`: give it every reason to block)
    /// and shows the discard question when `isAsking` turns true; `discard` runs on « Abandonner » only.
    func discardConfirmation(
        _ title: String, hasChanges: Bool, isAsking: Binding<Bool>, discard: @escaping () -> Void
    ) -> some View {
        interactiveDismissDisabled(hasChanges)
            .confirmationDialog(title, isPresented: isAsking, titleVisibility: .visible) {
                Button(DiscardConfirmation.discardTitle, role: .destructive, action: discard)
                Button(DiscardConfirmation.keepTitle, role: .cancel) {}
            }
    }
}
