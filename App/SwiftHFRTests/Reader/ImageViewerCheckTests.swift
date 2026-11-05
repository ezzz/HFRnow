import Foundation
import ImageIO
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

    @Test func anImageClaimingTooManyPixelsIsRefused() throws {
        // A well-formed PNG (IHDR with its CRC, IEND) that says 20000 x 20000 = 400 million pixels, with no pixel data.
        let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAATiAAAE4gCAIAAABsEtFuAAAAAElFTkSuQmCC"))
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        // ImageIO reads the size, so it is the pixel budget that refuses it.
        #expect(properties?[kCGImagePropertyPixelWidth] as? Int == 20_000)
        #expect(ViewerImageCheck.isShowable(png) == false)
    }
}
