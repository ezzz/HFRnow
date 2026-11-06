import Foundation
import HFRModels
import HFRNetwork
@testable import SwiftHFR
import Testing

/// The live quoter on a real session: the selection is the session's cookie, and releasing it touches only the messages the
/// posted text still quotes (LOT-049's rule, LOT-042's cookie).
struct LiveQuoterTests {
    private let topic = TopicID(category: .forum(13), topic: 28563)
    private func token(_ number: Int, topic: TopicID? = nil) -> QuoteSelectionToken {
        QuoteSelectionToken(forum: "hardwarefr", topic: topic ?? self.topic, numreponse: number)
    }

    private let elsewhere = TopicID(category: .forum(13), topic: 99)

    private func quoter(selected: [Int] = [], other: [Int] = []) async -> (LiveQuoter, HFRSession) {
        let session = HFRSession()
        let quoter = LiveQuoter(session: session)
        for number in selected { _ = await quoter.toggle(token(number)) }
        for number in other { _ = await quoter.toggle(token(number, topic: elsewhere)) }
        return (quoter, session)
    }

    @Test func theToggleSelectsAndUnselectsInTheSessionsCookieInToggleOrder() async {
        let (quoter, session) = await quoter()
        #expect(await quoter.toggle(token(12)))
        #expect(await quoter.toggle(token(3)))
        #expect(await quoter.selectedNumbers(for: token(12)) == [12, 3])
        #expect(!(await quoter.toggle(token(12))))
        #expect(await quoter.selectedNumbers(for: token(3)) == [3])
        #expect(await session.isQuoteSelected(token(3)))
    }

    @Test func theNumbersAreMatchedExactlyNotBySubstring() async {
        let (quoter, _) = await quoter(selected: [12, 123])
        #expect(await quoter.toggle(token(1)))
        #expect(await quoter.selectedNumbers(for: token(1)) == [12, 123, 1])
    }

    @Test func releaseUnselectsTheMessagesThePostedTextStillQuotes() async {
        let (quoter, _) = await quoter(selected: [100, 101, 102])
        let release = QuoteRelease(token: token(100), numbers: [100, 101])
        await quoter.release(release, postedText: "[quotemsg=100,13,900001]a[/quotemsg]\nmerci\n[QUOTEMSG=101,13,900002]b[/QUOTEMSG]")
        // 102 was selected after the composer was loaded: it stays.
        #expect(await quoter.selectedNumbers(for: token(100)) == [102])
    }

    @Test func aBlockTheUserRemovedLeavesItsMessageSelected() async {
        let (quoter, _) = await quoter(selected: [100, 101])
        await quoter.release(
            QuoteRelease(token: token(100), numbers: [100, 101]), postedText: "[quotemsg=100,13,900001]a[/quotemsg]"
        )
        #expect(await quoter.selectedNumbers(for: token(100)) == [101])
    }

    @Test func aMessageUnselectedMeanwhileIsNotSelectedAgain() async {
        let (quoter, _) = await quoter(selected: [100])
        _ = await quoter.toggle(token(101))
        _ = await quoter.toggle(token(101))
        await quoter.release(
            QuoteRelease(token: token(100), numbers: [100, 101]), postedText: "[quotemsg=101,13,900001]b[/quotemsg]"
        )
        #expect(await quoter.selectedNumbers(for: token(100)) == [100])
    }

    @Test func releaseNeverTouchesAnotherTopicsSelection() async {
        let (quoter, _) = await quoter(selected: [100], other: [100, 5])
        await quoter.release(QuoteRelease(token: token(100), numbers: [100]), postedText: "[quotemsg=100,13,900001]a[/quotemsg]")
        #expect(await quoter.selectedNumbers(for: token(100)).isEmpty)
        #expect(await quoter.selectedNumbers(for: token(1, topic: elsewhere)) == [100, 5])
    }

    @Test func textWithoutQuoteBlocksReleasesNothing() async {
        let (quoter, _) = await quoter(selected: [100])
        await quoter.release(QuoteRelease(token: token(100), numbers: [100]), postedText: "pas de citation, mais [quotemsg=abc]")
        #expect(await quoter.selectedNumbers(for: token(100)) == [100])
    }

    @Test func quotedNumbersReadTheFirstNumberOfEachTag() {
        let text = "[quotemsg=100,13,900001]a[/quotemsg]\n[quotemsg=7,13,5]b[/quotemsg] [quotemsg=100,1,1]c[/quotemsg]"
        #expect(LiveQuoter.quotedNumbers(in: text) == [100, 7])
    }
}
