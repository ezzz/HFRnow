import SwiftUI

/// An `info.circle` button that opens a bubble with a row's explanation: the pattern of « Bouton + » (#1062) and of the iCloud
/// account sync (#1065), instead of a paragraph under the row (operator decision of 2026-11-17). A popover on wide views; on
/// compact width (iPhone) the system turns it into a sheet whose content scrolls, so a long text at a large text size stays
/// reachable (#1181, HIG › Popovers: no popovers in compact views). The label is the button's accessibility label; the bubble's
/// content is read in full.
struct InfoBubbleButton<Bubble: View>: View {
    let label: String
    @ViewBuilder let bubble: () -> Bubble
    @State private var isShown = false
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        Button(label, systemImage: "info.circle") { isShown = true }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .popover(isPresented: $isShown) {
                if InfoBubblePresentation.isSheet(sizeClass) {
                    ScrollView { bubble() }
                        .presentationDetents(InfoBubblePresentation.sheetDetents)
                        .presentationDragIndicator(.visible)
                } else {
                    bubble()
                }
            }
    }
}

/// How the bubble is presented (#1181): the rule apart from the view, so a test pins it.
enum InfoBubblePresentation {
    /// Compact width gets a sheet, as the system does when a popover is not forced; any other width keeps the popover.
    static func isSheet(_ horizontalSizeClass: UserInterfaceSizeClass?) -> Bool { horizontalSizeClass == .compact }

    /// A sheet opens at half height and grows to full height for a long text at a large text size.
    static let sheetDetents: Set<PresentationDetent> = [.medium, .large]
}
