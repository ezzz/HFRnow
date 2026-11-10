import Foundation
import HFRModels
@testable import SwiftHFR
import Testing

/// Where the composer opens (#653): at partial height on an iPhone for a reply or an edit, so the page being answered
/// stays visible above it; full height otherwise, as before. The toggle goes from one to the other.
struct ComposerPresentationTests {
    private static let edit: ComposerTarget = {
        let topic = TopicID(category: .forum(6), topic: 9_900_001)
        let link = url(
            "https://forum.hardware.fr/message.php?config=hfr.inc&cat=6&post=9900001&numreponse=9910000006&page=1&p=1&subcat=173#formulaire"
        )
        guard let target = EditTarget(link: link, post: 9_910_000_006, topic: topic) else { preconditionFailure("an edit link") }
        return .edit(target)
    }()

    @Test(arguments: [true, false])
    func aReplyOrAnEditOpensAtPartialHeightOnlyOnAnIPhone(isPhone: Bool) {
        let expected: ComposerHeight = isPhone ? .partial : .full
        #expect(ComposerHeight.initial(for: .reply(replyTarget), isPhone: isPhone) == expected)
        #expect(ComposerHeight.initial(for: Self.edit, isPhone: isPhone) == expected)
        #expect(ComposerHeight.offersToggle(for: .reply(replyTarget), isPhone: isPhone) == isPhone)
    }

    @Test func aNewTopicOrANewMessageKeepsTheFullHeightWithoutAToggle() {
        for target: ComposerTarget in [.newTopic(newTopicTarget), .newPrivateMessage(newMessageTarget)] {
            #expect(ComposerHeight.initial(for: target, isPhone: true) == .full)
            #expect(!ComposerHeight.offersToggle(for: target, isPhone: true))
        }
    }

    @Test func theToggleGoesBothWays() {
        #expect(ComposerHeight.partial.toggled == .full)
        #expect(ComposerHeight.full.toggled == .partial)
    }

    @Test func thePartialHeightLeavesTheTopThirdToThePage() {
        // The system lifts the sheet above the keyboard: a third of the room, the keyboard below it, the page above.
        #expect(ComposerHeight.partialHeight(available: 900) == 300)
        // A short room (landscape, a small phone) still fits two lines of text and the control row, never more than the room.
        #expect(ComposerHeight.partialHeight(available: 450) == 220)
        #expect(ComposerHeight.partialHeight(available: 200) == 200)
    }
}
