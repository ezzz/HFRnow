import Foundation
import Testing
@testable import HFRModels

@Suite struct AQModelsTests {
    private let link = URL(string: "https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=13&post=1#t5") ?? URL(fileURLWithPath: "/")

    @Test func feedItemRoundTripsWithAndWithoutDate() throws {
        let dated = AQFeedItem(
            topicTitle: "T", title: "A", comment: "c", initiator: "i",
            publishedAt: Date(timeIntervalSince1970: 1_700_000_000), link: link
        )
        let undated = AQFeedItem(topicTitle: "T", title: "A", comment: "c", initiator: "i", publishedAt: nil, link: link)
        #expect(try roundTrip(dated) == dated)
        #expect(try roundTrip(undated) == undated)
        #expect(dated.id != undated.id)
    }

    @Test func feedItemsWithDifferentLinksHaveDifferentIdentities() {
        let other = URL(string: "https://forum.hardware.fr/other") ?? link
        let first = AQFeedItem(topicTitle: "T", title: "A", comment: "", initiator: "", publishedAt: nil, link: link)
        let second = AQFeedItem(topicTitle: "T", title: "A", comment: "", initiator: "", publishedAt: nil, link: other)
        #expect(first.id != second.id)
    }

    @Test func alertRoundTripsAndIsIdentifiedByItsNumber() throws {
        let alert = AQAlert(id: 13331, title: "Test", initiator: "ezzz", dateText: "05-03-2019", postIDs: [5934515])
        #expect(try roundTrip(alert) == alert)
        #expect(alert.id == 13331)
    }

    @Test func newReportDistinguishesNewFromExistingAlert() throws {
        let report = AQNewReport(
            title: "t", topicID: 1, topicTitle: "T", pseudo: "p", postID: 2, postURL: link, comment: "c"
        )
        var existing = report
        existing.existingAlertID = 13331
        #expect(report.existingAlertID == nil)
        #expect(report != existing)
        #expect(try roundTrip(existing) == existing)
    }
}
