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
        reader.requestMenu(post: 999, source: .message, token: token)
        reader.requestMenu(post: 101, source: .avatar, token: token) // no avatar handler registered
        #expect(reader.presentedMenu == nil)
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

    @Test func theDocumentHasNoButtonsWithoutAHandler() async {
        let reader = await loaded(registry: MessageActionRegistry())
        #expect(reader.document?.html.contains("data-menu") == false)
    }
}
