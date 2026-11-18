import Foundation
@testable import SwiftHFR
import Testing

/// The two ends of a list (#1207): each pull grows its own icon, the refresh fires once when one is full, and a scroll without a
/// finger (a fling that overshoots) is no pull.
struct PullEdgesTrackerTests {
    private let full = PullRefreshRule.threshold

    @Test func aPullFromTheTopGrowsTheTopIconAndFiresWhenItIsFull() {
        var tracker = PullEdgesTracker()
        let half = tracker.update(topPull: full / 2, bottomPull: 0, fingerDown: true)
        #expect(half.top == 0.5 && half.bottom == 0 && !half.fires)
        let reached = tracker.update(topPull: full, bottomPull: 0, fingerDown: true)
        #expect(reached.top == 1 && reached.fires)
    }

    @Test func aPullFromTheBottomGrowsTheBottomIconAndFiresWhenItIsFull() {
        var tracker = PullEdgesTracker()
        let half = tracker.update(topPull: 0, bottomPull: full / 2, fingerDown: true)
        #expect(half.bottom == 0.5 && half.top == 0 && !half.fires)
        let step1 = tracker.update(topPull: 0, bottomPull: full, fingerDown: true).fires
        #expect(step1)
    }

    @Test func eachEndFiresOnceForItsPullAndAgainAfterARest() {
        var tracker = PullEdgesTracker()
        let step2 = tracker.update(topPull: full, bottomPull: 0, fingerDown: true).fires
        #expect(step2)
        let step3 = tracker.update(topPull: full + 40, bottomPull: 0, fingerDown: true).fires
        #expect(!step3, "held: still one")
        let step4 = tracker.update(topPull: 0, bottomPull: 0, fingerDown: true).fires
        #expect(!step4)
        let step5 = tracker.update(topPull: full, bottomPull: 0, fingerDown: true).fires
        #expect(step5, "a new pull")
        let step6 = tracker.update(topPull: 0, bottomPull: full, fingerDown: true).fires
        #expect(step6, "the other end has its own rule")
    }

    @Test func aReleaseBeforeFullSizeDoesNothing() {
        var tracker = PullEdgesTracker()
        _ = tracker.update(topPull: full - 1, bottomPull: 0, fingerDown: true)
        let released = tracker.update(topPull: full - 1, bottomPull: 0, fingerDown: false)
        #expect(!released.fires)
        #expect(released.top == 0, "no finger: the icon goes")
    }

    @Test func aScrollWithoutAFingerIsNoPull() {
        var tracker = PullEdgesTracker()
        let fling = tracker.update(topPull: full * 2, bottomPull: full * 2, fingerDown: false)
        #expect(!fling.fires)
        #expect(fling.top == 0 && fling.bottom == 0)
    }
}
