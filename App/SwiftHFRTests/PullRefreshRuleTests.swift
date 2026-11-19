import Foundation
@testable import SwiftHFR
import Testing

/// The rule of the pull to refresh from either end of a page (#1207): the icon grows with the pull, the refresh fires once, when
/// the icon is full, and a release before that does nothing.
struct PullRefreshRuleTests {
    private let threshold = PullRefreshRule.threshold

    @Test func theIconGrowsLinearlyFromNothingToFullSize() {
        #expect(PullRefreshRule.scale(forPull: 0) == 0)
        #expect(PullRefreshRule.scale(forPull: threshold / 2) == 0.5)
        #expect(PullRefreshRule.scale(forPull: threshold) == 1)
    }

    @Test func theIconNeverExceedsFullSizeNorGoesNegative() {
        #expect(PullRefreshRule.scale(forPull: threshold * 3) == 1)
        #expect(PullRefreshRule.scale(forPull: -40) == 0)
    }

    @MainActor
    @Test func theThresholdIsTheReadersExistingSeventyTwoPoints() {
        #expect(PullRefreshRule.threshold == 72)
        #expect(ReaderPullWatcher.threshold == PullRefreshRule.threshold, "one threshold for the reader and the lists")
    }

    @Test func aShortPullThenALiftFiresNothing() {
        var rule = PullRefreshRule()
        let first = rule.update(pull: 10, fingerDown: true)
        let second = rule.update(pull: threshold - 1, fingerDown: true)
        let lifted = rule.update(pull: 0, fingerDown: false)
        #expect(!first && !second && !lifted)
    }

    @Test func reachingFullSizeFiresExactlyOnceForTheTouch() {
        var rule = PullRefreshRule()
        let short = rule.update(pull: threshold - 0.5, fingerDown: true)
        let full = rule.update(pull: threshold, fingerDown: true)
        let past = rule.update(pull: threshold + 20, fingerDown: true)
        let again = rule.update(pull: threshold, fingerDown: true)
        #expect(!short)
        #expect(full)
        #expect(!past && !again, "still pulled: no second refresh")
    }

    @Test func dippingBelowTheThresholdWithTheFingerDownDoesNotFireAgain() {
        var rule = PullRefreshRule()
        let first = rule.update(pull: threshold + 5, fingerDown: true)
        let dip = rule.update(pull: threshold - 20, fingerDown: true)
        let back = rule.update(pull: threshold + 5, fingerDown: true)
        #expect(first)
        #expect(!dip && !back, "one refresh per touch, not per crossing")
    }

    @Test func aNewTouchAfterTheFingerLeftFiresAgain() {
        var rule = PullRefreshRule()
        let first = rule.update(pull: threshold, fingerDown: true)
        let lifted = rule.update(pull: 0, fingerDown: false)
        let second = rule.update(pull: threshold, fingerDown: true)
        #expect(first && !lifted && second)
    }

    /// A lift with no offset change after it (no momentum) still arms the next touch.
    @Test func aLiftArmsTheNextTouchWithoutAnyOffsetChange() {
        var rule = PullRefreshRule()
        let first = rule.update(pull: threshold, fingerDown: true)
        rule.fingerLifted()
        let second = rule.update(pull: threshold, fingerDown: true)
        #expect(first && second)
    }

    /// A refresh resets the page to its top (WebKit, #642): a rest with the finger still down, so a member who keeps pulling
    /// gets no second refresh in the same touch.
    @Test func aRestWithTheFingerStillDownDoesNotArmTheNextPull() {
        var rule = PullRefreshRule()
        let first = rule.update(pull: threshold, fingerDown: true)
        let reset = rule.update(pull: -12, fingerDown: true)
        let second = rule.update(pull: threshold, fingerDown: true)
        #expect(first)
        #expect(!reset && !second)
    }
}
