import Foundation
import HFRClient
import HFRModels
import HFRNetwork
import HFRParsing
@testable import SwiftHFR
import Testing

/// "Marquer comme non lu" (LOT-127): the link of the page, the single write, what the reader and the list show after it. The
/// writes are scripted (`FakeFlagWriter`) or stop at the session check: nothing reaches HFR.
// The suite limit is a backstop for a hang only (#366).
@MainActor @Suite(.timeLimit(.minutes(5)))
struct MarkUnreadTests {
    private let link = url("https://forum.hardware.fr/user/nonlu.php?config=hfr.inc&cat=prive&post=3207033&page=1")
    private static let sentence = "Le message a été marqué comme non lu avec succès"

    /// A reader showing a conversation page with `link` (nil: a page without it).
    private func reader(link: URL?) async -> TopicReaderModel {
        var page = readerPage(page: 1, maxPage: 1)
        page.markUnreadURL = link
        let reader = TopicReaderModel(
            target: ReaderTarget(source: .topic(TopicID(category: .privateMessages, topic: 3207033))), title: "MP",
            source: FakeTopicPages { [page] _ in page }
        )
        await reader.onAppear()
        return reader
    }

    private func list(_ source: FakePrivateMessages) -> MessageListModel {
        MessageListModel(source: source, isLoggedIn: { true }, topicPages: FakeTopicPages())
    }

    /// A list of one thread that HFR holds as `unread`.
    private func source(with thread: PrivateMessageThread) -> FakePrivateMessages {
        let source = FakePrivateMessages()
        source.handler = { _ in PrivateMessageListPage(threads: [thread]) }
        return source
    }

    private func page(_ name: String) throws -> PrivateMessageListPage {
        let html = try #require(String(data: try LiveTopicPageSourceTests.capture(name), encoding: .utf8))
        return try PrivateMessageListParser.parse(html, pageURL: "https://forum.hardware.fr/forum1.php?config=hfr.inc&cat=prive&page=1")
    }

    // MARK: The link

    /// `RA1` carries the link `W18` requested; a topic page (`R21`) has none, so the entry is not offered there.
    @Test func theCapturedConversationCarriesW18sLinkAndATopicPageNone() throws {
        let conversation = try LiveTopicPageSourceTests.readerPage(of: "RA1-mp-thread-after-create.html")
        let query = "config=hfr.inc&cat=prive&subcat=0&post=3207033&page=1&p=1&sondage=0&owntopic=0&new=0"
        #expect(conversation.markUnreadURL == url("https://forum.hardware.fr/user/nonlu.php?\(query)"))
        #expect(try LiveTopicPageSourceTests.readerPage(of: "R21-topic-p1-logged-in.html").markUnreadURL == nil)
    }

    /// The live writer takes `TopicFlagFlow.markUnread`'s path: the link passes its check and a session that never logged in
    /// stops at the session gate, which needs no request. Another write would refuse this link as invalid.
    @Test func theLiveWriterStopsAtTheSessionCheckWithoutARequest() async {
        let actions = TopicFlagActions(writer: LiveTopicFlagWriter(session: HFRSession()))
        let expected = TopicFlagActions.reason(for: .sessionNotConfirmed(.expired(.noIdentityCookie)))
        #expect(await actions.markUnread(link: link) == .failed(expected))
    }

    // MARK: The reader

    @Test func theLinkIsFollowedOnceAndTheListIsTold() async {
        let reader = await reader(link: link)
        let writer = FakeFlagWriter()
        var told: [TopicFlagOutcome] = []
        await reader.markUnread(with: TopicFlagActions(writer: writer)) { told.append($0) }
        #expect(writer.markedUnread == [link])
        #expect(told == [.done(Self.sentence)])
        #expect(reader.markUnreadState == .idle)
        #expect(reader.menuFeedback == nil)
    }

    @Test func withoutAListTheReaderShowsHFRsSentence() async {
        let reader = await reader(link: link)
        await reader.markUnread(with: TopicFlagActions(writer: FakeFlagWriter()), host: nil)
        #expect(reader.menuFeedback == Self.sentence)
    }

    @Test func aPageWithoutTheLinkSendsNothing() async {
        let reader = await reader(link: nil)
        let writer = FakeFlagWriter()
        var told: [TopicFlagOutcome] = []
        await reader.markUnread(with: TopicFlagActions(writer: writer)) { told.append($0) }
        #expect(writer.markedUnread.isEmpty)
        #expect(told.isEmpty)
    }

    /// `W137a`'s refusal, a transport failure after sending, a refused session, a logged-out page: never shown as done.
    @Test(arguments: [
        TopicFlagError.rejected(message: "Désolé, ce message ne vous est pas destiné"), .unconfirmed(.transport(.timedOut)),
        .sessionNotConfirmed(.expired(.noIdentityCookie)), .notLoggedIn, .invalidLink
    ])
    func aFailureStaysInTheReaderSaysWhyAndIsNotResent(error: TopicFlagError) async {
        let reader = await reader(link: link)
        let writer = FakeFlagWriter()
        writer.unreadHandler = { (_) async throws(TopicFlagError) -> TopicFlagResult in throw error }
        let reason = TopicFlagActions.reason(for: error)
        var told: [TopicFlagOutcome] = []
        await reader.markUnread(with: TopicFlagActions(writer: writer)) { told.append($0) }
        #expect(writer.markedUnread == [link])
        #expect(reader.markUnreadState == .failed(reason))
        #expect(told == [.failed(reason)])
        #expect(reader.menuFeedback == nil)
        reader.clearMarkUnreadFailure()
        #expect(reader.markUnreadState == .idle)
    }

    @Test func aSecondTapWhileTheWriteRunsSendsNothing() async {
        let reader = await reader(link: link)
        let writer = FakeFlagWriter()
        let gate = CheckGate()
        writer.unreadHandler = { _ async throws(TopicFlagError) -> TopicFlagResult in
            await gate.wait()
            return confirmed(.markUnread, TopicID(category: .privateMessages, topic: 1), "ok")
        }
        let actions = TopicFlagActions(writer: writer)
        let first = gate.run { await reader.markUnread(with: actions, host: nil) }
        guard await gate.entered() else { Issue.record("The write never left"); return }
        #expect(reader.markUnreadState == .sending)
        await reader.markUnread(with: actions, host: nil)
        await gate.open()
        await first.value
        #expect(writer.markedUnread.count == 1)
        #expect(reader.markUnreadState == .idle)
    }

    // MARK: The list

    /// The capture pair: `R13b`, the list after `W18`, shows the conversation unread, and the list reloads to read it.
    @Test func hfrsConfirmationClosesTheConversationShowsTheSentenceAndReloads() async throws {
        let after = try page("R13b-mp-list-after-mark-unread.html")
        let thread = try #require(after.threads.first { $0.isUnread })
        var before = thread
        before.summary.readState = .read
        let source = source(with: before)
        let model = list(source)
        await model.onAppear()
        model.selected = before
        #expect(model.reader(for: before) != nil)
        source.handler = { _ in after }
        await model.markUnreadEnded(before, .done(Self.sentence))
        #expect(model.selected == nil)
        #expect(model.sentConfirmation == Self.sentence)
        #expect(source.requests == [1, 1])
        #expect(model.isUnread(thread))
    }

    /// A conversation just read (local mark) goes back to unread with the reload, not after the next one.
    @Test func aThreadOpenedHereShowsUnreadAgain() async throws {
        let thread = messageThread(7, unread: true)
        let model = list(source(with: thread))
        await model.onAppear()
        model.markOpened(thread, page: 1, of: 1)
        #expect(!model.isUnread(thread))
        await model.markUnreadEnded(thread, .done(Self.sentence))
        #expect(model.isUnread(thread))
    }

    /// HFR confirmed the write: a reload that fails keeps the row unread and the sentence, a later load brings HFR's state.
    @Test func aFailedReloadKeepsTheMarkUntilALoadAnswers() async {
        let read = messageThread(7)
        let source = source(with: read)
        let model = list(source)
        await model.onAppear()
        source.handler = { _ async throws(ListLoadError) -> PrivateMessageListPage in throw .offline }
        await model.markUnreadEnded(read, .done(Self.sentence))
        #expect(model.isUnread(read))
        #expect(model.sentConfirmation == Self.sentence)
        #expect(model.loader.error == .offline)
        source.handler = { _ in PrivateMessageListPage(threads: [read]) }
        await model.refresh()
        #expect(!model.isUnread(read))
    }

    /// A load that left before HFR's confirmation predates it (LESSONS 57): it never clears the mark.
    @Test func aLoadFromBeforeTheWriteDoesNotClearTheMark() async {
        let read = messageThread(7)
        let source = source(with: read)
        let model = list(source)
        await model.onAppear()
        let gate = CheckGate()
        source.handler = { _ async throws(ListLoadError) -> PrivateMessageListPage in
            await gate.wait()
            return PrivateMessageListPage(threads: [read])
        }
        let older = gate.run { await model.refresh() }
        guard await gate.entered() else { Issue.record("The refresh never asked for its page"); return }
        source.handler = { _ async throws(ListLoadError) -> PrivateMessageListPage in throw .offline }
        await model.markUnreadEnded(read, .done(Self.sentence))
        await gate.open()
        await older.value
        #expect(model.isUnread(read))
    }

    @Test func seeingTheLastPageAgainDropsTheMark() async {
        let read = messageThread(7)
        let source = source(with: read)
        let model = list(source)
        await model.onAppear()
        source.handler = { _ async throws(ListLoadError) -> PrivateMessageListPage in throw .offline }
        await model.markUnreadEnded(read, .done(Self.sentence))
        model.markOpened(read, page: 1, of: 1)
        #expect(!model.isUnread(read))
    }

    /// Another conversation opened while the write ran stays open (iPad), and its row is the one marked.
    @Test func theConfirmationLeavesAnotherOpenConversationAlone() async {
        let marked = messageThread(7)
        let other = messageThread(8)
        let source = FakePrivateMessages()
        source.handler = { _ in PrivateMessageListPage(threads: [marked, other]) }
        let model = list(source)
        await model.onAppear()
        model.selected = other
        await model.markUnreadEnded(marked, .done(Self.sentence))
        #expect(model.selected == other)
    }

    @Test func aFailureChangesNothingAndTheOpenReaderSaysIt() async {
        let read = messageThread(7)
        let source = source(with: read)
        let model = list(source)
        await model.onAppear()
        model.selected = read
        await model.markUnreadEnded(read, .failed("non"))
        #expect(model.selected == read)
        #expect(!model.isUnread(read))
        #expect(model.sentConfirmation == nil)
        #expect(model.actionFailure == nil)
        #expect(source.requests == [1])
    }

    /// The member left the conversation before the answer: its reader is gone, so the list says it.
    @Test func aFailureAfterLeavingTheConversationIsShownByTheList() async {
        let read = messageThread(7)
        let model = list(source(with: read))
        await model.onAppear()
        await model.markUnreadEnded(read, .failed("non"))
        #expect(model.actionFailure == "non")
    }
}
