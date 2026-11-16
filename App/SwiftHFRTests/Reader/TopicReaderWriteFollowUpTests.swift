import Foundation
import HFRClient
import HFRModels
@testable import SwiftHFR
import Testing

/// Issue #908: after a send HFR confirmed, the reader shows the result by itself, in a public topic and in a private
/// conversation alike (one reader, one write model for both): the edited message in place, or the reply on the last page.
/// Nothing is reloaded when the composer closes without a send; an unconfirmed send reloads once, without a success. A
/// disappearance that stops that reload (`viewDidDisappear`) leaves it owed, and the screen coming back runs it.
@MainActor
struct TopicReaderWriteFollowUpTests {
    /// What the reader shows: a public topic or a private conversation (`cat=prive`).
    enum Kind: String, CaseIterable, Sendable {
        case topic
        case conversation
    }

    private static let edited = PostingResult(
        action: .edit, message: "Votre message a été édité avec succès !",
        refreshURL: url("https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=prive&post=4242&page=2#t201"),
        refreshAnchor: "t201", postNumber: 201
    )

    private struct Fixture {
        let reader: TopicReaderModel
        let writes: MessageWriteModel
        let pages: FakeTopicPages
    }

    /// A reader on page `number` of the thread, before any send, with the write model the view installs. A viewer is on
    /// screen (the disappearance tests need one); the wait limit never fires, there is no web view to make a page ready.
    private func fixture(_ thread: Kind, onPage number: Int, maxPage: Int = 3) async -> Fixture {
        let pages = FakeTopicPages { target in followUpPage(thread, min(target.page, maxPage), maxPage: maxPage, text: "before") }
        let reader = TopicReaderModel(target: ReaderTarget(source: .topic(followUpTopic(thread)), page: number), source: pages)
        reader.waitClock = { _ in try await Task.sleep(for: .seconds(3_600)) }
        let writes = MessageWriteModel(reader: reader, services: ComposerFixture.services(poster: ScriptedPoster([])))
        await reader.onAppear(viewer: 1)
        return Fixture(reader: reader, writes: writes, pages: pages)
    }

    // MARK: - Success

    /// A confirmed edit: the page on screen is asked again and opens at the edited message, which shows the new text.
    @Test(arguments: Kind.allCases)
    func aConfirmedEditShowsTheEditedTextAtTheMessage(_ thread: Kind) async throws {
        let fixture = await fixture(thread, onPage: 2)
        fixture.pages.handler = { target in followUpPage(thread, target.page, text: "after-edit") }
        await fixture.writes.editorDidClose(.sent(Self.edited), post: 201)
        #expect(fixture.pages.requests.map(\.page) == [2, 2])
        #expect(fixture.reader.document?.anchor == 201)
        #expect(try #require(fixture.reader.document).html.contains("after-edit"))
        #expect(fixture.reader.replyConfirmation == "Votre message a été édité avec succès !")
    }

    /// A confirmed reply that opened a page: the reader ends on that page at the new message. A topic asks past its end
    /// (`R24`); a conversation asks its last known page, then the one its pager names (LOT-128).
    @Test(arguments: Kind.allCases)
    func aConfirmedReplyShowsTheNewMessageOnTheLastPage(_ thread: Kind) async throws {
        let fixture = await fixture(thread, onPage: 3)
        fixture.pages.handler = { target in followUpPage(thread, min(target.page, 4), maxPage: 4, text: "the-reply") }
        await fixture.reader.composerDidClose(.sent(replyConfirmed))
        #expect(fixture.pages.requests.map(\.page) == (thread == .topic ? [3, 4] : [3, 3, 4]))
        #expect(fixture.reader.page?.currentPage == 4)
        #expect(fixture.reader.document?.anchor == 401)
        #expect(try #require(fixture.reader.document).html.contains("the-reply"))
        #expect(fixture.reader.replyConfirmation == "Votre réponse a été postée avec succès !")
    }

    // MARK: - No success

    /// An unconfirmed send reloads once to show what the forum holds, and says no success.
    @Test(arguments: Kind.allCases)
    func anUnconfirmedSendReloadsOnceWithoutSuccess(_ thread: Kind) async {
        let fixture = await fixture(thread, onPage: 2)
        await fixture.writes.editorDidClose(.checkTopic, post: 201)
        #expect(fixture.pages.requests.map(\.page) == [2, 2])
        #expect(fixture.reader.replyConfirmation == nil)
        await fixture.reader.composerDidClose(.checkTopic)
        #expect(fixture.pages.requests.count == 3)
        #expect(fixture.reader.replyConfirmation == nil)
        #expect(fixture.reader.owedFollowUp == nil)
    }

    /// A composer closed without a send (draft kept, discarded, or not saved) reloads nothing and owes nothing.
    @Test(arguments: Kind.allCases, [ReplyComposerModel.CloseReason.keptDraft, .discardedDraft, .closedWithoutSaving])
    func closingWithoutASendReloadsNothing(_ thread: Kind, _ reason: ReplyComposerModel.CloseReason) async {
        let fixture = await fixture(thread, onPage: 2)
        await fixture.writes.editorDidClose(reason, post: 201)
        await fixture.reader.composerDidClose(reason)
        #expect(fixture.pages.requests.count == 1)
        #expect(fixture.reader.replyConfirmation == nil)
        #expect(fixture.reader.owedFollowUp == nil)
        await fixture.reader.onAppear(viewer: 1)
        #expect(fixture.pages.requests.count == 1)
    }

    // MARK: - Interrupted

    /// The reload after a confirmed edit is stopped by the reader's disappearance (#908: the old text stayed, only the
    /// round arrow showed the edit). The screen coming back runs it, once.
    @Test(arguments: Kind.allCases)
    func anEditReloadStoppedByADisappearanceRunsWhenTheScreenComesBack(_ thread: Kind) async throws {
        let fixture = await fixture(thread, onPage: 2)
        let gate = ReaderGate()
        fixture.pages.handler = { target in
            await gate.wait()
            return followUpPage(thread, target.page, text: "after-edit")
        }
        let close = Task { await fixture.writes.editorDidClose(.sent(Self.edited), post: 201) }
        await gate.untilArrived()
        fixture.reader.viewDidDisappear(viewer: 1)
        await gate.open()
        await close.value
        #expect(try #require(fixture.reader.document).html.contains("after-edit") == false)
        #expect(fixture.reader.owedFollowUp == .page(message: 201))
        await fixture.reader.onAppear(viewer: 1)
        #expect(fixture.pages.requests.map(\.page) == [2, 2, 2])
        #expect(fixture.reader.document?.anchor == 201)
        #expect(try #require(fixture.reader.document).html.contains("after-edit"))
        #expect(fixture.reader.owedFollowUp == nil)
        await fixture.reader.onAppear(viewer: 1)
        #expect(fixture.pages.requests.count == 3)
    }

    /// The same for a reply: the screen coming back shows the new message on the last page.
    @Test(arguments: Kind.allCases)
    func aReplyReloadStoppedByADisappearanceRunsWhenTheScreenComesBack(_ thread: Kind) async throws {
        let fixture = await fixture(thread, onPage: 3)
        let gate = ReaderGate()
        fixture.pages.handler = { target in
            await gate.wait()
            return followUpPage(thread, min(target.page, 4), maxPage: 4, text: "the-reply")
        }
        let close = Task { await fixture.reader.composerDidClose(.sent(replyConfirmed)) }
        await gate.untilArrived()
        fixture.reader.viewDidDisappear(viewer: 1)
        await gate.open()
        await close.value
        #expect(fixture.reader.page?.currentPage == 3)
        #expect(fixture.reader.owedFollowUp == .latestPost)
        await fixture.reader.onAppear(viewer: 1)
        #expect(fixture.reader.page?.currentPage == 4)
        #expect(fixture.reader.document?.anchor == 401)
        #expect(try #require(fixture.reader.document).html.contains("the-reply"))
        #expect(fixture.reader.owedFollowUp == nil)
    }

    /// A newer load that delivers settles what a write owed: the screen coming back then reloads nothing more.
    @Test func aRefreshThatDeliversSettlesTheOwedReload() async {
        let fixture = await fixture(.conversation, onPage: 2)
        let gate = ReaderGate()
        fixture.pages.handler = { target in
            await gate.wait()
            return followUpPage(.conversation, target.page, text: "after-edit")
        }
        let close = Task { await fixture.writes.editorDidClose(.sent(Self.edited), post: 201) }
        await gate.untilArrived()
        fixture.reader.viewDidDisappear(viewer: 1)
        await gate.open()
        await close.value
        await fixture.reader.refresh()
        #expect(fixture.reader.owedFollowUp == nil)
        let count = fixture.pages.requests.count
        await fixture.reader.onAppear(viewer: 1)
        #expect(fixture.pages.requests.count == count)
    }
}

/// The thread `thread` stands for.
private func followUpTopic(_ thread: TopicReaderWriteFollowUpTests.Kind) -> TopicID {
    switch thread {
    case .topic: readerTopic
    case .conversation: TopicID(category: .privateMessages, topic: 4242)
    }
}

/// Page `number` of `maxPage` of `thread`, whose second message (`number * 100 + 1`) reads `text`.
private func followUpPage(_ thread: TopicReaderWriteFollowUpTests.Kind, _ number: Int, maxPage: Int = 3, text: String) -> ReaderPage {
    var page = readerPage(page: number, maxPage: maxPage)
    page.topicID = followUpTopic(thread)
    page.messages[1].content = MessageContent(html: "<p>\(text)</p>")
    return page
}
