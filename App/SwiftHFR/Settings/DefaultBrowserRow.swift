import SwiftUI

/// The « Navigateur par défaut » row of Réglages: the switch and an info button that opens a bubble saying where links open
/// in each position (#1071, operator decision of 2026-11-17: a bubble, not a line under the switch).
struct DefaultBrowserRow: View {
    @Bindable var general: GeneralSettingsModel

    var body: some View {
        HStack {
            Toggle(DefaultBrowserMessages.title, isOn: $general.opensLinksInDefaultBrowser)
            InfoBubbleButton(label: DefaultBrowserMessages.infoLabel) {
                VStack(alignment: .leading) {
                    ForEach(DefaultBrowserMessages.explanation, id: \.self) { Text($0) }
                }
                .padding()
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
