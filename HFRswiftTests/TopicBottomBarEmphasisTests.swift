import XCTest
@testable import HFRswift

final class TopicBottomBarEmphasisTests: XCTestCase {
    func testReplyIsTheProminentButtonOutsideSearch() {
        let result = TopicBottomBarEmphasis.resolve(
            isInSearchMode: false,
            isReplyButtonVisible: true
        )

        XCTAssertEqual(result, .reply)
    }

    func testSearchModeKeepsSearchNextAsOnlyProminentButton() {
        let result = TopicBottomBarEmphasis.resolve(
            isInSearchMode: true,
            isReplyButtonVisible: true
        )

        XCTAssertEqual(result, .searchNext)
    }

    func testHiddenReplyButtonLeavesNothingProminent() {
        let result = TopicBottomBarEmphasis.resolve(
            isInSearchMode: false,
            isReplyButtonVisible: false
        )

        XCTAssertEqual(result, .none)
    }
}
