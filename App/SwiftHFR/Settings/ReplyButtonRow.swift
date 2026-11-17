import HFRModels
import SwiftUI

/// The « Bouton + » row of Réglages: the picker and an info button that opens a bubble describing the three choices (#1062,
/// operator decision of 2026-11-17: a bubble, not a description under the row, for this row only).
struct ReplyButtonRow: View {
    /// The info button's accessibility label.
    static let infoLabel = "À propos du bouton +"

    @Bindable var topics: TopicsSettingsModel

    var body: some View {
        HStack {
            Picker("Bouton +", selection: $topics.replyButton) {
                ForEach(ReplyButtonBehavior.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            InfoBubbleButton(label: Self.infoLabel) { ReplyButtonInfoView() }
        }
    }
}
