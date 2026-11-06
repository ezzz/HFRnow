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

    @Test func thePixelBudgetRefusesAnImageThatClaimsTooMany() {
        #expect(ViewerImageCheck.fitsBudget(width: 10_000, height: 10_000)) // exactly the budget
        #expect(ViewerImageCheck.fitsBudget(width: 10_001, height: 10_000) == false)
        #expect(ViewerImageCheck.fitsBudget(width: 20_000, height: 20_000) == false)
        #expect(ViewerImageCheck.fitsBudget(width: Int.max, height: Int.max) == false)
        #expect(ViewerImageCheck.fitsBudget(width: 0, height: 10) == false)
        #expect(ViewerImageCheck.fitsBudget(width: 10, height: 0) == false)
    }

    @Test func aHeaderOnlyPNGClaimingTooManyPixelsIsRefused() throws {
        // A well-formed PNG (IHDR with its CRC, IEND) that says 20000 x 20000 and holds no pixel data. Whether ImageIO reports
        // its size or refuses it first, it must never be showable.
        let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAATiAAAE4gCAIAAABsEtFuAAAAAElFTkSuQmCC"))
        #expect(ViewerImageCheck.isShowable(png) == false)
    }
}
