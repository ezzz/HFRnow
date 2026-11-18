import Foundation
import HFRClient
import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing

/// What a row opens and how its date reads.
@MainActor
struct QualityAlertsRowTests {
    typealias Support = QualityAlertsTestSupport

    @Test func everyCapturedRowOpensItsTopicAtItsPageAndMessage() async throws {
        let model = Support.model(source: FakeQualityAlertsSource(items: try Support.capturedItems()))
        await model.load()
        // Issues #105, #106: the page and the anchor of the link are kept (the first item of `T01`: topic 8680, page 4078).
        let first = try #require(model.rows.first?.target)
        #expect(first == ReaderTarget(
            source: .topic(TopicID(category: .forum(13), topic: 8680)), page: 4078, anchor: 75_396_914
        ))
        #expect(model.rows.allSatisfy { $0.target != nil && $0.target?.anchor != nil && $0.target?.numreponse == nil })
    }

    @Test func aLinkOutsideTheForumHasNoTarget() async throws {
        var item = try #require(Support.capturedItems().first)
        item.link = try #require(URL(string: "https://example.com/forum2.php?cat=13&post=1&page=2#t3"))
        let model = Support.model(source: FakeQualityAlertsSource(items: [item]))
        await model.load()
        #expect(model.rows.count == 1)
        #expect(model.rows.first?.target == nil)
    }

    /// Seconds since publication and the label legacy gives. Written out in full: a long literal of tuples with arithmetic
    /// exceeds the type-checker's time limit (LESSONS 53). Months are 31 days, so 12 of them last until day 403.
    struct AgeCase: Sendable {
        let seconds: Int
        let expected: String
    }

    nonisolated static let ageCases: [AgeCase] = [
        AgeCase(seconds: 0, expected: "il y a 1 h"),
        AgeCase(seconds: 3_600, expected: "il y a 1 h"),
        AgeCase(seconds: 7_199, expected: "il y a 1 h"),
        AgeCase(seconds: 7_200, expected: "il y a 2 h"),
        AgeCase(seconds: 82_859, expected: "il y a 23 h"),
        AgeCase(seconds: 86_400, expected: "il y a 1 j"),
        AgeCase(seconds: 2_678_399, expected: "il y a 30 j"),
        AgeCase(seconds: 2_678_400, expected: "il y a 1 mois"),
        AgeCase(seconds: 31_449_600, expected: "il y a 11 mois"),
        AgeCase(seconds: 32_140_800, expected: "il y a 12 mois"),
        AgeCase(seconds: 34_732_800, expected: "il y a 12 mois"),
        AgeCase(seconds: 34_819_200, expected: "il y a 1 an"),
        AgeCase(seconds: 62_985_600, expected: "il y a 1 an"),
        AgeCase(seconds: 63_072_000, expected: "il y a 2 ans"),
        AgeCase(seconds: -500, expected: "il y a 1 h")
    ]

    @Test(arguments: ageCases)
    func theAgeReadsAsLegacyWordsIt(_ ageCase: AgeCase) {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(QualityAlertAge.label(since: now.addingTimeInterval(-Double(ageCase.seconds)), now: now) == ageCase.expected)
    }

    @Test func anUnreadableDateHasNoAgeAndIsNotNew() throws {
        #expect(QualityAlertAge.label(since: nil, now: Date()) == nil)
        var item = try #require(Support.capturedItems().first)
        item.publishedAt = nil
        #expect(!AQClient.isNew(item, since: QualityAlertsModel.neverChecked))
    }

    @Test func theBuildsAddressMustBeAThirdPartyHttpsOrigin() {
        func source(_ value: Any?) -> LiveQualityAlertsSource? {
            LiveQualityAlertsSource.configured(from: value.map { ["AQBaseURL": $0] } ?? [:])
        }
        #expect(source("https://aq.example.test") != nil)
        #expect(source(" https://aq.example.test/ ") != nil)
        #expect(source(nil) == nil)
        #expect(source("") == nil)
        #expect(source("$(AQ_BASE_URL)") == nil)
        #expect(source("https://forum.hardware.fr") == nil)
        #expect(source("http://aq.example.test") == nil)
        #expect(source(42) == nil)
    }
}
