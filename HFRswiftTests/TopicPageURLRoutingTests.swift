import XCTest
@testable import HFRswift

final class TopicPageURLRoutingTests: XCTestCase {
    func testPageNumberReadsQueryStyleURL() {
        let url = "https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=13&post=29332&page=344&p=1#bas"

        XCTAssertEqual(TopicPageURLRouting.pageNumber(from: url), 344)
    }

    func testPageNumberReadsSeoStyleURL() {
        let url = "https://forum.hardware.fr/hfr/gsmgpspda/android/redface-client-android-sujet_29332_344.htm#bas"

        XCTAssertEqual(TopicPageURLRouting.pageNumber(from: url), 344)
    }

    func testReplacingPageUpdatesQueryStyleURLAndRemovesFragment() {
        let url = "https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=13&post=29332&page=344&p=1#bas"

        XCTAssertEqual(
            TopicPageURLRouting.replacingPage(in: url, page: 12),
            "https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=13&post=29332&page=12&p=1"
        )
    }

    func testReplacingPageUpdatesSeoStyleURLAndRemovesFragment() {
        let url = "https://forum.hardware.fr/hfr/gsmgpspda/android/redface-client-android-sujet_29332_344.htm#bas"

        XCTAssertEqual(
            TopicPageURLRouting.replacingPage(in: url, page: 12),
            "https://forum.hardware.fr/hfr/gsmgpspda/android/redface-client-android-sujet_29332_12.htm"
        )
    }

    func testReplacingPageAppendsQueryPageWhenMissing() {
        let url = "https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=13&post=29332&p=1#bas"

        XCTAssertEqual(
            TopicPageURLRouting.replacingPage(in: url, page: 12),
            "https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=13&post=29332&p=1&page=12"
        )
    }

    func testPhotoViewerAddsForumRefererForRehostImageRequests() throws {
        let url = try XCTUnwrap(URL(string: "https://reho.st/self/abc123.jpg"))

        let request = PhotoViewerNetworkRequestFactory.makeRequest(for: url)

        XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "https://forum.hardware.fr")
    }

    func testPhotoViewerDoesNotAddForumRefererForOtherHosts() throws {
        let url = try XCTUnwrap(URL(string: "https://img3.super-h.fr/images/full.jpg"))

        let request = PhotoViewerNetworkRequestFactory.makeRequest(for: url)

        XCTAssertNil(request.value(forHTTPHeaderField: "Referer"))
    }
}
