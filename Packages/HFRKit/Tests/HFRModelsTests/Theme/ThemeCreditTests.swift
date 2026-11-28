import Foundation
import Testing
@testable import HFRModels

/// The gallery credit (`credit`, `creditLine`) and the list style (`listStyle`) of a theme file (LOT-193, THEMES.md §3).
@Suite struct ThemeCreditTests {
    /// The test theme with `extra` keys added at the top level.
    private static func decode(_ extra: [String: Any]) throws -> ThemeDefinition {
        var json = try #require(try JSONSerialization.jsonObject(with: ThemeDefinitionTests.fixture("test-theme")) as? [String: Any])
        json.merge(extra) { $1 }
        return try JSONDecoder().decode(ThemeDefinition.self, from: JSONSerialization.data(withJSONObject: json))
    }

    /// The credit line: `credit` as it is when the file has one, else « par <author> », else nothing. The engine reads no word of
    /// the credit: the file says what it wants printed.
    @Test func theCreditLineIsTheCreditOrParTheAuthor() throws {
        let catalog = ThemeCatalog(files: try ThemeDefinitionTests.bundledFiles())
        func line(_ id: String) -> String? { catalog.themes.first { $0.id == id }?.creditLine }
        #expect(line("og-clair") == "d'après le forum HFR (thème web)")
        #expect(line("og-gris") == "d'après le forum HFR (thème web)")
        #expect(line("legacy") == "par Ezzz")
        #expect(line("swift") == nil)
        #expect(try Self.decode(["credit": "D’après un thème web"]).creditLine == "D’après un thème web")
        #expect(try Self.decode(["author": "user1"]).creditLine == "par user1")
        #expect(try Self.decode(["author": "user1", "credit": "avec l'aide de user2"]).creditLine == "avec l'aide de user2")
    }

    @Test func listStyleDefaultsToStandardAndOnlyKnownValuesDecode() throws {
        #expect(try Self.decode([:]).listStyle == .standard)
        #expect(try Self.decode(["listStyle": "ogTable"]).listStyle == .ogTable)
        #expect(throws: DecodingError.self) { try Self.decode(["listStyle": "table"]) }
    }

    @Test func theOGThemesDrawTheTableLookAndNoOtherTheme() throws {
        let catalog = ThemeCatalog(files: try ThemeDefinitionTests.bundledFiles())
        #expect(catalog.themes.filter { $0.listStyle == .ogTable }.map(\.id).sorted() == ["og-clair", "og-gris"])
    }

    @Test func aTypoOfAKeyIsStillAnError() throws {
        #expect(throws: DecodingError.self) { try Self.decode(["credits": "x"]) }
    }
}
