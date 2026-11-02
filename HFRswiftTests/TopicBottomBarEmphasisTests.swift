import XCTest
@testable import HFRswift

final class TopicBottomBarEmphasisTests: XCTestCase {
    func testLastPageBottomPromotesReplyNotRefresh() {
        let result = TopicBottomBarEmphasis.resolve(
            isInSearchMode: false,
            isNextPagePromoted: false,
            isReplyButtonVisible: true
        )

        XCTAssertEqual(result, .reply)
    }

    func testIntermediatePageBottomKeepsNextPageCue() {
        let result = TopicBottomBarEmphasis.resolve(
            isInSearchMode: false,
            isNextPagePromoted: true,
            isReplyButtonVisible: true
        )

        XCTAssertEqual(result, .nextPage)
    }

    func testSearchModeKeepsSearchNextAsOnlyProminentButton() {
        let result = TopicBottomBarEmphasis.resolve(
            isInSearchMode: true,
            isNextPagePromoted: true,
            isReplyButtonVisible: true
        )

        XCTAssertEqual(result, .searchNext)
    }

    func testHiddenReplyButtonLeavesNothingProminent() {
        let result = TopicBottomBarEmphasis.resolve(
            isInSearchMode: false,
            isNextPagePromoted: false,
            isReplyButtonVisible: false
        )

        XCTAssertEqual(result, .none)
    }
}
