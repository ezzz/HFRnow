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

    @Test(arguments: [
        (0, "il y a 1 h"), (3_600, "il y a 1 h"), (3_601, "il y a 1 h"), (7_199, "il y a 1 h"), (7_200, "il y a 2 h"),
        (23 * 3_600 + 59, "il y a 23 h"), (24 * 3_600, "il y a 1 j"), (30 * 86_400 + 86_399, "il y a 30 j"),
        (31 * 86_400, "il y a 1 mois"), (364 * 86_400, "il y a 11 mois"), (372 * 86_400, "il y a 12 mois"),
        // 12 months of 31 days last until day 403; then the year count (days / 365) starts at 1 and reaches 2 at day 730.
        (402 * 86_400, "il y a 12 mois"), (403 * 86_400, "il y a 1 an"), (729 * 86_400, "il y a 1 an"),
        (730 * 86_400, "il y a 2 ans"),
        (-500, "il y a 1 h")
    ])
    func theAgeReadsAsLegacyWordsIt(seconds: Int, expected: String) {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(QualityAlertAge.label(since: now.addingTimeInterval(-Double(seconds)), now: now) == expected)
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
