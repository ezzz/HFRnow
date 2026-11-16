import SwiftUI
import UIKit

/// The « Version » row of Réglages and À propos: a tap copies the build report, then confirms it (#970).
struct VersionRow: View {
    @State private var copied = false

    var body: some View {
        Button {
            UIPasteboard.general.string = BuildReport.current.text
            copied = true
            AccessibilityNotification.Announcement("Copié").post()
            Task {
                try? await Task.sleep(for: .seconds(2))
                copied = false
            }
        } label: {
            LabeledContent("Version", value: copied ? "Copié" : AppVersion.current.rowText)
                .foregroundStyle(.primary)
        }
        .accessibilityHint("Copie la version, le build, le commit, le système et le modèle")
    }
}
