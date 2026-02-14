import XCTest
@testable import HFRswift

final class MessageWebActionHandlerTests: XCTestCase {
    private let handler = MessageWebActionHandler()

    func testAutoNextLoadsNextPageFromLinkActivated() {
        let action = handler.action(
            for: URL(string: "oijlkajsdoihjlkjasdoauto://next")!,
            navigationType: .linkActivated,
            currentPage: 5,
            maxPage: 10
        )

        XCTAssertEqual(action, .loadPage(6, .top))
    }

    func testAutoBeginLoadsFirstPageWithTopScroll() {
        let action = handler.action(
            for: URL(string: "oijlkajsdoihjlkjasdoauto://begin")!,
            navigationType: .linkActivated,
            currentPage: 6,
            maxPage: 10
        )

        XCTAssertEqual(action, .loadPage(1, .top))
    }

    func testAutoEndLoadsLastPageWithBottomScroll() {
        let action = handler.action(
            for: URL(string: "oijlkajsdoihjlkjasdoauto://end")!,
            navigationType: .linkActivated,
            currentPage: 6,
            maxPage: 10
        )

        XCTAssertEqual(action, .loadPage(10, .bottom))
    }

    func testAutoPreviousAtFirstPageIsIgnored() {
        let action = handler.action(
            for: URL(string: "oijlkajsdoihjlkjasdoauto://previous")!,
            navigationType: .linkActivated,
            currentPage: 1,
            maxPage: 10
        )

        XCTAssertEqual(action, .ignore)
    }

    func testRefreshSchemeTriggersRefreshAction() {
        let action = handler.action(
            for: URL(string: "oijlkajsdoihjlkjasdorefresh://data")!,
            navigationType: .other,
            currentPage: 3,
            maxPage: 10
        )

        XCTAssertEqual(action, .refreshCurrentPage)
    }

    func testLoadedSchemeIsIgnored() {
        let action = handler.action(
            for: URL(string: "oijlkajsdoihjlkjasdoloaded://data")!,
            navigationType: .other,
            currentPage: 3,
            maxPage: 10
        )

        XCTAssertEqual(action, .ignore)
    }

    func testForumTopicURLIsRoutedAsInternalTopic() {
        let url = URL(string: "https://forum.hardware.fr/forum2.php?cat=1&page=55")!
        let action = handler.action(
            for: url,
            navigationType: .linkActivated,
            currentPage: 3,
            maxPage: 10
        )

        XCTAssertEqual(action, .openInternalTopic(url))
    }

    func testExternalURLIsRoutedAsExternal() {
        let url = URL(string: "https://example.com/path")!
        let action = handler.action(
            for: url,
            navigationType: .linkActivated,
            currentPage: 3,
            maxPage: 10
        )

        XCTAssertEqual(action, .openExternalURL(url))
    }

    func testFileURLIsRoutedAsInternalTopic() {
        let url = URL(string: "file:///tmp/hfr/topic-1.htm")!
        let action = handler.action(
            for: url,
            navigationType: .linkActivated,
            currentPage: 1,
            maxPage: 5
        )

        XCTAssertEqual(action, .openInternalTopic(url))
    }

    func testExternalURLWithOtherNavigationTypeStaysAllowed() {
        let url = URL(string: "https://example.com/path")!
        let action = handler.action(
            for: url,
            navigationType: .other,
            currentPage: 2,
            maxPage: 10
        )

        XCTAssertEqual(action, .allowNavigation)
    }

    func testFragmentBasInOtherNavigationIsIgnored() {
        let url = URL(string: "https://forum.hardware.fr/forum2.php?page=2#bas")!
        let action = handler.action(
            for: url,
            navigationType: .other,
            currentPage: 2,
            maxPage: 10
        )

        XCTAssertEqual(action, .ignore)
    }

    func testUnknownSchemeAllowsNavigation() {
        let action = handler.action(
            for: URL(string: "about:blank")!,
            navigationType: .other,
            currentPage: 2,
            maxPage: 10
        )

        XCTAssertEqual(action, .allowNavigation)
    }
}
