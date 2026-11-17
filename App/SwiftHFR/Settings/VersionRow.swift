import SwiftUI
import UIKit

/// The « Version » row of Réglages and À propos: a tap copies the build report, then confirms it (#970).
struct VersionRow: View {
    @State private var model = VersionCopyModel(
        report: { BuildReport.current.text },
        write: { UIPasteboard.general.string = $0 },
        announce: { AccessibilityNotification.Announcement($0).post() }
    )

    var body: some View {
        Button(action: model.copy) {
            LabeledContent("Version", value: model.copied ? "Copié" : AppVersion.current.rowText)
                .foregroundStyle(.primary)
        }
        .accessibilityHint("Copie la version, le build, le commit, le système et le modèle")
    }
}
