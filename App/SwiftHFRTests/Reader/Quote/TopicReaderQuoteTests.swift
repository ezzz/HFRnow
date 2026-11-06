import Foundation
import HFRClient
import HFRModels
@testable import SwiftHFR
import Testing

/// Quoting from the reader (LOT-086): what "Citer", the multi-quote toggle, "Citer extrait" / "Citer gras" and the reply button
/// hand to the composer, and what they never do.
@MainActor
struct TopicReaderQuoteTests {
    private let prefill = "[quotemsg=100,13,900001]Bonjour tout le monde[/quotemsg]\n"

    private func reader(
        quoter: ScriptedQuoter?, page: ReaderPage = quotablePage(), registered: Bool = true
    ) async -> TopicReaderModel {
        let model = TopicReaderModel(
            target: ReaderTarget(source: .topic(readerTopic)), title: "Sujet", source: FakeTopicPages { _ in page }
        )
        model.quoting = quoter
        if registered { model.install(MessageActionRegistry(model.quoteHandlers(confirm: { _ in }))) }
        await model.onAppear()
        return model
    }

    // MARK: Citer

    @Test func quoteOpensTheComposerWithHFRsQuoteOfThatMessageAndLeavesTheSelectionAlone() async throws {
        let quoter = ScriptedQuoter(selected: [101])
        quoter.scriptQuote(.success(prefill))
        let model = await reader(quoter: quoter)
        await model.quoteMessage(post: 100)
        #expect(quoter.quoteLinks == [quoteLink(100)])
        #expect(model.pendingReply?.quote == ReplyQuote(text: prefill, release: nil))
        #expect(quoter.selected == [101])
        #expect(quoter.releases.isEmpty)
    }

    @Test func aFailedQuoteOpensNothingAndSaysWhy() async {
        let quoter = ScriptedQuoter()
        quoter.scriptQuote(.failure(.noQuote))
        let model = await reader(quoter: quoter)
        await model.quoteMessage(post: 100)
        #expect(model.pendingReply == nil)
        #expect(model.menuFeedback == ComposerMessages.quote(.noQuote))
        #expect(!model.isLoadingQuote)
    }

    @Test func aContinuationCopyAndAMessageTheTopicLacksAreNotQuoted() async {
        let quoter = ScriptedQuoter()
        let model = await reader(quoter: quoter)
        await model.quoteMessage(post: 999)
        #expect(quoter.quoteLinks.isEmpty)
        #expect(model.pendingReply == nil)
    }

    @Test func aSecondQuoteWaitsForTheFirstOne() async throws {
        let gate = ReaderGate()
        let quoter = ScriptedQuoter(gate: gate)
        quoter.scriptQuote(.success(prefill))
        let model = await reader(quoter: quoter)
        let first = Task { await model.quoteMessage(post: 100) }
        await gate.untilArrived()
        #expect(model.isLoadingQuote)
        await model.quoteMessage(post: 101)
        #expect(quoter.quoteLinks == [quoteLink(100)])
        await gate.open()
        await first.value
        #expect(model.pendingReply?.quote?.text == prefill)
        #expect(!model.isLoadingQuote)
    }

    @Test func loggedOutThereIsNothingToQuoteWith() async {
        let model = await reader(quoter: nil)
        #expect(!model.canQuote)
        await model.quoteMessage(post: 100)
        #expect(model.pendingReply == nil)
    }

    @Test func aPageWithoutAnAnswerFormOffersNoQuote() async {
        let model = await reader(quoter: ScriptedQuoter(), page: quotablePage(answerURL: nil))
        #expect(!model.canQuote)
        await model.quoteMessage(post: 100)
        #expect(model.pendingReply == nil)
    }

    // MARK: Selection

    @Test func theSelectionAloneIsQuotedWithTheEnginesFormatter() async throws {
        let quoter = ScriptedQuoter()
        quoter.scriptQuote(.success(prefill))
        let model = await reader(quoter: quoter)
        let token = try #require(model.document?.token)
        await model.quoteSelection(post: 100, text: "tout le monde", bold: false, token: token)
        #expect(model.pendingReply?.quote == ReplyQuote(text: "[quotemsg=100,13,900001]tout le monde[/quotemsg]\n", release: nil))
    }

    @Test func theBoldSelectionQuotesTheWholeMessageWithThePassageInBold() async throws {
        let quoter = ScriptedQuoter()
        quoter.scriptQuote(.success(prefill))
        let model = await reader(quoter: quoter)
        let token = try #require(model.document?.token)
        await model.quoteSelection(post: 100, text: " tout le monde \n", bold: true, token: token)
        #expect(model.pendingReply?.quote?.text == "[quotemsg=100,13,900001]Bonjour [b]tout le monde[/b][/quotemsg]\n")
    }

    @Test func aSelectionOfAnotherDocumentIsDropped() async throws {
        let quoter = ScriptedQuoter()
        quoter.scriptQuote(.success(prefill))
        let model = await reader(quoter: quoter)
        let token = try #require(model.document?.token)
        await model.quoteSelection(post: 100, text: "tout", bold: false, token: token + 1)
        #expect(quoter.quoteLinks.isEmpty)
        #expect(model.pendingReply == nil)
    }

    // MARK: Multi-quote

    @Test func theToggleSelectsThenUnselectsAndShowsItsStateInTheMenu() async throws {
        let quoter = ScriptedQuoter()
        let model = await reader(quoter: quoter)
        let token = try #require(model.document?.token)
        await model.openMenu(post: 101, source: .message, token: token)
        #expect(model.presentedMenu?.entries.map(\.title) == ["Citer", "Citer ☐"])
        let context = try #require(model.presentedMenu?.context)
        #expect(await model.toggleQuoteSelection(context) == "Ajouté aux citations (1)")
        #expect(quoter.selected == [101])
        await model.openMenu(post: 101, source: .message, token: token)
        #expect(model.presentedMenu?.entries.map(\.title) == ["Citer", "Citer ☑"])
        #expect(await model.toggleQuoteSelection(context) == "Retiré des citations (0)")
        #expect(quoter.selected.isEmpty)
    }

    @Test func theToggleRunsFromTheMenuAndAnnouncesItsState() async throws {
        let quoter = ScriptedQuoter()
        let model = await reader(quoter: quoter, registered: false)
        var told: [String] = []
        model.install(MessageActionRegistry(model.quoteHandlers(confirm: { told.append($0) })))
        let token = try #require(model.document?.token)
        await model.openMenu(post: 100, source: .message, token: token)
        let menu = try #require(model.presentedMenu)
        await model.perform(.quoteSelection(isSelected: false), in: menu)
        #expect(told == ["Ajouté aux citations (1)"])
        #expect(quoter.selected == [100])
    }

    @Test func theMenuReadsTheSelectionAgainBeforeItOpens() async throws {
        // A reply sent since released message 101 behind the reader's back: the entry must not still show it selected.
        let quoter = ScriptedQuoter()
        let model = await reader(quoter: quoter)
        let token = try #require(model.document?.token)
        _ = await quoter.toggle(quoteToken(101))
        await model.openMenu(post: 101, source: .message, token: token)
        #expect(model.presentedMenu?.entries.map(\.title) == ["Citer", "Citer ☑"])
        _ = await quoter.toggle(quoteToken(101))
        await model.openMenu(post: 101, source: .message, token: token)
        #expect(model.presentedMenu?.entries.map(\.title) == ["Citer", "Citer ☐"])
    }

    @Test func loggedOutTheMenuOffersNeitherQuote() async throws {
        let model = await reader(quoter: nil)
        let token = try #require(model.document?.token)
        await model.openMenu(post: 100, source: .message, token: token)
        #expect(model.presentedMenu == nil)
    }

    // MARK: Reply button

    @Test func withoutASelectionTheReplyButtonOpensTheDraftAsItIs() async {
        let quoter = ScriptedQuoter()
        let model = await reader(quoter: quoter)
        await model.requestReply()
        #expect(model.pendingReply != nil)
        #expect(model.pendingReply?.quote == nil)
        #expect(quoter.selectionLinks.isEmpty)
    }

    @Test func withASelectionTheReplyButtonCarriesItsQuotes() async throws {
        let quoter = ScriptedQuoter(selected: [101, 100])
        quoter.scriptSelection(.success("blocs"))
        let model = await reader(quoter: quoter)
        await model.requestReply()
        #expect(quoter.selectionLinks == [replyFormURL])
        #expect(model.pendingReply?.quote == ReplyQuote(text: "blocs", release: QuoteRelease(token: quoteToken(100), numbers: [101, 100])))
    }

    @Test func aFailedMultiQuoteStillOpensTheComposerAndKeepsTheSelection() async {
        let quoter = ScriptedQuoter(selected: [100])
        quoter.scriptSelection(.failure(.otherTopic))
        let model = await reader(quoter: quoter)
        await model.requestReply()
        #expect(model.pendingReply != nil)
        #expect(model.pendingReply?.quote == nil)
        #expect(model.menuFeedback == ComposerMessages.quote(.otherTopic))
        #expect(quoter.selected == [100])
    }

    @Test func aPageWithoutAnAnswerFormHasNoReplyToOpen() async {
        let model = await reader(quoter: ScriptedQuoter(selected: [100]), page: quotablePage(answerURL: nil))
        await model.requestReply()
        #expect(model.pendingReply == nil)
    }

    @Test func theScreenTakesAPendingReplyOnce() async {
        let model = await reader(quoter: ScriptedQuoter())
        await model.requestReply()
        #expect(model.takePendingReply() != nil)
        #expect(model.takePendingReply() == nil)
        #expect(model.pendingReply == nil)
    }
}
