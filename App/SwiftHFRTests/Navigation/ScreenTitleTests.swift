@testable import SwiftHFR
import Testing

/// The title rule of the main and pushed screens (#977, #978, #865).
struct ScreenTitleTests {
    @Test func aMainScreenShowsThePillOnlyOnceItsLargeTitleIsGone() {
        #expect(!ScreenTitleStyle.largeThenPill.showsPill(headerVisible: true))
        #expect(ScreenTitleStyle.largeThenPill.showsPill(headerVisible: false))
    }

    @Test func aPushedScreenHasThePillFromTheStart() {
        #expect(ScreenTitleStyle.pill.showsPill(headerVisible: true))
        #expect(ScreenTitleStyle.pill.showsPill(headerVisible: false))
    }

    /// Favoris is a main screen; the category lists a forum row pushes get the pill from the start.
    @Test func onlyTheFavoritesListIsAMainScreenAmongTheTopicLists() {
        #expect(ScreenTitleStyle.topicList(isFavoritesRoot: true) == .largeThenPill)
        #expect(ScreenTitleStyle.topicList(isFavoritesRoot: false) == .pill)
    }

    /// #1012: the bar's centre slot must never be empty, or the system drops it and the pill never appears on the device.
    @Test func theCentreSlotIsNeverEmptyWhateverTheModeAndTheLargeTitle() {
        for style in [ScreenTitleStyle.largeThenPill, .pill] {
            for headerVisible in [true, false] {
                let presentation = style.pillPresentation(headerVisible: headerVisible)
                #expect(presentation == (style.showsPill(headerVisible: headerVisible) ? .shown : .reserved))
            }
        }
        #expect(ScreenTitleStyle.largeThenPill.pillPresentation(headerVisible: true) == .reserved)
        #expect(ScreenTitleStyle.pill.pillPresentation(headerVisible: true) == .shown)
    }

    @Test func aTapShowsTheFullTitleAndTheNextTapOrTheDelayFoldsIt() {
        var state = TitlePillState()
        #expect(!state.isExpanded)
        state.tap()
        #expect(state.isExpanded)
        state.tap()
        #expect(!state.isExpanded)
        state.tap()
        state.fold()
        #expect(!state.isExpanded)
        state.fold()
        #expect(!state.isExpanded)
    }
}
