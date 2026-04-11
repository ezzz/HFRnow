import XCTest
@testable import HFRswift

final class TopicPageRefreshProbePolicyTests: XCTestCase {
    func testBottomRefreshOnKnownLastPageProbesNextPageWhenLoadedMaxDidNotMove() {
        let policy = TopicPageRefreshProbePolicy(
            previousPage: 10,
            previousMaxPage: 10,
            loadedPage: 10,
            loadedMaxPage: 10,
            initialScrollToBottom: true
        )

        XCTAssertEqual(policy.nextPageToProbe, 11)
    }

    func testProbeIsSkippedWhenLoadedMaxPageAlreadyMovedForward() {
        let policy = TopicPageRefreshProbePolicy(
            previousPage: 10,
            previousMaxPage: 10,
            loadedPage: 10,
            loadedMaxPage: 11,
            initialScrollToBottom: true
        )

        XCTAssertNil(policy.nextPageToProbe)
    }

    func testProbeIsSkippedWhenRefreshDoesNotTargetBottomOfLastPage() {
        let policy = TopicPageRefreshProbePolicy(
            previousPage: 9,
            previousMaxPage: 10,
            loadedPage: 9,
            loadedMaxPage: 10,
            initialScrollToBottom: false
        )

        XCTAssertNil(policy.nextPageToProbe)
    }

    func testMergedMaxPageUsesProbeResultWhenNextPageExists() {
        let merged = TopicPageRefreshProbePolicy.mergedMaxPage(
            currentMaxPage: 10,
            probeCurrentPage: 11,
            probeMaxPage: 11
        )

        XCTAssertEqual(merged, 11)
    }
}
