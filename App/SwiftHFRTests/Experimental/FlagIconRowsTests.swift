import HFRModels
import HFRStorage
import SwiftUI
@testable import SwiftHFR
import Testing

/// Réglages › Expérimental › « Lignes avec icônes de drapeau » (#903, #905): today's marks moved unchanged behind the option,
/// which stays hidden until #817 builds its switch-off path.
@MainActor
struct FlagIconRowsTests {
    /// The marks are the ones the row showed before the move (`TopicRowView` @ dev-swift bfb855ef).
    @Test func theFlagMarksAreTheRowsOfBeforeTheMove() {
        #expect(FlagIconRows.flagMark(.blue) == .init(symbol: "flag.fill", color: Color.blue, label: "Drapeau"))
        #expect(FlagIconRows.flagMark(.red) == .init(symbol: "flag.fill", color: Color.red, label: "Lu"))
        #expect(FlagIconRows.flagMark(.yellow) == .init(symbol: "star.fill", color: Color.yellow, label: "Favori"))
        #expect(FlagIconRows.flagMark(nil) == nil)
    }

    /// With nothing to switch to yet, the option is not offered and reads off; the rows keep their marks either way.
    @Test func theOptionWaitsForTheLegacyRows() {
        let settings = ExperimentalSettings(store: InMemorySettingsStore())
        #expect(!ExperimentalFeature.flagIconRows.isListed)
        #expect(!settings.isOn(.flagIconRows))
        #expect(!ExperimentalTheme.listed.contains(.lists))
    }
}
