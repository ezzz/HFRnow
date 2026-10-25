import Foundation
import Testing
@testable import HFRModels

@Suite struct CommonSmileyCatalogTests {
    @Test func bundledCatalogueMatchesTheLegacyPlist() throws {
        let catalogue = try CommonSmileyCatalog.bundled()
        #expect(catalogue.count == 59)
        #expect(catalogue.filter(\.isEditorSmiley).count == 35)
        #expect(Set(catalogue.map(\.id)).count == catalogue.count)
    }

    @Test func bundledEntriesAreWellFormed() throws {
        for smiley in try CommonSmileyCatalog.bundled() {
            #expect(smiley.url.scheme == "https", "\(smiley.code)")
            #expect(smiley.url.host == "forum-images.hardware.fr", "\(smiley.code)")
            #expect(!smiley.resourceName.isEmpty, "\(smiley.code)")
        }
    }

    /// Every code in the legacy plist's order; guards against a wrong code or a reordering anywhere in the file.
    private static let legacyCodes = [
            ":pfff:", ":)", ":o", ":mad:", ":love:", ":pt1cable:", ":ange:", ":(", ":??:", ":jap:", ":heink:", ":sleep:",
            ":non:", ":D", ":p", ":lol:", ":cry:", ":sweat:", ":bounce:", ";)", ":na:", ":wahoo:", ":whistle:", ":hello:",
            ":ouch:", ":sarcastic:", ":kaola:", ":sol:", ":'(", ":/", ":vomi:", ":sum:", ":spookie:", ":spamafote:",
            ":pouah:", ":ouimaitre:", ":mouais:", ":mmmfff:", ":miam:", ":int:", ":hot:", ":hebe:", ":hap:", ":gun:",
            ":gratgrat:", ":fuck:", ":fouyaya:", ":foudtag:", ":fou:", ":evil:", ":eek2:", ":eek:", ":dtc:", ":crazy:",
            ":calimero:", ":bug:", ":bic:", ":benetton:", ":24:"
    ]

    @Test func bundledCodesMatchTheLegacyPlistInOrder() throws {
        #expect(try CommonSmileyCatalog.bundled().map(\.code) == Self.legacyCodes)
    }

    @Test func resourceNamesAreTheImageFileNames() throws {
        for smiley in try CommonSmileyCatalog.bundled() {
            #expect(smiley.url.lastPathComponent == smiley.resourceName, "\(smiley.code)")
        }
    }

    @Test func firstEntriesKeepLegacyOrder() throws {
        let catalogue = try CommonSmileyCatalog.bundled()
        #expect(catalogue.prefix(2).map(\.code) == [":pfff:", ":)"])
        #expect(catalogue[1].resourceName == "smile.gif")
    }

    @Test func decodesTheResourceFileKeys() throws {
        let json = #"[{"code":":)","resource":"smile.gif","url":"https://forum-images.hardware.fr/icones/smile.gif","editor":true}]"#
        let decoded = try CommonSmileyCatalog.decode(Data(json.utf8))
        #expect(decoded == [CommonSmiley(
            code: ":)",
            url: URL(string: "https://forum-images.hardware.fr/icones/smile.gif") ?? URL(fileURLWithPath: "/"),
            resourceName: "smile.gif",
            isEditorSmiley: true
        )])
    }

    @Test func malformedCatalogueThrows() {
        #expect(throws: DecodingError.self) { try CommonSmileyCatalog.decode(Data(#"[{"code":1}]"#.utf8)) }
    }
}
