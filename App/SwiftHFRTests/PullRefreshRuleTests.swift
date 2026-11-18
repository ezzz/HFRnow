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

    @Test func theThresholdIsTheReadersExistingSeventyTwoPoints() {
        #expect(PullRefreshRule.threshold == 72)
        #expect(ReaderPullWatcher.threshold == PullRefreshRule.threshold, "one threshold for the reader and the lists")
    }

    @Test func aShortPullThenARestFiresNothing() {
        var rule = PullRefreshRule()
        #expect(!rule.update(pull: 10))
        #expect(!rule.update(pull: threshold - 1))
        #expect(!rule.update(pull: 0))
    }

    @Test func reachingFullSizeFiresExactlyOnceForThePull() {
        var rule = PullRefreshRule()
        #expect(!rule.update(pull: threshold - 0.5))
        #expect(rule.update(pull: threshold))
        #expect(!rule.update(pull: threshold + 20), "still pulled: no second refresh")
        #expect(!rule.update(pull: threshold))
    }

    @Test func dippingBelowTheThresholdWithoutRestingDoesNotFireAgain() {
        var rule = PullRefreshRule()
        #expect(rule.update(pull: threshold + 5))
        #expect(!rule.update(pull: threshold - 20))
        #expect(!rule.update(pull: threshold + 5), "one refresh per pull, not per crossing")
    }

    @Test func aNewPullAfterTheRestFiresAgain() {
        var rule = PullRefreshRule()
        #expect(rule.update(pull: threshold))
        #expect(!rule.update(pull: 0))
        #expect(rule.update(pull: threshold))
    }

    @Test func aNegativeOffsetIsAnotherRest() {
        var rule = PullRefreshRule()
        #expect(rule.update(pull: threshold))
        #expect(!rule.update(pull: -12), "scrolled back into the content")
        #expect(rule.update(pull: threshold))
    }
}
