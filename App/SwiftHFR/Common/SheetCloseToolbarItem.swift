import SwiftUI

/// The close button of a sheet or full-screen panel (#1150): the system close symbol on the leading edge (HIG › Toolbars, › Sheets).
/// Legacy's panels use an `xmark` symbol; the label « Fermer » stays for VoiceOver, which reads the role's own title anyway.
struct SheetCloseToolbarItem: ToolbarContent {
    /// Disables the button while the sheet must not close (a send in flight).
    var isDisabled = false
    /// What closing does: `dismiss()` for most sheets, a model's own close for a sheet driven by state.
    let action: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(role: .close, action: action)
                .accessibilityLabel("Fermer")
                .disabled(isDisabled)
        }
    }
}
