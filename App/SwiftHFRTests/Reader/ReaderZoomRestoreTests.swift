import CoreGraphics
import Testing
@testable import SwiftHFR

/// Issue #587: a refresh after a pinch zoom reopened several messages too far down, because the reading top was saved in the
/// zoomed scroll view's points and handed to `window.scrollTo`, which counts the page's own (unzoomed) points.
struct ReaderZoomRestoreTests {
    @Test func aZoomedReadingTopIsRestoredInThePagesOwnPoints() {
        // Scrolled to content 500 under a 100-point bar, zoomed 1.8 times: the page's own position is 600 / 1.8.
        let top = ReaderScrollGeometry.readingTop(offsetY: 500, obscuredTop: 100)
        #expect(abs(ReaderScrollGeometry.layoutY(readingTop: top, zoomScale: 1.8) - 600 / 1.8) < 0.001)
        // Zoomed out below 1 the other way round.
        #expect(abs(ReaderScrollGeometry.layoutY(readingTop: 300, zoomScale: 0.5) - 600) < 0.001)
    }

    @Test func anUnzoomedPageIsRestoredWhereItWas() {
        #expect(ReaderScrollGeometry.layoutY(readingTop: 742, zoomScale: 1) == 742)
        #expect(ReaderScrollGeometry.layoutY(readingTop: -40, zoomScale: 1) == -40)
    }

    @Test func aMissingScaleIsNotZoom() {
        #expect(ReaderScrollGeometry.layoutY(readingTop: 500, zoomScale: 0) == 500)
        #expect(ReaderScrollGeometry.layoutY(readingTop: 500, zoomScale: .nan) == 500)
    }
}
