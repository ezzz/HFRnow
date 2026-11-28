import SwiftUI

/// An `info.circle` button that opens a bubble with a row's explanation: the pattern of « Bouton + » (#1062) and of the iCloud
/// account sync (#1065), instead of a paragraph under the row (operator decision of 2026-11-17). The system decides the form: a
/// popover on wide views, a sheet in a compact one (HIG › Popovers: no popovers in compact views, #1181); the content fits both,
/// whatever the system picks: as is when it fits, scrolling when it does not (a sheet on a short screen, a large text size). The
/// label is the button's accessibility label; the bubble's content is read in full.
struct InfoBubbleButton<Bubble: View>: View {
    let label: String
    @ViewBuilder let bubble: () -> Bubble
    @State private var isShown = false

    var body: some View {
        Button(label, systemImage: "info.circle") { isShown = true }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .popover(isPresented: $isShown) {
                // No guess about the form the system chooses (width and height both decide it): the first variant that fits wins.
                ViewThatFits(in: .vertical) {
                    bubble()
                    ScrollView { bubble().frame(maxWidth: .infinity, alignment: .leading) }
                }
                .presentationDetents(InfoBubblePresentation.sheetDetents)
                .presentationDragIndicator(.visible)
            }
    }
}

/// The bubble's sheet form (#1181), apart from the view so a test pins it; a popover ignores the detents.
enum InfoBubblePresentation {
    /// A sheet opens at half height and grows to full height for a long text at a large text size.
    static let sheetDetents: Set<PresentationDetent> = [.medium, .large]
}
