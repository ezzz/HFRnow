import Foundation
@testable import SwiftHFR
import Testing

/// What the viewer accepts to decode (LOT-109): an image within the pixel budget, nothing else.
struct ImageViewerCheckTests {
    @Test func aRealImageIsShowableAndSampledForDisplay() {
        #expect(ViewerImageCheck.isShowable(readerTestPixel))
        #expect(ViewerImageCheck.displayImage(readerTestPixel) != nil)
    }

    @Test func bytesThatAreNotAnImageAreRefused() {
        #expect(ViewerImageCheck.isShowable(Data("<svg xmlns=\"http://www.w3.org/2000/svg\"/>".utf8)) == false)
        #expect(ViewerImageCheck.isShowable(Data([1, 2, 3])) == false)
        #expect(ViewerImageCheck.isShowable(Data()) == false)
    }

    @Test func anImageClaimingTooManyPixelsIsRefused() {
        // A PNG header whose IHDR says 20000 x 20000 (400 million pixels), with no pixel data: refused on its size, not decoded.
        var png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52])
        png += Data([0, 0, 0x4E, 0x20, 0, 0, 0x4E, 0x20, 8, 2, 0, 0, 0])
        #expect(ViewerImageCheck.isShowable(png) == false)
    }
}
