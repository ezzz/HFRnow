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
