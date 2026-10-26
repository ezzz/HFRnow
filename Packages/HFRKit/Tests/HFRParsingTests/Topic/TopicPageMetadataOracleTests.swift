import Foundation
import HFRModels
import Testing
@testable import HFRParsing

/// Differential tests (ADR 0004): the page-level fields of every LOT-003 oracle must be reproduced from the same capture.
@Suite("Topic page metadata against the legacy oracle")
struct TopicPageMetadataOracleTests {
    /// Every case of `Fixtures/LOT-003/oracle-map.json` (R25 has no body; RA5 is a deleted conversation).
    static let cases = [
        "R20", "R21", "R22a", "R22b", "R23", "R24", "R26", "R27", "R27b", "R28", "R31", "R32a", "R32b",
        "RA1", "RA2", "RA3", "RA4", "RA5", "RU1", "RU2"
    ]

    @Test("the case list covers the oracle map")
    func casesCoverTheMap() throws {
        let map = try Self.jsonObject(Fixture.text("oracle-map", extension: "json", subdirectory: "Fixtures/LOT-003"))
        let mapped = Set(map.keys.map { $0.replacing(".html", with: "") })
        #expect(mapped == Set(Self.cases))
    }

    @Test("title, pager, answer form, hidden fields, unread link, poll and search form equal the oracle", arguments: cases)
    func matchesOracle(id: String) throws {
        let oracle = try Self.oracle(id)
        let metadata = try TopicPageMetadataParser.parse(html: oracle.html, pageURL: oracle.currentURL)

        #expect(metadata.title == oracle.string("sNavigationViewTitle")?.trimmingCharacters(in: .whitespacesAndNewlines))
        #expect(metadata.title == oracle.string("topicName")?.trimmingCharacters(in: .whitespacesAndNewlines))
        #expect(metadata.currentPage == oracle.page["currentPage"] as? Int)
        #expect(metadata.maxPage == oracle.page["maxPage"] as? Int)
        #expect(metadata.maxPage == max(oracle.parser["iLastPageNumber"] as? Int ?? 0, 1))
        #expect(metadata.answerFormURL?.absoluteString == oracle.string("answerURL"))
        #expect(metadata.answerFormFields == oracle.strings("inputData"))
        #expect(metadata.isUnreadable == oracle.page["unreadable"] as? Bool)
        #expect(metadata.hasPoll == (oracle.page["poll"] as? [String: Any])?["hasPoll"] as? Bool)
        #expect((metadata.searchFormFields ?? [:]) == oracle.strings("searchInputData"))
    }

    @Test("the topic identity agrees with the oracle's hidden fields when the page has them", arguments: cases)
    func topicIDAgreesWithHiddenFields(id: String) throws {
        let oracle = try Self.oracle(id)
        let metadata = try TopicPageMetadataParser.parse(html: oracle.html, pageURL: oracle.currentURL)
        let fields = oracle.strings("inputData")
        if let cat = fields["cat"], let post = fields["post"].flatMap(Int.init) {
            #expect(metadata.topicID == TopicID(category: try #require(CategoryID(queryValue: cat)), topic: post))
        }
    }

    // MARK: - Helpers

    struct Oracle {
        let html: String
        let currentURL: String
        let page: [String: Any]
        let parser: [String: Any]

        func string(_ key: String) -> String? { page[key] as? String }

        func strings(_ key: String) -> [String: String] { page[key] as? [String: String] ?? [:] }
    }

    static func oracle(_ id: String) throws -> Oracle {
        let root = try jsonObject(Fixture.text("\(id).oracle", extension: "json", subdirectory: "Fixtures/LOT-003"))
        let input = try #require(root["input"] as? [String: Any])
        let result = try #require(root["result"] as? [String: Any])
        let file = try #require(input["file"] as? String)
        let capture = file.split(separator: "/").last.map { String($0).replacing(".html", with: "") } ?? file
        return Oracle(
            html: try Fixture.capture(capture),
            currentURL: try #require(input["currentURL"] as? String),
            page: try #require(result["page"] as? [String: Any]),
            parser: try #require(result["parser"] as? [String: Any])
        )
    }

    static func jsonObject(_ text: String) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: Data(text.utf8))
        return try #require(object as? [String: Any])
    }
}
