import Foundation
import HFRClient
import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing

/// A quote in the reply composer (LOT-086): merged into the restored draft, saved like typing, and the multi-quote selection
/// released only once HFR confirmed the reply that quotes it.
@MainActor
struct ReplyComposerQuoteTests {
    private let block = "[quotemsg=100,13,900001]Bonjour[/quotemsg]\n"
    private let selection = QuoteRelease(token: quoteToken(100), numbers: [100, 101])

    private func composer(
        quote: ReplyQuote?, poster: ScriptedPoster = ScriptedPoster([]),
        drafts: DraftStore = DraftStore(persistence: InMemoryDraftPersistence()), quoter: ScriptedQuoter = ScriptedQuoter(),
        target: ComposerTarget? = nil
    ) -> ReplyComposerModel {
        var services = ComposerFixture.services(poster: poster, drafts: drafts)
        services.quoting = quoter
        return ReplyComposerModel(composing: target ?? .reply(replyTarget), services: services, autosaveDelay: .seconds(60), quote: quote)
    }

    @Test func aQuoteOpensAnEmptyDraftWithTheQuoteAsServed() async {
        let model = composer(quote: ReplyQuote(text: block))
        await model.start()
        #expect(model.text == block)
    }

    @Test func aQuoteGoesAfterTheRestoredDraftWithABlankLine() async {
        let drafts = DraftStore(persistence: InMemoryDraftPersistence())
        try? await drafts.save("Mon brouillon", subject: nil, for: replyTarget.draftContext, account: ComposerFixture.account)
        let model = composer(quote: ReplyQuote(text: block), drafts: drafts)
        await model.start()
        #expect(model.text == "Mon brouillon\n\n" + block)
    }

    @Test func aQuoteTheDraftAlreadyHoldsIsNotAddedTwice() async {
        let drafts = DraftStore(persistence: InMemoryDraftPersistence())
        try? await drafts.save("Avant\n\n" + block, subject: nil, for: replyTarget.draftContext, account: ComposerFixture.account)
        let model = composer(quote: ReplyQuote(text: block), drafts: drafts)
        await model.start()
        #expect(model.text == "Avant\n\n" + block)
    }

    @Test func theMergedTextIsSavedAsTheDraftAfterAPause() async {
        let drafts = DraftStore(persistence: InMemoryDraftPersistence())
        let model = composer(quote: ReplyQuote(text: block), drafts: drafts)
        await model.start()
        await model.flushDraft()
        #expect(await ComposerFixture.storedText(drafts) == block)
    }

    @Test func noQuoteLeavesTheRestoredDraftAlone() async {
        let drafts = DraftStore(persistence: InMemoryDraftPersistence())
        try? await drafts.save("Mon brouillon", subject: nil, for: replyTarget.draftContext, account: ComposerFixture.account)
        let model = composer(quote: nil, drafts: drafts)
        await model.start()
        #expect(model.text == "Mon brouillon")
    }

    @Test func aPrivateMessageNeverTakesAQuote() async {
        let model = composer(quote: ReplyQuote(text: block, release: selection), target: .newPrivateMessage(newMessageTarget))
        await model.start()
        #expect(model.text.isEmpty)
    }

    // MARK: Release

    @Test func theSelectionIsReleasedOnlyAfterHFRConfirmedTheReply() async {
        let quoter = ScriptedQuoter(selected: [100, 101])
        let poster = ScriptedPoster([.success(replyConfirmed)])
        let model = composer(quote: ReplyQuote(text: block, release: selection), poster: poster, quoter: quoter)
        await model.start()
        model.update(text: block + "\nD'accord.")
        #expect(quoter.releases.isEmpty)
        await model.send()
        #expect(model.closeReason == .sent(replyConfirmed))
        #expect(quoter.releases == [ReleaseCall(release: selection, postedText: block + "\nD'accord.")])
    }

    @Test(arguments: [
        PostingError.rejected(message: "flood"),
        .notLoggedIn,
        .network(.offline),
        .unconfirmed(.transport(.timedOut)),
        .unconfirmed(.unrecognizedAnswer(message: nil))
    ])
    func everyOtherOutcomeKeepsTheSelection(_ failure: PostingError) async {
        let quoter = ScriptedQuoter(selected: [100, 101])
        let model = composer(
            quote: ReplyQuote(text: block, release: selection), poster: ScriptedPoster([.failure(failure)]), quoter: quoter
        )
        await model.start()
        await model.send()
        #expect(model.closeReason == nil)
        #expect(quoter.releases.isEmpty)
        #expect(quoter.selected == [100, 101])
    }

    @Test func aRefusedLocalSendKeepsTheSelectionToo() async {
        let quoter = ScriptedQuoter(selected: [100])
        let poster = ScriptedPoster([.success(replyConfirmed)])
        let model = composer(quote: ReplyQuote(text: block, release: selection), poster: poster, quoter: quoter)
        await model.start()
        model.update(text: block + "😀")
        await model.send()
        #expect(poster.calls.isEmpty)
        #expect(quoter.releases.isEmpty)
    }

    @Test func aSingleQuoteNeverTouchesTheSelection() async {
        let quoter = ScriptedQuoter(selected: [100])
        let poster = ScriptedPoster([.success(replyConfirmed)])
        let model = composer(quote: ReplyQuote(text: block), poster: poster, quoter: quoter)
        await model.start()
        await model.send()
        #expect(model.closeReason == .sent(replyConfirmed))
        #expect(quoter.releases.isEmpty)
        #expect(quoter.selected == [100])
    }

    @Test func aReplyWithoutAnyQuoteReleasesNothing() async {
        let quoter = ScriptedQuoter(selected: [100])
        let model = composer(quote: nil, poster: ScriptedPoster([.success(replyConfirmed)]), quoter: quoter)
        await model.start()
        model.update(text: "Salut")
        await model.send()
        #expect(model.closeReason == .sent(replyConfirmed))
        #expect(quoter.releases.isEmpty)
    }

    @Test func aTextSentTwiceAfterAFailureReleasesOnceOnTheConfirmedSend() async {
        let quoter = ScriptedQuoter(selected: [100, 101])
        let poster = ScriptedPoster([.failure(.network(.offline)), .success(replyConfirmed)])
        let model = composer(quote: ReplyQuote(text: block, release: selection), poster: poster, quoter: quoter)
        await model.start()
        await model.send()
        #expect(quoter.releases.isEmpty)
        await model.send()
        #expect(quoter.releases.count == 1)
    }
}
