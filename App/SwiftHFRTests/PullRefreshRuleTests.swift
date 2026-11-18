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

    @Test func aShortPullThenARestFiresNothing() {
        var rule = PullRefreshRule()
        let step1 = rule.update(pull: 10)
        #expect(!step1)
        let step2 = rule.update(pull: threshold - 1)
        #expect(!step2)
        let step3 = rule.update(pull: 0)
        #expect(!step3)
    }

    @Test func reachingFullSizeFiresExactlyOnceForThePull() {
        var rule = PullRefreshRule()
        let step4 = rule.update(pull: threshold - 0.5)
        #expect(!step4)
        let step5 = rule.update(pull: threshold)
        #expect(step5)
        let step6 = rule.update(pull: threshold + 20)
        #expect(!step6, "still pulled: no second refresh")
        let step7 = rule.update(pull: threshold)
        #expect(!step7)
    }

    @Test func dippingBelowTheThresholdWithoutRestingDoesNotFireAgain() {
        var rule = PullRefreshRule()
        let step8 = rule.update(pull: threshold + 5)
        #expect(step8)
        let step9 = rule.update(pull: threshold - 20)
        #expect(!step9)
        let step10 = rule.update(pull: threshold + 5)
        #expect(!step10, "one refresh per pull, not per crossing")
    }

    @Test func aNewPullAfterTheRestFiresAgain() {
        var rule = PullRefreshRule()
        let step11 = rule.update(pull: threshold)
        #expect(step11)
        let step12 = rule.update(pull: 0)
        #expect(!step12)
        let step13 = rule.update(pull: threshold)
        #expect(step13)
    }

    @Test func aNegativeOffsetIsAnotherRest() {
        var rule = PullRefreshRule()
        let step14 = rule.update(pull: threshold)
        #expect(step14)
        let step15 = rule.update(pull: -12)
        #expect(!step15, "scrolled back into the content")
        let step16 = rule.update(pull: threshold)
        #expect(step16)
    }
}
