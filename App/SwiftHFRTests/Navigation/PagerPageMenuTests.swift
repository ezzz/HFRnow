@testable import SwiftHFR
import Testing

/// The « page x / y » menu (#968, #980): targets, disabled states at the bounds, the typed entry.
struct PagerPageMenuTests {
    @Test func inTheMiddleEveryStepIsEnabledAndAimsOneStepAway() {
        let menu = PagerPageMenu(current: 5, total: 12)
        #expect(menu.canGoFirst && menu.canGoPrevious && menu.canGoNext && menu.canGoLast && menu.canEnterPage)
        #expect([menu.firstPage, menu.previousPage, menu.nextPage, menu.lastPage] == [1, 4, 6, 12])
    }

    @Test func onTheFirstPageBackwardsStepsAreDisabled() {
        let menu = PagerPageMenu(current: 1, total: 12)
        #expect(!menu.canGoFirst && !menu.canGoPrevious && menu.canGoNext && menu.canGoLast)
        #expect(menu.previousPage == 1)
    }

    @Test func onTheLastPageForwardsStepsAreDisabled() {
        let menu = PagerPageMenu(current: 12, total: 12)
        #expect(menu.canGoFirst && menu.canGoPrevious && !menu.canGoNext && !menu.canGoLast)
        #expect(menu.nextPage == 12)
    }

    @Test func aSinglePageOffersNothing() {
        let menu = PagerPageMenu(current: 1, total: 1)
        #expect(!menu.canGoFirst && !menu.canGoPrevious && !menu.canGoNext && !menu.canGoLast && !menu.canEnterPage)
    }

    @Test func aTotalBelowTheCurrentPageIsRaisedToIt() {
        let menu = PagerPageMenu(current: 7, total: 3)
        #expect(menu.total == 7 && !menu.canGoNext)
        #expect(PagerPageMenu(current: 0, total: 0).current == 1)
    }

    @Test func aTypedEntryIsAcceptedWithinTheBoundsOnly() {
        let menu = PagerPageMenu(current: 2, total: 12)
        #expect(menu.page(fromEntry: "8") == 8)
        #expect(menu.page(fromEntry: " 12 ") == 12)
        #expect(menu.page(fromEntry: "1") == 1)
        #expect(menu.page(fromEntry: "0") == nil)
        #expect(menu.page(fromEntry: "13") == nil)
        #expect(menu.page(fromEntry: "-3") == nil)
        #expect(menu.page(fromEntry: "huit") == nil)
        #expect(menu.page(fromEntry: "") == nil)
    }
}
