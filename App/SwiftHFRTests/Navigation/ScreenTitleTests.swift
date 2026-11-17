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

    @Test func aTapShowsTheFullTitleAndTheNextTapOrAScrollFoldsIt() {
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

    @Test func theFullTitleFoldsBackAfterAboutFourSeconds() {
        #expect(TitlePillState.foldDelay == .seconds(4))
        #expect(TitlePillState.copiedAnnouncement == "Titre copié")
    }
}
