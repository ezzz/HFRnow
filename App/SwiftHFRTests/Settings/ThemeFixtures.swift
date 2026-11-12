import Foundation
import HFRModels
@testable import SwiftHFR

/// The fixture themes of `ThemeFixtures/` (LOT-188), shared with HFRKit's `ThemeDefinitionTests`: `test-theme` meets every rule
/// (background #E6EEF8 light, #101820 dark; surface #FFFFFF light, #1A2430 dark), `broken-theme` breaks one.
enum ThemeFixtures {
    struct Malformed: Error {}

    static func data(_ name: String) throws -> Data {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "ThemeFixtures")
        return try Data(contentsOf: folder.appending(path: "\(name).theme.json"))
    }

    /// The app's Legacy file plus the fixture `name`.
    static func catalog(adding name: String = "test-theme") throws -> ThemeCatalog {
        ThemeCatalog(files: [("\(name).theme.json", try data(name))] + legacyFile())
    }

    /// The test theme with its dark variant alone (`any`): a single-variant, « clair = sombre », theme.
    static func singleVariantCatalog() throws -> ThemeCatalog {
        guard var json = try JSONSerialization.jsonObject(with: data("test-theme")) as? [String: Any],
              let variants = json["variants"] as? [String: Any], let dark = variants["dark"] else { throw Malformed() }
        json["variants"] = ["any": dark]
        json["id"] = "single-theme"
        return ThemeCatalog(files: [("single-theme.theme.json", try JSONSerialization.data(withJSONObject: json))] + legacyFile())
    }

    /// The decoded test theme.
    static func testTheme() throws -> ThemeDefinition {
        try JSONDecoder().decode(ThemeDefinition.self, from: data("test-theme"))
    }

    private static func legacyFile() -> [(source: String, data: Data)] {
        guard let url = Bundle.main.url(forResource: "legacy.theme", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        return [("legacy.theme.json", data)]
    }
}
