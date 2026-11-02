import Foundation
import HFRClient
import HFRModels
import HFRParsing
@testable import SwiftHFR
import Testing

/// Where the private message composers come from and where the screens go after them (LOT-128): the list's "new message"
/// link, the thread opened after a confirmed new MP, the conversation's answer link and its latest post after a reply.
@MainActor
struct MessageComposerEntryTests {
    private static let listButton = listButtonPath

    private func listModel(_ source: FakePrivateMessages, loggedIn: Bool = true) -> MessageListModel {
        MessageListModel(source: source, isLoggedIn: { loggedIn })
    }

    // MARK: New message from the list

    @Test func theCapturedListLinksToTheNewMessageForm() throws {
        let html = try #require(String(data: try LiveTopicPageSourceTests.capture("R13a-mp-list.html"), encoding: .utf8))
        let page = try PrivateMessageListParser.parse(html, pageURL: "https://forum.hardware.fr/forum1.php?config=hfr.inc&cat=prive&page=1")
        let content = MessageListContent(page: page)
        let target = try #require(content.newMessageURL.flatMap(NewMessageTarget.init(link:)))
        #expect(target.formURL.absoluteString == "https://forum.hardware.fr" + Self.listButton)
        #expect(target.recipient.isEmpty)
    }

    @Test func theButtonFollowsTheLoadedPage() async {
        let source = FakePrivateMessages()
        source.handler = { _ in listPage([]) }
        let model = listModel(source)
        #expect(model.newMessageTarget == nil)
        await model.onAppear()
        #expect(model.newMessageTarget?.formURL.absoluteString == "https://forum.hardware.fr" + Self.listButton)
        source.handler = { _ in messagePage(page: 1) }
        await model.refresh()
        #expect(model.newMessageTarget == nil)
    }

    @Test func loggedOutThereIsNoNewMessage() async {
        let source = FakePrivateMessages()
        source.handler = { _ in listPage([]) }
        let model = listModel(source, loggedIn: false)
        await model.onAppear()
        #expect(model.newMessageTarget == nil)
        #expect(source.requests.isEmpty)
    }

    @Test func aConfirmedMessageReloadsPageOneAndOpensTheThreadWithItsSubject() async {
        let source = FakePrivateMessages()
        let model = listModel(source)
        await model.onAppear()
        await model.goToNextPage()
        source.handler = { _ in listPage([thread(7, title: "Autre"), thread(8, title: "Rendez-vous")]) }
        await model.newMessageDidClose(.sent(newMessageConfirmed), subject: " Rendez-vous ")
        #expect(source.requests == [1, 2, 1])
        #expect(model.selected?.summary.topicID?.topic == 8)
        #expect(model.sentConfirmation == "Votre message a été posté avec succès !")
        model.clearSentConfirmation()
        #expect(model.sentConfirmation == nil)
    }

    @Test(arguments: [["Autre"], ["Rendez-vous", "Rendez-vous"]])
    func noThreadOpensUnlessExactlyOneRowBearsTheSubject(_ titles: [String]) async {
        let source = FakePrivateMessages()
        source.handler = { _ in listPage(titles.enumerated().map { thread($0.offset + 1, title: $0.element) }) }
        let model = listModel(source)
        await model.newMessageDidClose(.sent(newMessageConfirmed), subject: "Rendez-vous")
        #expect(source.requests == [1])
        #expect(model.selected == nil)
        #expect(model.sentConfirmation != nil)
    }

    @Test func anUnconfirmedMessageReloadsTheListAndClosingDoesNothing() async {
        let source = FakePrivateMessages()
        source.handler = { _ in listPage([thread(8, title: "Rendez-vous")]) }
        let model = listModel(source)
        await model.newMessageDidClose(.keptDraft, subject: "Rendez-vous")
        await model.newMessageDidClose(.discardedDraft, subject: "Rendez-vous")
        #expect(source.requests.isEmpty)
        await model.newMessageDidClose(.checkTopic, subject: "Rendez-vous")
        #expect(source.requests == [1])
        #expect(model.selected == nil)
        #expect(model.sentConfirmation == nil)
    }

    /// `R13a` is the sender's list right after `W10`: the thread is listed under the subject sent ("fixture-test-1").
    @Test func theCapturedListAfterANewMessageOpensItsThread() async throws {
        let html = try #require(String(data: try LiveTopicPageSourceTests.capture("R13a-mp-list.html"), encoding: .utf8))
        let page = try PrivateMessageListParser.parse(html, pageURL: "https://forum.hardware.fr/forum1.php?config=hfr.inc&cat=prive&page=1")
        let source = FakePrivateMessages()
        source.handler = { _ in page }
        let model = listModel(source)
        await model.newMessageDidClose(.sent(newMessageConfirmed), subject: "fixture-test-1")
        #expect(model.selected?.summary.topicID == TopicID(category: .privateMessages, topic: 3207033))
    }

    // MARK: Reply in a conversation

    /// `RA1` (the owner's thread) carries the answer link of `R47b`, the MP reply composer: the reader offers "Répondre".
    @Test func aCapturedConversationOffersTheReply() throws {
        let html = try #require(String(data: try LiveTopicPageSourceTests.capture("RA1-mp-thread-after-create.html"), encoding: .utf8))
        let pageURL = url("https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=prive&post=3207033&page=1")
        let page = try LiveTopicPageSource.parse(html, pageURL: pageURL, normalizer: LiveTopicPageSourceTests.MarkingNormalizer())
        let topic = TopicID(category: .privateMessages, topic: 3207033)
        #expect(page.topicID == topic)
        #expect(page.answerURL?.absoluteString == "https://forum.hardware.fr/message.php?config=hfr.inc&cat=prive&post=3207033"
            + "&page=1&p=1&subcat=0&sondage=0&owntopic=0&new=0")
        #expect(page.answerURL.flatMap { HFRURL.topicID(in: $0.absoluteString) } == topic)
    }

    @Test func afterAReplyAConversationAsksItsLastKnownPageNeverPastIt() async {
        let pages = FakeTopicPages { target in privatePage(min(target.page, 5)) }
        let reader = TopicReaderModel(target: ReaderTarget(source: .topic(privateTopic), page: 2), title: "", source: pages)
        await reader.onAppear()
        await reader.composerDidClose(.sent(replyConfirmed))
        #expect(pages.requests.map(\.page) == [2, 5])
        #expect(reader.document?.anchor == 501)
        #expect(reader.replyConfirmation == "Votre réponse a été postée avec succès !")
    }

    @Test func aReplyThatOpenedAPageIsShownOnIt() async {
        let pages = FakeTopicPages { target in privatePage(target.page, maxPage: target.page == 2 ? 5 : 6) }
        let reader = TopicReaderModel(target: ReaderTarget(source: .topic(privateTopic), page: 2), title: "", source: pages)
        await reader.onAppear()
        await reader.composerDidClose(.checkTopic)
        #expect(pages.requests.map(\.page) == [2, 5, 6])
        #expect(reader.page?.currentPage == 6)
        #expect(reader.document?.anchor == 601)
    }

    @Test func aFailedLatestPageLoadAsksNothingMore() async {
        let pages = FakeTopicPages { target in privatePage(target.page) }
        let reader = TopicReaderModel(target: ReaderTarget(source: .topic(privateTopic), page: 2), title: "", source: pages)
        await reader.onAppear()
        pages.handler = { (_) async throws(ListLoadError) -> ReaderPage in throw .offline }
        await reader.composerDidClose(.checkTopic)
        #expect(pages.requests.map(\.page) == [2, 5])
        #expect(reader.error == .offline)
    }
}

/// The MP list's new-MP button (`R13a`, `md_btn_new_topic`).
private let listButtonPath = "/message.php?config=hfr.inc&cat=prive&sond=0&p=1&subcat=0&dest=&subcatgroup=0"

/// Page 1 of the list with `threads` and the list's new-MP button (`R13a`).
private func listPage(_ threads: [PrivateMessageThread]) -> PrivateMessageListPage {
    PrivateMessageListPage(threads: threads, navigation: PageNavigation(current: 1, last: 1), newMessagePath: listButtonPath)
}

private func thread(_ number: Int, title: String) -> PrivateMessageThread {
    var thread = messageThread(number)
    thread.summary.title = title
    return thread
}

private let privateTopic = TopicID(category: .privateMessages, topic: 3207033)

/// Page `number` of `maxPage` of a private thread, two messages numbered from `number * 100`.
private func privatePage(_ number: Int, maxPage: Int = 5) -> ReaderPage {
    var page = readerPage(page: number, maxPage: maxPage)
    page.topicID = privateTopic
    page.answerURL = url("https://forum.hardware.fr/message.php?config=hfr.inc&cat=prive&post=3207033&page=1&p=1&subcat=0")
    return page
}
