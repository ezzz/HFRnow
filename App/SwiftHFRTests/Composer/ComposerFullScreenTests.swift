import Foundation
import SwiftUI
@testable import SwiftHFR
import Testing

/// #1137 (operator 2026-11-18): a new private message and a new topic always open full screen, with no height toggle; replies
/// and edits keep the partial height and its toggle.
@MainActor
struct ComposerFullScreenTests {
    private func model(_ target: ComposerTarget) -> ReplyComposerModel {
        ReplyComposerModel(composing: target, services: ComposerFixture.services(poster: ScriptedPoster([])), autosaveDelay: .seconds(60))
    }

    @Test func onlyANewMessageAndANewTopicOpenFullScreen() {
        #expect(model(.newPrivateMessage(newMessageTarget)).opensFullScreen)
        #expect(model(.newTopic(newTopicTarget)).opensFullScreen)
        #expect(!model(.reply(replyTarget)).opensFullScreen)
    }

    @Test(arguments: [nil, ComposerHeight.partial, .full])
    func aComposerThatOpensFullIsFullWhateverWasChosenAndOffersNoToggle(chosen: ComposerHeight?) {
        #expect(ComposerHeight.shown(chosen: chosen, isPhone: true, verticalSizeClass: .regular, opensFull: true) == .full)
        #expect(!ComposerHeight.offersToggle(isPhone: true, verticalSizeClass: .regular, opensFull: true))
    }

    @Test func aReplyOrAnEditKeepsThePartialHeightAndItsToggle() {
        #expect(ComposerHeight.shown(chosen: nil, isPhone: true, verticalSizeClass: .regular, opensFull: false) == .partial)
        #expect(ComposerHeight.offersToggle(isPhone: true, verticalSizeClass: .regular, opensFull: false))
        #expect(ComposerHeight.shown(chosen: nil, isPhone: true, verticalSizeClass: .regular) == .partial, "the default is unchanged")
    }
}
