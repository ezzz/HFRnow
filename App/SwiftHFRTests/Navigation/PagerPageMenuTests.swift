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

    @Test func aLowerBoundTotalHidesLastPageLabelsItWithAPlusAndAcceptsLaterPages() {
        let menu = PagerPageMenu(current: 1, total: 10, isExact: false)
        #expect(!menu.canGoLast && menu.canGoNext && menu.canEnterPage)
        #expect(menu.label == "page 1 / 10+")
        #expect(menu.page(fromEntry: "23") == 23)
        #expect(menu.page(fromEntry: "0") == nil)
        #expect(PagerPageMenu(current: 1, total: 10).label == "page 1 / 10")
    }

    /// #1154: « Aller » is off while the entry cannot be taken, so the alert never closes on nothing; the range is in its message.
    @Test(arguments: [
        ("8", true), ("12", true), ("1", true), ("0", false), ("13", false), ("9999", false), ("huit", false), ("", false), (" ", false)
    ])
    func theGoButtonIsOnlyOnForAnEntryInRange(entry: String, accepted: Bool) {
        #expect(PagerPageMenu(current: 2, total: 12).canSubmit(entry: entry) == accepted)
    }

    @Test func theAlertMessageStatesTheRange() {
        #expect(PagerPageMenu(current: 2, total: 12).entryMessage == "Choisir une page entre 1 et 12")
        #expect(PagerPageMenu(current: 1, total: 10, isExact: false).entryMessage == "Choisir une page à partir de 1 (au moins 10 pages)")
        #expect(PagerPageMenu(current: 1, total: 10, isExact: false).canSubmit(entry: "23"))
    }
}
