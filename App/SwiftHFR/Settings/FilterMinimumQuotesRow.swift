import SwiftUI

/// The « Minimum de citations » row of Réglages › Filtrer les posts: the picker and an info button that opens a bubble
/// explaining the filter and that minimum (#1072, on this row rather than on the section header: a header button is styled as
/// header text, and the bubble explains the number the picker sets).
struct FilterMinimumQuotesRow: View {
    @Bindable var general: GeneralSettingsModel

    var body: some View {
        HStack {
            Picker("Minimum de citations", selection: $general.filterMinimumQuotes) {
                ForEach(general.filterMinimumQuoteOptions, id: \.self) { Text("\($0)").tag($0) }
            }
            InfoBubbleButton(label: FilteredPostsMessages.infoLabel) {
                VStack(alignment: .leading) {
                    ForEach(FilteredPostsMessages.explanation, id: \.self) { Text($0) }
                }
                .padding()
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
