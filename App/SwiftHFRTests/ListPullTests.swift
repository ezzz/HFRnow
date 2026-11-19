import SwiftUI
@testable import SwiftHFR
import Testing

/// The geometry-to-pull formula behind the lists' pull to refresh (#1207), tested on `ScrollGeometry` values: no finger needed.
struct ListPullTests {
    private func geometry(offset: CGFloat, content: CGFloat, viewport: CGFloat = 800, top: CGFloat = 100, bottom: CGFloat = 80)
        -> ScrollGeometry {
        ScrollGeometry(
            contentOffset: CGPoint(x: 0, y: offset), contentSize: CGSize(width: 390, height: content),
            contentInsets: EdgeInsets(top: top, leading: 0, bottom: bottom, trailing: 0),
            containerSize: CGSize(width: 390, height: viewport)
        )
    }

    @Test func atRestUnderTheBarsThereIsNoPull() {
        let pull = ListPull(geometry(offset: -100, content: 2000))
        #expect(pull == ListPull(top: 0, bottom: 0))
    }

    @Test func pastTheTopIsMeasuredFromTheTopInset() {
        let pull = ListPull(geometry(offset: -100 - 40, content: 2000))
        #expect(pull.top == 40 && pull.bottom == 0)
    }

    @Test func pastTheEndIsMeasuredAboveTheBottomInset() {
        // The last offset is 2000 + 80 - 800 = 1280.
        #expect(ListPull(geometry(offset: 1280, content: 2000)).bottom == 0)
        let pull = ListPull(geometry(offset: 1280 + 30, content: 2000))
        #expect(pull.bottom == 30 && pull.top == 0)
    }

    @Test func aListShorterThanItsViewportIsPulledFromWhereItsContentEnds() {
        let rest = ListPull(geometry(offset: -100, content: 300))
        let pulled = ListPull(geometry(offset: -100 + 25, content: 300))
        #expect(rest.bottom == 0)
        #expect(pulled.bottom == 25, "the short list's bottom pull starts at its top")
    }
}
