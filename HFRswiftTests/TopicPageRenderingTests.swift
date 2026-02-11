import XCTest
@testable import HFRswift

final class TopicPageRenderingTests: XCTestCase {
    func testOfflineStorageTopicPageRendererCreatesLocalFile() throws {
        let renderer = OfflineStorageTopicPageRenderer()

        let output = try renderer.render(html: "<html><body>test</body></html>")

        XCTAssertNotNil(output.fileURL)
        XCTAssertNotNil(output.readAccessURL)
    }

    func testTopicPageLoadingErrorHasMessage() {
        XCTAssertEqual(
            TopicPageLoadingError.missingHTML.localizedDescription,
            "No HTML returned for topic page"
        )
    }
}
