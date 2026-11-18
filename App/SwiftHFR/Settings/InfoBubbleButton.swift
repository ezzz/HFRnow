import SwiftUI

/// An `info.circle` button that opens a bubble (a popover kept as a bubble on iPhone) with a row's explanation: the pattern of
/// « Bouton + » (#1062) and of the iCloud account sync (#1065), instead of a paragraph under the row (operator decision of
/// 2026-11-17). The label is the button's accessibility label; the bubble's content is read in full.
struct InfoBubbleButton<Bubble: View>: View {
    let label: String
    @ViewBuilder let bubble: () -> Bubble
    @State private var isShown = false

    var body: some View {
        Button(label, systemImage: "info.circle") { isShown = true }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .popover(isPresented: $isShown) {
                bubble().presentationCompactAdaptation(.popover)
            }
    }
}
