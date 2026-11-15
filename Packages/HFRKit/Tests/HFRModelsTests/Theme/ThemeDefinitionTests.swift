import Foundation
import Testing
@testable import HFRModels

/// The theme file model and its contrast rules (LOT-188, THEMES.md §3), on the fixture themes of the app's tests and on every
/// theme the app bundles.
@Suite struct ThemeDefinitionTests {
    /// The repository root, from this file's path.
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: root.appending(path: "App/SwiftHFRTests/Settings/ThemeFixtures/\(name).theme.json"))
    }

    /// Every `*.theme.json` under `App/SwiftHFR/Themes`, as the app bundles them.
    static func bundledFiles() throws -> [(source: String, data: Data)] {
        let folder = root.appending(path: "App/SwiftHFR/Themes")
        let enumerator = try #require(FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil))
        return try enumerator.compactMap { $0 as? URL }.filter { $0.lastPathComponent.hasSuffix(".theme.json") }
            .map { ($0.lastPathComponent, try Data(contentsOf: $0)) }
    }

    @Test func colorsParseSixAndEightDigitsAndRejectTheRest() {
        #expect(ThemeRGB(hex: "#0a84FF") == ThemeRGB(red: 10, green: 132, blue: 255))
        #expect(ThemeRGB(hex: "#0A84FF80") == ThemeRGB(red: 10, green: 132, blue: 255, alpha: 128))
        for bad in ["0A84FF", "#0A84F", "#0A84FFF", "#GGGGGG", "#+A84FF", "", "#"] {
            #expect(ThemeRGB(hex: bad) == nil, "\(bad)")
        }
        #expect(ThemeRGB(hex: "#0A84FF80")?.description == "#0A84FF80" && ThemeRGB(hex: "#0a84ff")?.description == "#0A84FF")
    }

    @Test func contrastMatchesWCAGReferenceValues() throws {
        let white = ThemeRGB(red: 255, green: 255, blue: 255)
        #expect(abs(ThemeRGB(red: 0, green: 0, blue: 0).contrast(with: white) - 21) < 1e-9)
        #expect(abs(try #require(ThemeRGB(hex: "#777777")).contrast(with: white) - 4.48) < 0.01)
    }

    @Test func theTestThemeDecodesWithBothVariantsAndMeetsEveryRule() throws {
        let theme = try JSONDecoder().decode(ThemeDefinition.self, from: Self.fixture("test-theme"))
        #expect(theme.id == "test-theme" && theme.family == "Classiques" && theme.author == "user1" && theme.fontDesign == .rounded)
        let variants = try #require(theme.variants)
        #expect(variants.light.background == ThemeRGB(hex: "#E6EEF8") && variants.dark.background == ThemeRGB(hex: "#101820"))
        #expect(variants.light.isLight && !variants.dark.isLight)
        #expect(theme.contrastViolations.isEmpty, "\(theme.contrastViolations.map { "\($0.variant) \($0.violation)" })")
    }

    @Test func theBrokenThemeFailsTheContrastRuleItBreaks() throws {
        let theme = try JSONDecoder().decode(ThemeDefinition.self, from: Self.fixture("broken-theme"))
        let failures = theme.contrastViolations.map { "\($0.variant) \($0.violation.rule.foreground)/\($0.violation.rule.background)" }
        // Its dark link fails on every surface links are drawn on (the reader's page, quotes, spoilers, code, even messages).
        #expect(failures == [
            "dark link/surface", "dark link/quoteBackground", "dark link/spoilerBackground", "dark link/codeBackground",
            "dark link/readerAlternate"
        ])
        #expect(theme.contrastViolations.first?.violation.description == "link on surface: 1.64:1, needs 4.5:1")
    }

    /// Every bundled theme file decodes, has a unique id, and meets every contrast rule; Legacy is one of them.
    @Test func everyBundledThemeDecodesAndMeetsEveryRule() throws {
        let files = try Self.bundledFiles()
        let catalog = ThemeCatalog(files: files)
        #expect(catalog.rejections.isEmpty, "\(catalog.rejections)")
        #expect(catalog.themes.count == files.count)
        #expect(catalog.themes.first?.id == ThemeDefinition.legacyID && catalog.themes.first?.variants == nil)
        for theme in catalog.themes {
            #expect(theme.contrastViolations.isEmpty, "\(theme.id): \(theme.contrastViolations.map { "\($0.variant) \($0.violation)" })")
        }
        // A theme lives in `Themes/<id>/<id>.theme.json`: one name per file, since the app bundle flattens folders.
        let folder = Self.root.appending(path: "App/SwiftHFR/Themes")
        for theme in catalog.themes {
            let path = folder.appending(path: "\(theme.id)/\(theme.id).theme.json").path
            #expect(FileManager.default.fileExists(atPath: path), "\(theme.id)")
        }
    }

    /// The contrast test fails on a broken bundled theme: the same check, given the broken fixture among the bundled files.
    @Test func theBundledCheckFailsWhenABrokenThemeIsAdded() throws {
        let catalog = ThemeCatalog(files: try Self.bundledFiles() + [("broken-theme.theme.json", Self.fixture("broken-theme"))])
        #expect(catalog.themes.contains { !$0.contrastViolations.isEmpty })
    }

    @Test func aMissingTokenAnUnknownTokenOrAnOpaqueRuleBreakIsRefused() throws {
        func decode(_ edit: (inout [String: Any]) -> Void) throws -> ThemeDefinition {
            var json = try #require(try JSONSerialization.jsonObject(with: Self.fixture("test-theme")) as? [String: Any])
            edit(&json)
            return try JSONDecoder().decode(ThemeDefinition.self, from: JSONSerialization.data(withJSONObject: json))
        }
        func editDark(_ json: inout [String: Any], _ change: (inout [String: Any]) -> Void) {
            var variants = json["variants"] as? [String: Any] ?? [:]
            var dark = variants["dark"] as? [String: Any] ?? [:]
            change(&dark)
            variants["dark"] = dark
            json["variants"] = variants
        }
        #expect(throws: DecodingError.self) { try decode { editDark(&$0) { $0["link"] = nil } } }
        #expect(throws: DecodingError.self) { try decode { editDark(&$0) { $0["headrBand"] = "#000000" } } }
        #expect(throws: DecodingError.self) { try decode { editDark(&$0) { $0["link"] = "blue" } } }
        // An optional token is accepted and used instead of its fallback.
        let banded = try decode { editDark(&$0) { $0["headerBand"] = "#000000" } }
        #expect(banded.variants?.dark.resolvedHeaderBand == ThemeRGB(red: 0, green: 0, blue: 0))
        #expect(banded.variants?.light.resolvedHeaderBand == ThemeRGB(hex: "#FFFFFF"))
        // A translucent colour in a contrast pair breaks its rule.
        let translucent = try decode { editDark(&$0) { $0["link"] = "#8CC8FF80" } }
        #expect(!translucent.contrastViolations.isEmpty && translucent.contrastViolations.allSatisfy { $0.violation.ratio == 0 })
    }

    /// The system text of a slot is the appearance it shows in: a dark palette put in the `light` slot is shown in light, under
    /// black system text, and fails (Fable round 1 probe).
    @Test func theSystemTextRuleFollowsTheSlotNotThePalette() throws {
        var json = try #require(try JSONSerialization.jsonObject(with: Self.fixture("test-theme")) as? [String: Any])
        var variants = try #require(json["variants"] as? [String: Any])
        variants["light"] = variants["dark"]
        json["variants"] = variants
        let theme = try JSONDecoder().decode(ThemeDefinition.self, from: JSONSerialization.data(withJSONObject: json))
        let light = theme.contrastViolations.filter { $0.variant == "light" }
            .map { "\($0.violation.rule.foreground)/\($0.violation.rule.background)" }
        #expect(light.contains("systemText/background") && light.contains("systemText/surface"))
        #expect(theme.contrastViolations.allSatisfy { $0.variant == "light" })
    }

    /// Pairs the app draws beyond THEMES.md §3's table: a link that passes on the page but not on a quote, the reader's even
    /// message, an optional table token.
    @Test func theRulesCoverEveryPairTheAppDraws() throws {
        let tokens = try JSONDecoder().decode(ThemeDefinition.self, from: Self.fixture("test-theme")).variants?.light
        let light = try #require(tokens)
        // #767676 is 4.54:1 on white: it passes on the page and fails on the quote (#F2F2F7) and the code (#EAEAF0) backgrounds.
        let grey = try #require(ThemeRGB(hex: "#767676"))
        #expect(grey.contrast(with: light.surface) >= 4.5)
        #expect(grey.contrast(with: light.quoteBackground) < 4.5 && grey.contrast(with: light.codeBackground) < 4.5)
        let names = Set(ThemeTokens.contrastRules.map { "\($0.foreground)/\($0.background)" })
        for pair in [
            "link/quoteBackground", "link/codeBackground", "link/readerAlternate", "textSecondary/codeBackground",
            "accentText/codeBackground", "accentText/systemCard", "accentText/background", "meta/surface", "counter/surface",
            "textSecondary/readerAlternate"
        ] {
            #expect(names.contains(pair), "\(pair)")
        }
        // The even message is the text mixed into the surface: 7 % in light, 16 % in dark.
        #expect(light.color(named: "readerAlternate", inLight: true) == light.surface.mixed(with: light.textPrimary, amount: 0.07))
        #expect(ThemeRGB(red: 255, green: 255, blue: 255).mixed(with: ThemeRGB(red: 0, green: 0, blue: 0), amount: 0.5)
            == ThemeRGB(red: 128, green: 128, blue: 128))
    }

    @Test func unknownKeysAndVariantsAreRefused() throws {
        func decode(_ edit: (inout [String: Any]) -> Void) throws -> ThemeDefinition {
            var json = try #require(try JSONSerialization.jsonObject(with: Self.fixture("test-theme")) as? [String: Any])
            edit(&json)
            return try JSONDecoder().decode(ThemeDefinition.self, from: JSONSerialization.data(withJSONObject: json))
        }
        #expect(throws: DecodingError.self) { try decode { $0["fontdesign"] = "monospaced" } }
        #expect(throws: DecodingError.self) {
            try decode { json in
                var variants = json["variants"] as? [String: Any] ?? [:]
                variants["anny"] = variants["dark"]
                json["variants"] = variants
            }
        }
        _ = try decode { _ in }
    }

    @Test func variantsAreLightAndDarkOrAnyAlone() throws {
        func decode(_ variants: [String: Any], id: String = "x") throws -> ThemeDefinition {
            let json: [String: Any] = ["id": id, "name": "X", "family": "Rétro", "variants": variants]
            return try JSONDecoder().decode(ThemeDefinition.self, from: JSONSerialization.data(withJSONObject: json))
        }
        let source = try #require(try JSONSerialization.jsonObject(with: Self.fixture("test-theme")) as? [String: Any])
        let variants = try #require(source["variants"] as? [String: Any])
        let dark = try #require(variants["dark"])
        let single = try decode(["any": dark])
        #expect(single.variants?.light == single.variants?.dark && single.variants?.light.isLight == false)
        #expect(single.fontDesign == .default && single.author == nil)
        #expect(throws: DecodingError.self) { try decode(["light": dark]) }
        #expect(throws: DecodingError.self) { try decode(["light": dark, "dark": dark, "any": dark]) }
        #expect(throws: DecodingError.self) { try decode([:]) }
        // Only Legacy goes without variants, and Legacy has none.
        #expect(throws: DecodingError.self) { try decode(["any": dark], id: "legacy") }
        let bare = try JSONSerialization.data(withJSONObject: ["id": "x", "name": "X", "family": "Rétro"])
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(ThemeDefinition.self, from: bare) }
        #expect(throws: DecodingError.self) { try decode(["any": dark], id: "Not Kebab") }
    }

    @Test func theCatalogKeepsLegacyFirstOrdersByFamilyAndReadsAnUnknownIDAsLegacy() throws {
        func theme(_ id: String, _ name: String, _ family: String) throws -> (source: String, data: Data) {
            let source = try #require(try JSONSerialization.jsonObject(with: Self.fixture("test-theme")) as? [String: Any])
            var json = source
            (json["id"], json["name"], json["family"]) = (id, name, family)
            return ("\(id).theme.json", try JSONSerialization.data(withJSONObject: json))
        }
        let files = [
            try theme("og-clair", "OG clair", "OG Web"), try theme("retro-5250", "Rétro 5250", "Rétro"),
            try theme("swift", "Swift", "Classiques"), try theme("noel-soft", "Noël soft", "Noël"),
            try theme("zz", "Zed", "Autre"), ("bad.theme.json", Data("{".utf8)), try theme("swift", "Swift bis", "Classiques")
        ]
        let catalog = ThemeCatalog(files: files)
        // No Legacy file: the built-in Legacy still comes first.
        #expect(catalog.themes.map(\.id) == ["legacy", "swift", "retro-5250", "og-clair", "zz", "noel-soft"])
        #expect(catalog.rejections.map(\.source).sorted() == ["bad.theme.json", "swift.theme.json"])
        #expect(catalog.theme(id: nil).isLegacy && catalog.theme(id: "gone").isLegacy && catalog.theme(id: "swift").name == "Swift")
        // The gallery hides seasonal families (LOT-166 owns their window).
        #expect(catalog.galleryFamilies.map(\.family) == ["Classiques", "Rétro", "OG Web", "Autre"])
        #expect(catalog.galleryFamilies[0].themes.map(\.id) == ["legacy", "swift"])
    }
}
