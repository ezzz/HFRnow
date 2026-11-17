import HFRModels
import SwiftUI

/// The « Bouton + » row of Réglages: the picker and, under it, what the selected choice does (#1062). The description is read
/// with the picker as its hint, so the text below is hidden from VoiceOver instead of being read twice.
struct ReplyButtonRow: View {
    @Bindable var topics: TopicsSettingsModel

    var body: some View {
        VStack(alignment: .leading) {
            Picker("Bouton +", selection: $topics.replyButton) {
                ForEach(ReplyButtonBehavior.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .accessibilityHint(topics.replyButtonExplanation)
            Text(topics.replyButtonExplanation)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}
