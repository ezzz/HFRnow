import Foundation
import HFRClient
import HFRModels
import Observation
@testable import SwiftHFR
import Testing

/// Issue #908, after #950: the reload a write still owes (`owedFollowUp`) runs when the last composer closes only while it
/// is still owed and the reader can run it (on screen, nothing loading, no composer open), and a conversation's reply
/// stays owed until its second load (the page its pager names) has delivered.
@MainActor
struct TopicReaderOwedReloadTests {
    typealias Kind = TopicReaderWriteFollowUpTests.Kind

    /// A reader on page 2 whose confirmed edit's reload a disappearance stopped: `.page(message: 201)` is owed, the reader
    /// is off screen, and every later request is answered at once with page 2.
    private func owingAnEdit(_ thread: Kind) async -> FollowUpFixture {
        let fixture = await followUpFixture(thread, onPage: 2)
        let gate = ReaderGate()
        fixture.pages.handler = { target in
            await gate.wait()
            return followUpPage(thread, target.page, text: "after-edit")
        }
        let close = Task { await fixture.writes.editorDidClose(.sent(TopicReaderWriteFollowUpTests.edited), post: 201) }
        await gate.untilArrived()
        fixture.reader.viewDidDisappear(viewer: 1)
        await gate.open()
        await close.value
        return fixture
    }

    /// The stale edit reload must not cancel a reply's (finding 1 of #950 round 3). The reader comes back under an open
    /// reply composer with an edit's reload owed, and the reply is sent: the last composer closing queues the owed task,
    /// and the reply's reload starts before that task runs (it starts in this very turn, the task only after a suspension).
    /// The task finds a newer reload owed and a load running, and does nothing: the reader ends at the reply.
    @Test(arguments: Kind.allCases)
    func aStaleOwedEditDoesNotCancelTheReplysReload(_ thread: Kind) async throws {
        let fixture = await owingAnEdit(thread)
        fixture.reader.composer(.reply, isOpen: true)
        await fixture.reader.onAppear(viewer: 1)
        #expect(fixture.reader.owedFollowUp == .page(message: 201))
        fixture.pages.handler = { target in followUpPage(thread, min(target.page, 4), maxPage: 4, text: "the-reply") }
        fixture.reader.composer(.reply, isOpen: false)
        await fixture.reader.composerDidClose(.sent(replyConfirmed))
        await fixture.reader.owedTask?.value
        #expect(fixture.pages.requests.map(\.page) == (thread == .topic ? [2, 2, 4] : [2, 2, 3, 4]))
        #expect(fixture.reader.page?.currentPage == 4)
        #expect(fixture.reader.document?.anchor == 401)
        #expect(try #require(fixture.reader.document).html.contains("the-reply"))
        #expect(fixture.reader.owedFollowUp == nil)
    }

    /// A conversation's reply asks its last known page, then the page its pager names (LOT-128). A disappearance that
    /// stops that second load leaves the reply owed, and the screen coming back shows the new page (finding 2).
    @Test func aConversationReplyStoppedBeforeItsSecondLoadStaysOwed() async throws {
        let fixture = await followUpFixture(.conversation, onPage: 3)
        let gate = ReaderGate()
        fixture.pages.handler = { target in
            if target.page == 4 { await gate.wait() }
            return followUpPage(.conversation, min(target.page, 4), maxPage: 4, text: "the-reply")
        }
        let close = Task { await fixture.reader.composerDidClose(.sent(replyConfirmed)) }
        await gate.untilArrived()
        fixture.reader.viewDidDisappear(viewer: 1)
        await gate.open()
        await close.value
        #expect(fixture.pages.requests.map(\.page) == [3, 3, 4])
        #expect(fixture.reader.page?.currentPage == 3)
        #expect(fixture.reader.owedFollowUp == .latestPost)
        await fixture.reader.onAppear(viewer: 1)
        #expect(fixture.pages.requests.map(\.page) == [3, 3, 4, 4])
        #expect(fixture.reader.page?.currentPage == 4)
        #expect(fixture.reader.document?.anchor == 401)
        #expect(try #require(fixture.reader.document).html.contains("the-reply"))
        #expect(fixture.reader.owedFollowUp == nil)
    }

    /// The same stop between the two loads: the first one has delivered, the second one has not started. The reader goes
    /// away as the first page is delivered (the page's observer fires in that very turn, before `showLatestPost` goes on),
    /// so the second load is never asked; the first load must not have settled the reply, which stays owed.
    @Test func aConversationReplyStoppedBetweenItsTwoLoadsStaysOwed() async throws {
        let fixture = await followUpFixture(.conversation, onPage: 3)
        let reader = fixture.reader
        fixture.pages.handler = { target in followUpPage(.conversation, min(target.page, 4), maxPage: 4, text: "the-reply") }
        withObservationTracking { _ = reader.page } onChange: {
            MainActor.assumeIsolated { reader.viewDidDisappear(viewer: 1) }
        }
        await reader.composerDidClose(.sent(replyConfirmed))
        #expect(fixture.pages.requests.map(\.page) == [3, 3])
        #expect(reader.page?.currentPage == 3)
        #expect(reader.owedFollowUp == .latestPost)
        await reader.onAppear(viewer: 1)
        #expect(fixture.pages.requests.map(\.page) == [3, 3, 4])
        #expect(reader.page?.currentPage == 4)
        #expect(reader.document?.anchor == 401)
        #expect(try #require(reader.document).html.contains("the-reply"))
        #expect(reader.owedFollowUp == nil)
    }

    /// A composer closing while the reader is off screen runs nothing: the reload stays owed for the screen's return.
    @Test(arguments: Kind.allCases)
    func aComposerClosingOffScreenLeavesTheReloadOwed(_ thread: Kind) async {
        let fixture = await owingAnEdit(thread)
        fixture.reader.composer(.edit, isOpen: true)
        fixture.reader.composer(.edit, isOpen: false)
        await fixture.reader.owedTask?.value
        #expect(fixture.pages.requests.count == 2)
        #expect(fixture.reader.owedFollowUp == .page(message: 201))
        await fixture.reader.onAppear(viewer: 1)
        #expect(fixture.pages.requests.count == 3)
        #expect(fixture.reader.owedFollowUp == nil)
    }

    /// A composer closing while the owed reload already runs starts no second one, which would cancel the first and ask
    /// the page again.
    @Test(arguments: Kind.allCases)
    func aComposerClosingWhileTheOwedReloadRunsStartsNoOther(_ thread: Kind) async throws {
        let fixture = await owingAnEdit(thread)
        fixture.reader.composer(.reply, isOpen: true)
        await fixture.reader.onAppear(viewer: 1)
        let gate = ReaderGate()
        let pages = fixture.pages
        // Only the owed reload (the third request) waits: a second one would not, so the test cannot hang on it.
        pages.handler = { target in
            if pages.requests.count == 3 { await gate.wait() }
            return followUpPage(thread, target.page, text: "after-edit")
        }
        fixture.reader.composer(.reply, isOpen: false)
        let first = try #require(fixture.reader.owedTask)
        await gate.untilArrived()
        #expect(fixture.reader.isLoading)
        fixture.reader.composer(.edit, isOpen: true)
        fixture.reader.composer(.edit, isOpen: false)
        if let second = fixture.reader.owedTask, second != first { await second.value }
        await gate.open()
        await first.value
        #expect(fixture.pages.requests.count == 3)
        #expect(try #require(fixture.reader.document).html.contains("after-edit"))
        #expect(fixture.reader.owedFollowUp == nil)
    }
}
