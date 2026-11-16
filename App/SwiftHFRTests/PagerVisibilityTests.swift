import CoreGraphics
import Testing

@testable import SwiftHFR

/// #898: the list pager shows only when the list reaches its end.
@Suite struct PagerVisibilityTests {
    // A 2000 pt list in an 800 pt viewport, no insets: the end is reached at offset 1200.
    private func distance(offset: CGFloat, content: CGFloat = 2000, container: CGFloat = 800, inset: CGFloat = 0) -> CGFloat {
        PagerVisibility.distanceFromEnd(offsetY: offset, containerHeight: container, contentHeight: content, bottomInset: inset)
    }

    @Test func hiddenWhileTheListScrollsAwayFromItsEnd() {
        #expect(!PagerVisibility.isShown(distanceFromEnd: distance(offset: 0), voiceOver: false))
        #expect(!PagerVisibility.isShown(distanceFromEnd: distance(offset: 600), voiceOver: false))
    }

    @Test func shownAtTheEndAndHiddenAgainWhenScrollingBackUp() {
        #expect(PagerVisibility.isShown(distanceFromEnd: distance(offset: 1200), voiceOver: false))
        #expect(PagerVisibility.isShown(distanceFromEnd: distance(offset: 1290), voiceOver: false), "rubber band past the end")
        #expect(!PagerVisibility.isShown(distanceFromEnd: distance(offset: 1000), voiceOver: false))
    }

    @Test func aListShorterThanTheScreenShowsItAtOnce() {
        #expect(PagerVisibility.isShown(distanceFromEnd: distance(offset: 0, content: 300), voiceOver: false))
    }

    @Test func theBottomInsetDoesNotMoveTheEnd() {
        // The pager's own inset grows the scrollable range by its height: the end stays the end.
        #expect(PagerVisibility.isShown(distanceFromEnd: distance(offset: 1250, inset: 50), voiceOver: false))
        #expect(!PagerVisibility.isShown(distanceFromEnd: distance(offset: 1000, inset: 50), voiceOver: false))
    }

    @Test func theBarAppearingDoesNotHideItAgain() {
        // At the end (offset 1200) the bar shows and its inset grows 0 -> 52 without the offset moving: still shown.
        let before = distance(offset: 1200)
        #expect(PagerVisibility.isShown(distanceFromEnd: before, wasShown: false, voiceOver: false))
        let after = distance(offset: 1200, inset: 52)
        #expect(after > PagerVisibility.tolerance, "the inset alone pushes the distance past the tolerance")
        #expect(PagerVisibility.isShown(distanceFromEnd: after, wasShown: true, barHeight: 52, voiceOver: false))
        // Scrolling really away hides it, and then it takes the tolerance again to come back.
        #expect(!PagerVisibility.isShown(distanceFromEnd: distance(offset: 1000, inset: 52), wasShown: true, barHeight: 52, voiceOver: false))
        #expect(!PagerVisibility.isShown(distanceFromEnd: after, wasShown: false, voiceOver: false))
    }

    @Test func aTallerBarThanAnyConstantStaysShownToo() {
        // Accessibility text sizes: a 90 pt strip. Shown -> inset 90 -> (offset unchanged) still shown, no flicker.
        let after = distance(offset: 1200, inset: 90)
        #expect(after > 64 + PagerVisibility.tolerance, "past what a 64 pt guess would allow")
        #expect(PagerVisibility.isShown(distanceFromEnd: after, wasShown: true, barHeight: 90, voiceOver: false))
        #expect(!PagerVisibility.isShown(distanceFromEnd: distance(offset: 1000, inset: 90), wasShown: true, barHeight: 90, voiceOver: false))
    }

    @Test func theBarHeightIsMeasuredFromTheStripOrTheInsetItAdds() {
        #expect(PagerVisibility.measuredBarHeight(strip: 90, inset: 0, hiddenInset: nil) == 90)
        #expect(PagerVisibility.measuredBarHeight(strip: 0, inset: 142, hiddenInset: 52) == 90)
        #expect(PagerVisibility.measuredBarHeight(strip: 0, inset: 52, hiddenInset: nil) == 0)
        #expect(PagerVisibility.measuredBarHeight(strip: 40, inset: 30, hiddenInset: 52) == 40)
    }

    @Test func voiceOverAlwaysSeesThePager() {
        #expect(PagerVisibility.isShown(distanceFromEnd: distance(offset: 0), voiceOver: true))
    }

    @Test func noAnimationUnderReduceMotion() {
        #expect(PagerVisibility.animation(reduceMotion: true) == nil)
        #expect(PagerVisibility.animation(reduceMotion: false) != nil)
    }

    @Test func pageActionsListOnlyTheEnabledSteps() {
        let pager = PagerToolbar(
            first: .init(enabled: false) {}, previous: .init(enabled: false) {}, next: .init(enabled: true) {},
            last: .init(enabled: true) {}, status: .page(1)
        )
        #expect(pager.pageActions.map(\.name) == ["Page suivante", "Dernière page"])
        let forumPager = PagerToolbar(
            first: .init(enabled: true) {}, previous: .init(enabled: true) {}, next: .init(enabled: false) {}, last: nil, status: .page(3)
        )
        #expect(forumPager.pageActions.map(\.name) == ["Première page", "Page précédente"])
    }
}
