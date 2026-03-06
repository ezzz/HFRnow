import XCTest
@testable import HFRswift

final class TopicPageRenderingTests: XCTestCase {
    func testOfflineStorageTopicPageRendererCreatesLocalFile() throws {
        let renderer = OfflineStorageTopicPageRenderer()

        let output = try renderer.render(html: "<html><body>test</body></html>")

        XCTAssertNotNil(output.fileURL)
        XCTAssertNotNil(output.readAccessURL)
    }
    
    func testOfflineStorageTopicPageRendererWritesHTMLInGeneratedFile() throws {
        let renderer = OfflineStorageTopicPageRenderer()
        let html = "<html><body><p>hello baseline</p></body></html>"

        let output = try renderer.render(html: html)
        guard let fileURL = output.fileURL else {
            return XCTFail("Expected fileURL")
        }
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let renderedHTML = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertEqual(renderedHTML, html)
        XCTAssertEqual(output.readAccessURL?.standardizedFileURL, fileURL.deletingLastPathComponent().standardizedFileURL)
    }

    func testOfflineStorageTopicPageRendererGeneratesDistinctFilesAcrossCalls() throws {
        let renderer = OfflineStorageTopicPageRenderer()

        let first = try renderer.render(html: "<html><body>first</body></html>")
        let second = try renderer.render(html: "<html><body>second</body></html>")

        guard let firstFileURL = first.fileURL, let secondFileURL = second.fileURL else {
            return XCTFail("Expected both file URLs")
        }
        defer {
            try? FileManager.default.removeItem(at: firstFileURL)
            try? FileManager.default.removeItem(at: secondFileURL)
        }

        XCTAssertNotEqual(firstFileURL.standardizedFileURL, secondFileURL.standardizedFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstFileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondFileURL.path))
    }

    func testTopicPageLoadingErrorHasMessage() {
        XCTAssertEqual(
            TopicPageLoadingError.missingHTML.localizedDescription,
            "No HTML returned for topic page"
        )
    }
}
