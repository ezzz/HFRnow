import CoreGraphics
@testable import SwiftHFR
import SwiftUI
import Testing
import UIKit

/// Piled snow, the snow's pauses and the art (LOT-166, THEMES.md §4 rules 6–9).
@MainActor
struct NoelDecorationTests {
    /// The caps sit on the card's top edge and enter it by less than a row's top padding: never down to its text.
    @Test func capsStayAboveTheFirstRowsText() {
        let frames = SnowPileLayout.capFrames(cardWidth: 370)
        #expect(frames.count == 2)
        for frame in frames {
            #expect(frame.maxY > 0)
            #expect(frame.maxY < SnowPileLayout.rowTextPadding)
            #expect(frame.minX >= 0 && frame.maxX <= 370)
        }
        #expect(SnowPileLayout.capFrames(cardWidth: 0).isEmpty)
    }

    /// Drifts stay in the bottom safe area, clear of the home indicator in the middle; none without one.
    @Test func bottomDriftsStayInTheSafeAreaAndOffTheHomeIndicator() {
        let frames = SnowPileLayout.bottomFrames(width: 402, height: 874, bottomInset: 34)
        #expect(frames.count == 2)
        for frame in frames {
            #expect(frame.minY >= 874 - 34 && frame.maxY <= 874)
            #expect(frame.maxX <= (402 - SnowPileLayout.homeIndicatorClearance) / 2 + 0.001
                || frame.minX >= (402 + SnowPileLayout.homeIndicatorClearance) / 2 - 0.001)
        }
        #expect(SnowPileLayout.bottomFrames(width: 402, height: 874, bottomInset: 0).isEmpty)
    }

    @Test(arguments: [(true, false, false, false), (false, false, false, true), (true, true, false, true), (true, false, true, true)])
    func snowPausesWhenInactiveInLowPowerAndWhileScrolling(active: Bool, lowPower: Bool, scrolling: Bool, paused: Bool) {
        #expect(NoelSnowLayer.isPaused(active: active, lowPower: lowPower, scrolling: scrolling) == paused)
    }

    @Test func scrollingLastsUntilEveryScrollViewStops() {
        let activity = SeasonalScrollActivity()
        // Kept alive, so the two identifiers differ.
        let sources = (NSObject(), NSObject())
        let list = ObjectIdentifier(sources.0)
        let reader = ObjectIdentifier(sources.1)
        activity.set(list, scrolling: true)
        activity.set(reader, scrolling: true)
        activity.set(list, scrolling: false)
        #expect(activity.isScrolling)
        activity.set(reader, scrolling: false)
        #expect(!activity.isScrolling)
        withExtendedLifetime(sources) {}
    }

    @Test(arguments: NoelCrossingItem.allCases)
    func everyItemHasItsTransparentImage(item: NoelCrossingItem) throws {
        let image = try #require(UIImage(named: item.assetName))
        #expect(abs(image.size.width / image.size.height - item.aspectRatio) < 0.02)
        let alpha = image.cgImage?.alphaInfo
        #expect(alpha != CGImageAlphaInfo.none && alpha != .noneSkipLast && alpha != .noneSkipFirst)
    }

    @Test func onlyTheSleighHasAFront() {
        #expect(NoelCrossingItem.allCases.filter(\.isDirectional) == [.sleigh])
        #expect(UIImage(named: "NoelSnowPile") != nil)
    }
}
