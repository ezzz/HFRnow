import Foundation
import Testing
@testable import HFRModels

@Suite struct SettingsEnumsTests {
    @Test func stringRawValuesMatchTheLegacyDefaultsValues() {
        #expect(EmbeddedVideosMode.allCases.map(\.rawValue) == ["no", "yes", "both"])
        #expect(ImageDisplayMode.allCases.map(\.rawValue) == ["yes", "no", "wifi"])
        #expect(LandscapeMode.allCases.map(\.rawValue) == ["galerie_message", "none"])
    }

    @Test func integerRawValuesMatchTheLegacyDefaultsValues() {
        #expect(AutoThemeMode.allCases.map(\.rawValue) == [0, 3])
        #expect(ThemeVariant.allCases.map(\.rawValue) == [0, 1])
        #expect(ThemeStyle.allCases.map(\.rawValue) == [0, 1])
        #expect(TextSizeScale.allCases.map(\.rawValue) == [100, 110, 120, 130])
        #expect(RehostMaxDimension.allCases.map(\.rawValue) == [400, 600, 800, 1000, 1200])
    }

    @Test func unknownStoredValuesAreNotInvented() {
        #expect(EmbeddedVideosMode(rawValue: "maybe") == nil)
        #expect(AutoThemeMode(rawValue: 1) == nil)
        #expect(RehostMaxDimension(rawValue: 1) == nil)
    }

    @Test func codableUsesTheRawValue() throws {
        let data = try JSONEncoder().encode([LandscapeMode.galerieMessage])
        #expect(try text(of: data) == #"["galerie_message"]"#)
        #expect(try roundTrip(RehostMaxDimension.px800) == .px800)
        #expect(try roundTrip(AutoThemeMode.system) == .system)
    }
}
