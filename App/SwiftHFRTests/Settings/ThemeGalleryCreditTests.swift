import HFRModels
@testable import SwiftHFR
import SwiftUI
import Testing

/// LOT-193: the gallery row's VoiceOver label and its credit text come from `ThemeDefinition.creditLine`: « d'après … » for the OG
/// themes (no « par »), « par Ezzz » for Legacy.
@MainActor
struct ThemeGalleryCreditTests {
    private func row(_ id: String) throws -> ThemeGalleryRow {
        let theme = try #require(ThemeCatalog.bundled.themes.first { $0.id == id })
        return ThemeGalleryRow(theme: theme, legacy: .standard, isSelected: false, select: {})
    }

    @Test func theVoiceOverLabelReadsTheCreditLine() throws {
        #expect(try row("og-clair").accessibilityLabel == "OG clair, d'après le forum HFR (thème web), clair = sombre")
        #expect(try row("og-gris").accessibilityLabel == "OG gris, d'après le forum HFR (thème web), clair = sombre")
        #expect(try row("legacy").accessibilityLabel == "Legacy, par Ezzz")
        #expect(try row("og-gris").accessibilityLabel.contains("par ") == false)
    }

    /// The visible credit is the same line as the label's.
    @Test func theVisibleCreditIsTheLabelsLine() throws {
        #expect(try row("og-gris").theme.creditLine == "d'après le forum HFR (thème web)")
        #expect(try row("og-gris").creditText == row("og-gris").theme.creditLine)
    }
}
