import CoreGraphics
import Foundation
import HFRModels
import HFRNetwork
@testable import SwiftHFR
import Testing
import WebKit

/// The page under an open composer (#653, operator 2026-11-10): it scrolls, but a tap on a link or an action of the page is
/// ignored while a composer is open over it, and nothing reloads or stops the page.
@MainActor
struct ReaderComposerSuspensionTests: ReaderWebTesting {
    private func reader(
        _ pages: FakeTopicPages = FakeTopicPages(), quoter: ScriptedQuoter? = ScriptedQuoter()
    ) async -> TopicReaderModel {
        let model = TopicReaderModel(
            target: ReaderTarget(source: .topic(readerTopic), page: 1), title: "Sujet", source: pages
        )
        model.quoting = quoter
        model.install(MessageActionRegistry(model.quoteHandlers(confirm: { _ in })))
        await model.onAppear()
        return model
    }

    @Test func theReaderIsSuspendedWhileAnyOfItsComposersIsOpen() async {
        let model = await reader()
        #expect(!model.suspendsPageInteractions)
        model.composer(.reply, isOpen: true)
        #expect(model.suspendsPageInteractions)
        model.composer(.privateMessage, isOpen: true)
        model.composer(.reply, isOpen: false)
        #expect(model.suspendsPageInteractions, "the author menu's MP is still open")
        model.composer(.privateMessage, isOpen: false)
        #expect(!model.suspendsPageInteractions)
        // A close reported twice (the sheet's state and a dismissal) never leaves the page suspended.
        model.composer(.edit, isOpen: true)
        model.composer(.edit, isOpen: false)
        model.composer(.edit, isOpen: false)
        #expect(!model.suspendsPageInteractions)
    }

    @Test func underAnOpenComposerNoLinkNavigatesAndNoPageLoads() async {
        let pages = FakeTopicPages { target in readerPage(page: target.page) }
        let model = await reader(pages)
        let document = model.document
        model.composer(.reply, isOpen: true)
        let post = url("https://forum.hardware.fr/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_4.htm#t401")
        #expect(model.action(forLink: post, defaultBrowser: false) == .ignored)
        #expect(model.action(forLink: url("https://example.com/a"), defaultBrowser: true) == .ignored)
        model.follow(ReaderTarget(source: .topic(TopicID(category: .forum(5), topic: 77)), page: 2))
        #expect(model.linkedReader == nil)
        await model.goToPage(2)
        await model.refresh()
        await model.retry()
        model.documentDidBecomeReady(token: document?.token ?? 0)
        await model.swipe(.next)
        #expect(pages.requests.count == 1, "only the first load")
        #expect(model.document == document)
        // Once the composer is closed, the same taps work again.
        model.composer(.reply, isOpen: false)
        #expect(model.action(forLink: post, defaultBrowser: false) != .ignored)
        await model.goToPage(2)
        #expect(pages.requests.count == 2)
    }

    @Test func underAnOpenComposerNoMenuQuoteOrSecondComposerOpens() async throws {
        let quoter = ScriptedQuoter()
        quoter.scriptQuote(.success("[quotemsg=100,13,900001]x[/quotemsg]\n"))
        let pages = FakeTopicPages { _ in quotablePage() }
        let model = await reader(pages, quoter: quoter)
        let token = try #require(model.document?.token)
        model.composer(.edit, isOpen: true)
        await model.openMenu(post: 100, source: .message, token: token)
        #expect(model.presentedMenu == nil)
        await model.requestReply()
        await model.quoteMessage(post: 100)
        await model.quoteSelection(post: 100, text: "x", bold: false, token: token)
        #expect(model.pendingReply == nil)
        #expect(quoter.quoteLinks.isEmpty)
        model.composer(.edit, isOpen: false)
        await model.openMenu(post: 100, source: .message, token: token)
        #expect(model.presentedMenu != nil)
    }

    @Test func theWebViewDropsTheTapsButKeepsTheReadingPosition() {
        let (controller, recorder) = makeController(transport: MockTransport { request in HTTPResponse(statusCode: 404, url: request.url) })
        var menus: [Int] = []
        var quotes: [Int] = []
        var positions: [Int] = []
        controller.events.menu = { post, _, _, _ in menus.append(post) }
        controller.events.quote = { post, _, _, _ in quotes.append(post) }
        controller.events.position = { post, _ in positions.append(post) }
        let shown = document(token: 1)
        controller.ignoresPageTaps = true
        _ = controller.handle(.menu(post: 7, source: .message, anchor: nil), in: shown)
        _ = controller.handle(.quote(post: 7, text: "x", bold: false), in: shown)
        _ = controller.handle(.video(post: 7, index: 0), in: shown)
        _ = controller.handle(.image(urls: ["https://forum-images.hardware.fr/icones/smile.gif"], index: 0), in: shown)
        let consent = controller.handle(.tap(url: "https://i.imgur.com/photo.jpg"), in: shown) as? Bool
        controller.route(link: url("https://example.com/page"))
        _ = controller.handle(.position(post: 7), in: shown)
        #expect(menus.isEmpty)
        #expect(quotes.isEmpty)
        #expect(recorder.videos.isEmpty)
        #expect(recorder.viewers.isEmpty)
        #expect(consent == false)
        #expect(controller.consented.isEmpty)
        #expect(recorder.links.isEmpty)
        #expect(positions == [7], "scrolling still records the reading position")
        #expect(controller.linkMenuEntries(for: url("https://example.com/page")).isEmpty)
        #expect(controller.linkMenuConfiguration(for: url("https://example.com/page")) != nil, "ours, never WebKit's")
        controller.ignoresPageTaps = false
        _ = controller.handle(.menu(post: 7, source: .message, anchor: nil), in: shown)
        controller.route(link: url("https://example.com/page"))
        #expect(menus == [7])
        #expect(recorder.links == [url("https://example.com/page")])
        #expect(!controller.linkMenuEntries(for: url("https://example.com/page")).isEmpty)
    }
}
