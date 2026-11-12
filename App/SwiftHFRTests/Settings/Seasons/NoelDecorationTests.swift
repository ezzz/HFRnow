import CoreGraphics
import Foundation
import Observation
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

    /// A drag reports every frame: only a change of state is written, so the snow's observers are not invalidated per frame.
    @Test func repeatedReportsWriteNothing() {
        let activity = SeasonalScrollActivity()
        let source = NSObject()
        let key = ObjectIdentifier(source)
        activity.set(key, scrolling: true)
        let writes = Counter()
        func observe() {
            withObservationTracking { _ = activity.moving } onChange: { writes.add() }
        }
        observe()
        activity.set(key, scrolling: true)
        #expect(writes.value == 0)
        activity.set(key, scrolling: false)
        #expect(writes.value == 1)
        observe()
        activity.set(key, scrolling: false)
        #expect(writes.value == 1)
        withExtendedLifetime(source) {}
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

/// A count bumped from observation callbacks, which are `@Sendable`.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int { lock.withLock { count } }

    func add() { lock.withLock { count += 1 } }
}
