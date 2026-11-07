import Foundation
import HFRModels
@testable import SwiftHFR
import Testing

/// The reader's message menu: what a tap on the web view's button opens, and what it must never open.
@MainActor
struct TopicReaderMenuTests {
    private static let canonical = url(
        "https://forum.hardware.fr/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_1.htm#bas"
    )
    private static let edit = url("https://forum.hardware.fr/message.php?config=hfr.inc&cat=13&post=28563&numreponse=100")

    private func message(_ number: Int, continuation: Bool = false, own: Bool = false) -> ReaderMessage {
        ReaderMessage(
            numreponse: number, author: "auteur", isDeleted: false, isContinuation: continuation, avatarURL: nil,
            dateText: "27-10-2026 10:00:00", editNote: nil, quotedByCount: nil, content: MessageContent(html: "<p>x</p>"),
            actions: MessageActions(editURL: own ? Self.edit : nil)
        )
    }

    private func loaded(
        page: Int = 1, messages: [ReaderMessage]? = nil, pageURL: URL? = TopicReaderMenuTests.canonical,
        registry: MessageActionRegistry? = nil
    ) async -> TopicReaderModel {
        let shown = messages ?? [message(100, own: true), message(101)]
        let pages = FakeTopicPages { _ in
            ReaderPage(topicID: readerTopic, title: "Sujet", currentPage: page, maxPage: 5, messages: shown, pageURL: pageURL)
        }
        let reader = TopicReaderModel(target: ReaderTarget(source: .topic(readerTopic), page: page), source: pages)
        reader.install(registry ?? MessageActionRegistry([
            LinkActionHandler(copy: { _ in }, confirm: { _ in }), RecordingHandler(.edit), RecordingHandler(.delete),
            RecordingHandler(.alert)
        ]))
        await reader.onAppear()
        return reader
    }

    @Test func aTapOpensTheMenuOfThatMessage() async throws {
        let reader = await loaded()
        let token = try #require(reader.document?.token)
        reader.requestMenu(post: 101, source: .message, token: token)
        let menu = try #require(reader.presentedMenu)
        #expect(menu.post == 101)
        #expect(menu.entries == [.link, .alert])
        #expect(menu.context.permalinkURL?.absoluteString
            == "https://forum.hardware.fr/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_1.htm#t101")
    }

    @Test func theMenuKeepsItsAnchorAndIsTitledWithTheAuthor() async throws {
        let reader = await loaded()
        let token = try #require(reader.document?.token)
        let anchor = CGRect(x: 300, y: 120, width: 30, height: 30)
        reader.requestMenu(post: 101, source: .message, anchor: anchor, token: token)
        #expect(reader.presentedMenu?.anchor == anchor)
        #expect(reader.presentedMenu?.title == "Post de auteur")
    }

    @Test func aLaterInstallOffersTheEntriesItsHandlersServe() async throws {
        // The screen reinstalls the handlers when the composer or the flag actions arrive: the menu then shows them.
        let reader = await loaded(registry: MessageActionRegistry([LinkActionHandler(copy: { _ in }, confirm: { _ in })]))
        let token = try #require(reader.document?.token)
        reader.requestMenu(post: 101, source: .message, token: token)
        #expect(reader.presentedMenu?.entries == [.link])
        reader.install(MessageActionRegistry([
            LinkActionHandler(copy: { _ in }, confirm: { _ in }), RecordingHandler(.alert)
        ]))
        reader.requestMenu(post: 101, source: .message, token: token)
        #expect(reader.presentedMenu?.entries == [.link, .alert])
    }

    @Test func theFirstPostOfTheTopicCannotBeDeletedButAnyOtherOwnPostCan() async throws {
        let reader = await loaded(messages: [message(100, own: true), message(101, own: true)])
        let token = try #require(reader.document?.token)
        reader.requestMenu(post: 100, source: .message, token: token)
        #expect(reader.presentedMenu?.entries == [.edit, .link])
        reader.requestMenu(post: 101, source: .message, token: token)
        #expect(reader.presentedMenu?.entries == [.edit, .link, .delete])
    }

    @Test func aLaterPageHasNoFirstPostAndItsContinuationCopyOpensNoMenu() async throws {
        let reader = await loaded(page: 2, messages: [message(100, continuation: true), message(101, own: true)])
        let token = try #require(reader.document?.token)
        reader.requestMenu(post: 101, source: .message, token: token)
        #expect(reader.presentedMenu?.entries.contains(.delete) == true)
        reader.dismissMenu()
        reader.requestMenu(post: 100, source: .message, token: token)
        #expect(reader.presentedMenu == nil, "the copy of 100 is no menu target")
    }

    @Test func aStaleTokenAnUnknownMessageOrNoEntryOpensNothing() async throws {
        let reader = await loaded()
        let token = try #require(reader.document?.token)
        reader.requestMenu(post: 101, source: .message, token: token + 1)
        #expect(reader.presentedMenu == nil, "stale document")
        reader.requestMenu(post: 999, source: .message, token: token)
        #expect(reader.presentedMenu == nil, "not on the page")
        reader.requestMenu(post: 101, source: .avatar, token: token) // no avatar handler registered
        #expect(reader.presentedMenu == nil, "no entry")
        // A refused request leaves an open menu as it is.
        reader.requestMenu(post: 101, source: .message, token: token)
        let open = reader.presentedMenu
        #expect(open != nil)
        reader.requestMenu(post: 999, source: .message, token: token)
        reader.requestMenu(post: 101, source: .message, token: token + 1)
        reader.requestMenu(post: 101, source: .avatar, token: token) // valid, but offers nothing
        #expect(reader.presentedMenu == open)
        reader.dismissMenu()
        let bare = await loaded(registry: MessageActionRegistry())
        #expect(!bare.hasMessageMenus)
        bare.requestMenu(post: 101, source: .message, token: try #require(bare.document?.token))
        #expect(bare.presentedMenu == nil)
    }

    @Test func withoutAPageURLThereIsNoLink() async throws {
        let reader = await loaded(pageURL: nil)
        reader.requestMenu(post: 101, source: .message, token: try #require(reader.document?.token))
        #expect(reader.presentedMenu == nil, "only Link and Alerter were offered, both need the permalink")
    }

    @Test func pickingAnEntryRunsItsHandlerOnTheContextThatWasShown() async throws {
        var copied: [URL] = []
        let reader = await loaded(registry: MessageActionRegistry([
            LinkActionHandler(copy: { copied.append($0) }, confirm: { _ in })
        ]))
        reader.requestMenu(post: 101, source: .message, token: try #require(reader.document?.token))
        let menu = try #require(reader.presentedMenu)
        await reader.perform(.link, in: menu)
        #expect(copied.map(\.fragment) == ["t101"])
        #expect(reader.presentedMenu == nil)
        await reader.perform(.delete, in: menu) // not offered by that menu
        #expect(copied.count == 1)
    }

    @Test func aNewDocumentClosesTheMenuAndDrawsTheButtons() async throws {
        let reader = await loaded()
        reader.requestMenu(post: 101, source: .message, token: try #require(reader.document?.token))
        #expect(reader.presentedMenu != nil)
        await reader.refresh()
        #expect(reader.presentedMenu == nil)
        #expect(reader.document?.html.contains("data-menu=\"message\"") == true)
    }

    @Test func onlyTheMenusThatCanOpenAreDrawn() async {
        let reader = await loaded()
        let html = reader.document?.html ?? ""
        #expect(html.contains("data-menu=\"message\"") && !html.contains("data-menu=\"avatar\""))
    }

    @Test func installingTheHandlersDoesNotKeepTheModelAlive() async {
        weak var weakReader: TopicReaderModel?
        do {
            let reader = TopicReaderModel(target: ReaderTarget(source: .topic(readerTopic)), source: FakeTopicPages())
            weakReader = reader
            // The same wiring as `TopicReaderView.installMenuActions()`: the registry the model stores points back to it.
            reader.install(MessageActionRegistry([
                LinkActionHandler(copy: { _ in }, confirm: { [weak reader] in reader?.showMenuFeedback($0) })
            ]))
            await reader.onAppear()
        }
        #expect(weakReader == nil)
    }

    @Test func feedbackRestartsItsTimerWhenTheSameTextComesTwice() {
        let reader = TopicReaderModel(target: ReaderTarget(source: .topic(readerTopic)), source: FakeTopicPages())
        reader.showMenuFeedback("Lien copié")
        let first = reader.menuFeedbackSerial
        reader.showMenuFeedback("Lien copié")
        #expect(reader.menuFeedbackSerial == first + 1)
        reader.clearMenuFeedback(serial: first) // the first confirmation's timer ends: the second stays
        #expect(reader.menuFeedback == "Lien copié")
        reader.clearMenuFeedback(serial: first + 1)
        #expect(reader.menuFeedback == nil)
    }

    @Test func theDocumentHasNoButtonsWithoutAHandler() async {
        let reader = await loaded(registry: MessageActionRegistry())
        #expect(reader.document?.html.contains("data-menu") == false)
    }
}
